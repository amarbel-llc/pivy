use std::sync::Arc;
use tokio::sync::Mutex;

use ssh_agent_lib::{
    agent::Session,
    error::AgentError,
    proto::{Identity, SignRequest},
};
use ssh_key::{public::KeyData, Signature};

use pivy_piv::{Guid, PivAlgorithm};

/// Cached key info from a PIV token (populated at startup)
#[derive(Clone)]
pub struct CachedKey {
    pub guid: Guid,
    pub reader_name: String,
    pub slot_id: u8,
    pub algorithm: PivAlgorithm,
    pub public_key: KeyData,
    pub comment: String,
}

#[derive(Clone)]
pub struct PivyAgent {
    keys: Arc<Mutex<Vec<CachedKey>>>,
}

impl PivyAgent {
    pub fn new(keys: Vec<CachedKey>) -> Self {
        Self {
            keys: Arc::new(Mutex::new(keys)),
        }
    }
}

#[ssh_agent_lib::async_trait]
impl Session for PivyAgent {
    async fn request_identities(&mut self) -> Result<Vec<Identity>, AgentError> {
        let keys = self.keys.lock().await;
        let identities = keys
            .iter()
            .map(|k| Identity {
                pubkey: k.public_key.clone(),
                comment: k.comment.clone(),
            })
            .collect();
        Ok(identities)
    }

    async fn sign(&mut self, request: SignRequest) -> Result<Signature, AgentError> {
        // Will be implemented in Task 10
        let _ = request;
        Err(AgentError::Failure)
    }
}

