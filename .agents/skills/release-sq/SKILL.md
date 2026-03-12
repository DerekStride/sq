---
name: release-sq
description: Maintainer checklist for preparing an `sq` release in this repository up to tag creation/push. Use when bumping `sq`, validating the crate release, drafting notes, or preparing a tag before the manual GitHub Release publish step.
license: MIT
allowed-tools: Bash(git:*,cargo:*,gh:*)
---

# Release `sq`

Use this skill when preparing a new `sq` release for this repository.

`sq` is published as the `sift-queue` crate from the repository root.

## Source of truth

Release automation lives in:

- `.github/workflows/publish.yml`

Key behavior:

- pushing a `v*` tag runs a version check
- publishing a GitHub Release triggers `cargo publish`
- the tag version must match `Cargo.toml`

Example for `v0.3.0`:

- git tag: `v0.3.0`
- crate version: `0.3.0`

## Maintainer checklist

This skill documents the prep work up to tag creation/push. The GitHub Release publication and post-publish verification are handled manually afterward.

1. Bump the crate version in `Cargo.toml`.
2. Update version-sensitive tests, especially `tests/cli_integration.rs`.
3. Run the Rust test suite:

   ```bash
   cargo test --all --verbose
   ```

4. Run a crates.io dry run:

   ```bash
   cargo publish --dry-run
   ```

5. Draft release notes in `tmp/release-vX.Y.Z.md`.
6. Commit the release prep, merge to `main`, then create and push the tag:

   ```bash
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```

## Files to check during release prep

- `Cargo.toml` — crate version
- `tests/cli_integration.rs` — `sq --version` assertion
- `tmp/release-vX.Y.Z.md` — release notes draft
- `.github/workflows/publish.yml` — release automation behavior

## Notes

- Tag format must be `vX.Y.Z`, not just `X.Y.Z`.
- Tag push alone does not publish the crate.
- Actual crates.io publication happens only after the GitHub Release is published.
