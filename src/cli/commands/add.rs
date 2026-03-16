use crate::cli::help::{HelpDoc, HelpSection};
use crate::queue::{parse_priority_value, Queue, Source};
use crate::AddArgs;
use anyhow::Result;
use clap::builder::{StyledStr, Styles};
use std::io::Read;
use std::path::PathBuf;

pub fn after_help(styles: &Styles) -> StyledStr {
    HelpDoc::new()
        .section(
            HelpSection::new("Task content:")
                .text("Provide at least one of --title, --description, or a source."),
        )
        .section(
            HelpSection::new("Dependencies:")
                .text("Use --blocked-by <id1,id2> to declare blockers when creating an item."),
        )
        .render(styles)
}

/// Execute the `sq add` command.
pub fn execute(args: &AddArgs, queue_path: PathBuf) -> Result<i32> {
    let queue = Queue::new(queue_path);

    let mut sources: Vec<Source> = Vec::new();

    for path in &args.diff {
        sources.push(Source {
            type_: "diff".to_string(),
            path: Some(path.clone()),
            content: None,
        });
    }

    for path in &args.file {
        sources.push(Source {
            type_: "file".to_string(),
            path: Some(path.clone()),
            content: None,
        });
    }

    for text in &args.text {
        sources.push(Source {
            type_: "text".to_string(),
            path: None,
            content: Some(text.clone()),
        });
    }

    for path in &args.directory {
        sources.push(Source {
            type_: "directory".to_string(),
            path: Some(path.clone()),
            content: None,
        });
    }

    if let Some(ref stdin_type) = args.stdin {
        let mut content = String::new();
        std::io::stdin().read_to_string(&mut content)?;
        sources.push(Source {
            type_: stdin_type.clone(),
            path: None,
            content: Some(content),
        });
    }

    let priority = match &args.priority {
        Some(value) => match parse_priority_value(value) {
            Ok(priority) => Some(priority),
            Err(err) => {
                eprintln!("Error: {}", err);
                return Ok(1);
            }
        },
        None => None,
    };

    let has_source = !sources.is_empty();
    let has_description = args.description.is_some();
    let has_title = args.title.is_some();

    if !has_source && !has_description && !has_title {
        eprintln!("Error: At least one of --description, --title, or a source is required");
        eprintln!("Use --diff, --file, --text, --directory, --stdin, --description, or --title");
        return Ok(1);
    }

    let metadata = match &args.metadata {
        Some(json_str) => match serde_json::from_str::<serde_json::Value>(json_str) {
            Ok(v) => {
                if !v.is_object() {
                    eprintln!("Error: --metadata must be a JSON object");
                    return Ok(1);
                }
                v
            }
            Err(e) => {
                eprintln!("Error: Invalid JSON for metadata: {}", e);
                return Ok(1);
            }
        },
        None => serde_json::Value::Object(serde_json::Map::new()),
    };

    let blocked_by: Vec<String> = match &args.blocked_by {
        Some(ids) => ids
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect(),
        None => Vec::new(),
    };

    let item = queue.push(
        sources,
        args.title.clone(),
        args.description.clone(),
        priority,
        metadata,
        blocked_by,
    )?;

    if args.json {
        let json = serde_json::to_string_pretty(&item.to_json_value())?;
        println!("{}", json);
    } else {
        println!("{}", item.id);
        eprintln!(
            "Added item {} with {} source(s)",
            item.id,
            item.sources.len()
        );
    }

    Ok(0)
}
