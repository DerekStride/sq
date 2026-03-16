pub mod cli;
pub mod collect;
pub mod queue;
pub mod queue_path;

use clap::{Arg, ArgAction, Args, Command, CommandFactory, Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser)]
#[command(
    name = "sq",
    version,
    about = "Lightweight task-list CLI with structured sources",
    long_about = "sq is a lightweight task-list CLI with structured sources.\n\nIt manages tasks in a JSONL file. You can use it directly from the shell or instruct agents to manage them for you."
)]
pub struct Cli {
    /// Path to task file
    #[arg(
        short = 'q',
        long = "queue",
        value_name = "PATH",
        global = true,
        display_order = 900
    )]
    pub queue: Option<PathBuf>,

    #[command(subcommand)]
    pub command: Commands,
}

pub fn build_cli() -> Command {
    let mut cmd = Cli::command()
        .propagate_version(true)
        .disable_version_flag(true)
        .arg(
            Arg::new("version")
                .short('v')
                .long("version")
                .help("Print version")
                .action(ArgAction::Version)
                .global(true),
        );
    let root_help = crate::cli::help::root_after_help(cmd.get_styles());
    cmd = cmd.after_help(root_help);

    cmd = cmd.mut_subcommand("collect", |subcmd| {
        let help = crate::cli::commands::collect::after_help(subcmd.get_styles());
        subcmd.after_help(help)
    });

    cmd = cmd.mut_subcommand("add", |subcmd| {
        let help = crate::cli::commands::add::after_help(subcmd.get_styles());
        subcmd.after_help(help)
    });

    cmd = cmd.mut_subcommand("edit", |subcmd| {
        let help = crate::cli::commands::edit::after_help(subcmd.get_styles());
        subcmd.after_help(help)
    });

    cmd = cmd.mut_subcommand("list", |subcmd| {
        let help = crate::cli::commands::list::after_help(subcmd.get_styles());
        subcmd.after_help(help)
    });

    cmd = cmd.mut_subcommand("rm", |subcmd| {
        let help = crate::cli::commands::rm::after_help(subcmd.get_styles());
        subcmd.after_help(help)
    });

    cmd = cmd.mut_subcommand("close", |subcmd| {
        let help = crate::cli::commands::status::close_after_help(subcmd.get_styles());
        subcmd.long_about("").after_help(help)
    });

    cmd
}

#[derive(Subcommand)]
pub enum Commands {
    /// Add a new task
    Add(AddArgs),
    /// Collect tasks from stdin
    Collect(CollectArgs),
    /// List tasks
    List(ListArgs),
    /// Show task details
    Show(ShowArgs),
    /// Edit an existing task
    Edit(EditArgs),
    /// Mark a task as closed
    Close(StatusArgs),
    /// Remove a task
    Rm(RmArgs),
    /// Output task workflow context for AI agents
    Prime(PrimeArgs),
}

#[derive(Args)]
#[command(about = "Output task workflow context for AI agents")]
pub struct PrimeArgs {
    /// Output only the prelude and skip the command reference
    #[arg(long = "prelude", display_order = 1)]
    pub prelude: bool,
}

#[derive(Parser)]
pub struct AddArgs {
    /// Title for the item
    #[arg(long = "title", value_name = "TITLE", display_order = 1)]
    pub title: Option<String>,

    /// Description for the item
    #[arg(long = "description", value_name = "TEXT", display_order = 2)]
    pub description: Option<String>,

    /// Priority (0-4, 0=highest)
    #[arg(long = "priority", value_name = "PRIORITY", display_order = 3)]
    pub priority: Option<String>,

    /// Add diff source (repeatable)
    #[arg(long = "diff", value_name = "PATH", display_order = 10)]
    pub diff: Vec<String>,

    /// Add file source (repeatable)
    #[arg(long = "file", value_name = "PATH", display_order = 11)]
    pub file: Vec<String>,

    /// Add text source (repeatable)
    #[arg(long = "text", value_name = "STRING", display_order = 12)]
    pub text: Vec<String>,

    /// Add directory source (repeatable)
    #[arg(long = "directory", value_name = "PATH", display_order = 13)]
    pub directory: Vec<String>,

    /// Read source content from stdin (diff|file|text|directory)
    #[arg(long = "stdin", value_name = "TYPE", display_order = 14)]
    pub stdin: Option<String>,

    /// Attach metadata as JSON
    #[arg(long = "metadata", value_name = "JSON", display_order = 15)]
    pub metadata: Option<String>,

    /// Comma-separated blocker IDs
    #[arg(long = "blocked-by", value_name = "IDS", display_order = 16)]
    pub blocked_by: Option<String>,

    /// Output as JSON
    #[arg(long = "json", display_order = 17)]
    pub json: bool,
}

#[derive(Args)]
#[command(about = "Collect tasks from stdin")]
pub struct CollectArgs {
    /// Title for every created item
    #[arg(long = "title", value_name = "TITLE", display_order = 1)]
    pub title: Option<String>,

    /// Description for every created item
    #[arg(long = "description", value_name = "TEXT", display_order = 2)]
    pub description: Option<String>,

    /// Priority (0-4, 0=highest)
    #[arg(long = "priority", value_name = "PRIORITY", display_order = 3)]
    pub priority: Option<String>,

    /// Split stdin into one item per file
    #[arg(long = "by-file", display_order = 10)]
    pub by_file: bool,

    /// Input format: currently only rg-json is supported
    #[arg(long = "stdin-format", value_name = "FORMAT", display_order = 11)]
    pub stdin_format: Option<String>,

    /// Template for each created item title
    #[arg(long = "title-template", value_name = "TEMPLATE", display_order = 12)]
    pub title_template: Option<String>,

    /// Attach metadata as JSON
    #[arg(long = "metadata", value_name = "JSON", display_order = 13)]
    pub metadata: Option<String>,

    /// Comma-separated blocker IDs
    #[arg(long = "blocked-by", value_name = "IDS", display_order = 14)]
    pub blocked_by: Option<String>,

    /// Output as JSON
    #[arg(long = "json", display_order = 15)]
    pub json: bool,
}

#[derive(Parser)]
pub struct ListArgs {
    /// Filter by status (pending|blocked|in_progress|closed)
    #[arg(long = "status", value_name = "STATUS", display_order = 1)]
    pub status: Option<String>,

    /// Include closed items when status is not explicitly filtered
    #[arg(long = "all", display_order = 2)]
    pub all: bool,

    /// Filter by priority (repeatable: 0-4)
    #[arg(long = "priority", value_name = "PRIORITY", display_order = 3)]
    pub priority: Vec<String>,

    /// Show only ready items (pending and unblocked)
    #[arg(long = "ready", display_order = 4)]
    pub ready: bool,

    /// Output as JSON
    #[arg(long = "json", display_order = 10)]
    pub json: bool,

    /// jq select expression
    #[arg(long = "filter", value_name = "EXPR", display_order = 11)]
    pub filter: Option<String>,

    /// jq path expression to sort by
    #[arg(long = "sort", value_name = "PATH", display_order = 12)]
    pub sort: Option<String>,

    /// Reverse sort order
    #[arg(long = "reverse", display_order = 13)]
    pub reverse: bool,
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

    /// Set title for the item
    #[arg(long = "set-title", value_name = "TITLE", display_order = 1)]
    pub set_title: Option<String>,

    /// Set description for the item
    #[arg(long = "set-description", value_name = "TEXT", display_order = 2)]
    pub set_description: Option<String>,

    /// Change status (pending|in_progress|closed)
    #[arg(long = "set-status", value_name = "STATUS", display_order = 3)]
    pub set_status: Option<String>,

    /// Set priority (0-4, 0=highest)
    #[arg(long = "set-priority", value_name = "PRIORITY", display_order = 4)]
    pub set_priority: Option<String>,

    /// Clear priority
    #[arg(long = "clear-priority", display_order = 5)]
    pub clear_priority: bool,

    /// Add diff source
    #[arg(long = "add-diff", value_name = "PATH", display_order = 10)]
    pub add_diff: Vec<String>,

    /// Add file source
    #[arg(long = "add-file", value_name = "PATH", display_order = 11)]
    pub add_file: Vec<String>,

    /// Add text source
    #[arg(long = "add-text", value_name = "STRING", display_order = 12)]
    pub add_text: Vec<String>,

    /// Add directory source
    #[arg(long = "add-directory", value_name = "PATH", display_order = 13)]
    pub add_directory: Vec<String>,

    /// Remove source by index (0-based, repeatable)
    #[arg(long = "rm-source", value_name = "INDEX", display_order = 14)]
    pub rm_source: Vec<usize>,

    /// Set metadata as JSON (replaces full metadata object)
    #[arg(long = "set-metadata", value_name = "JSON", display_order = 15)]
    pub set_metadata: Option<String>,

    /// Merge metadata object as JSON (deep object merge)
    #[arg(long = "merge-metadata", value_name = "JSON", display_order = 16)]
    pub merge_metadata: Option<String>,

    /// Set blocker IDs (comma-separated, empty to clear)
    #[arg(long = "set-blocked-by", value_name = "IDS", display_order = 17)]
    pub set_blocked_by: Option<String>,

    /// Output as JSON
    #[arg(long = "json", display_order = 18)]
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
