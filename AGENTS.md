## Scope

- Crate: `sift-queue`
- Binary: `sq`
- Main areas:
  - `src/lib.rs` (CLI args + command wiring types)
  - `src/main.rs` (subcommand dispatch)
  - `src/queue/mod.rs` (queue model + JSONL persistence)
  - `src/cli/commands/*.rs` (subcommand handlers)
  - `tests/cli_integration.rs` (end-to-end CLI behavior)
  - `tests/queue_parity.rs` (queue model + serialization behavior)

## Development workflow

Run from `sq/` unless otherwise noted.

Always run `cargo fmt` before finalizing changes or committing.

```bash
cargo fmt
cargo test
```

For single test iteration:

```bash
cargo test test_name
```

## Change guidelines

1. **Preserve JSON compatibility intentionally**
   - `Item::to_json_value()` controls output field order and optional fields.
   - If changing queue schema or output shape, update tests accordingly.

2. **Keep CLI human + JSON modes consistent**
   - Human mode: concise IDs/messages.
   - `--json`: machine-readable item payloads.

3. **Update help + tests together**
   - New flags/subcommands should include integration test coverage.

4. **Validate at command edge**
   - Parse/validate user input in command handlers.
   - Keep `Queue` APIs predictable and explicit.

5. **Prefer small, focused edits**
   - Keep command-specific behavior in command files.
   - Share logic only when it reduces duplication without obscuring behavior.

## Common feature touchpoints

- Add flag/subcommand:
  - `src/lib.rs` (arg structs / `Commands` enum)
  - `src/main.rs` (dispatch)
  - `src/cli/commands/*` (implementation)
  - `tests/cli_integration.rs` (coverage)

- Change item fields:
  - `src/queue/mod.rs` (`Item`, serializer, update attrs)
  - command handlers (`add`, `edit`, formatters)
  - both test suites

- Change list/show formatting:
  - `src/cli/formatters.rs`
  - relevant integration tests
