use sift_queue::queue::{parse_priority_value, Item, Queue, Source, UpdateAttrs};
use std::collections::HashSet;
use tempfile::TempDir;

fn test_queue(dir: &TempDir) -> Queue {
    let path = dir.path().join("queue.jsonl");
    Queue::new(path)
}

// ── JSONL Parsing + Serialization Tests ─────────────────────────────────────

#[test]
fn test_parse_minimal_item() {
    let json = r#"{"id":"abc","status":"pending","sources":[{"type":"text","content":"Hello world"}],"metadata":{},"created_at":"2025-01-01T12:00:00.000Z","updated_at":"2025-01-01T12:00:00.000Z"}"#;
    let item: Item = serde_json::from_str(json).unwrap();
    assert_eq!(item.id, "abc");
    assert_eq!(item.status, "pending");
    assert!(item.title.is_none());
    assert!(item.description.is_none());
    assert_eq!(item.sources.len(), 1);
    assert_eq!(item.sources[0].type_, "text");
    assert_eq!(item.sources[0].content.as_deref(), Some("Hello world"));
    assert!(item.blocked_by.is_empty());
    assert!(item.errors.is_empty());

    let serialized = item.to_json_value();
    assert_eq!(serialized["id"], "abc");
    assert_eq!(serialized["status"], "pending");
    assert!(serialized.get("created_at").is_some());
    assert!(serialized.get("updated_at").is_some());
}

#[test]
fn test_parse_full_item() {
    let json = r#"{"id":"x1y","title":"Fix login bug","status":"in_progress","priority":1,"sources":[{"type":"diff","path":"/changes.patch"},{"type":"text","content":"Summary"}],"metadata":{"workflow":"analyze"},"created_at":"2025-01-01T12:00:00.000Z","updated_at":"2025-01-01T12:05:00.000Z","blocked_by":["abc","def"],"errors":[{"message":"timeout","timestamp":"2025-01-01T12:01:00.000Z"}]}"#;
    let item: Item = serde_json::from_str(json).unwrap();
    assert_eq!(item.id, "x1y");
    assert_eq!(item.title.as_deref(), Some("Fix login bug"));
    assert!(item.description.is_none());
    assert_eq!(item.status, "in_progress");
    assert_eq!(item.priority, Some(1));
    assert_eq!(item.sources.len(), 2);
    assert_eq!(item.blocked_by, vec!["abc", "def"]);
    assert_eq!(item.errors.len(), 1);

    let serialized = item.to_json_value();
    assert_eq!(serialized["priority"], 1);
    assert_eq!(serialized["blocked_by"], serde_json::json!(["abc", "def"]));
    assert_eq!(serialized["errors"].as_array().unwrap().len(), 1);
}

#[test]
fn test_parse_priority_value_accepts_numeric_only() {
    assert_eq!(parse_priority_value("0").unwrap(), 0);
    assert_eq!(parse_priority_value("4").unwrap(), 4);
    assert!(parse_priority_value("P4").is_err());
    assert!(parse_priority_value("p2").is_err());
    assert!(parse_priority_value("5").is_err());
}

#[test]
fn test_source_serialization() {
    let json = r#"{"type":"directory","path":"/some/dir"}"#;
    let source: Source = serde_json::from_str(json).unwrap();
    assert_eq!(source.type_, "directory");
    assert_eq!(source.path.as_deref(), Some("/some/dir"));
    assert!(source.content.is_none());
    let serialized = source.to_json_value();
    assert_eq!(serialized["type"], "directory");
    assert_eq!(serialized["path"], "/some/dir");
}

#[test]
fn test_unknown_source_type_serialization() {
    let json = r#"{"type":"transcript","path":"/session.jsonl"}"#;
    let source: Source = serde_json::from_str(json).unwrap();
    assert_eq!(source.type_, "transcript");
    let serialized = source.to_json_value();
    assert_eq!(serialized["type"], "transcript");
    assert_eq!(serialized["path"], "/session.jsonl");
}

#[test]
fn test_optional_fields_omitted_when_empty() {
    let item = Item {
        id: "abc".to_string(),
        title: None,
        description: None,
        status: "pending".to_string(),
        priority: None,
        sources: vec![Source {
            type_: "text".to_string(),
            path: None,
            content: Some("test".to_string()),
        }],
        metadata: serde_json::json!({}),
        blocked_by: Vec::new(),
        errors: Vec::new(),
        created_at: "2025-01-01T12:00:00.000Z".to_string(),
        updated_at: "2025-01-01T12:00:00.000Z".to_string(),
    };
    let json = item.to_json_string();
    assert!(
        !json.contains("\"title\""),
        "title should be omitted when None"
    );
    assert!(
        !json.contains("\"description\""),
        "description should be omitted when None"
    );
    assert!(
        !json.contains("\"blocked_by\""),
        "blocked_by should be omitted when empty"
    );
    assert!(
        !json.contains("\"errors\""),
        "errors should be omitted when empty"
    );
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
                }],
            Some("Test".to_string()),
            None,
            serde_json::json!({}),
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
    let result = queue.push(vec![], None, None, serde_json::json!({}), vec![]);
    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Sources cannot be empty"));
}

#[test]
fn test_push_with_description_allows_empty_sources() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let item = queue
        .push_with_description(
            vec![],
            Some("Title".to_string()),
            Some("Description".to_string()),
            None,
            serde_json::json!({}),
            vec![],
        )
        .unwrap();

    assert_eq!(item.title.as_deref(), Some("Title"));
    assert_eq!(item.description.as_deref(), Some("Description"));
    assert!(item.sources.is_empty());
}

#[test]
fn test_push_with_title_allows_empty_sources() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let item = queue
        .push_with_description(
            vec![],
            Some("Title".to_string()),
            None,
            None,
            serde_json::json!({}),
            vec![],
        )
        .unwrap();

    assert_eq!(item.title.as_deref(), Some("Title"));
    assert!(item.description.is_none());
    assert!(item.sources.is_empty());
}

#[test]
fn test_push_with_metadata_only_requires_task_content() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let result = queue.push_with_description(
        vec![],
        None,
        None,
        None,
        serde_json::json!({"kind":"task"}),
        vec![],
    );

    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Item requires at least one source, title, or description"));
}

#[test]
fn test_push_with_description_requires_some_content_when_sources_empty() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let result =
        queue.push_with_description(vec![], None, None, None, serde_json::json!({}), vec![]);
    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Item requires at least one source, title, or description"));
}

#[test]
fn test_push_with_priority_only_requires_task_content() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let result = queue.push_with_description(
        vec![],
        None,
        None,
        Some(1),
        serde_json::json!({}),
        vec![],
    );

    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Item requires at least one source, title, or description"));
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
        }],
        None,
        None,
        serde_json::json!({}),
        vec![],
    );
    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Invalid source type"));
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
                        }],
                None,
                None,
                serde_json::json!({}),
                vec![],
            )
            .unwrap();
        assert!(
            ids.insert(item.id.clone()),
            "Duplicate ID generated: {}",
            item.id
        );
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
                }],
            None,
            None,
            serde_json::json!({}),
            vec![],
        )
        .unwrap();
    queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("second".to_string()),
                }],
            None,
            None,
            serde_json::json!({}),
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
                }],
            None,
            None,
            serde_json::json!({}),
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
                }],
            None,
            None,
            serde_json::json!({}),
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
                }],
            None,
            None,
            serde_json::json!({}),
            vec![],
        )
        .unwrap();

    let _blocked = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("blocked".to_string()),
                }],
            None,
            None,
            serde_json::json!({}),
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
                }],
            None,
            None,
            serde_json::json!({}),
            vec![],
        )
        .unwrap();

    let blocked = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("blocked".to_string()),
                }],
            None,
            None,
            serde_json::json!({}),
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
                }],
            None,
            None,
            serde_json::json!({}),
            vec![],
        )
        .unwrap();

    let updated = queue
        .update(
            &item.id,
            UpdateAttrs {
                status: Some("in_progress".to_string()),
                title: Some("New title".to_string()),
                description: Some("New description".to_string()),
                priority: Some(Some(1)),
                metadata: Some(serde_json::json!({"key": "value"})),
                ..Default::default()
            },
        )
        .unwrap()
        .unwrap();

    assert_eq!(updated.status, "in_progress");
    assert_eq!(updated.title.as_deref(), Some("New title"));
    assert_eq!(updated.description.as_deref(), Some("New description"));
    assert_eq!(updated.priority, Some(1));
    assert_eq!(updated.metadata["key"], "value");
    assert!(updated.updated_at >= item.updated_at);
}

#[test]
fn test_update_can_clear_priority() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let item = queue
        .push_with_description(
            vec![],
            Some("Test".to_string()),
            None,
            Some(1),
            serde_json::json!({}),
            vec![],
        )
        .unwrap();

    let updated = queue
        .update(
            &item.id,
            UpdateAttrs {
                priority: Some(None),
                ..Default::default()
            },
        )
        .unwrap()
        .unwrap();

    assert_eq!(updated.priority, None);
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
                }],
            None,
            None,
            serde_json::json!({}),
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
                }],
            None,
            None,
            serde_json::json!({}),
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
        r#"{"id":"abc","status":"pending","sources":[{"type":"text","content":"good"}],"metadata":{},"created_at":"2025-01-01T12:00:00.000Z","updated_at":"2025-01-01T12:00:00.000Z"}
this is not valid json
{"id":"def","status":"pending","sources":[{"type":"text","content":"also good"}],"metadata":{},"created_at":"2025-01-01T12:00:00.000Z","updated_at":"2025-01-01T12:00:00.000Z"}
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
{"id":"abc","status":"pending","sources":[{"type":"text","content":"test"}],"metadata":{},"created_at":"2025-01-01T12:00:00.000Z","updated_at":"2025-01-01T12:00:00.000Z"}

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
                }],
            None,
            None,
            serde_json::json!({}),
            vec![],
        )
        .unwrap();

    // Format: YYYY-MM-DDTHH:MM:SS.mmmZ
    let re = regex_lite(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$");
    assert!(
        re.is_match(&item.created_at),
        "Bad timestamp format: {}",
        item.created_at
    );
    assert!(
        re.is_match(&item.updated_at),
        "Bad timestamp format: {}",
        item.updated_at
    );
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
            chars[4] == '-'
                && chars[7] == '-'
                && chars[10] == 'T'
                && chars[13] == ':'
                && chars[16] == ':'
                && chars[19] == '.'
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
                        }],
                None,
                None,
                serde_json::json!({}),
                vec![],
            )
            .unwrap();
        assert_eq!(item.id.len(), 3);
        assert!(
            item.id
                .chars()
                .all(|c: char| c.is_ascii_lowercase() || c.is_ascii_digit()),
            "ID contains invalid chars: {}",
            item.id
        );
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
                }],
            None,
            None,
            serde_json::json!({"nested": {"key": "value"}, "array": [1, 2, 3]}),
            vec![],
        )
        .unwrap();

    let found = queue.find(&item.id).unwrap();
    assert_eq!(found.metadata["nested"]["key"], "value");
    assert_eq!(found.metadata["array"], serde_json::json!([1, 2, 3]));
}

// ══════════════════════════════════════════════════════════════════════════════
// AUDIT — Failing tests for discovered bugs, edge cases, and missing validation
// ══════════════════════════════════════════════════════════════════════════════

// ── BUG: push() rejects empty sources but push_with_description() doesn't ───
//
// These two APIs have asymmetric validation. push() always requires sources,
// but push_with_description() allows empty sources if there's a title.
// This is intentional, but push() bypasses this by calling validate_sources()
// first and then delegating to push_with_description(). The two codepaths
// give different errors for the same underlying situation.
#[test]
fn test_push_error_message_matches_push_with_description() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    // push() with empty sources + title gives "Sources cannot be empty"
    let push_err = queue
        .push(vec![], Some("Title".to_string()), None, serde_json::json!({}), vec![])
        .unwrap_err();

    // But this should succeed because there IS a title — same as push_with_description
    // BUG: push() rejects valid input that push_with_description() accepts
    let push_desc_result = queue.push_with_description(
        vec![],
        Some("Title".to_string()),
        None,
        None,
        serde_json::json!({}),
        vec![],
    );

    assert!(
        push_desc_result.is_ok(),
        "push_with_description accepts empty sources with title"
    );

    // The push() error says "Sources cannot be empty" even though the item
    // has a title and would be valid. This is because push() pre-validates
    // sources before delegating.
    assert!(
        !push_err.to_string().contains("Sources cannot be empty"),
        "push() should not reject items with a title just because sources are empty. \
         Error was: {}",
        push_err
    );
}

// ── BUG: update() validates status but not source types ──────────────────────
//
// Queue::update() validates status values but does NOT validate source types
// when sources are replaced. You can update an item's sources to contain
// invalid types like "transcript" or "bogus" through the update API.
#[test]
fn test_update_should_validate_source_types() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let item = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("test".to_string()),
            }],
            None,
            None,
            serde_json::json!({}),
            vec![],
        )
        .unwrap();

    // Replacing sources with an invalid type should fail
    let result = queue.update(
        &item.id,
        UpdateAttrs {
            sources: Some(vec![Source {
                type_: "invalid_type".to_string(),
                path: None,
                content: Some("test".to_string()),
            }]),
            ..Default::default()
        },
    );

    assert!(
        result.is_err(),
        "update() should validate source types but currently doesn't"
    );
}

// ── EDGE CASE: ready() with self-blocked item ────────────────────────────────
//
// An item that blocks itself should not be considered ready.
#[test]
fn test_ready_self_blocked_item_not_ready() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let item = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("self-blocker".to_string()),
            }],
            None,
            None,
            serde_json::json!({}),
            vec![],
        )
        .unwrap();

    // Set item to block itself
    queue
        .update(
            &item.id,
            UpdateAttrs {
                blocked_by: Some(vec![item.id.clone()]),
                ..Default::default()
            },
        )
        .unwrap();

    let ready = queue.ready();
    assert!(
        ready.is_empty() || !ready.iter().any(|i| i.id == item.id),
        "Self-blocked item should not appear in ready list"
    );
}

// ── EDGE CASE: ready() with in_progress blocker ──────────────────────────────
//
// Currently ready() only considers pending items as blockers. An item
// blocked by an in_progress item is considered "ready" because the blocker
// isn't pending. This may be surprising.
#[test]
fn test_ready_blocked_by_in_progress_is_not_ready() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let blocker = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("blocker".to_string()),
            }],
            None,
            None,
            serde_json::json!({}),
            vec![],
        )
        .unwrap();

    let blocked = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("blocked".to_string()),
            }],
            None,
            None,
            serde_json::json!({}),
            vec![blocker.id.clone()],
        )
        .unwrap();

    // Move blocker to in_progress
    queue
        .update(
            &blocker.id,
            UpdateAttrs {
                status: Some("in_progress".to_string()),
                ..Default::default()
            },
        )
        .unwrap();

    let ready = queue.ready();
    // The blocked item should NOT be ready because its blocker is in_progress
    // BUG: Currently the blocked item IS considered ready because ready()
    // only looks at pending_ids, and in_progress items aren't pending.
    assert!(
        !ready.iter().any(|i| i.id == blocked.id),
        "Item blocked by in_progress item should not be ready"
    );
}

// ── EDGE CASE: ID generation with nearly-full ID space ───────────────────────
//
// With 3-char alphanumeric IDs (36^3 = 46656 possibilities), the generator
// loops until it finds an unused one. This test doesn't exercise exhaustion
// but verifies the ID space characteristics.
#[test]
fn test_id_uses_lowercase_and_digits_only() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    for _ in 0..50 {
        let item = queue
            .push(
                vec![Source {
                    type_: "text".to_string(),
                    path: None,
                    content: Some("test".to_string()),
                }],
                None,
                None,
                serde_json::json!({}),
                vec![],
            )
            .unwrap();

        assert_eq!(item.id.len(), 3);
        assert!(
            item.id.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit()),
            "ID should only contain lowercase letters and digits: {}",
            item.id
        );
        // No uppercase letters
        assert!(
            !item.id.chars().any(|c| c.is_ascii_uppercase()),
            "ID should not contain uppercase letters: {}",
            item.id
        );
    }
}

// ── FIXTURE DISCREPANCY: x1y has priority in metadata but not as first-class field
//
// The fixture file's x1y item has {"workflow":"analyze","priority":1} in
// metadata, but no top-level "priority" field. This is a legacy data shape
// from before priority was promoted to a first-class field. The fixture
// should be updated to reflect the current schema.
#[test]
fn test_fixture_x1y_has_first_class_priority() {
    let fixture = include_str!("fixtures/queue_samples.jsonl");
    let items: Vec<Item> = fixture
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();

    let x1y = items.iter().find(|i| i.id == "x1y").unwrap();
    // The fixture has priority:1 in metadata but NOT as a first-class field
    assert!(
        x1y.priority.is_some(),
        "Fixture item x1y should have priority as a first-class field, \
         but it only exists in metadata: {:?}",
        x1y.metadata
    );
}

// ── EDGE CASE: update with no changes still bumps updated_at ─────────────────
//
// Calling update() with an UpdateAttrs that matches the current state still
// changes updated_at. This means the item appears modified even though
// nothing actually changed.
#[test]
fn test_update_with_same_values_bumps_updated_at() {
    let dir = TempDir::new().unwrap();
    let queue = test_queue(&dir);

    let item = queue
        .push(
            vec![Source {
                type_: "text".to_string(),
                path: None,
                content: Some("test".to_string()),
            }],
            None,
            None,
            serde_json::json!({}),
            vec![],
        )
        .unwrap();

    // Wait a tiny bit so timestamp would differ
    std::thread::sleep(std::time::Duration::from_millis(5));

    // "Update" with the same status
    let updated = queue
        .update(
            &item.id,
            UpdateAttrs {
                status: Some("pending".to_string()),
                ..Default::default()
            },
        )
        .unwrap()
        .unwrap();

    // updated_at was bumped even though nothing changed
    // This documents the current behavior (not necessarily a bug,
    // but worth knowing about)
    assert_ne!(
        updated.updated_at, item.updated_at,
        "update() always bumps updated_at even when values don't change"
    );
}

// ── Fixture-based Parsing Test ──────────────────────────────────────────────

#[test]
fn test_fixture_items_parse() {
    let fixture = include_str!("fixtures/queue_samples.jsonl");
    let items: Vec<Item> = fixture
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();

    assert_eq!(items.len(), 3);
    assert_eq!(items[0].id, "abc");
    assert_eq!(items[1].id, "x1y");
    assert_eq!(items[2].id, "z99");
}
