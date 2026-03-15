use anyhow::Result;
use crate::PrimeArgs;

/// Execute the `sq prime` command.
pub fn execute(args: &PrimeArgs) -> Result<i32> {
    println!("{}", generate(args.prelude));
    Ok(0)
}

/// Generate the prime context string.
pub fn generate(prelude_only: bool) -> String {
    let mut parts = Vec::new();

    parts.push(
        r#"# sq — Lightweight task-list CLI with structured sources

Use `sq` to manage tasks in a JSONL file during agent workflows.

Default queue path: `.sift/issues.jsonl`. Override it with `-q, --queue <PATH>` or `SQ_QUEUE_PATH=<PATH>`.

## Examples

```bash
sq add --title "Investigate checkout exception" \
  --description "Review the pasted error report and identify the failing code path" \
  --priority 1 \
  --text "Sentry alert: NoMethodError in Checkout::ApplyDiscount at app/services/checkout/apply_discount.rb:42"

rg --json -n -C2 'OldApi.call' | sq collect --by-file \
  --title-template "migrate: {{filepath}}" \
  --description "Migrate OldApi.call to NewApi.call" \
  --priority 2

sq list --ready
```

## Readiness and dependencies

Use `blocked_by` to model dependencies. A task is ready when it is `pending` and none of its blocker IDs refer to another open `pending` task.

Use these list views:

- `sq list --ready` — actionable work only (`pending` and unblocked)
- `sq list` — default view; shows all non-closed items so blocked dependencies and `in_progress` work stay visible
- `sq list --all` — include closed items for history/auditing

When you need the next task, start with `sq list --ready`.

Manage blockers like this:

```bash
sq add --title "Implement feature" --blocked-by abc123
sq edit xyz789 --set-blocked-by abc123,def456
sq edit xyz789 --set-blocked-by ""
sq show xyz789
```

## Priority

Priority uses the inclusive range `0..4`, where `0` is highest.

Use priority to order ready work. Do not treat it as a measure of overall importance.

Combine `priority` with `blocked_by` so ready items form a practical next-work queue.

User instruction overrides queue order. If the user asks for a specific task, do that task even when other tasks have higher priority.

Do not treat lower-priority tasks as ignorable; they are just not the default next task."#
            .to_string(),
    );

    if !prelude_only {
        parts.push(generate_command_reference());
    }

    parts.join("\n\n")
}

fn generate_command_reference() -> String {
    let cmd = crate::build_cli();
    let mut lines = vec!["## `sq` Commands".to_string(), String::new()];

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
