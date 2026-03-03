pub mod cli;
pub mod queue;
pub mod queue_path;

use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "sq", about = "Manage Sift's review queue")]
pub struct Cli {
    /// Path to queue file
    #[arg(short = 'q', long = "queue", value_name = "PATH", global = true)]
    pub queue: Option<PathBuf>,

    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Add a new item to the review queue
    Add(AddArgs),
    /// List queue items
    List(ListArgs),
    /// Show details of a queue item
    Show(ShowArgs),
    /// Edit an existing queue item
    Edit(EditArgs),
    /// Remove an item from the queue
    Rm(RmArgs),
    /// Output sift workflow context for AI agents
    Prime(PrimeArgs),
}

#[derive(Parser)]
pub struct AddArgs {
    /// Add diff source (repeatable)
    #[arg(long = "diff", value_name = "PATH")]
    pub diff: Vec<String>,

    /// Add file source (repeatable)
    #[arg(long = "file", value_name = "PATH")]
    pub file: Vec<String>,

    /// Add text source (repeatable)
    #[arg(long = "text", value_name = "STRING")]
    pub text: Vec<String>,

    /// Add directory source (repeatable)
    #[arg(long = "directory", value_name = "PATH")]
    pub directory: Vec<String>,

    /// Read source content from stdin (diff|file|text|directory)
    #[arg(long = "stdin", value_name = "TYPE")]
    pub stdin: Option<String>,

    /// Title for the item
    #[arg(long = "title", value_name = "TITLE")]
    pub title: Option<String>,

    /// Attach metadata as JSON
    #[arg(long = "metadata", value_name = "JSON")]
    pub metadata: Option<String>,

    /// Comma-separated blocker IDs
    #[arg(long = "blocked-by", value_name = "IDS")]
    pub blocked_by: Option<String>,
}

#[derive(Parser)]
pub struct ListArgs {
    /// Filter by status (pending|in_progress|closed)
    #[arg(long = "status", value_name = "STATUS")]
    pub status: Option<String>,

    /// Output as JSON
    #[arg(long = "json")]
    pub json: bool,

    /// jq select expression
    #[arg(long = "filter", value_name = "EXPR")]
    pub filter: Option<String>,

    /// jq path expression to sort by
    #[arg(long = "sort", value_name = "PATH")]
    pub sort: Option<String>,

    /// Reverse sort order
    #[arg(long = "reverse")]
    pub reverse: bool,

    /// Show only ready items (pending and unblocked)
    #[arg(long = "ready")]
    pub ready: bool,
}

#[derive(Parser)]
pub struct ShowArgs {
    /// Item ID
    pub id: Option<String>,

    /// Output as JSON
    #[arg(long = "json")]
    pub json: bool,
}

#[derive(Parser)]
pub struct EditArgs {
    /// Item ID
    pub id: Option<String>,

    /// Add diff source
    #[arg(long = "add-diff", value_name = "PATH")]
    pub add_diff: Vec<String>,

    /// Add file source
    #[arg(long = "add-file", value_name = "PATH")]
    pub add_file: Vec<String>,

    /// Add text source
    #[arg(long = "add-text", value_name = "STRING")]
    pub add_text: Vec<String>,

    /// Add directory source
    #[arg(long = "add-directory", value_name = "PATH")]
    pub add_directory: Vec<String>,

    /// Add transcript source
    #[arg(long = "add-transcript", value_name = "PATH")]
    pub add_transcript: Vec<String>,

    /// Remove source by index (0-based, repeatable)
    #[arg(long = "rm-source", value_name = "INDEX")]
    pub rm_source: Vec<usize>,

    /// Change status (pending|in_progress|closed)
    #[arg(long = "set-status", value_name = "STATUS")]
    pub set_status: Option<String>,

    /// Set title for the item
    #[arg(long = "set-title", value_name = "TITLE")]
    pub set_title: Option<String>,

    /// Set metadata as JSON
    #[arg(long = "set-metadata", value_name = "JSON")]
    pub set_metadata: Option<String>,

    /// Set blocker IDs (comma-separated, empty to clear)
    #[arg(long = "set-blocked-by", value_name = "IDS")]
    pub set_blocked_by: Option<String>,
}

#[derive(Parser)]
pub struct RmArgs {
    /// Item ID
    pub id: Option<String>,
}

#[derive(Parser)]
pub struct PrimeArgs {
    /// Force full CLI output
    #[arg(long = "full")]
    pub full: bool,
}
