use clap::FromArgMatches;
use sift_queue::{build_cli, Cli, Commands};

fn main() {
    let matches = build_cli().get_matches();
    let cli = Cli::from_arg_matches(&matches).unwrap_or_else(|e| e.exit());
    let queue_path = sift_queue::queue_path::resolve_queue_path(cli.queue.as_ref());

    let exit_code = match cli.command {
        Commands::Add(ref args) => sift_queue::cli::commands::add::execute(args, queue_path),
        Commands::Collect(ref args) => {
            sift_queue::cli::commands::collect::execute(args, queue_path)
        }
        Commands::List(ref args) => sift_queue::cli::commands::list::execute(args, queue_path),
        Commands::Show(ref args) => sift_queue::cli::commands::show::execute(args, queue_path),
        Commands::Edit(ref args) => sift_queue::cli::commands::edit::execute(args, queue_path),
        Commands::Close(ref args) => {
            sift_queue::cli::commands::status::execute(args, queue_path, "closed")
        }
        Commands::Rm(ref args) => sift_queue::cli::commands::rm::execute(args, queue_path),
        Commands::Prime => sift_queue::cli::commands::prime::execute(),
    };

    match exit_code {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            eprintln!("Error: {}", e);
            std::process::exit(1);
        }
    }
}
