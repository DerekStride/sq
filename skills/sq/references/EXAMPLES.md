# Examples

## Collect one item per file from ripgrep results

Use `sq collect --by-file` when you already have a stream of findings and want to turn them into a queue quickly.

Canonical pattern:

```bash
rg --json PATTERN | sq collect --by-file
```

Recommended variants:

```bash
# Include line numbers and context in each created text source
rg --json -n -C2 PATTERN | sq collect --by-file

# Add a shared description to every created item
rg --json -n -C2 PATTERN | sq collect --by-file \
  --description "Migrate PATTERN to Y"

# Add shared metadata
rg --json PATTERN | sq collect --by-file \
  --metadata '{"kind":"migration","priority":"p2"}'

# Customize titles per file
rg --json PATTERN | sq collect --by-file \
  --title-template 'migrate: {{filepath}}'
```

What `collect --by-file` does:

- reads piped stdin
- expects `rg --json` input
- groups results by file
- creates one queue item per file
- attaches:
  - a `file` source for the grouped file path
  - a `text` source containing the grouped match/context lines

Important constraints:

- plain-text `rg` output is not supported
- use `rg --json`
- use `-n`, `-C`, `-A`, or `-B` on `rg` when you want more useful context in the created `text` source

Default title template:

```text
{{match_count}}:{{filepath}}
```

Template variables:

- `{{filepath}}`
- `{{filename}}`
- `{{match_count}}`
