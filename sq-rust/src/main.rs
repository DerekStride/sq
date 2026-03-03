use clap::Parser;
use sq::{Cli, Commands};

fn main() {
    let cli = Cli::parse();
    let queue_path = sq::queue_path::resolve_queue_path(cli.queue.as_ref());

    let exit_code = match cli.command {
        Commands::Add(ref args) => sq::cli::commands::add::execute(args, queue_path),
        Commands::List(ref args) => sq::cli::commands::list::execute(args, queue_path),
        Commands::Show(ref args) => sq::cli::commands::show::execute(args, queue_path),
        Commands::Edit(ref args) => sq::cli::commands::edit::execute(args, queue_path),
        Commands::Rm(ref args) => sq::cli::commands::rm::execute(args, queue_path),
        Commands::Prime(_) => sq::cli::commands::prime::execute(),
    };

    match exit_code {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            eprintln!("Error: {}", e);
            std::process::exit(1);
        }
    }
}
