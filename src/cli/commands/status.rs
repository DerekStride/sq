use crate::queue::{Queue, UpdateAttrs};
use crate::StatusArgs;
use anyhow::Result;
use std::path::PathBuf;

pub fn execute(args: &StatusArgs, queue_path: PathBuf, status: &str) -> Result<i32> {
    let queue = Queue::new(queue_path);

    let id = match &args.id {
        Some(id) => id.as_str(),
        None => {
            eprintln!("Error: Item ID is required");
            return Ok(1);
        }
    };

    let attrs = UpdateAttrs {
        status: Some(status.to_string()),
        ..Default::default()
    };

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
