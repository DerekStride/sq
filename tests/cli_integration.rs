use assert_cmd::Command;
use predicates::prelude::*;
use std::fs;
use tempfile::TempDir;

fn sq_cmd() -> Command {
    assert_cmd::cargo::cargo_bin_cmd!("sq")
}

fn queue_path(dir: &TempDir) -> String {
    dir.path().join("queue.jsonl").to_str().unwrap().to_string()
}

fn rg_json_input() -> &'static str {
    concat!(
        "{\"type\":\"begin\",\"data\":{\"path\":{\"text\":\"app/models/a.rb\"}}}\n",
        "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"app/models/a.rb\"},\"lines\":{\"text\":\"foo\\n\"},\"line_number\":1}}\n",
        "{\"type\":\"context\",\"data\":{\"path\":{\"text\":\"app/models/a.rb\"},\"lines\":{\"text\":\"bar\\n\"},\"line_number\":2}}\n",
        "{\"type\":\"end\",\"data\":{\"path\":{\"text\":\"app/models/a.rb\"}}}\n",
        "{\"type\":\"begin\",\"data\":{\"path\":{\"text\":\"lib/b.rb\"}}}\n",
        "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"lib/b.rb\"},\"lines\":{\"text\":\"baz\\n\"},\"line_number\":4}}\n",
        "{\"type\":\"end\",\"data\":{\"path\":{\"text\":\"lib/b.rb\"}}}\n"
    )
}

fn assert_contains_in_order(haystack: &str, needles: &[&str]) {
    let mut last = 0;
    for needle in needles {
        let rel = haystack[last..]
            .find(needle)
            .unwrap_or_else(|| panic!("missing `{needle}` in output:\n{haystack}"));
        last += rel + needle.len();
    }
}

// ── Add Command ─────────────────────────────────────────────────────────────

#[test]
fn test_add_text_source() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "Hello world"])
        .output()
        .unwrap();

    assert!(output.status.success());
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();
    assert_eq!(id.len(), 3);

    // Verify it's in the queue
    let content = fs::read_to_string(dir.path().join("queue.jsonl")).unwrap();
    assert!(content.contains(&id));
    assert!(content.contains("Hello world"));
}

#[test]
fn test_add_with_title() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add", "--text", "content", "--title", "My Title"])
        .assert()
        .success();

    let content = fs::read_to_string(dir.path().join("queue.jsonl")).unwrap();
    assert!(content.contains("\"title\":\"My Title\""));
}

#[test]
fn test_add_with_description() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--text",
            "content",
            "--description",
            "My description",
        ])
        .assert()
        .success();

    let content = fs::read_to_string(dir.path().join("queue.jsonl")).unwrap();
    assert!(content.contains("\"description\":\"My description\""));
}

#[test]
fn test_add_with_metadata() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--text",
            "content",
            "--metadata",
            r#"{"workflow":"analyze"}"#,
        ])
        .assert()
        .success();

    let content = fs::read_to_string(dir.path().join("queue.jsonl")).unwrap();
    assert!(content.contains("\"workflow\":\"analyze\""));
}

#[test]
fn test_add_with_blocked_by() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--text",
            "content",
            "--blocked-by",
            "abc,def",
        ])
        .assert()
        .success();

    let content = fs::read_to_string(dir.path().join("queue.jsonl")).unwrap();
    assert!(content.contains("\"blocked_by\":[\"abc\",\"def\"]"));
}

#[test]
fn test_add_json() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--text",
            "content",
            "--title",
            "My Item",
            "--description",
            "Describe it",
            "--json",
        ])
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["title"], "My Item");
    assert_eq!(json["description"], "Describe it");
    assert_eq!(json["status"], "pending");
    assert!(json["id"].as_str().unwrap().len() == 3);
}

#[test]
fn test_add_multiple_sources() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--text",
            "some text",
            "--diff",
            "changes.patch",
            "--file",
            "main.rb",
        ])
        .assert()
        .success();

    let content = fs::read_to_string(dir.path().join("queue.jsonl")).unwrap();
    assert!(content.contains("\"type\":\"text\""));
    assert!(content.contains("\"type\":\"diff\""));
    assert!(content.contains("\"type\":\"file\""));
}

#[test]
fn test_add_no_fields_fails() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add"])
        .assert()
        .failure()
        .stderr(predicate::str::contains(
            "At least one of --description, --title, or a source is required",
        ));
}

#[test]
fn test_add_description_without_sources() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--description", "desc only", "--json"])
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["description"], "desc only");
    assert!(json["sources"].as_array().unwrap().is_empty());
}

#[test]
fn test_add_title_without_sources() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--title", "title only", "--json"])
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["title"], "title only");
    assert!(json["sources"].as_array().unwrap().is_empty());
}

#[test]
fn test_add_metadata_without_sources_fails() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--metadata",
            r#"{"kind":"task"}"#,
            "--json",
        ])
        .assert()
        .failure()
        .stderr(predicate::str::contains(
            "At least one of --description, --title, or a source is required",
        ));
}

#[test]
fn test_add_priority_without_sources_fails() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add", "--priority", "1", "--json"])
        .assert()
        .failure()
        .stderr(predicate::str::contains(
            "At least one of --description, --title, or a source is required",
        ));
}

#[test]
fn test_add_invalid_priority_fails() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add", "--text", "x", "--priority", "P1"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Invalid priority: P1. Valid: 0-4"));
}

#[test]
fn test_add_invalid_metadata_fails() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add", "--text", "x", "--metadata", "not json"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Invalid JSON for metadata"));
}

// ── List Command ────────────────────────────────────────────────────────────

#[test]
fn test_list_empty() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);
    fs::create_dir_all(dir.path()).unwrap();
    fs::write(dir.path().join("queue.jsonl"), "").unwrap();

    sq_cmd()
        .args(["-q", &qp, "list"])
        .assert()
        .success()
        .stderr(predicate::str::contains("No items found"));
}

#[test]
fn test_list_human_readable() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    // Add an item
    sq_cmd()
        .args(["-q", &qp, "add", "--text", "test", "--title", "Test Item"])
        .assert()
        .success();

    sq_cmd()
        .args(["-q", &qp, "list"])
        .assert()
        .success()
        .stdout(predicate::str::contains("[pending]"))
        .stdout(predicate::str::contains("Test Item"))
        .stdout(predicate::str::contains("text"))
        .stderr(predicate::str::contains("1 item(s)"));
}

#[test]
fn test_list_json() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "list", "--json"])
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert!(json.is_array());
    assert_eq!(json.as_array().unwrap().len(), 1);
}

#[test]
fn test_list_default_sorts_by_priority() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add", "--title", "low", "--priority", "3"])
        .assert()
        .success();

    sq_cmd()
        .args(["-q", &qp, "add", "--title", "high", "--priority", "0"])
        .assert()
        .success();

    sq_cmd()
        .args(["-q", &qp, "add", "--title", "none"])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "list", "--json"])
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let items = json.as_array().unwrap();
    assert_eq!(items[0]["title"], "high");
    assert_eq!(items[1]["title"], "low");
    assert_eq!(items[2]["title"], "none");
}

#[test]
fn test_list_filters_by_repeatable_priority_flag() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add", "--title", "p1", "--priority", "1"])
        .assert()
        .success();

    sq_cmd()
        .args(["-q", &qp, "add", "--title", "p0", "--priority", "0"])
        .assert()
        .success();

    sq_cmd()
        .args(["-q", &qp, "add", "--title", "p4", "--priority", "4"])
        .assert()
        .success();

    sq_cmd()
        .args(["-q", &qp, "add", "--title", "none"])
        .assert()
        .success();

    let output = sq_cmd()
        .args([
            "-q",
            &qp,
            "list",
            "--priority",
            "0",
            "--priority",
            "1",
            "--json",
        ])
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let items = json.as_array().unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(items[0]["title"], "p0");
    assert_eq!(items[1]["title"], "p1");
}

#[test]
fn test_list_priority_filter_rejects_invalid_value() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add", "--title", "p1", "--priority", "1"])
        .assert()
        .success();

    sq_cmd()
        .args(["-q", &qp, "list", "--priority", "P9"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Invalid priority: P9. Valid: 0-4"));
}

#[test]
fn test_list_default_excludes_closed() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "item1"])
        .output()
        .unwrap();
    let id1 = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "add", "--text", "item2"])
        .assert()
        .success();

    sq_cmd()
        .args(["-q", &qp, "edit", &id1, "--set-status", "closed"])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "list", "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json.as_array().unwrap().len(), 1);
    assert_eq!(json[0]["status"], "pending");
}

#[test]
fn test_list_all_includes_closed() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "item1"])
        .output()
        .unwrap();
    let id1 = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "add", "--text", "item2"])
        .assert()
        .success();

    sq_cmd()
        .args(["-q", &qp, "edit", &id1, "--set-status", "closed"])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "list", "--all", "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json.as_array().unwrap().len(), 2);
}

#[test]
fn test_list_status_filter() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    // Add two items
    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "item1"])
        .output()
        .unwrap();
    let id1 = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "add", "--text", "item2"])
        .assert()
        .success();

    // Close first
    sq_cmd()
        .args(["-q", &qp, "edit", &id1, "--set-status", "closed"])
        .assert()
        .success();

    // List only pending
    let output = sq_cmd()
        .args(["-q", &qp, "list", "--status", "pending", "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json.as_array().unwrap().len(), 1);
    assert_eq!(json[0]["status"], "pending");
}

#[test]
fn test_list_ready() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    // Add blocker
    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "blocker"])
        .output()
        .unwrap();
    let blocker_id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    // Add blocked item
    sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--text",
            "blocked",
            "--blocked-by",
            &blocker_id,
        ])
        .assert()
        .success();

    // Only blocker should be ready
    let output = sq_cmd()
        .args(["-q", &qp, "list", "--ready", "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json.as_array().unwrap().len(), 1);
    assert_eq!(json[0]["id"], blocker_id);
}

// ── Show Command ────────────────────────────────────────────────────────────

#[test]
fn test_show_json() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--text",
            "content",
            "--title",
            "My Item",
            "--description",
            "My Description",
        ])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["id"], id);
    assert_eq!(json["title"], "My Item");
    assert_eq!(json["description"], "My Description");
    assert_eq!(json["status"], "pending");
}

#[test]
fn test_show_human_readable() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--text",
            "content",
            "--title",
            "My Item",
            "--description",
            "My Description",
        ])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "show", &id])
        .assert()
        .success()
        .stdout(predicate::str::contains("Item:"))
        .stdout(predicate::str::contains("Title: My Item"))
        .stdout(predicate::str::contains("Description: My Description"))
        .stdout(predicate::str::contains("Status: pending"));
}

#[test]
fn test_show_human_readable_with_priority() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--title",
            "My Item",
            "--priority",
            "2",
        ])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "show", &id])
        .assert()
        .success()
        .stdout(predicate::str::contains("Priority: 2"));
}

#[test]
fn test_show_not_found() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);
    fs::create_dir_all(dir.path()).unwrap();
    fs::write(dir.path().join("queue.jsonl"), "").unwrap();

    sq_cmd()
        .args(["-q", &qp, "show", "zzz"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Item not found: zzz"));
}

#[test]
fn test_show_no_id() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "show"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("required"));
}

// ── Edit Command ────────────────────────────────────────────────────────────

#[test]
fn test_edit_set_status() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "edit", &id, "--set-status", "closed"])
        .assert()
        .success()
        .stdout(predicate::str::contains(&id));

    // Verify
    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["status"], "closed");
}

#[test]
fn test_edit_set_and_clear_priority() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--title", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "edit", &id, "--set-priority", "1"])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["priority"], 1);

    sq_cmd()
        .args(["-q", &qp, "edit", &id, "--clear-priority"])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert!(json.get("priority").is_none());
}

#[test]
fn test_edit_invalid_priority_fails() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--title", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "edit", &id, "--set-priority", "9"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Invalid priority"));
}

#[test]
fn test_edit_set_and_clear_priority_are_mutually_exclusive() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--title", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args([
            "-q",
            &qp,
            "edit",
            &id,
            "--set-priority",
            "1",
            "--clear-priority",
        ])
        .assert()
        .failure()
        .stderr(predicate::str::contains(
            "--set-priority and --clear-priority are mutually exclusive",
        ));
}

#[test]
fn test_edit_set_description() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args([
            "-q",
            &qp,
            "edit",
            &id,
            "--set-description",
            "Updated description",
        ])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["description"], "Updated description");
}

#[test]
fn test_edit_json() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    let output = sq_cmd()
        .args(["-q", &qp, "edit", &id, "--set-status", "closed", "--json"])
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["id"], id);
    assert_eq!(json["status"], "closed");
}

#[test]
fn test_edit_merge_metadata_deep_merge() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--text",
            "test",
            "--metadata",
            r#"{"pi_tasks":{"priority":"low","type":"bug"},"owner":"derek"}"#,
        ])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args([
            "-q",
            &qp,
            "edit",
            &id,
            "--merge-metadata",
            r#"{"pi_tasks":{"priority":"high"}}"#,
        ])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();

    assert_eq!(json["metadata"]["pi_tasks"]["priority"], "high");
    assert_eq!(json["metadata"]["pi_tasks"]["type"], "bug");
    assert_eq!(json["metadata"]["owner"], "derek");
}

#[test]
fn test_edit_merge_metadata_array_replace_and_null() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--text",
            "test",
            "--metadata",
            r#"{"labels":["a","b"],"pi_tasks":{"due":"2026-03-10"}}"#,
        ])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args([
            "-q",
            &qp,
            "edit",
            &id,
            "--merge-metadata",
            r#"{"labels":["urgent"],"pi_tasks":{"due":null}}"#,
        ])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();

    assert_eq!(json["metadata"]["labels"], serde_json::json!(["urgent"]));
    assert!(json["metadata"]["pi_tasks"]["due"].is_null());
}

#[test]
fn test_edit_merge_metadata_invalid_non_object_fails() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "edit", &id, "--merge-metadata", "[]"])
        .assert()
        .failure()
        .stderr(predicate::str::contains(
            "--merge-metadata must be a JSON object",
        ));
}

#[test]
fn test_edit_set_and_merge_metadata_mutually_exclusive() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args([
            "-q",
            &qp,
            "edit",
            &id,
            "--set-metadata",
            "{}",
            "--merge-metadata",
            "{}",
        ])
        .assert()
        .failure()
        .stderr(predicate::str::contains(
            "--set-metadata and --merge-metadata are mutually exclusive",
        ));
}

#[test]
fn test_edit_add_and_rm_source() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--text",
            "original",
            "--text",
            "remove me",
        ])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    // Remove second source (index 1) and add a new one
    sq_cmd()
        .args([
            "-q",
            &qp,
            "edit",
            &id,
            "--rm-source",
            "1",
            "--add-text",
            "replacement",
        ])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let sources = json["sources"].as_array().unwrap();
    assert_eq!(sources.len(), 2);
    assert_eq!(sources[0]["content"], "original");
    assert_eq!(sources[1]["content"], "replacement");
}

#[test]
fn test_edit_cannot_remove_all_sources() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "only source"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "edit", &id, "--rm-source", "0"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Cannot remove all sources"));
}

#[test]
fn test_edit_no_changes_fails() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "edit", &id])
        .assert()
        .failure()
        .stderr(predicate::str::contains("No changes specified"));
}

#[test]
fn test_edit_set_blocked_by() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "edit", &id, "--set-blocked-by", "abc,def"])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["blocked_by"], serde_json::json!(["abc", "def"]));
}

#[test]
fn test_edit_clear_blocked_by() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test", "--blocked-by", "abc"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    // Clear blocked_by with empty string
    sq_cmd()
        .args(["-q", &qp, "edit", &id, "--set-blocked-by", ""])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    // blocked_by should be omitted (empty)
    assert!(json.get("blocked_by").is_none());
}

// ── Status Transition Commands ──────────────────────────────────────────────

#[test]
fn test_close_command() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd().args(["-q", &qp, "close", &id]).assert().success();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["status"], "closed");
}

#[test]
fn test_close_command_json() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    let output = sq_cmd()
        .args(["-q", &qp, "close", &id, "--json"])
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["id"], id);
    assert_eq!(json["status"], "closed");
}

#[test]
fn test_status_command_not_found() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);
    fs::create_dir_all(dir.path()).unwrap();
    fs::write(dir.path().join("queue.jsonl"), "").unwrap();

    sq_cmd()
        .args(["-q", &qp, "close", "zzz"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Item not found: zzz"));
}

// ── Rm Command ──────────────────────────────────────────────────────────────

#[test]
fn test_rm_item() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "rm", &id])
        .assert()
        .success()
        .stdout(predicate::str::contains(&id));

    // Verify it's gone
    let output = sq_cmd()
        .args(["-q", &qp, "list", "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert!(json.as_array().unwrap().is_empty());
}

#[test]
fn test_rm_json() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    let output = sq_cmd()
        .args(["-q", &qp, "rm", &id, "--json"])
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["id"], id);
}

#[test]
fn test_rm_not_found() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);
    fs::create_dir_all(dir.path()).unwrap();
    fs::write(dir.path().join("queue.jsonl"), "").unwrap();

    sq_cmd()
        .args(["-q", &qp, "rm", "zzz"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Item not found: zzz"));
}

// ── Collect Command ─────────────────────────────────────────────────────────

#[test]
fn test_collect_by_file_rg_json() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "collect", "--by-file"])
        .write_stdin(rg_json_input())
        .output()
        .unwrap();

    assert!(output.status.success());
    let stdout = String::from_utf8(output.stdout).unwrap();
    let ids: Vec<&str> = stdout
        .lines()
        .filter(|line| !line.trim().is_empty())
        .collect();
    assert_eq!(ids.len(), 2);

    let content = fs::read_to_string(dir.path().join("queue.jsonl")).unwrap();
    assert!(content.contains("\"path\":\"app/models/a.rb\""));
    assert!(content.contains("\"path\":\"lib/b.rb\""));
    assert!(content.contains("\"title\":\"1:app/models/a.rb\""));
    assert!(content.contains("\"title\":\"1:lib/b.rb\""));
    assert!(content.contains("1: foo\\n2: bar"));
    assert!(content.contains("4: baz"));
}

#[test]
fn test_collect_by_file_with_title_template() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args([
            "-q",
            &qp,
            "collect",
            "--by-file",
            "--title-template",
            "collect {{filename}} ({{match_count}})",
        ])
        .write_stdin(rg_json_input())
        .assert()
        .success();

    let content = fs::read_to_string(dir.path().join("queue.jsonl")).unwrap();
    assert!(content.contains("\"title\":\"collect a.rb (1)\""));
    assert!(content.contains("\"title\":\"collect b.rb (1)\""));
}

#[test]
fn test_collect_by_file_json_output_returns_full_items() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args([
            "-q",
            &qp,
            "collect",
            "--by-file",
            "--description",
            "Migrate",
            "--json",
        ])
        .write_stdin(rg_json_input())
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let items = json.as_array().unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(items[0]["status"], "pending");
    assert_eq!(items[0]["description"], "Migrate");
    assert_eq!(items[0]["sources"].as_array().unwrap().len(), 2);
}

#[test]
fn test_collect_by_file_with_description_priority_metadata_and_blocked_by() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args([
            "-q",
            &qp,
            "collect",
            "--by-file",
            "--description",
            "Remove foo",
            "--priority",
            "2",
            "--metadata",
            r#"{"kind":"migration"}"#,
            "--blocked-by",
            "abc,def",
            "--json",
        ])
        .write_stdin(rg_json_input())
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let items = json.as_array().unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(items[0]["description"], "Remove foo");
    assert_eq!(items[0]["priority"], 2);
    assert_eq!(items[0]["metadata"]["kind"], "migration");
    assert_eq!(items[0]["blocked_by"], serde_json::json!(["abc", "def"]));
}

#[test]
fn test_collect_by_file_empty_stdin_fails() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "collect", "--by-file"])
        .write_stdin("")
        .assert()
        .failure()
        .stderr(predicate::str::contains("no stdin input received"));
}

#[test]
fn test_collect_requires_split_mode() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "collect"])
        .write_stdin(rg_json_input())
        .assert()
        .failure()
        .stderr(predicate::str::contains("collect requires a split mode"));
}

#[test]
fn test_collect_title_and_title_template_are_mutually_exclusive() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args([
            "-q",
            &qp,
            "collect",
            "--by-file",
            "--title",
            "x",
            "--title-template",
            "{{filepath}}",
        ])
        .write_stdin(rg_json_input())
        .assert()
        .failure()
        .stderr(predicate::str::contains(
            "--title and --title-template are mutually exclusive",
        ));
}

#[test]
fn test_collect_top_level_by_file_without_subcommand_fails() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "--by-file"])
        .write_stdin(rg_json_input())
        .assert()
        .failure()
        .stderr(predicate::str::contains("unexpected argument '--by-file'"));
}

#[test]
fn test_collect_unsupported_input_fails_atomically() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "collect", "--by-file"])
        .write_stdin("app/models/a.rb:1:foo\n")
        .assert()
        .failure()
        .stderr(predicate::str::contains(
            "could not detect a supported stdin format",
        ));

    assert!(!dir.path().join("queue.jsonl").exists());
}

#[test]
fn test_collect_appears_in_main_help() {
    sq_cmd()
        .args(["--help"])
        .assert()
        .success()
        .stdout(predicate::str::contains(
            "lightweight task-list CLI with structured sources",
        ))
        .stdout(predicate::str::contains("collect"))
        .stdout(predicate::str::contains("Path to task file"))
        .stdout(predicate::str::contains(".sift/issues.jsonl"))
        .stdout(predicate::str::contains("Manage Sift's review queue").not());
}

#[test]
fn test_collect_examples_and_templates_appear_in_collect_help() {
    sq_cmd()
        .args(["collect", "--help"])
        .assert()
        .success()
        .stdout(predicate::str::contains("Examples:"))
        .stdout(predicate::str::contains("Templates:"))
        .stdout(predicate::str::contains(
            "rg --json PATTERN | sq collect --by-file",
        ))
        .stdout(predicate::str::contains("{{filepath}}"))
        .stdout(predicate::str::contains("{{filename}}"))
        .stdout(predicate::str::contains("{{match_count}}"))
        .stdout(predicate::str::contains(
            "Default title template: {{match_count}}:{{filepath}}",
        ))
        .stdout(predicate::str::contains("Collect tasks from stdin"));
}

#[test]
fn test_add_help_puts_title_and_description_first() {
    let output = sq_cmd().args(["add", "--help"]).output().unwrap();
    assert!(output.status.success());
    let stdout = String::from_utf8(output.stdout).unwrap();

    assert_contains_in_order(
        &stdout,
        &[
            "--title <TITLE>",
            "--description <TEXT>",
            "--priority <PRIORITY>",
            "--diff <PATH>",
            "--file <PATH>",
            "--text <STRING>",
        ],
    );
}

#[test]
fn test_collect_help_puts_title_and_description_first() {
    let output = sq_cmd().args(["collect", "--help"]).output().unwrap();
    assert!(output.status.success());
    let stdout = String::from_utf8(output.stdout).unwrap();

    assert_contains_in_order(
        &stdout,
        &[
            "--title <TITLE>",
            "--description <TEXT>",
            "--priority <PRIORITY>",
            "--by-file",
            "--stdin-format <FORMAT>",
            "--title-template <TEMPLATE>",
        ],
    );
}

#[test]
fn test_edit_help_puts_title_and_description_first() {
    let output = sq_cmd().args(["edit", "--help"]).output().unwrap();
    assert!(output.status.success());
    let stdout = String::from_utf8(output.stdout).unwrap();

    assert_contains_in_order(
        &stdout,
        &[
            "--set-title <TITLE>",
            "--set-description <TEXT>",
            "--set-status <STATUS>",
            "--set-priority <PRIORITY>",
            "--add-diff <PATH>",
        ],
    );
}

#[test]
fn test_list_help_includes_priority_filter_near_other_filters() {
    let output = sq_cmd().args(["list", "--help"]).output().unwrap();
    assert!(output.status.success());
    let stdout = String::from_utf8(output.stdout).unwrap();

    assert_contains_in_order(
        &stdout,
        &[
            "--status <STATUS>",
            "--all",
            "--priority <PRIORITY>",
            "--ready",
            "--json",
        ],
    );
}

#[test]
fn test_list_help_documents_views_and_dependencies() {
    sq_cmd()
        .args(["list", "--help"])
        .assert()
        .success()
        .stdout(predicate::str::contains("Views:"))
        .stdout(predicate::str::contains("sq list --ready"))
        .stdout(predicate::str::contains(
            "Show only actionable work: pending items with no open blockers",
        ))
        .stdout(predicate::str::contains(
            "Default view: show all non-closed items so blocked dependencies and in_progress work remain visible",
        ))
        .stdout(predicate::str::contains("Dependencies:"))
        .stdout(predicate::str::contains("--blocked-by <id1,id2>"))
        .stdout(predicate::str::contains("sq edit <id> --set-blocked-by ..."));
}

// ── Prime Command ───────────────────────────────────────────────────────────

#[test]
fn test_prime_output() {
    sq_cmd()
        .args(["prime"])
        .assert()
        .success()
        .stdout(predicate::str::contains(
            "# sq — Lightweight task-list CLI with structured sources",
        ))
        .stdout(predicate::str::contains(
            "`sq` manages tasks in a JSONL file for agent workflows.",
        ))
        .stdout(predicate::str::contains(".sift/issues.jsonl"))
        .stdout(predicate::str::contains("## Examples"))
        .stdout(predicate::str::contains("sq list --ready"))
        .stdout(predicate::str::contains("## Readiness and dependencies"))
        .stdout(predicate::str::contains("Dependencies are modeled with `blocked_by`"))
        .stdout(predicate::str::contains(
            "- `sq list` — default view; shows all non-closed items so blocked dependencies and `in_progress` work stay visible",
        ))
        .stdout(predicate::str::contains(
            "When choosing the next task to start, prefer `sq list --ready`.",
        ))
        .stdout(predicate::str::contains("sq edit xyz789 --set-blocked-by abc123,def456"))
        .stdout(predicate::str::contains("## Priority"))
        .stdout(predicate::str::contains(
            "Priority uses the inclusive range `0..4`, where `0` is highest.",
        ))
        .stdout(predicate::str::contains("## `sq` Commands"))
        .stdout(predicate::str::contains("### `sq add` — Add a new task"))
        .stdout(predicate::str::contains(
            "### `sq collect` — Collect tasks from stdin",
        ))
        .stdout(predicate::str::contains("### `sq list` — List tasks"))
        .stdout(predicate::str::contains(
            "### `sq show` — Show task details",
        ))
        .stdout(predicate::str::contains(
            "### `sq edit` — Edit an existing task",
        ))
        .stdout(predicate::str::contains("### `sq rm` — Remove a task"))
        .stdout(predicate::str::contains("Use it to:").not())
        .stdout(predicate::str::contains("## Core Workflow").not())
        .stdout(predicate::str::contains("JSONL queue").not());
}

#[test]
fn test_prime_help_has_no_full_flag() {
    sq_cmd()
        .args(["prime", "--help"])
        .assert()
        .success()
        .stdout(predicate::str::contains("Output task workflow context for AI agents"))
        .stdout(predicate::str::contains("--full").not())
        .stdout(predicate::str::contains("Force full CLI output").not());
}

// ── Version Flag ────────────────────────────────────────────────────────────

#[test]
fn test_version_flag() {
    sq_cmd()
        .args(["--version"])
        .assert()
        .success()
        .stdout(predicate::str::contains("sq 0.5.0"));
}

#[test]
fn test_version_short_flag() {
    sq_cmd()
        .args(["-v"])
        .assert()
        .success()
        .stdout(predicate::str::contains("sq 0.5.0"));
}

// ── Queue Path Resolution ───────────────────────────────────────────────────

#[test]
fn test_env_queue_path() {
    let dir = TempDir::new().unwrap();
    let qp = dir.path().join("env_queue.jsonl");

    let output = sq_cmd()
        .env("SQ_QUEUE_PATH", qp.to_str().unwrap())
        .args(["add", "--text", "env test"])
        .output()
        .unwrap();

    assert!(output.status.success());
    assert!(qp.exists());
}

#[test]
fn test_default_queue_path() {
    let dir = TempDir::new().unwrap();
    let qp = dir.path().join(".sift").join("issues.jsonl");

    let output = sq_cmd()
        .current_dir(dir.path())
        .env_remove("SQ_QUEUE_PATH")
        .args(["add", "--text", "default path test"])
        .output()
        .unwrap();

    assert!(output.status.success());
    assert!(qp.exists());

    let content = fs::read_to_string(qp).unwrap();
    assert!(content.contains("default path test"));
}

// ── JSON Output ─────────────────────────────────────────────────────────────

#[test]
fn test_json_output_includes_priority_when_present() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args([
            "-q",
            &qp,
            "add",
            "--text",
            "test",
            "--title",
            "Title",
            "--description",
            "Description",
            "--priority",
            "1",
        ])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();

    assert_eq!(json["id"], id);
    assert_eq!(json["priority"], 1);
}

// ══════════════════════════════════════════════════════════════════════════════
// AUDIT — Failing tests for discovered bugs, edge cases, and missing validation
// ══════════════════════════════════════════════════════════════════════════════

// ── BUG: Duplicate --rm-source indices removes more sources than intended ────
//
// If a user passes `--rm-source 0 --rm-source 0`, the code sorts+reverses
// without deduplication. The first removal shifts indices, so the second
// removal hits a *different* source than intended. Given sources [a, b, c],
// `--rm-source 0 --rm-source 0` removes a (index 0), then b (now at index 0),
// leaving only [c] — the user meant to remove only one source.
#[test]
fn test_edit_duplicate_rm_source_indices_should_dedup() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args([
            "-q", &qp, "add", "--text", "a", "--text", "b", "--text", "c",
        ])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    // Remove index 0 twice — user intent: remove only one source
    sq_cmd()
        .args([
            "-q", &qp, "edit", &id, "--rm-source", "0", "--rm-source", "0",
        ])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let sources = json["sources"].as_array().unwrap();

    // After removing index 0 once, we should have [b, c] — two sources left.
    // BUG: Currently removes two sources (a and b), leaving only [c].
    assert_eq!(
        sources.len(),
        2,
        "Duplicate --rm-source 0 should only remove one source, not two"
    );
}

// ── BUG: edit --add-transcript bypasses VALID_SOURCE_TYPES validation ────────
//
// The edit command can add transcript sources via --add-transcript, but
// "transcript" is not in VALID_SOURCE_TYPES. The `add` command properly
// validates source types, but `edit` constructs Source structs from JSON
// values and never calls validate_source_types on the result. This means
// `edit` silently introduces sources that `add` would reject.
#[test]
fn test_edit_add_transcript_should_be_validated_against_source_types() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    // Adding transcript via --add-transcript should either succeed (if
    // transcript is a valid type) or fail with a validation error.
    // Currently it silently succeeds even though "transcript" is not
    // in VALID_SOURCE_TYPES.
    let output = sq_cmd()
        .args([
            "-q", &qp, "edit", &id, "--add-transcript", "/session.jsonl",
        ])
        .output()
        .unwrap();

    // If transcript is a valid type, the add command should also accept it.
    // If it's not valid, edit should reject it.
    // This test asserts the two commands should be consistent:
    // Either both accept transcript OR both reject it.
    let edit_succeeded = output.status.success();

    // Try adding a transcript source via the add command's --stdin type
    let add_output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "placeholder"])
        .output()
        .unwrap();
    assert!(add_output.status.success(), "baseline add should work");

    // The add command has no --transcript flag at all, so there's no way
    // to add a transcript source via `sq add` — only via `sq edit`.
    // This inconsistency should be resolved.
    assert!(
        !edit_succeeded,
        "edit --add-transcript should reject 'transcript' type since it's not in VALID_SOURCE_TYPES, \
         but currently it silently succeeds"
    );
}

// ── MISSING VALIDATION: list --status with invalid status silently returns empty
//
// `sq list --status bogus` doesn't error — it just shows no results.
// Compare with `sq edit --set-status bogus` which properly validates.
// Users get no feedback that they misspelled a status.
#[test]
fn test_list_invalid_status_should_error() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .assert()
        .success();

    // Using a bogus status should give an error, not silently return nothing
    sq_cmd()
        .args(["-q", &qp, "list", "--status", "bogus_status"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Invalid status"));
}

// ── INCONSISTENCY: Cannot remove all sources from item with title/description ─
//
// The `add` command allows creating items with no sources (just title or
// description). But `edit --rm-source` blocks removing all sources, even
// when the item has a title or description. This creates an inconsistency:
// you can create source-less items, but you can't edit an item to be source-less.
#[test]
fn test_edit_rm_all_sources_should_succeed_when_item_has_title() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args([
            "-q", &qp, "add", "--title", "Has title", "--text", "remove me",
        ])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    // Item has a title, so removing all sources should be fine — the item
    // is still valid (sq add --title "x" works without sources)
    sq_cmd()
        .args(["-q", &qp, "edit", &id, "--rm-source", "0"])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert!(
        json["sources"].as_array().unwrap().is_empty(),
        "Sources should be empty after removing the only source from a titled item"
    );
}

// ── EDGE CASE: edit --set-title to empty string ──────────────────────────────
//
// Setting a title to "" creates an item with an empty string title, which
// is different from None. The JSON will contain `"title":""` instead of
// omitting the field. This is arguably a bug — empty string should either
// be rejected or treated as clearing the title.
#[test]
fn test_edit_set_title_empty_string_should_clear_or_reject() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--title", "Original", "--text", "x"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "edit", &id, "--set-title", ""])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();

    // An empty title should either be None (field omitted) or rejected.
    // Currently it's set to "" which serializes as "title":"" — not ideal.
    assert!(
        json.get("title").is_none(),
        "Empty string title should be treated as clearing the title (None), \
         but currently serializes as an empty string"
    );
}

// ── EDGE CASE: close already-closed item succeeds silently ───────────────────
//
// Closing an already-closed item is a no-op that succeeds. This could mask
// accidental double-closes. At minimum the user should get a warning.
#[test]
fn test_close_already_closed_item_should_warn_or_noop() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "close", &id])
        .assert()
        .success();

    // Closing again should indicate it's already closed
    sq_cmd()
        .args(["-q", &qp, "close", &id])
        .assert()
        .success()
        .stderr(predicate::str::contains("already closed").or(predicate::str::contains("no change")));
}

// ── EDGE CASE: add --priority boundary values ────────────────────────────────
//
// Priority 5 is out of range but the error message should be clear.
// Also tests negative-like strings.
#[test]
fn test_add_priority_out_of_range_high() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add", "--text", "x", "--priority", "5"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Invalid priority"));
}

#[test]
fn test_add_priority_negative() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add", "--text", "x", "--priority", "-1"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Invalid priority"));
}

// ── EDGE CASE: blocked-by with self-reference ────────────────────────────────
//
// An item shouldn't be able to block itself, but there's no validation.
// Since IDs are generated at push time, you can't self-block on add, but
// you can do it via edit.
#[test]
fn test_edit_set_blocked_by_self_should_error_or_ignore() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    // Setting an item to be blocked by itself should either fail or be ignored
    sq_cmd()
        .args(["-q", &qp, "edit", &id, "--set-blocked-by", &id])
        .assert()
        .success();

    // If self-blocking is allowed, the item should NOT appear in --ready
    // because it blocks itself. Let's verify list --ready handles this sanely.
    let output = sq_cmd()
        .args(["-q", &qp, "list", "--ready", "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let items = json.as_array().unwrap();

    // The self-blocked item IS in pending_ids, and it blocks itself,
    // so it should NOT be ready. This test verifies that.
    assert_eq!(
        items.len(),
        0,
        "Self-blocked item should not appear in ready list"
    );
}

// ── EDGE CASE: list --ready with in_progress blockers ────────────────────────
//
// An item blocked by an in_progress item is considered "ready" because
// ready() only checks pending_ids. This means an item whose dependency
// is still being worked on shows up as actionable. This is documented
// behavior but may be surprising.
#[test]
fn test_list_ready_considers_in_progress_blockers() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    // Create blocker
    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "blocker", "--title", "Blocker"])
        .output()
        .unwrap();
    let blocker_id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    // Create blocked item
    sq_cmd()
        .args([
            "-q", &qp, "add", "--text", "blocked", "--title", "Blocked",
            "--blocked-by", &blocker_id,
        ])
        .assert()
        .success();

    // Move blocker to in_progress (not closed/done)
    sq_cmd()
        .args(["-q", &qp, "edit", &blocker_id, "--set-status", "in_progress"])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "list", "--ready", "--json"])
        .output()
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let items = json.as_array().unwrap();
    let titles: Vec<&str> = items
        .iter()
        .filter_map(|i| i["title"].as_str())
        .collect();

    // Currently "Blocked" appears in ready because blocker is in_progress
    // (not pending), so it's not in pending_ids. This test documents that
    // in_progress blockers don't actually block readiness.
    // If the intended behavior is that in_progress items also block, this
    // test should assert that "Blocked" is NOT in the ready list.
    assert!(
        !titles.contains(&"Blocked"),
        "Item blocked by an in_progress item should NOT be considered ready — \
         the blocker is still being worked on. Currently it IS shown as ready."
    );
}

// ── EDGE CASE: show with no queue file ───────────────────────────────────────
//
// Running show on a nonexistent queue file should give a clear error.
#[test]
fn test_show_on_nonexistent_queue_file() {
    let dir = TempDir::new().unwrap();
    let qp = dir.path().join("does_not_exist.jsonl").to_str().unwrap().to_string();

    sq_cmd()
        .args(["-q", &qp, "show", "abc"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("not found").or(predicate::str::contains("No such file")));
}

// ── EDGE CASE: list on nonexistent queue file ────────────────────────────────
//
// Running list on a nonexistent queue file should show "No items found".
#[test]
fn test_list_on_nonexistent_queue_file() {
    let dir = TempDir::new().unwrap();
    let qp = dir.path().join("does_not_exist.jsonl").to_str().unwrap().to_string();

    sq_cmd()
        .args(["-q", &qp, "list"])
        .assert()
        .success()
        .stderr(predicate::str::contains("No items found"));
}

// ── EDGE CASE: add with non-object metadata ──────────────────────────────────
//
// Metadata should be a JSON object. Passing an array or scalar should fail.
#[test]
fn test_add_metadata_non_object_should_fail() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    // Array metadata
    sq_cmd()
        .args(["-q", &qp, "add", "--text", "x", "--metadata", "[1,2,3]"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("must be a JSON object").or(
            predicate::str::contains("Invalid"),
        ));
}

// ── EDGE CASE: edit --set-metadata to non-object ─────────────────────────────
//
// --set-metadata with a non-object value should fail, similar to how
// --merge-metadata already validates this.
#[test]
fn test_edit_set_metadata_non_object_should_fail() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "x"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    // Setting metadata to a string should fail
    sq_cmd()
        .args(["-q", &qp, "edit", &id, "--set-metadata", "\"just a string\""])
        .assert()
        .failure()
        .stderr(predicate::str::contains("must be a JSON object").or(
            predicate::str::contains("Invalid"),
        ));
}

// ── EDGE CASE: rm-source with out-of-range index ─────────────────────────────
//
// Passing an out-of-range index to --rm-source gives a warning but still
// succeeds. It would be better to fail with an error.
#[test]
fn test_edit_rm_source_out_of_range_should_error() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "only"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    // Index 5 doesn't exist — only index 0 does
    sq_cmd()
        .args(["-q", &qp, "edit", &id, "--rm-source", "5"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("out of range").or(
            predicate::str::contains("index"),
        ));
}

// ── EDGE CASE: collect --by-file with --title sets same title for all items ──
//
// When using --title with collect, every item gets the exact same title.
// This works but may not be what users expect vs --title-template.
// Verify the behavior is at least consistent.
#[test]
fn test_collect_with_title_gives_all_items_same_title() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args([
            "-q", &qp, "collect", "--by-file", "--title", "Same for all", "--json",
        ])
        .write_stdin(rg_json_input())
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let items = json.as_array().unwrap();
    assert_eq!(items.len(), 2);
    // Both items should have the same title
    assert_eq!(items[0]["title"], "Same for all");
    assert_eq!(items[1]["title"], "Same for all");
}

// ── EDGE CASE: list --reverse without --sort ─────────────────────────────────
//
// --reverse should work with the default sort order too.
#[test]
fn test_list_reverse_with_default_sort() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add", "--title", "first", "--priority", "0"])
        .assert()
        .success();
    sq_cmd()
        .args(["-q", &qp, "add", "--title", "second", "--priority", "4"])
        .assert()
        .success();

    let output = sq_cmd()
        .args(["-q", &qp, "list", "--reverse", "--json"])
        .output()
        .unwrap();

    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let items = json.as_array().unwrap();
    // Default sort: priority 0 first, then 4. Reversed: 4 first, then 0.
    assert_eq!(items[0]["title"], "second");
    assert_eq!(items[1]["title"], "first");
}

// ── DOCUMENTATION: Prime output uses 6-char IDs but generated IDs are 3-char ─
//
// The prime command includes examples like `abc123`, `xyz789`, `def456` which
// are 6 characters, but generate_id() creates 3-character IDs. This could
// confuse users/agents.
#[test]
fn test_prime_example_ids_match_generated_id_length() {
    let output = sq_cmd()
        .args(["prime"])
        .output()
        .unwrap();

    let stdout = String::from_utf8(output.stdout).unwrap();

    // The examples use abc123, xyz789, def456 which are 6 chars.
    // These should match the actual ID format (3-char alphanumeric).
    // This test will fail because prime hardcodes 6-char example IDs.
    assert!(
        !stdout.contains("abc123"),
        "Prime examples should use 3-char IDs to match actual generated IDs, \
         but contains 'abc123' (6 chars)"
    );
}
