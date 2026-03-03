use std::path::PathBuf;

/// Resolve the queue file path from (in priority order):
/// 1. CLI --queue flag
/// 2. SIFT_QUEUE_PATH environment variable
/// 3. Default: .sift/queue.jsonl
pub fn resolve_queue_path(cli_flag: Option<&PathBuf>) -> PathBuf {
    if let Some(path) = cli_flag {
        return path.clone();
    }
    if let Ok(env_path) = std::env::var("SIFT_QUEUE_PATH") {
        return PathBuf::from(env_path);
    }
    PathBuf::from(".sift/queue.jsonl")
}
