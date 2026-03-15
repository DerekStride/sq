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
fn test_list_invalid_status_fails() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add", "--text", "item1"])
        .assert()
        .success();

    sq_cmd()
        .args(["-q", &qp, "list", "--status", "bogus_status"])
        .assert()
        .failure()
        .stderr(predicate::str::contains(
            "Invalid status: bogus_status. Valid: pending, in_progress, closed",
        ));
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
