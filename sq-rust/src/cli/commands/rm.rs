use crate::queue::Queue;
use crate::RmArgs;
use anyhow::Result;
use std::path::PathBuf;

/// Execute the `sq rm` command.
pub fn execute(args: &RmArgs, queue_path: PathBuf) -> Result<i32> {
    let queue = Queue::new(queue_path);

    let id = match &args.id {
        Some(ref id) => id.as_str(),
        None => {
            eprintln!("Error: Item ID is required");
            return Ok(1);
        }
    };

    match queue.remove(id)? {
        Some(removed) => {
            println!("{}", removed.id);
            eprintln!("Removed item {}", removed.id);
            Ok(0)
        }
        None => {
            eprintln!("Error: Item not found: {}", id);
            Ok(1)
        }
    }
}
