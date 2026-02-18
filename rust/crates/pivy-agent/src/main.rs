use clap::Parser;
use ssh_agent_lib::agent::listen;
use tokio::net::UnixListener;

mod agent;
mod card;

use agent::{CachedKey, PivyAgent};

#[derive(Parser, Debug)]
#[command(name = "pivy-agent", about = "PIV-backed SSH agent")]
struct Cli {
    /// GUID of the PIV card to use
    #[arg(short = 'g')]
    guid: Option<String>,

    /// All-card mode: expose keys from all PIV cards
    #[arg(short = 'A')]
    all_cards: bool,

    /// Socket path for the agent
    #[arg(short = 'a')]
    socket: Option<String>,

    /// Debug level (repeat for more)
    #[arg(short = 'd', action = clap::ArgAction::Count)]
    debug: u8,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();

    let filter = match cli.debug {
        0 => "pivy_agent=info",
        1 => "pivy_agent=debug",
        _ => "pivy_agent=trace",
    };
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .init();

    // Enumerate PIV tokens and cache their keys
    let ctx = pivy_piv::PivContext::new()?;
    let tokens = ctx.enumerate_tokens()?;

    let mut cached_keys = Vec::new();
    let mut primary_guid = None;
    for token in &tokens {
        let guid = token.guid().clone();

        // Filter by GUID if specified
        if let Some(ref filter_guid) = cli.guid {
            if guid.to_hex() != *filter_guid && guid.short_id() != *filter_guid {
                continue;
            }
        }

        if primary_guid.is_none() {
            primary_guid = Some(guid.clone());
        }

        let slots = token.read_all_slots().unwrap_or_default();
        for slot in &slots {
            cached_keys.push(CachedKey {
                guid: guid.clone(),
                reader_name: token.reader_name().to_string(),
                slot_id: slot.id(),
                algorithm: slot.algorithm(),
                public_key: slot.public_key().key_data().clone(),
                comment: format!("PIV_slot_{:02X} {}", slot.id(), guid.short_id()),
            });
        }

        if !cli.all_cards {
            break;
        }
    }

    tracing::info!("Loaded {} keys from PIV tokens", cached_keys.len());

    // Determine socket path
    let socket_path = cli.socket.unwrap_or_else(|| {
        let dir = std::env::temp_dir().join(format!("pivy-agent.{}", std::process::id()));
        std::fs::create_dir_all(&dir).ok();
        dir.join("agent.sock").to_string_lossy().into_owned()
    });

    println!("SSH_AUTH_SOCK={}; export SSH_AUTH_SOCK;", socket_path);
    println!(
        "SSH_AGENT_PID={}; export SSH_AGENT_PID;",
        std::process::id()
    );
    println!("echo Agent pid {};", std::process::id());

    let listener = UnixListener::bind(&socket_path)?;
    let agent = PivyAgent::new(cached_keys);

    // Spawn card probe loop if we have a primary card
    if let Some(guid) = primary_guid {
        let pin_handle = agent.pin_handle();
        tokio::spawn(card::probe_loop(guid, pin_handle));
    }

    listen(listener, agent).await?;

    Ok(())
}
