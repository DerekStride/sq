use sq::queue::{Item, Queue, Source, UpdateAttrs, Worktree};
use std::collections::HashSet;
use tempfile::TempDir;

fn test_queue(dir: &TempDir) -> Queue {
    let path = dir.path().join("queue.jsonl");
    Queue::new(path)
}

// ── JSONL Round-trip Tests ──────────────────────────────────────────────────

#[test]
fn test_parse_minimal_item() {
    let json = r#"{"id":"abc","status":"pending","sources":[{"type":"text","content":"Hello world"}],"metadata":{},"session_id":null,"created_at":"2025-01-01T12:00:00.000Z","updated_at":"2025-01-01T12:00:00.000Z"}"#;
    let item: Item = serde_json::from_str(json).unwrap();
    assert_eq!(item.id, "abc");
    assert_eq!(item.status, "pending");
    assert!(item.title.is_none());
    assert_eq!(item.sources.len(), 1);
    assert_eq!(item.sources[0].type_, "text");
    assert_eq!(item.sources[0].content.as_deref(), Some("Hello world"));
    assert!(item.session_id.is_none());
    assert!(item.worktree.is_none());
    assert!(item.blocked_by.is_empty());
    assert!(item.errors.is_empty());

    // Round-trip: serialize and compare
    let serialized = item.to_json_string();
    assert_eq!(serialized, json);
}

#[test]
fn test_parse_full_item() {
    let json = r#"{"id":"x1y","title":"Fix login bug","status":"in_progress","sources":[{"type":"diff","path":"/changes.patch","session_id":"sess123"},{"type":"text","content":"Summary"}],"metadata":{"workflow":"analyze","priority":1},"session_id":"sess456","created_at":"2025-01-01T12:00:00.000Z","updated_at":"2025-01-01T12:05:00.000Z","worktree":{"path":".sift/worktrees/x1y","branch":"sift/x1y"},"blocked_by":["abc","def"],"errors":[{"message":"timeout","timestamp":"2025-01-01T12:01:00.000Z"}]}"#;
    let item: Item = serde_json::from_str(json).unwrap();
    assert_eq!(item.id, "x1y");
    assert_eq!(item.title.as_deref(), Some("Fix login bug"));
    assert_eq!(item.status, "in_progress");
    assert_eq!(item.sources.len(), 2);
    assert_eq!(item.session_id.as_deref(), Some("sess456"));
    assert!(item.worktree.is_some());
    assert_eq!(item.blocked_by, vec!["abc", "def"]);
    assert_eq!(item.errors.len(), 1);

    // Round-trip
    let serialized = item.to_json_string();
    assert_eq!(serialized, json);
}

#[test]
fn test_source_round_trip() {
    // Source with only type
    let json = r#"{"type":"directory","path":"/some/dir"}"#;
    let source: Source = serde_json::from_str(json).unwrap();
    assert_eq!(source.type_, "directory");
    assert_eq!(source.path.as_deref(), Some("/some/dir"));
    assert!(source.content.is_none());
    let serialized = source.to_json_value().to_string();
    assert_eq!(serialized, json);
}

#[test]
fn test_unknown_source_type_round_trip() {
    // Source types are free-form strings; unknown types must round-trip
    let json = r#"{"type":"transcript","path":"/session.jsonl"}"#;
    let source: Source = serde_json::from_str(json).unwrap();
    assert_eq!(source.type_, "transcript");
    let serialized = source.to_json_value().to_string();
    assert_eq!(serialized, json);
}

#[test]
fn test_session_id_always_serialized() {
    // Even when null, session_id must appear in JSON output
    let item = Item {
        id: "abc".to_string(),
        title: None,
        status: "pending".to_string(),
        sources: vec![Source {
            type_: "text".to_string(),
            path: None,
            content: Some("test".to_string()),
            session_id: None,
        }],
        metadata: serde_json::json!({}),
        session_id: None,
        worktree: None,
        blocked_by: Vec::new(),
        errors: Vec::new(),
        created_at: "2025-01-01T12:00:00.000Z".to_string(),
        updated_at: "2025-01-01T12:00:00.000Z".to_string(),
    };
    let json = item.to_json_string();
    assert!(json.contains("\"session_id\":null"), "session_id must appear even when null");
}

#[test]
fn test_optional_fields_omitted_when_empty() {
    let item = Item {
        id: "abc".to_string(),
        title: None,
        status: "pending".to_string(),
        sources: vec![Source {
            type_: "text".to_string(),
            path: None,
            content: Some("test".to_string()),
            session_id: None,
        }],
        metadata: serde_json::json!({}),
        session_id: None,
        worktree: None,
        blocked_by: Vec::new(),
        errors: Vec::new(),
        created_at: "2025-01-01T12:00:00.000Z".to_string(),
        updated_at: "2025-01-01T12:00:00.000Z".to_string(),
    };
    let json = item.to_json_string();
    assert!(!json.contains("\"title\""), "title should be omitted when None");
    assert!(!json.contains("\"worktree\""), "worktree should be omitted when None");
    assert!(!json.contains("\"blocked_by\""), "blocked_by should be omitted when empty");
    assert!(!json.contains("\"errors\""), "errors should be omitted when empty");
}

#[test]
fn test_worktree_serialization() {
    let wt = Worktree {
        path: Some(".sift/worktrees/abc".to_string()),
        branch: Some("sift/abc".to_string()),
    };
    let json = wt.to_json_value().to_string();
    assert_eq!(json, r#"{"path":".sift/worktrees/abc","branch":"sift/abc"}"#);
}

// ── Queue Operation Tests ───────────────────────────────────────────────────

#[test]
fn test_push_and_find() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let item = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("Hello".to_string()),
                session_id: None,
            }],
            Some("Test".to_string()),
            serde_json::json!({}),
            None,
            vec![],
        )
        .unwrap();

    assert_eq!(item.id.len(), 3);
    assert_eq!(item.status, "pending");
    assert_eq!(item.title.as_deref(), Some("Test"));

    let found = queue.find(&item.id);
    assert!(found.is_some());
    assert_eq!(found.unwrap().id, item.id);
}

#[test]
fn test_push_validates_empty_sources() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);
    let result = queue.push(vec![], None, serde_json::json!({}), None, vec![]);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("Sources cannot be empty"));
}

#[test]
fn test_push_validates_source_type() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);
    let result = queue.push(
        vec![Source {
            type_: "invalid".to_string(),
            path: None,
            content: Some("test".to_string()),
            session_id: None,
        }],
        None,
        serde_json::json!({}),
        None,
        vec![],
    );
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("Invalid source type"));
}

#[test]
fn test_push_unique_ids() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);
    let mut ids = HashSet::new();

    for _ in 0..20 {
        let item = queue
            .push(
                vec![Source {
                    type_: "text".to_string(),
                    path: None,
                    content: Some("test".to_string()),
                    session_id: None,
                }],
                None,
                serde_json::json!({}),
                None,
                vec![],
            )
            .unwrap();
        assert!(ids.insert(item.id.clone()), "Duplicate ID generated: {}", item.id);
    }
}

#[test]
fn test_all_items() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("first".to_string()),
                session_id: None,
            }],
            None,
            serde_json::json!({}),
            None,
            vec![],
        )
        .unwrap();
    queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("second".to_string()),
                session_id: None,
            }],
            None,
            serde_json::json!({}),
            None,
            vec![],
        )
        .unwrap();

    let items = queue.all();
    assert_eq!(items.len(), 2);
}

#[test]
fn test_all_nonexistent_file() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("nonexistent.jsonl");
    let queue = Queue::new(path);
    let items = queue.all();
    assert!(items.is_empty());
}

#[test]
fn test_filter_by_status() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let item = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("test".to_string()),
                session_id: None,
            }],
            None,
            serde_json::json!({}),
            None,
            vec![],
        )
        .unwrap();

    queue
        .update(
            &item.id,
            UpdateAttrs {
                status: Some("closed".to_string()),
                ..Default::default()
            },
        )
        .unwrap();

    queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("test2".to_string()),
                session_id: None,
            }],
            None,
            serde_json::json!({}),
            None,
            vec![],
        )
        .unwrap();

    let pending = queue.filter(Some("pending"));
    assert_eq!(pending.len(), 1);

    let closed = queue.filter(Some("closed"));
    assert_eq!(closed.len(), 1);

    let all = queue.filter(None);
    assert_eq!(all.len(), 2);
}

#[test]
fn test_ready_items() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let blocker = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("blocker".to_string()),
                session_id: None,
            }],
            None,
            serde_json::json!({}),
            None,
            vec![],
        )
        .unwrap();

    let _blocked = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("blocked".to_string()),
                session_id: None,
            }],
            None,
            serde_json::json!({}),
            None,
            vec![blocker.id.clone()],
        )
        .unwrap();

    let ready = queue.ready();
    assert_eq!(ready.len(), 1);
    assert_eq!(ready[0].id, blocker.id);
}

#[test]
fn test_ready_unblocks_after_close() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let blocker = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("blocker".to_string()),
                session_id: None,
            }],
            None,
            serde_json::json!({}),
            None,
            vec![],
        )
        .unwrap();

    let blocked = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("blocked".to_string()),
                session_id: None,
            }],
            None,
            serde_json::json!({}),
            None,
            vec![blocker.id.clone()],
        )
        .unwrap();

    // Close blocker
    queue
        .update(
            &blocker.id,
            UpdateAttrs {
                status: Some("closed".to_string()),
                ..Default::default()
            },
        )
        .unwrap();

    let ready = queue.ready();
    assert_eq!(ready.len(), 1);
    assert_eq!(ready[0].id, blocked.id);
}

#[test]
fn test_update_item() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let item = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("test".to_string()),
                session_id: None,
            }],
            None,
            serde_json::json!({}),
            None,
            vec![],
        )
        .unwrap();

    let updated = queue
        .update(
            &item.id,
            UpdateAttrs {
                status: Some("in_progress".to_string()),
                title: Some("New title".to_string()),
                metadata: Some(serde_json::json!({"key": "value"})),
                ..Default::default()
            },
        )
        .unwrap()
        .unwrap();

    assert_eq!(updated.status, "in_progress");
    assert_eq!(updated.title.as_deref(), Some("New title"));
    assert_eq!(updated.metadata["key"], "value");
    assert_ne!(updated.updated_at, item.updated_at);
}

#[test]
fn test_update_invalid_status() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let item = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("test".to_string()),
                session_id: None,
            }],
            None,
            serde_json::json!({}),
            None,
            vec![],
        )
        .unwrap();

    let result = queue.update(
        &item.id,
        UpdateAttrs {
            status: Some("invalid".to_string()),
            ..Default::default()
        },
    );
    assert!(result.is_err());
}

#[test]
fn test_update_nonexistent() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let result = queue
        .update(
            "zzz",
            UpdateAttrs {
                status: Some("closed".to_string()),
                ..Default::default()
            },
        )
        .unwrap();
    assert!(result.is_none());
}

#[test]
fn test_remove_item() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let item = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("test".to_string()),
                session_id: None,
            }],
            None,
            serde_json::json!({}),
            None,
            vec![],
        )
        .unwrap();

    let removed = queue.remove(&item.id).unwrap();
    assert!(removed.is_some());
    assert_eq!(removed.unwrap().id, item.id);

    let items = queue.all();
    assert!(items.is_empty());
}

#[test]
fn test_remove_nonexistent() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let result = queue.remove("zzz").unwrap();
    assert!(result.is_none());
}

#[test]
fn test_corrupt_line_skipped() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("queue.jsonl");
    std::fs::write(
        &path,
        r#"{"id":"abc","status":"pending","sources":[{"type":"text","content":"good"}],"metadata":{},"session_id":null,"created_at":"2025-01-01T12:00:00.000Z","updated_at":"2025-01-01T12:00:00.000Z"}
this is not valid json
{"id":"def","status":"pending","sources":[{"type":"text","content":"also good"}],"metadata":{},"session_id":null,"created_at":"2025-01-01T12:00:00.000Z","updated_at":"2025-01-01T12:00:00.000Z"}
"#,
    )
    .unwrap();

    let queue = Queue::new(path);
    let items = queue.all();
    assert_eq!(items.len(), 2);
    assert_eq!(items[0].id, "abc");
    assert_eq!(items[1].id, "def");
}

#[test]
fn test_empty_lines_skipped() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("queue.jsonl");
    std::fs::write(
        &path,
        r#"
{"id":"abc","status":"pending","sources":[{"type":"text","content":"test"}],"metadata":{},"session_id":null,"created_at":"2025-01-01T12:00:00.000Z","updated_at":"2025-01-01T12:00:00.000Z"}

"#,
    )
    .unwrap();

    let queue = Queue::new(path);
    let items = queue.all();
    assert_eq!(items.len(), 1);
}

#[test]
fn test_timestamp_format() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let item = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("test".to_string()),
                session_id: None,
            }],
            None,
            serde_json::json!({}),
            None,
            vec![],
        )
        .unwrap();

    // Format: YYYY-MM-DDTHH:MM:SS.mmmZ
    let re = regex_lite(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$");
    assert!(re.is_match(&item.created_at), "Bad timestamp format: {}", item.created_at);
    assert!(re.is_match(&item.updated_at), "Bad timestamp format: {}", item.updated_at);
}

// Simple regex matcher without importing regex crate
fn regex_lite(pattern: &str) -> RegexLite {
    RegexLite(pattern.to_string())
}

struct RegexLite(String);

impl RegexLite {
    fn is_match(&self, s: &str) -> bool {
        // Simple check for the timestamp format pattern
        if self.0 == r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$" {
            if s.len() != 24 {
                return false;
            }
            // Check positions: YYYY-MM-DDTHH:MM:SS.mmmZ
            let chars: Vec<char> = s.chars().collect();
            chars[4] == '-' && chars[7] == '-' && chars[10] == 'T'
                && chars[13] == ':' && chars[16] == ':' && chars[19] == '.'
                && chars[23] == 'Z'
                && chars.iter().enumerate().all(|(i, c)| {
                    if [4, 7, 10, 13, 16, 19, 23].contains(&i) {
                        true
                    } else {
                        c.is_ascii_digit()
                    }
                })
        } else {
            false
        }
    }
}

#[test]
fn test_id_format() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    for _ in 0..10 {
        let item = queue
            .push(
                vec![Source {
                    type_: "text".to_string(),
                    path: None,
                    content: Some("test".to_string()),
                    session_id: None,
                }],
                None,
                serde_json::json!({}),
                None,
                vec![],
            )
            .unwrap();
        assert_eq!(item.id.len(), 3);
        assert!(item.id.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit()),
            "ID contains invalid chars: {}", item.id);
    }
}

#[test]
fn test_metadata_preserved() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let item = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("test".to_string()),
                session_id: None,
            }],
            None,
            serde_json::json!({"nested": {"key": "value"}, "array": [1, 2, 3]}),
            None,
            vec![],
        )
        .unwrap();

    let found = queue.find(&item.id).unwrap();
    assert_eq!(found.metadata["nested"]["key"], "value");
    assert_eq!(found.metadata["array"], serde_json::json!([1, 2, 3]));
}

// ── Fixture-based Round-trip Test ───────────────────────────────────────────

#[test]
fn test_fixture_round_trip() {
    let fixture = include_str!("fixtures/queue_samples.jsonl");
    for line in fixture.lines() {
        if line.trim().is_empty() {
            continue;
        }
        let item: Item = serde_json::from_str(line).unwrap();
        let serialized = item.to_json_string();
        assert_eq!(serialized, line, "Round-trip mismatch for item {}", item.id);
    }
}
