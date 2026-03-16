use crate::cli::help::{HelpDoc, HelpSection};
use crate::queue::{Queue, UpdateAttrs};
use crate::StatusArgs;
use anyhow::Result;
use clap::builder::{StyledStr, Styles};
use std::path::PathBuf;

pub fn close_after_help(styles: &Styles) -> StyledStr {
    HelpDoc::new()
        .section(
            HelpSection::new("Behavior:")
                .item("sq close <id>", "Keep an item in history with status closed")
                .item(
                    "sq close <id> --json",
                    "Return the updated item payload as JSON",
                ),
        )
        .render(styles)
}

pub fn execute(args: &StatusArgs, queue_path: PathBuf, status: &str) -> Result<i32> {
    let queue = Queue::new(queue_path);

    let id = match &args.id {
        Some(id) => id.as_str(),
        None => {
            eprintln!("Error: Item ID is required");
            return Ok(1);
        }
    };

    let existing = match queue.find(id) {
        Some(item) => item,
        None => {
            eprintln!("Error: Item not found: {}", id);
            return Ok(1);
        }
    };

    if existing.status == status {
        if args.json {
            let json = serde_json::to_string_pretty(&existing.to_json_value())?;
            println!("{}", json);
        } else {
            println!("{}", existing.id);
        }
        eprintln!("Item {} is already {}", existing.id, status);
        return Ok(0);
    }

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
