use crate::cli::formatters;
use crate::queue::Queue;
use crate::ShowArgs;
use anyhow::Result;
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

    let item = match queue.find(id) {
        Some(item) => item,
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
