use clap::Parser;

#[derive(Parser, Debug)]
#[command(name = "pivy-agent", about = "PIV-backed SSH agent")]
struct Cli {
    /// GUID of the PIV card to use
    #[arg(short = 'g')]
    guid: Option<String>,

    /// All-card mode: expose keys from all PIV cards
    #[arg(short = 'A')]
    all_cards: bool,
}

fn main() {
    let cli = Cli::parse();
    println!("pivy-agent starting with {:?}", cli);
}
