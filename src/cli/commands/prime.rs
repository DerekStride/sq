use anyhow::Result;

/// Execute the `sq prime` command.
pub fn execute() -> Result<i32> {
    println!("{}", generate());
    Ok(0)
}

/// Generate the prime context string.
pub fn generate() -> String {
    let mut parts = Vec::new();

    parts.push(
        r#"# sq — Queue CLI and Queue-Native Task/Review Substrate

`sq` manages work in a JSONL queue.

Use it to:

- add and organize review/task items
- collect work from search results
- inspect queue state
- drive human or agent workflows from the queue

## Core Workflow

1. Create items with `sq add` or `sq collect --by-file`
2. Inspect queue state with `sq list` and `sq show`
3. Update progress with `sq edit`, `sq close`, or `sq rm`
4. Use the queue directly, or hand it off to another consumer such as `sift`

## `sq` Commands"#
            .to_string(),
    );

    parts.push(generate_command_reference());

    parts.join("\n\n")
}

fn generate_command_reference() -> String {
    let cmd = crate::build_cli();
    let mut lines = Vec::new();

    for sub in cmd.get_subcommands() {
        let name = sub.get_name();
        if name == "prime" || name == "help" {
            continue;
        }

        let about = sub.get_about().map(|a| a.to_string()).unwrap_or_default();
        lines.push(format!("### `sq {}` — {}\n", name, about));
        lines.push("```".to_string());

        for arg in sub.get_arguments() {
            if arg.is_hide_set() {
                continue;
            }
            let id = arg.get_id().as_str();
            if id == "help" || id == "version" {
                continue;
            }

            // Skip positional arguments in the flags listing
            let is_positional = arg.get_long().is_none() && arg.get_short().is_none();
            if is_positional {
                continue;
            }

            let long = arg.get_long().map(|l| format!("--{}", l));
            let short = arg.get_short().map(|s| format!("-{}", s));
            let names: Vec<String> = [short, long].into_iter().flatten().collect();
            let names_str = names.join(", ");

            // For boolean flags (num_vals == 0), don't show value name
            let is_bool = arg.get_action().takes_values();
            let value = if is_bool {
                arg.get_value_names()
                    .map(|v| {
                        v.iter()
                            .map(|s| s.to_string())
                            .collect::<Vec<_>>()
                            .join(" ")
                    })
                    .unwrap_or_default()
            } else {
                String::new()
            };

            let usage = if value.is_empty() {
                names_str
            } else {
                format!("{} {}", names_str, value)
            };

            let help = arg.get_help().map(|h| h.to_string()).unwrap_or_default();

            lines.push(format!("  {}  {}", usage, help));
        }

        lines.push("```".to_string());
        lines.push(String::new());
        lines.push(format!("For more information, use `sq {} --help`.", name));
        lines.push(String::new());
    }

    lines.join("\n")
}
