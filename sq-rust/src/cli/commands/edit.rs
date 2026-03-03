use crate::queue::{Queue, Source, UpdateAttrs, VALID_STATUSES};
use crate::EditArgs;
use anyhow::Result;
use std::path::PathBuf;

/// Execute the `sq edit` command.
pub fn execute(args: &EditArgs, queue_path: PathBuf) -> Result<i32> {
    let queue = Queue::new(queue_path);

    let id = match &args.id {
        Some(ref id) => id.as_str(),
        None => {
            eprintln!("Error: Item ID is required");
            return Ok(1);
        }
    };

    let item = match queue.find(id) {
        Some(item) => item,
        None => {
            eprintln!("Error: Item not found: {}", id);
            return Ok(1);
        }
    };

    let mut attrs = UpdateAttrs::default();
    let mut has_changes = false;

    // Status
    if let Some(ref status) = args.set_status {
        if !VALID_STATUSES.contains(&status.as_str()) {
            eprintln!(
                "Error: Invalid status: {}. Valid: {}",
                status,
                VALID_STATUSES.join(", ")
            );
            return Ok(1);
        }
        attrs.status = Some(status.clone());
        has_changes = true;
    }

    // Title
    if let Some(ref title) = args.set_title {
        attrs.title = Some(title.clone());
        has_changes = true;
    }

    // Metadata
    if let Some(ref json_str) = args.set_metadata {
        match serde_json::from_str::<serde_json::Value>(json_str) {
            Ok(v) => {
                attrs.metadata = Some(v);
                has_changes = true;
            }
            Err(e) => {
                eprintln!("Error: Invalid JSON for metadata: {}", e);
                return Ok(1);
            }
        }
    }

    // Blocked by
    if let Some(ref ids_str) = args.set_blocked_by {
        let blocked_by: Vec<String> = ids_str
            .split(',')
            .map(|s: &str| s.trim().to_string())
            .filter(|s: &String| !s.is_empty())
            .collect();
        attrs.blocked_by = Some(blocked_by);
        has_changes = true;
    }

    // Source modifications
    let has_source_adds = !args.add_diff.is_empty()
        || !args.add_file.is_empty()
        || !args.add_text.is_empty()
        || !args.add_directory.is_empty()
        || !args.add_transcript.is_empty();
    let has_source_removes = !args.rm_source.is_empty();

    if has_source_adds || has_source_removes {
        has_changes = true;
        let mut sources: Vec<serde_json::Value> =
            item.sources.iter().map(|s| s.to_json_value()).collect();

        // Remove sources (sort indices in reverse to preserve correctness)
        let mut rm_indices: Vec<usize> = args.rm_source.clone();
        rm_indices.sort();
        rm_indices.reverse();
        for index in rm_indices {
            if index < sources.len() {
                sources.remove(index);
            } else {
                eprintln!("Warning: Source index {} out of range", index);
            }
        }

        // Add new sources
        for path in &args.add_diff {
            sources.push(source_value("diff", Some(path.as_str()), None));
        }
        for path in &args.add_file {
            sources.push(source_value("file", Some(path.as_str()), None));
        }
        for text in &args.add_text {
            sources.push(source_value("text", None, Some(text.as_str())));
        }
        for path in &args.add_directory {
            sources.push(source_value("directory", Some(path.as_str()), None));
        }
        for path in &args.add_transcript {
            sources.push(source_value("transcript", Some(path.as_str()), None));
        }

        if sources.is_empty() {
            eprintln!("Error: Cannot remove all sources");
            return Ok(1);
        }

        // Convert back to Source structs
        let new_sources: Vec<Source> = sources
            .into_iter()
            .filter_map(|v| serde_json::from_value(v).ok())
            .collect();
        attrs.sources = Some(new_sources);
    }

    if !has_changes {
        eprintln!("Error: No changes specified");
        return Ok(1);
    }

    match queue.update(id, attrs)? {
        Some(updated) => {
            println!("{}", updated.id);
            eprintln!("Updated item {}", updated.id);
            Ok(0)
        }
        None => {
            eprintln!("Error: Item not found: {}", id);
            Ok(1)
        }
    }
}

fn source_value(
    type_: &str,
    path: Option<&str>,
    content: Option<&str>,
) -> serde_json::Value {
    let mut map = serde_json::Map::new();
    map.insert(
        "type".to_string(),
        serde_json::Value::String(type_.to_string()),
    );
    if let Some(p) = path {
        map.insert(
            "path".to_string(),
            serde_json::Value::String(p.to_string()),
        );
    }
    if let Some(c) = content {
        map.insert(
            "content".to_string(),
            serde_json::Value::String(c.to_string()),
        );
    }
    serde_json::Value::Object(map)
}
