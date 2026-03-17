use crate::cli::help::{HelpDoc, HelpSection};
use crate::queue::Queue;
use crate::RmArgs;
use anyhow::Result;
use clap::builder::{StyledStr, Styles};
use std::path::PathBuf;

pub fn after_help(styles: &Styles) -> StyledStr {
    HelpDoc::new()
        .section(
            HelpSection::new("Behavior:")
                .item("sq rm <id>", "Remove an item from the task file entirely")
                .item(
                    "sq rm <id> --json",
                    "Return the removed item payload as JSON",
                ),
        )
        .section(
            HelpSection::new("Safety:")
                .text("Prefer sq close when you want to preserve history or keep completed work visible.")
                .text("Use sq rm when an item was created by mistake or should be deleted entirely."),
        )
        .section(
            HelpSection::new("Examples:")
                .item("sq rm abc", "Delete a mistaken task")
                .item(
                    "sq rm abc --json",
                    "Delete an item and emit the removed record for downstream tooling",
                ),
        )
        .render(styles)
}

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
            if args.json {
                let json = serde_json::to_string_pretty(&removed.to_json_value())?;
                println!("{}", json);
            } else {
                println!("{}", removed.id);
                eprintln!("Removed item {}", removed.id);
            }
            Ok(0)
        }
        None => {
            eprintln!("Error: Item not found: {}", id);
            Ok(1)
        }
    }
}
