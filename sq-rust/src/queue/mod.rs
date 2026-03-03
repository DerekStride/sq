use anyhow::{Context, Result};
use rand::Rng;
use rustix::fs::{flock, FlockOperation};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Seek, Write};
use std::os::fd::AsFd;
use std::path::{Path, PathBuf};

/// Valid status values for queue items.
pub const VALID_STATUSES: &[&str] = &["pending", "in_progress", "closed"];

/// Valid source types accepted by `push` (used for validation on add).
pub const VALID_SOURCE_TYPES: &[&str] = &["diff", "file", "text", "directory"];

// ── Types ───────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Item {
    pub id: String,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,

    pub status: String,

    pub sources: Vec<Source>,

    pub metadata: serde_json::Value,

    /// Always serialized, even when null.
    pub session_id: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub worktree: Option<Worktree>,

    #[serde(skip_serializing_if = "is_empty_vec")]
    #[serde(default)]
    pub blocked_by: Vec<String>,

    #[serde(skip_serializing_if = "is_empty_json_vec")]
    #[serde(default)]
    pub errors: Vec<serde_json::Value>,

    pub created_at: String,
    pub updated_at: String,
}

fn is_empty_vec(v: &[String]) -> bool {
    v.is_empty()
}

fn is_empty_json_vec(v: &[serde_json::Value]) -> bool {
    v.is_empty()
}

/// We need the JSON field order to match Ruby exactly.
/// Ruby `to_h` outputs: id, (title if present), status, sources, metadata,
/// session_id, created_at, updated_at, (worktree if present),
/// (blocked_by if non-empty), (errors if non-empty).
///
/// serde by default serializes in struct field order, so we order the fields
/// to match. But Ruby puts title BEFORE status when present, and worktree/
/// blocked_by/errors AFTER updated_at. Let's use a custom serializer.
impl Item {
    pub fn to_json_value(&self) -> serde_json::Value {
        let mut map = serde_json::Map::new();

        map.insert("id".to_string(), serde_json::Value::String(self.id.clone()));

        // title goes right after id, before status (only if present)
        if let Some(ref title) = self.title {
            map.insert(
                "title".to_string(),
                serde_json::Value::String(title.clone()),
            );
        }

        map.insert(
            "status".to_string(),
            serde_json::Value::String(self.status.clone()),
        );

        map.insert(
            "sources".to_string(),
            serde_json::Value::Array(self.sources.iter().map(|s| s.to_json_value()).collect()),
        );

        map.insert("metadata".to_string(), self.metadata.clone());

        map.insert(
            "session_id".to_string(),
            match &self.session_id {
                Some(s) => serde_json::Value::String(s.clone()),
                None => serde_json::Value::Null,
            },
        );

        map.insert(
            "created_at".to_string(),
            serde_json::Value::String(self.created_at.clone()),
        );
        map.insert(
            "updated_at".to_string(),
            serde_json::Value::String(self.updated_at.clone()),
        );

        // worktree after updated_at, only if present
        if let Some(ref wt) = self.worktree {
            map.insert("worktree".to_string(), wt.to_json_value());
        }

        // blocked_by after worktree, only if non-empty
        if !self.blocked_by.is_empty() {
            map.insert(
                "blocked_by".to_string(),
                serde_json::Value::Array(
                    self.blocked_by
                        .iter()
                        .map(|s| serde_json::Value::String(s.clone()))
                        .collect(),
                ),
            );
        }

        // errors after blocked_by, only if non-empty
        if !self.errors.is_empty() {
            map.insert(
                "errors".to_string(),
                serde_json::Value::Array(self.errors.clone()),
            );
        }

        serde_json::Value::Object(map)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_string()
    }

    pub fn pending(&self) -> bool {
        self.status == "pending"
    }

    pub fn blocked(&self) -> bool {
        !self.blocked_by.is_empty()
    }

    pub fn ready(&self, pending_ids: Option<&HashSet<String>>) -> bool {
        if !self.pending() {
            return false;
        }
        if !self.blocked() {
            return true;
        }
        match pending_ids {
            None => true,
            Some(ids) => self.blocked_by.iter().all(|id| !ids.contains(id)),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Source {
    #[serde(rename = "type")]
    pub type_: String,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
}

impl Source {
    pub fn to_json_value(&self) -> serde_json::Value {
        let mut map = serde_json::Map::new();
        map.insert(
            "type".to_string(),
            serde_json::Value::String(self.type_.clone()),
        );
        if let Some(ref path) = self.path {
            map.insert(
                "path".to_string(),
                serde_json::Value::String(path.clone()),
            );
        }
        if let Some(ref content) = self.content {
            map.insert(
                "content".to_string(),
                serde_json::Value::String(content.clone()),
            );
        }
        if let Some(ref session_id) = self.session_id {
            map.insert(
                "session_id".to_string(),
                serde_json::Value::String(session_id.clone()),
            );
        }
        serde_json::Value::Object(map)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Worktree {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
}

impl Worktree {
    pub fn to_json_value(&self) -> serde_json::Value {
        let mut map = serde_json::Map::new();
        if let Some(ref path) = self.path {
            map.insert(
                "path".to_string(),
                serde_json::Value::String(path.clone()),
            );
        }
        if let Some(ref branch) = self.branch {
            map.insert(
                "branch".to_string(),
                serde_json::Value::String(branch.clone()),
            );
        }
        serde_json::Value::Object(map)
    }
}

// ── Queue ───────────────────────────────────────────────────────────────────

pub struct Queue {
    pub path: PathBuf,
}

impl Queue {
    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }

    /// Add a new item to the queue. Returns the created Item.
    pub fn push(
        &self,
        sources: Vec<Source>,
        title: Option<String>,
        metadata: serde_json::Value,
        session_id: Option<String>,
        blocked_by: Vec<String>,
    ) -> Result<Item> {
        self.validate_sources(&sources)?;

        self.with_exclusive_lock(|f| {
            let existing = read_items(f, &self.path);
            let existing_ids: HashSet<String> = existing.iter().map(|i| i.id.clone()).collect();

            let now = now_iso8601();
            let item = Item {
                id: generate_id(&existing_ids),
                title,
                status: "pending".to_string(),
                sources,
                metadata,
                session_id,
                worktree: None,
                blocked_by,
                errors: Vec::new(),
                created_at: now.clone(),
                updated_at: now,
            };

            // Append to end of file
            f.seek(std::io::SeekFrom::End(0))?;
            writeln!(f, "{}", item.to_json_string())?;
            f.flush()?;

            Ok(item)
        })
    }

    /// Get all items, skipping corrupt lines with warnings.
    pub fn all(&self) -> Vec<Item> {
        if !self.path.exists() {
            return Vec::new();
        }
        match self.with_shared_lock(|f| Ok(read_items(f, &self.path))) {
            Ok(items) => items,
            Err(_) => Vec::new(),
        }
    }

    /// Find an item by ID.
    pub fn find(&self, id: &str) -> Option<Item> {
        self.all().into_iter().find(|item| item.id == id)
    }

    /// Filter items by status (optional).
    pub fn filter(&self, status: Option<&str>) -> Vec<Item> {
        let items = self.all();
        match status {
            Some(s) => items.into_iter().filter(|item| item.status == s).collect(),
            None => items,
        }
    }

    /// Return pending items that are not blocked by any pending item.
    pub fn ready(&self) -> Vec<Item> {
        let items = self.all();
        let pending_ids: HashSet<String> = items
            .iter()
            .filter(|i| i.pending())
            .map(|i| i.id.clone())
            .collect();
        items
            .into_iter()
            .filter(|item| item.ready(Some(&pending_ids)))
            .collect()
    }

    /// Update an item by ID. Returns the updated Item or None.
    pub fn update(&self, id: &str, attrs: UpdateAttrs) -> Result<Option<Item>> {
        self.with_exclusive_lock(|f| {
            let mut items = read_items(f, &self.path);
            let index = items.iter().position(|item| item.id == id);
            let index = match index {
                Some(i) => i,
                None => return Ok(None),
            };

            let item = &mut items[index];

            if let Some(status) = &attrs.status {
                if !VALID_STATUSES.contains(&status.as_str()) {
                    anyhow::bail!(
                        "Invalid status: {}. Valid: {}",
                        status,
                        VALID_STATUSES.join(", ")
                    );
                }
                item.status = status.clone();
            }
            if let Some(title) = attrs.title {
                item.title = Some(title);
            }
            if let Some(metadata) = attrs.metadata {
                item.metadata = metadata;
            }
            if let Some(session_id) = attrs.session_id {
                item.session_id = Some(session_id);
            }
            if let Some(blocked_by) = attrs.blocked_by {
                item.blocked_by = blocked_by;
            }
            if let Some(sources) = attrs.sources {
                item.sources = sources;
            }

            item.updated_at = now_iso8601();

            let updated = item.clone();
            rewrite_items(f, &items)?;
            Ok(Some(updated))
        })
    }

    /// Remove an item by ID. Returns the removed Item or None.
    pub fn remove(&self, id: &str) -> Result<Option<Item>> {
        self.with_exclusive_lock(|f| {
            let mut items = read_items(f, &self.path);
            let index = items.iter().position(|item| item.id == id);
            match index {
                Some(i) => {
                    let removed = items.remove(i);
                    rewrite_items(f, &items)?;
                    Ok(Some(removed))
                }
                None => Ok(None),
            }
        })
    }

    // ── Private helpers ─────────────────────────────────────────────────

    fn validate_sources(&self, sources: &[Source]) -> Result<()> {
        if sources.is_empty() {
            anyhow::bail!("Sources cannot be empty");
        }
        for source in sources {
            if !VALID_SOURCE_TYPES.contains(&source.type_.as_str()) {
                anyhow::bail!(
                    "Invalid source type: {}. Valid: {}",
                    source.type_,
                    VALID_SOURCE_TYPES.join(", ")
                );
            }
        }
        Ok(())
    }

    fn ensure_directory(&self) -> Result<()> {
        if let Some(parent) = self.path.parent() {
            if !parent.exists() {
                fs::create_dir_all(parent)?;
            }
        }
        Ok(())
    }

    fn with_exclusive_lock<T, F>(&self, f: F) -> Result<T>
    where
        F: FnOnce(&mut File) -> Result<T>,
    {
        self.ensure_directory()?;
        let mut file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(&self.path)
            .with_context(|| format!("Failed to open queue file: {}", self.path.display()))?;

        flock(&file.as_fd(), FlockOperation::LockExclusive)
            .with_context(|| "Failed to acquire exclusive lock")?;

        let result = f(&mut file);

        // Lock released when file is dropped
        result
    }

    fn with_shared_lock<T, F>(&self, f: F) -> Result<T>
    where
        F: FnOnce(&mut File) -> Result<T>,
    {
        let mut file = File::open(&self.path)
            .with_context(|| format!("Failed to open queue file: {}", self.path.display()))?;

        flock(&file.as_fd(), FlockOperation::LockShared)
            .with_context(|| "Failed to acquire shared lock")?;

        f(&mut file)
    }
}

/// Read items from an open file, skipping corrupt lines.
fn read_items(file: &mut File, path: &Path) -> Vec<Item> {
    file.seek(std::io::SeekFrom::Start(0)).ok();
    let reader = BufReader::new(file);
    let mut items = Vec::new();

    for (line_num, line) in reader.lines().enumerate() {
        let line = match line {
            Ok(l) => l,
            Err(_) => continue,
        };
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        match serde_json::from_str::<Item>(trimmed) {
            Ok(item) => items.push(item),
            Err(e) => {
                eprintln!(
                    "Warning: Skipping corrupt line {} in {}: {}",
                    line_num + 1,
                    path.display(),
                    e
                );
            }
        }
    }
    items
}

/// Truncate and rewrite all items to the file.
fn rewrite_items(file: &mut File, items: &[Item]) -> Result<()> {
    file.seek(std::io::SeekFrom::Start(0))?;
    file.set_len(0)?;
    for item in items {
        writeln!(file, "{}", item.to_json_string())?;
    }
    file.flush()?;
    Ok(())
}

/// Generate a 3-char alphanumeric ID that doesn't collide with existing.
fn generate_id(existing_ids: &HashSet<String>) -> String {
    let chars: Vec<char> = ('a'..='z').chain('0'..='9').collect();
    let mut rng = rand::thread_rng();
    loop {
        let id: String = (0..3).map(|_| chars[rng.gen_range(0..chars.len())]).collect();
        if !existing_ids.contains(&id) {
            return id;
        }
    }
}

/// Current UTC time in ISO 8601 with millisecond precision.
fn now_iso8601() -> String {
    chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string()
}

/// Attributes for updating an item.
#[derive(Default)]
pub struct UpdateAttrs {
    pub status: Option<String>,
    pub title: Option<String>,
    pub metadata: Option<serde_json::Value>,
    pub session_id: Option<String>,
    pub blocked_by: Option<Vec<String>>,
    pub sources: Option<Vec<Source>>,
}
