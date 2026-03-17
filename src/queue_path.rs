use std::path::{Path, PathBuf};
use std::process::Command;

/// Resolve the queue file path from (in priority order):
/// 1. CLI --queue flag
/// 2. SQ_QUEUE_PATH environment variable
/// 3. Implicit discovery via git worktree semantics
/// 4. Fallback default path
pub fn resolve_queue_path(cli_flag: Option<&PathBuf>) -> PathBuf {
    if let Some(path) = cli_flag {
        return path.clone();
    }
    if let Ok(env_path) = std::env::var("SQ_QUEUE_PATH") {
        return PathBuf::from(env_path);
    }

    let cwd = match std::env::current_dir() {
        Ok(path) => path,
        Err(_) => return PathBuf::from(".sift/issues.jsonl"),
    };

    let git = git_context(&cwd);
    resolve_implicit_queue_path(&cwd, git.as_ref())
}

fn resolve_implicit_queue_path(cwd: &Path, git: Option<&GitContext>) -> PathBuf {
    if let Some(git) = git {
        if let Some(found) = find_existing_queue(&git.cwd, &git.worktree_root) {
            return found;
        }

        if let Some(main_worktree_root) = linked_main_worktree_root(git) {
            if let Ok(rel_cwd) = git.cwd.strip_prefix(&git.worktree_root) {
                if let Some(found) =
                    find_existing_queue(&main_worktree_root.join(rel_cwd), &main_worktree_root)
                {
                    return found;
                }
            }
        }

        return git.cwd.join(".sift").join("issues.jsonl");
    }

    cwd.join(".sift").join("issues.jsonl")
}

#[derive(Debug)]
struct GitContext {
    cwd: PathBuf,
    worktree_root: PathBuf,
    git_dir: PathBuf,
    git_common_dir: PathBuf,
}

fn git_context(cwd: &Path) -> Option<GitContext> {
    let cwd = std::fs::canonicalize(cwd).unwrap_or_else(|_| cwd.to_path_buf());
    let worktree_root = resolve_git_path(&cwd, &git_rev_parse(&cwd, "--show-toplevel")?);
    let git_dir = resolve_git_path(&cwd, &git_rev_parse(&cwd, "--git-dir")?);
    let git_common_dir = resolve_git_path(&cwd, &git_rev_parse(&cwd, "--git-common-dir")?);

    Some(GitContext {
        cwd,
        worktree_root,
        git_dir,
        git_common_dir,
    })
}

fn linked_main_worktree_root(git: &GitContext) -> Option<PathBuf> {
    if git.git_dir == git.git_common_dir {
        return None;
    }

    git.git_common_dir.parent().map(Path::to_path_buf)
}

fn git_rev_parse(cwd: &Path, arg: &str) -> Option<String> {
    let output = Command::new("git")
        .current_dir(cwd)
        .args(["rev-parse", arg])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let stdout = String::from_utf8(output.stdout).ok()?;
    let line = stdout.lines().next()?.trim();
    if line.is_empty() {
        None
    } else {
        Some(line.to_string())
    }
}

fn resolve_git_path(cwd: &Path, raw: &str) -> PathBuf {
    let path = PathBuf::from(raw);
    let absolute = if path.is_absolute() {
        path
    } else {
        cwd.join(path)
    };
    std::fs::canonicalize(&absolute).unwrap_or(absolute)
}

fn find_existing_queue(start: &Path, stop: &Path) -> Option<PathBuf> {
    let mut current = start.to_path_buf();

    loop {
        let candidate = current.join(".sift").join("issues.jsonl");
        if candidate.is_file() {
            return Some(candidate);
        }

        if current == stop {
            return None;
        }

        if !current.starts_with(stop) {
            return None;
        }

        current = current.parent()?.to_path_buf();
    }
}

#[cfg(test)]
mod tests {
    use super::{resolve_implicit_queue_path, GitContext};
    use std::fs;
    use std::path::{Path, PathBuf};
    use tempfile::TempDir;

    fn write_queue(path: &Path) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, "").unwrap();
    }

    #[test]
    fn prefers_nearest_existing_ancestor_queue_in_worktree() {
        let dir = TempDir::new().unwrap();
        let root = dir.path().to_path_buf();
        let cwd = root.join("packages/alpha/client");
        fs::create_dir_all(&cwd).unwrap();

        let ancestor_queue = root.join("packages/.sift/issues.jsonl");
        write_queue(&ancestor_queue);

        let git = GitContext {
            cwd: cwd.clone(),
            worktree_root: root.clone(),
            git_dir: root.join(".git"),
            git_common_dir: root.join(".git"),
        };

        assert_eq!(
            resolve_implicit_queue_path(&cwd, Some(&git)),
            ancestor_queue
        );
    }

    #[test]
    fn falls_back_to_cwd_when_no_existing_queue_is_found() {
        let dir = TempDir::new().unwrap();
        let root = dir.path().to_path_buf();
        let cwd = root.join("packages/alpha/client");
        fs::create_dir_all(&cwd).unwrap();

        let git = GitContext {
            cwd: cwd.clone(),
            worktree_root: root.clone(),
            git_dir: root.join(".git"),
            git_common_dir: root.join(".git"),
        };

        assert_eq!(
            resolve_implicit_queue_path(&cwd, Some(&git)),
            cwd.join(".sift/issues.jsonl")
        );
    }

    #[test]
    fn linked_worktree_checks_main_worktree_when_current_worktree_has_no_queue() {
        let dir = TempDir::new().unwrap();
        let main_root = dir.path().join("main");
        let linked_root = dir.path().join("linked");
        fs::create_dir_all(&main_root).unwrap();
        fs::create_dir_all(&linked_root).unwrap();

        let cwd = linked_root.join("src/packages/alpha/client");
        fs::create_dir_all(&cwd).unwrap();

        let main_queue = main_root.join("src/packages/.sift/issues.jsonl");
        write_queue(&main_queue);

        let git = GitContext {
            cwd: cwd.clone(),
            worktree_root: linked_root.clone(),
            git_dir: main_root.join(".git/worktrees/linked"),
            git_common_dir: main_root.join(".git"),
        };

        assert_eq!(resolve_implicit_queue_path(&cwd, Some(&git)), main_queue);
    }

    #[test]
    fn outside_git_falls_back_to_cwd_relative_queue() {
        let dir = TempDir::new().unwrap();
        let cwd = dir.path().join("scratch/nested");
        fs::create_dir_all(&cwd).unwrap();

        assert_eq!(
            resolve_implicit_queue_path(&cwd, None),
            PathBuf::from(&cwd).join(".sift/issues.jsonl")
        );
    }
}
