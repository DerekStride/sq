use crate::cli::formatters;
use crate::queue::Queue;
use crate::ShowArgs;
use anyhow::Result;
use std::collections::HashSet;
use std::path::PathBuf;

/// Execute the `sq show` command.
pub fn execute(args: &ShowArgs, queue_path: PathBuf) -> Result<i32> {
    let queue = Queue::new(queue_path);

    let id = match &args.id {
        Some(id) => id.as_str(),
        None => {
            eprintln!("Error: Item ID is required");
            return Ok(1);
        }
    };

    let all_items = queue.all();
    let open_ids: HashSet<String> = all_items
        .iter()
        .filter(|item| item.status != "closed")
        .map(|item| item.id.clone())
        .collect();

    let item = match all_items.into_iter().find(|item| item.id == id) {
        Some(item) => item.with_computed_status(Some(&open_ids)),
        None => {
            eprintln!("Error: Item not found: {}", id);
            return Ok(1);
        }
    };

    if args.json {
        let json = serde_json::to_string_pretty(&item.to_json_value())?;
        println!("{}", json);
    } else {
        formatters::print_item_detail(&item);
    }

    Ok(0)
}
