use assert_cmd::Command;
use predicates::prelude::*;
use std::fs;
use tempfile::TempDir;

fn sq_cmd() -> Command {
    Command::cargo_bin("sq").unwrap()
}

fn queue_path(dir: &TempDir) -> String {
    dir.path().join("queue.jsonl").to_str().unwrap().to_string()
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
fn test_add_with_metadata() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args([
            "-q", &qp, "add", "--text", "content",
            "--metadata", r#"{"workflow":"analyze"}"#,
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
            "-q", &qp, "add", "--text", "content",
            "--blocked-by", "abc,def",
        ])
        .assert()
        .success();

    let content = fs::read_to_string(dir.path().join("queue.jsonl")).unwrap();
    assert!(content.contains("\"blocked_by\":[\"abc\",\"def\"]"));
}

#[test]
fn test_add_multiple_sources() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args([
            "-q", &qp, "add",
            "--text", "some text",
            "--diff", "changes.patch",
            "--file", "main.rb",
        ])
        .assert()
        .success();

    let content = fs::read_to_string(dir.path().join("queue.jsonl")).unwrap();
    assert!(content.contains("\"type\":\"text\""));
    assert!(content.contains("\"type\":\"diff\""));
    assert!(content.contains("\"type\":\"file\""));
}

#[test]
fn test_add_no_sources_fails() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    sq_cmd()
        .args(["-q", &qp, "add"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("At least one source is required"));
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
    let json: serde_json::Value =
        serde_json::from_slice(&output.stdout).unwrap();
    assert!(json.is_array());
    assert_eq!(json.as_array().unwrap().len(), 1);
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
        .args(["-q", &qp, "add", "--text", "blocked", "--blocked-by", &blocker_id])
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
        .args(["-q", &qp, "add", "--text", "content", "--title", "My Item"])
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
    assert_eq!(json["status"], "pending");
    assert!(json["session_id"].is_null());
}

#[test]
fn test_show_human_readable() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "content", "--title", "My Item"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    sq_cmd()
        .args(["-q", &qp, "show", &id])
        .assert()
        .success()
        .stdout(predicate::str::contains("Item:"))
        .stdout(predicate::str::contains("Title: My Item"))
        .stdout(predicate::str::contains("Status: pending"))
        .stdout(predicate::str::contains("Session: none"));
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
fn test_edit_add_and_rm_source() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "original", "--text", "remove me"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    // Remove second source (index 1) and add a new one
    sq_cmd()
        .args([
            "-q", &qp, "edit", &id,
            "--rm-source", "1",
            "--add-text", "replacement",
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

// ── Prime Command ───────────────────────────────────────────────────────────

#[test]
fn test_prime_output() {
    sq_cmd()
        .args(["prime"])
        .assert()
        .success()
        .stdout(predicate::str::contains("# Sift — Queue-Driven Review System"))
        .stdout(predicate::str::contains("## `sq` Commands"))
        .stdout(predicate::str::contains("### `sq add`"))
        .stdout(predicate::str::contains("### `sq list`"))
        .stdout(predicate::str::contains("### `sq show`"))
        .stdout(predicate::str::contains("### `sq edit`"))
        .stdout(predicate::str::contains("### `sq rm`"));
}

// ── Queue Path Resolution ───────────────────────────────────────────────────

#[test]
fn test_env_queue_path() {
    let dir = TempDir::new().unwrap();
    let qp = dir.path().join("env_queue.jsonl");

    let output = sq_cmd()
        .env("SIFT_QUEUE_PATH", qp.to_str().unwrap())
        .args(["add", "--text", "env test"])
        .output()
        .unwrap();

    assert!(output.status.success());
    assert!(qp.exists());
}

// ── JSON Field Order ────────────────────────────────────────────────────────

#[test]
fn test_json_field_order() {
    let dir = TempDir::new().unwrap();
    let qp = queue_path(&dir);

    let output = sq_cmd()
        .args(["-q", &qp, "add", "--text", "test", "--title", "Title"])
        .output()
        .unwrap();
    let id = String::from_utf8(output.stdout).unwrap().trim().to_string();

    let output = sq_cmd()
        .args(["-q", &qp, "show", &id, "--json"])
        .output()
        .unwrap();
    let stdout = String::from_utf8(output.stdout).unwrap();

    // Verify field order: id, title, status, sources, metadata, session_id, created_at, updated_at
    let id_pos = stdout.find("\"id\"").unwrap();
    let title_pos = stdout.find("\"title\"").unwrap();
    let status_pos = stdout.find("\"status\"").unwrap();
    let sources_pos = stdout.find("\"sources\"").unwrap();
    let metadata_pos = stdout.find("\"metadata\"").unwrap();
    let session_id_pos = stdout.find("\"session_id\"").unwrap();
    let created_at_pos = stdout.find("\"created_at\"").unwrap();
    let updated_at_pos = stdout.find("\"updated_at\"").unwrap();

    assert!(id_pos < title_pos);
    assert!(title_pos < status_pos);
    assert!(status_pos < sources_pos);
    assert!(sources_pos < metadata_pos);
    assert!(metadata_pos < session_id_pos);
    assert!(session_id_pos < created_at_pos);
    assert!(created_at_pos < updated_at_pos);
}
