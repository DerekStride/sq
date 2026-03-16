use crate::cli::help::{HelpDoc, HelpSection};
use crate::collect::{detect_format, render_title, Format};
use crate::queue::{parse_priority_value, NewItem, Queue, Source};
use crate::CollectArgs;
use anyhow::Result;
use clap::builder::{StyledStr, Styles};
use std::io::{IsTerminal, Read};
use std::path::PathBuf;

pub fn after_help(styles: &Styles) -> StyledStr {
    HelpDoc::new()
        .section(
            HelpSection::new("Examples:")
                .item(
                    "rg --json PATTERN | sq collect --by-file --title-template \"review: {{filepath}}\"",
                    "Group ripgrep matches by file with a custom title",
                )
                .item(
                    "rg --json -n -C2 PATTERN | sq collect --by-file",
                    "Preserve line numbers and nearby context in the collected text source",
                ),
        )
        .section(
            HelpSection::new("Templates:")
                .item("{{filepath}}", "Full file path for the grouped result")
                .item("{{filename}}", "Basename of {{filepath}}")
                .item(
                    "{{match_count}}",
                    "Number of rg match events collected for the file",
                )
                .text("Default title template: {{match_count}}:{{filepath}}"),
        )
        .section(
            HelpSection::new("Dependencies:")
                .text("Use --blocked-by <id1,id2> to declare blockers for every created item."),
        )
        .render(styles)
}

/// Execute the `sq collect` command.
pub fn execute(args: &CollectArgs, queue_path: PathBuf) -> Result<i32> {
    if !args.by_file {
        eprintln!("Error: collect requires a split mode (currently only --by-file is supported)");
        return Ok(1);
    }

    if args.title.is_some() && args.title_template.is_some() {
        eprintln!("Error: --title and --title-template are mutually exclusive");
        return Ok(1);
    }

    if std::io::stdin().is_terminal() {
        eprintln!("Error: sq collect --by-file expects piped stdin");
        eprintln!("Try: rg --json PATTERN | sq collect --by-file");
        return Ok(1);
    }

    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input)?;

    if input.trim().is_empty() {
        eprintln!("Error: no stdin input received");
        eprintln!("Try: rg --json PATTERN | sq collect --by-file");
        return Ok(1);
    }

    let format = match args.stdin_format.as_deref() {
        Some("rg-json") => Format::RgJson,
        Some(other) => {
            eprintln!("Error: Unsupported stdin format: {}", other);
            eprintln!("Currently supported: rg --json");
            return Ok(1);
        }
        None => match detect_format(&input) {
            Some(format) => format,
            None => {
                eprintln!("Error: could not detect a supported stdin format");
                eprintln!("Currently supported: rg --json");
                return Ok(1);
            }
        },
    };

    let grouped = match format {
        Format::RgJson => match crate::collect::rg::parse_json(&input) {
            Ok(items) => items,
            Err(err) => {
                eprintln!("Error: {}", err);
                return Ok(1);
            }
        },
    };

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

    let metadata = match &args.metadata {
        Some(json_str) => match serde_json::from_str(json_str) {
            Ok(v) => v,
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

    let mut new_items = Vec::with_capacity(grouped.len());
    for grouped_item in &grouped {
        let title = match render_title(
            args.title.as_deref(),
            args.title_template.as_deref(),
            grouped_item,
        ) {
            Ok(title) => title,
            Err(err) => {
                eprintln!("Error: {}", err);
                return Ok(1);
            }
        };

        new_items.push(NewItem {
            sources: vec![
                Source {
                    type_: "file".to_string(),
                    path: Some(grouped_item.filepath.clone()),
                    content: None,
                },
                Source {
                    type_: "text".to_string(),
                    path: None,
                    content: Some(grouped_item.text.clone()),
                },
            ],
            title: Some(title),
            description: args.description.clone(),
            priority,
            metadata: metadata.clone(),
            blocked_by: blocked_by.clone(),
        });
    }

    let queue = Queue::new(queue_path);
    let items = queue.push_many_with_description(new_items)?;

    if args.json {
        let json_values: Vec<serde_json::Value> = items.iter().map(|i| i.to_json_value()).collect();
        let json = serde_json::to_string_pretty(&json_values)?;
        println!("{}", json);
    } else {
        for item in &items {
            println!("{}", item.id);
        }
        eprintln!("Added {} item(s)", items.len());
    }

    Ok(0)
}
