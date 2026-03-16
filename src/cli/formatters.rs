use crate::queue::Item;

/// Print a one-line summary for an item (used by `sq list`).
/// Format: {id}  [{status}]  {title_or_description}  {source_types}  {created_at}
pub fn print_item_summary(item: &Item) {
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

    let label = match (&item.title, &item.description) {
        (Some(t), _) => t.clone(),
        (None, Some(d)) => d.clone(),
        (None, None) => String::new(),
    };

    let priority = item
        .priority
        .map(|value| format!("  [priority:{}]", value))
        .unwrap_or_default();

    println!(
        "{}  [{}]{}  {}  {}  {}",
        item.id, item.status, priority, label, source_types, item.created_at
    );
}

/// Print detailed view for an item (used by `sq show`).
pub fn print_item_detail(item: &Item) {
    println!("Item: {}", item.id);
    if let Some(ref title) = item.title {
        println!("Title: {}", title);
    }
    if let Some(ref description) = item.description {
        println!("Description: {}", description);
    }
    println!("Status: {}", item.status);
    if let Some(priority) = item.priority {
        println!("Priority: {}", priority);
    }
    println!("Created: {}", item.created_at);
    println!("Updated: {}", item.updated_at);

    if !item.blocked_by.is_empty() {
        println!("Blocked by: {}", item.blocked_by.join(", "));
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
