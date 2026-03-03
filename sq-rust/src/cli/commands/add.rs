use crate::queue::{Queue, Source};
use crate::AddArgs;
use anyhow::Result;
use std::io::Read;
use std::path::PathBuf;

/// Execute the `sq add` command.
pub fn execute(args: &AddArgs, queue_path: PathBuf) -> Result<i32> {
    let queue = Queue::new(queue_path);

    let mut sources: Vec<Source> = Vec::new();

    for path in &args.diff {
        sources.push(Source {
            type_: "diff".to_string(),
            path: Some(path.clone()),
            content: None,
            session_id: None,
        });
    }

    for path in &args.file {
        sources.push(Source {
            type_: "file".to_string(),
            path: Some(path.clone()),
            content: None,
            session_id: None,
        });
    }

    for text in &args.text {
        sources.push(Source {
            type_: "text".to_string(),
            path: None,
            content: Some(text.clone()),
            session_id: None,
        });
    }

    for path in &args.directory {
        sources.push(Source {
            type_: "directory".to_string(),
            path: Some(path.clone()),
            content: None,
            session_id: None,
        });
    }

    if let Some(ref stdin_type) = args.stdin {
        let mut content = String::new();
        std::io::stdin().read_to_string(&mut content)?;
        sources.push(Source {
            type_: stdin_type.clone(),
            path: None,
            content: Some(content),
            session_id: None,
        });
    }

    if sources.is_empty() {
        eprintln!("Error: At least one source is required");
        eprintln!("Use --diff, --file, --text, --directory, or --stdin");
        return Ok(1);
    }

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

    let item = queue.push(sources, args.title.clone(), metadata, None, blocked_by)?;
    println!("{}", item.id);
    eprintln!(
        "Added item {} with {} source(s)",
        item.id,
        item.sources.len()
    );
    Ok(0)
}
