# Conventions

## Metadata

Use metadata for machine-readable structured extension fields:

| Key | Values | Description |
|-----|--------|-------------|
| `taskType` | `task`, `feature`, `bug`, `chore`, `epic` | Item classification |
| `dueAt` | ISO 8601 datetime | Deadline |

Example:

```bash
sq add --title "Migrate query helper" \
  --text "Refactor ..." \
  --metadata '{"taskType":"feature"}'
```

## Extensions

When an external tool consumes task data, scope its metadata under a key named after the extension. This keeps extension-specific fields separate from general metadata and avoids collisions between consumers.

For example, the `pi_tasks` extension:

```bash
sq add --title "Migrate query helper" \
  --text "Refactor ..." \
  --metadata '{"pi_tasks":{"taskType":"feature"}}'
```
