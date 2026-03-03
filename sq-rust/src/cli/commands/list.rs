use crate::cli::formatters;
use crate::queue::{Item, Queue};
use crate::ListArgs;
use anyhow::Result;
use std::collections::HashSet;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

/// Execute the `sq list` command.
pub fn execute(args: &ListArgs, queue_path: PathBuf) -> Result<i32> {
    let queue = Queue::new(queue_path);

    let mut items: Vec<Item> = if args.ready {
        queue.ready()
    } else {
        queue.filter(args.status.as_deref())
    };

    // Apply jq filter
    if let Some(ref filter_expr) = args.filter {
        let expr = format!("[.[] | {}]", filter_expr);
        match jq_filter(&items, &expr) {
            Some(filtered) => items = filtered,
            None => return Ok(1),
        }
    }

    // Apply jq sort
    if let Some(ref sort_path) = args.sort {
        let expr = format!("sort_by({} // infinite)", sort_path);
        match jq_filter(&items, &expr) {
            Some(sorted) => items = sorted,
            None => return Ok(1),
        }
    }

    // Apply reverse
    if args.reverse {
        items.reverse();
    }

    if args.json {
        let values: Vec<serde_json::Value> = items.iter().map(|i: &Item| i.to_json_value()).collect();
        let json = serde_json::to_string_pretty(&values)?;
        println!("{}", json);
    } else if items.is_empty() {
        eprintln!("No items found");
    } else {
        let pending_ids: HashSet<String> = queue
            .filter(Some("pending"))
            .iter()
            .map(|i| i.id.clone())
            .collect();
        for item in &items {
            formatters::print_item_summary(item, Some(&pending_ids));
        }
        eprintln!("{} item(s)", items.len());
    }

    Ok(0)
}

/// Run a jq expression on items, returning parsed results or None on error.
fn jq_filter(items: &[Item], expr: &str) -> Option<Vec<Item>> {
    let json_values: Vec<serde_json::Value> = items.iter().map(|i: &Item| i.to_json_value()).collect();
    let json = serde_json::to_string(&json_values).ok()?;

    let mut child = Command::new("jq")
        .arg("-e")
        .arg(expr)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| {
            eprintln!("Error: Failed to run jq: {}", e);
        })
        .ok()?;

    if let Some(ref mut stdin) = child.stdin {
        stdin.write_all(json.as_bytes()).ok()?;
    }
    // Close stdin
    drop(child.stdin.take());

    let output = child.wait_with_output().ok()?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        eprintln!("Error: Filter failed: {}", stderr.trim());
        return None;
    }

    let parsed: Vec<serde_json::Value> = serde_json::from_slice(&output.stdout).ok()?;
    Some(
        parsed
            .into_iter()
            .filter_map(|v| serde_json::from_value::<Item>(v).ok())
            .collect(),
    )
}
