pub mod cli;
pub mod collect;
pub mod queue;
pub mod queue_path;

use clap::{builder::StyledStr, Args, Command, CommandFactory, Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "sq", version)]
pub struct Cli {
    /// Path to queue file
    #[arg(short = 'q', long = "queue", value_name = "PATH", global = true)]
    pub queue: Option<PathBuf>,

    #[command(subcommand)]
    pub command: Commands,
}

pub fn build_cli() -> Command {
    Cli::command().mut_subcommand("collect", |subcmd| {
        let styles = subcmd.get_styles();
        let header = styles.get_header();
        let literal = styles.get_literal();
        let help = StyledStr::from(format!(
            "{header}Examples:{header:#}\n  {literal}rg --json PATTERN | sq collect --by-file{literal:#}\n  {literal}rg --json -n -C2 PATTERN | sq collect --by-file --title-template \"migrate: {{{{filepath}}}}\"{literal:#}\n\n{header}Templates:{header:#}\n  {literal}{{{{filepath}}}}{literal:#}     Full file path for the grouped result\n  {literal}{{{{filename}}}}{literal:#}     Basename of {literal}{{{{filepath}}}}{literal:#}\n  {literal}{{{{match_count}}}}{literal:#}  Number of rg match events collected for the file\n\n  Default title template: {literal}{{{{match_count}}}}:{{{{filepath}}}}{literal:#}"
        ));

        subcmd.after_help(help)
    })
}

#[derive(Subcommand)]
pub enum Commands {
    /// Add a new item to the review queue
    Add(AddArgs),
    /// Collect items from stdin into queue items
    Collect(CollectArgs),
    /// List queue items
    List(ListArgs),
    /// Show details of a queue item
    Show(ShowArgs),
    /// Edit an existing queue item
    Edit(EditArgs),
    /// Mark an item as closed
    Close(StatusArgs),
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

    /// Description for the item
    #[arg(long = "description", value_name = "TEXT")]
    pub description: Option<String>,

    /// Attach metadata as JSON
    #[arg(long = "metadata", value_name = "JSON")]
    pub metadata: Option<String>,

    /// Comma-separated blocker IDs
    #[arg(long = "blocked-by", value_name = "IDS")]
    pub blocked_by: Option<String>,

    /// Output as JSON
    #[arg(long = "json")]
    pub json: bool,
}

#[derive(Args)]
#[command(about = "Collect items from stdin into queue items")]
pub struct CollectArgs {
    /// Split stdin into one item per file
    #[arg(long = "by-file")]
    pub by_file: bool,

    /// Input format: currently only rg-json is supported
    #[arg(long = "stdin-format", value_name = "FORMAT")]
    pub stdin_format: Option<String>,

    /// Title for every created item
    #[arg(long = "title", value_name = "TITLE")]
    pub title: Option<String>,

    /// Description for every created item
    #[arg(long = "description", value_name = "TEXT")]
    pub description: Option<String>,

    /// Template for each created item title
    #[arg(long = "title-template", value_name = "TEMPLATE")]
    pub title_template: Option<String>,

    /// Attach metadata as JSON
    #[arg(long = "metadata", value_name = "JSON")]
    pub metadata: Option<String>,

    /// Comma-separated blocker IDs
    #[arg(long = "blocked-by", value_name = "IDS")]
    pub blocked_by: Option<String>,

    /// Output as JSON
    #[arg(long = "json")]
    pub json: bool,
}

#[derive(Parser)]
pub struct ListArgs {
    /// Filter by status (pending|in_progress|closed)
    #[arg(long = "status", value_name = "STATUS")]
    pub status: Option<String>,

    /// Include closed items when status is not explicitly filtered
    #[arg(long = "all")]
    pub all: bool,

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

    /// Set description for the item
    #[arg(long = "set-description", value_name = "TEXT")]
    pub set_description: Option<String>,

    /// Set metadata as JSON (replaces full metadata object)
    #[arg(long = "set-metadata", value_name = "JSON")]
    pub set_metadata: Option<String>,

    /// Merge metadata object as JSON (deep object merge)
    #[arg(long = "merge-metadata", value_name = "JSON")]
    pub merge_metadata: Option<String>,

    /// Set blocker IDs (comma-separated, empty to clear)
    #[arg(long = "set-blocked-by", value_name = "IDS")]
    pub set_blocked_by: Option<String>,

    /// Output as JSON
    #[arg(long = "json")]
    pub json: bool,
}

#[derive(Parser)]
pub struct StatusArgs {
    /// Item ID
    pub id: Option<String>,

    /// Output as JSON
    #[arg(long = "json")]
    pub json: bool,
}

#[derive(Parser)]
pub struct RmArgs {
    /// Item ID
    pub id: Option<String>,

    /// Output as JSON
    #[arg(long = "json")]
    pub json: bool,
}

#[derive(Parser)]
pub struct PrimeArgs {
    /// Force full CLI output
    #[arg(long = "full")]
    pub full: bool,
}
