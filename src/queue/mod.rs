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

/// Valid priority range accepted by first-class priority fields.
pub const VALID_PRIORITY_RANGE: std::ops::RangeInclusive<u8> = 0..=4;

// ── Types ───────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Item {
    pub id: String,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,

    pub status: String,

    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(default)]
    pub priority: Option<u8>,

    pub sources: Vec<Source>,

    pub metadata: serde_json::Value,

    pub created_at: String,
    pub updated_at: String,

    #[serde(skip_serializing_if = "is_empty_vec")]
    #[serde(default)]
    pub blocked_by: Vec<String>,

    #[serde(skip_serializing_if = "is_empty_json_vec")]
    #[serde(default)]
    pub errors: Vec<serde_json::Value>,
}

fn is_empty_vec(v: &[String]) -> bool {
    v.is_empty()
}

fn is_empty_json_vec(v: &[serde_json::Value]) -> bool {
    v.is_empty()
}

/// Serialize items through serde so the struct definition is the source of
/// truth for JSON output.
impl Item {
    pub fn to_json_value(&self) -> serde_json::Value {
        serde_json::to_value(self).expect("item serialization should succeed")
    }

    pub fn to_json_string(&self) -> String {
        serde_json::to_string(self).expect("item serialization should succeed")
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

pub fn parse_priority_value(input: &str) -> Result<u8> {
    let trimmed = input.trim();

    let priority = trimmed
        .parse::<u8>()
        .with_context(|| format!("Invalid priority: {input}. Valid: 0-4"))?;

    if !VALID_PRIORITY_RANGE.contains(&priority) {
        anyhow::bail!("Invalid priority: {input}. Valid: 0-4");
    }

    Ok(priority)
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Source {
    #[serde(rename = "type")]
    pub type_: String,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
}

impl Source {
    pub fn to_json_value(&self) -> serde_json::Value {
        serde_json::to_value(self).expect("source serialization should succeed")
    }
}

// ── Queue ───────────────────────────────────────────────────────────────────

pub struct Queue {
    pub path: PathBuf,
}

pub struct NewItem {
    pub sources: Vec<Source>,
    pub title: Option<String>,
    pub description: Option<String>,
    pub priority: Option<u8>,
    pub metadata: serde_json::Value,
    pub blocked_by: Vec<String>,
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
        description: Option<String>,
        priority: Option<u8>,
        metadata: serde_json::Value,
        blocked_by: Vec<String>,
    ) -> Result<Item> {
        let new_item = NewItem {
            sources,
            title,
            description,
            priority,
            metadata,
            blocked_by,
        };

        let mut items = self.push_many_with_description(vec![new_item])?;
        Ok(items.remove(0))
    }

    /// Add many new items to the queue under a single lock.
    pub fn push_many_with_description(&self, items: Vec<NewItem>) -> Result<Vec<Item>> {
        if items.is_empty() {
            anyhow::bail!("At least one item is required");
        }

        for item in &items {
            self.validate_new_item(item)?;
        }

        self.with_exclusive_lock(|f| {
            let existing = read_items(f, &self.path);
            let mut existing_ids: HashSet<String> = existing.iter().map(|i| i.id.clone()).collect();
            let now = now_iso8601();
            let mut created = Vec::with_capacity(items.len());

            f.seek(std::io::SeekFrom::End(0))?;
            for new_item in items {
                let id = generate_id(&existing_ids);
                existing_ids.insert(id.clone());

                let item = Item {
                    id,
                    title: new_item.title,
                    description: new_item.description,
                    status: "pending".to_string(),
                    priority: new_item.priority,
                    sources: new_item.sources,
                    metadata: new_item.metadata,
                    created_at: now.clone(),
                    updated_at: now.clone(),
                    blocked_by: new_item.blocked_by,
                    errors: Vec::new(),
                };

                writeln!(f, "{}", item.to_json_string())?;
                created.push(item);
            }
            f.flush()?;

            Ok(created)
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
            if let Some(description) = attrs.description {
                item.description = Some(description);
            }
            if let Some(priority) = attrs.priority {
                if let Some(value) = priority {
                    validate_priority(value)?;
                }
                item.priority = priority;
            }
            if let Some(metadata) = attrs.metadata {
                item.metadata = metadata;
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

    fn validate_new_item(&self, item: &NewItem) -> Result<()> {
        if let Some(priority) = item.priority {
            validate_priority(priority)?;
        }

        if item.sources.is_empty() && item.title.is_none() && item.description.is_none() {
            anyhow::bail!("Item requires at least one source, title, or description");
        }

        self.validate_source_types(&item.sources)
    }

    fn validate_source_types(&self, sources: &[Source]) -> Result<()> {
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
        let id: String = (0..3)
            .map(|_| chars[rng.gen_range(0..chars.len())])
            .collect();
        if !existing_ids.contains(&id) {
            return id;
        }
    }
}

/// Current UTC time in ISO 8601 with millisecond precision.
fn now_iso8601() -> String {
    chrono::Utc::now()
        .format("%Y-%m-%dT%H:%M:%S%.3fZ")
        .to_string()
}

fn validate_priority(priority: u8) -> Result<()> {
    if VALID_PRIORITY_RANGE.contains(&priority) {
        Ok(())
    } else {
        anyhow::bail!("Invalid priority: {}. Valid: 0-4", priority);
    }
}

/// Attributes for updating an item.
#[derive(Default)]
pub struct UpdateAttrs {
    pub status: Option<String>,
    pub title: Option<String>,
    pub description: Option<String>,
    pub priority: Option<Option<u8>>,
    pub metadata: Option<serde_json::Value>,
    pub blocked_by: Option<Vec<String>>,
    pub sources: Option<Vec<Source>>,
}
