use pcsc::{Protocols, ShareMode};

use crate::apdu::{Apdu, StatusWord, PIV_AID};
use crate::error::PivError;
use crate::guid::Guid;
use crate::tlv::TlvReader;
use crate::PivContext;

/// CHUID data object tag (NIST SP 800-73-4)
const PIV_TAG_CHUID: u32 = 0x5FC102;

/// Tag for GUID within CHUID
const CHUID_TAG_GUID: u32 = 0x34;

pub struct PivToken {
    card: pcsc::Card,
    guid: Guid,
    reader_name: String,
}

impl PivToken {
    pub fn connect(ctx: &PivContext, reader: &str) -> Result<Self, PivError> {
        let cstr =
            std::ffi::CString::new(reader).map_err(|e| PivError::Other(e.to_string()))?;
        let card = ctx
            .pcsc_context()
            .connect(&cstr, ShareMode::Shared, Protocols::ANY)?;
        let mut token = Self {
            card,
            guid: Guid::from_bytes(&[0; 16])?,
            reader_name: reader.to_string(),
        };
        token.select_piv()?;
        token.read_chuid()?;
        Ok(token)
    }

    fn transmit(&self, apdu: &Apdu) -> Result<(Vec<u8>, StatusWord), PivError> {
        let cmd = apdu.to_bytes();
        let mut resp_buf = vec![0u8; 4096];
        let resp = self.card.transmit(&cmd, &mut resp_buf)?;
        let len = resp.len();
        if len < 2 {
            return Err(PivError::Other("response too short for status word".into()));
        }
        let sw = StatusWord::from_bytes(resp[len - 2], resp[len - 1]);
        let data = resp[..len - 2].to_vec();

        // Handle GET RESPONSE chaining (SW 61xx)
        if sw.has_more_data() {
            let mut full = data;
            let mut chain_sw = sw;
            while chain_sw.has_more_data() {
                let mut get_resp = Apdu::new(0x00, 0xC0, 0x00, 0x00);
                get_resp.le = Some(chain_sw.remaining_bytes() as u16);
                let cmd2 = get_resp.to_bytes();
                let mut resp_buf2 = vec![0u8; 4096];
                let resp2 = self.card.transmit(&cmd2, &mut resp_buf2)?;
                let len2 = resp2.len();
                if len2 < 2 {
                    return Err(PivError::Other("chained response too short".into()));
                }
                chain_sw = StatusWord::from_bytes(resp2[len2 - 2], resp2[len2 - 1]);
                full.extend_from_slice(&resp2[..len2 - 2]);
            }
            return Ok((full, chain_sw));
        }

        Ok((data, sw))
    }

    fn select_piv(&mut self) -> Result<(), PivError> {
        let apdu = Apdu::select(PIV_AID);
        let (_, sw) = self.transmit(&apdu)?;
        if !sw.is_success() {
            return Err(PivError::Apdu { sw: sw.as_u16() });
        }
        Ok(())
    }

    fn read_chuid(&mut self) -> Result<(), PivError> {
        let apdu = Apdu::get_data(PIV_TAG_CHUID);
        let (data, sw) = self.transmit(&apdu)?;
        if !sw.is_success() {
            return Err(PivError::Apdu { sw: sw.as_u16() });
        }

        // Response is wrapped in tag 0x53
        let mut reader = TlvReader::new(&data);
        let outer_tag = reader.read_tag()?;
        if outer_tag != 0x53 {
            return Err(PivError::Tlv {
                message: format!("expected CHUID outer tag 0x53, got {:#X}", outer_tag),
            });
        }
        let chuid_data = reader.read_value()?;

        // Parse CHUID TLV to find GUID (tag 0x34)
        let mut chuid_reader = TlvReader::new(chuid_data);
        while chuid_reader.has_remaining() {
            let tag = chuid_reader.read_tag()?;
            let value = chuid_reader.read_value()?;
            if tag == CHUID_TAG_GUID {
                self.guid = Guid::from_bytes(value)?;
                return Ok(());
            }
        }

        Err(PivError::Tlv {
            message: "GUID tag (0x34) not found in CHUID".into(),
        })
    }

    pub fn guid(&self) -> &Guid {
        &self.guid
    }

    pub fn reader_name(&self) -> &str {
        &self.reader_name
    }

    pub fn transmit_apdu(&self, apdu: &Apdu) -> Result<(Vec<u8>, StatusWord), PivError> {
        self.transmit(apdu)
    }
}

impl PivContext {
    /// Enumerate all PIV tokens across all readers.
    /// Silently skips readers that don't have PIV cards.
    pub fn enumerate_tokens(&self) -> Result<Vec<PivToken>, PivError> {
        let readers = self.list_readers()?;
        let mut tokens = Vec::new();
        for reader in &readers {
            match PivToken::connect(self, reader) {
                Ok(token) => tokens.push(token),
                Err(_) => continue, // Not a PIV card or not inserted
            }
        }
        Ok(tokens)
    }
}
