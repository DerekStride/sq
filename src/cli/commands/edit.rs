use crate::queue::{parse_priority_value, Queue, Source, UpdateAttrs, VALID_STATUSES};
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

    if args.set_metadata.is_some() && args.merge_metadata.is_some() {
        eprintln!("Error: --set-metadata and --merge-metadata are mutually exclusive");
        return Ok(1);
    }

    if args.set_priority.is_some() && args.clear_priority {
        eprintln!("Error: --set-priority and --clear-priority are mutually exclusive");
        return Ok(1);
    }

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

    // Description
    if let Some(ref description) = args.set_description {
        attrs.description = Some(description.clone());
        has_changes = true;
    }

    // Priority
    if let Some(ref priority_str) = args.set_priority {
        match parse_priority_value(priority_str) {
            Ok(priority) => {
                attrs.priority = Some(Some(priority));
                has_changes = true;
            }
            Err(err) => {
                eprintln!("Error: {}", err);
                return Ok(1);
            }
        }
    }

    if args.clear_priority {
        attrs.priority = Some(None);
        has_changes = true;
    }

    // Metadata (full replace)
    if let Some(ref json_str) = args.set_metadata {
        match serde_json::from_str::<serde_json::Value>(json_str) {
            Ok(v) => {
                if !v.is_object() {
                    eprintln!("Error: --set-metadata must be a JSON object");
                    return Ok(1);
                }
                attrs.metadata = Some(v);
                has_changes = true;
            }
            Err(e) => {
                eprintln!("Error: Invalid JSON for metadata: {}", e);
                return Ok(1);
            }
        }
    }

    // Metadata (deep merge)
    if let Some(ref json_str) = args.merge_metadata {
        let patch = match serde_json::from_str::<serde_json::Value>(json_str) {
            Ok(v) => v,
            Err(e) => {
                eprintln!("Error: Invalid JSON for merge metadata: {}", e);
                return Ok(1);
            }
        };

        if !patch.is_object() {
            eprintln!("Error: --merge-metadata must be a JSON object");
            return Ok(1);
        }

        let merged = deep_merge(item.metadata.clone(), patch);
        attrs.metadata = Some(merged);
        has_changes = true;
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

        // Remove sources (deduplicate, then sort indices in reverse to preserve correctness)
        let mut rm_indices: Vec<usize> = args.rm_source.clone();
        rm_indices.sort_unstable();
        rm_indices.dedup();
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
            if args.json {
                let json = serde_json::to_string_pretty(&updated.to_json_value())?;
                println!("{}", json);
            } else {
                println!("{}", updated.id);
                eprintln!("Updated item {}", updated.id);
            }
            Ok(0)
        }
        None => {
            eprintln!("Error: Item not found: {}", id);
            Ok(1)
        }
    }
}

fn deep_merge(current: serde_json::Value, patch: serde_json::Value) -> serde_json::Value {
    match (current, patch) {
        (serde_json::Value::Object(mut cur_map), serde_json::Value::Object(patch_map)) => {
            for (k, patch_v) in patch_map {
                let next = match cur_map.remove(&k) {
                    Some(cur_v) => deep_merge(cur_v, patch_v),
                    None => patch_v,
                };
                cur_map.insert(k, next);
            }
            serde_json::Value::Object(cur_map)
        }
        (_, patch_non_object) => patch_non_object,
    }
}

fn source_value(type_: &str, path: Option<&str>, content: Option<&str>) -> serde_json::Value {
    let mut map = serde_json::Map::new();
    map.insert(
        "type".to_string(),
        serde_json::Value::String(type_.to_string()),
    );
    if let Some(p) = path {
        map.insert("path".to_string(), serde_json::Value::String(p.to_string()));
    }
    if let Some(c) = content {
        map.insert(
            "content".to_string(),
            serde_json::Value::String(c.to_string()),
        );
    }
    serde_json::Value::Object(map)
}
