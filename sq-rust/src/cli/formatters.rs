use crate::queue::Item;
use std::collections::HashSet;

/// Print a one-line summary for an item (used by `sq list`).
/// Format: {id}  [{status}]{title}  {source_types}  {created_at}
pub fn print_item_summary(item: &Item, pending_ids: Option<&HashSet<String>>) {
    let display_status = resolve_display_status(item, pending_ids);

    // Tally source types
    let mut type_counts: Vec<(String, usize)> = Vec::new();
    for source in &item.sources {
        if let Some(entry) = type_counts.iter_mut().find(|(t, _)| *t == source.type_) {
            entry.1 += 1;
        } else {
            type_counts.push((source.type_.clone(), 1));
        }
    }
    let source_types: String = type_counts
        .iter()
        .map(|(t, c)| {
            if *c > 1 {
                format!("{}:{}", t, c)
            } else {
                t.clone()
            }
        })
        .collect::<Vec<_>>()
        .join(",");

    let title_part = match &item.title {
        Some(t) => format!("  {}", t),
        None => String::new(),
    };

    println!(
        "{}  [{}]{}  {}  {}",
        item.id, display_status, title_part, source_types, item.created_at
    );
}

/// Print detailed view for an item (used by `sq show`).
pub fn print_item_detail(item: &Item) {
    println!("Item: {}", item.id);
    if let Some(ref title) = item.title {
        println!("Title: {}", title);
    }
    println!("Status: {}", item.status);
    println!("Created: {}", item.created_at);
    println!("Updated: {}", item.updated_at);
    println!(
        "Session: {}",
        item.session_id.as_deref().unwrap_or("none")
    );

    if !item.blocked_by.is_empty() {
        println!("Blocked by: {}", item.blocked_by.join(", "));
    }

    if let Some(ref wt) = item.worktree {
        let branch = wt.branch.as_deref().unwrap_or("");
        let path = wt.path.as_deref().unwrap_or("");
        println!("Worktree: {} {}", branch, path);
    }

    if let serde_json::Value::Object(ref map) = item.metadata {
        if !map.is_empty() {
            println!("Metadata:");
            for (k, v) in map {
                println!("  {}: {}", k, v);
            }
        }
    }

    println!("Sources: ({})", item.sources.len());
    for (i, source) in item.sources.iter().enumerate() {
        print_source(source, i);
    }
}

/// Print a single source entry.
fn print_source(source: &crate::queue::Source, index: usize) {
    let location = if let Some(ref path) = source.path {
        path.clone()
    } else if source.content.is_some() {
        "[inline]".to_string()
    } else {
        "[empty]".to_string()
    };

    println!("  [{}] {}: {}", index, source.type_, location);

    if let (Some(ref content), None) = (&source.content, &source.path) {
        let lines: Vec<&str> = content.lines().collect();
        let preview: Vec<&str> = lines.iter().take(3).copied().collect();
        let preview_str = preview.join("\n      ");
        println!("      {}", preview_str);
        if lines.len() > 3 {
            println!("      ...");
        }
    }
}

/// Determine display status (may show "blocked" for pending+blocked items).
fn resolve_display_status(item: &Item, pending_ids: Option<&HashSet<String>>) -> String {
    if !item.pending() || !item.blocked() {
        return item.status.clone();
    }
    match pending_ids {
        None => "blocked".to_string(),
        Some(ids) => {
            if item.blocked_by.iter().any(|id| ids.contains(id)) {
                "blocked".to_string()
            } else {
                item.status.clone()
            }
        }
    }
}
