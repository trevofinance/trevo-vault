//! Typed regular-account attestation consent; never a generic raw-digest signer.

use crate::{Error, Result};
use std::convert::TryInto;

const CONSENT_LENGTH: usize = 95;
const CONSENT_LIFETIME_MS: u64 = 604_800_000;

/// Admit only the runtime's v1, scope-21 SCALE message and return its exact digest.
pub(crate) fn signing_request(
    message: &[u8],
    account: &[u8],
    genesis: &[u8],
) -> Result<(Vec<u8>, String)> {
    if message.len() != CONSENT_LENGTH
        || message[0] != 1
        || message[25] != 21
        || message[58] != 1
        || message[7] >> 4 != 4
        || message[9] & 0xc0 != 0x80
        || message[26..58] != *genesis
        || message[59..91] != *account
        || genesis.iter().all(|byte| *byte == 0)
    {
        return Err(Error::InvalidMessagePayload);
    }
    let issued = u64::from_le_bytes(
        message[17..25]
            .try_into()
            .map_err(|_| Error::InvalidMessagePayload)?,
    );
    let service = u32::from_le_bytes(
        message[91..95]
            .try_into()
            .map_err(|_| Error::InvalidMessagePayload)?,
    );
    let expires = issued
        .checked_add(CONSENT_LIFETIME_MS)
        .ok_or(Error::InvalidMessagePayload)?;
    if issued == 0 || service == 0 {
        return Err(Error::InvalidMessagePayload);
    }
    let id = hex::encode(&message[1..17]);
    let uuid = format!(
        "{}-{}-{}-{}-{}",
        &id[..8],
        &id[8..12],
        &id[12..16],
        &id[16..20],
        &id[20..]
    );
    let digest = sp_core::blake2_256(message);
    let display = format!(
        "Trevo attested credential consent v1\nPurpose: issue one credential for this regular account\nScope: 21\nAccount: 0x{}\nNetwork genesis: 0x{}\nAttestation service: {}\nConsent UUID: {}\nIssued at (Unix milliseconds): {}\nExpires at (Unix milliseconds): {}\nDigest (Blake2b-256): 0x{}\nThe service and chain enforce expiry and one-time use.",
        hex::encode(account), hex::encode(genesis), service, uuid, issued, expires, hex::encode(digest),
    );
    Ok((digest.to_vec(), display))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn message() -> Vec<u8> {
        let mut value = vec![1];
        value.extend_from_slice(&[
            0x12, 0x34, 0x56, 0x78, 0x12, 0x34, 0x42, 0x34, 0x82, 0x34, 0x12, 0x34, 0x56, 0x78,
            0x90, 0xab,
        ]);
        value.extend_from_slice(&1_800_000_000_000u64.to_le_bytes());
        value.push(21);
        value.extend_from_slice(&[0x11; 32]);
        value.push(1);
        value.extend_from_slice(&[0x22; 32]);
        value.extend_from_slice(&7u32.to_le_bytes());
        value
    }

    #[test]
    fn signs_only_the_digest_and_displays_all_purpose_bindings() {
        let input = message();
        let (digest, display) = signing_request(&input, &[0x22; 32], &[0x11; 32]).unwrap();
        assert_eq!(digest, sp_core::blake2_256(&input));
        assert!(display.contains("issue one credential"));
        assert!(display.contains("12345678-1234-4234-8234-1234567890ab"));
        assert!(display.contains("Attestation service: 7"));
        assert!(display.contains("1800604800000"));
        assert!(display.contains(&hex::encode([0x11; 32])));
        assert!(display.contains(&hex::encode([0x22; 32])));
        assert!(display.contains(&hex::encode(digest)));
    }

    #[test]
    fn rejects_other_scope_versions_uuid_bindings_and_overflow() {
        for (offset, byte) in [
            (0, 2),
            (7, 0x32),
            (9, 0x42),
            (25, 20),
            (26, 0x33),
            (58, 2),
            (59, 0x33),
        ] {
            let mut input = message();
            input[offset] = byte;
            assert!(signing_request(&input, &[0x22; 32], &[0x11; 32]).is_err());
        }
        for issued in [0u64, u64::MAX] {
            let mut input = message();
            input[17..25].copy_from_slice(&issued.to_le_bytes());
            assert!(signing_request(&input, &[0x22; 32], &[0x11; 32]).is_err());
        }
        for length in [0, 32, 94, 96] {
            assert!(signing_request(&vec![0; length], &[0x22; 32], &[0x11; 32]).is_err());
        }
        let mut input = message();
        input[91..95].fill(0);
        assert!(signing_request(&input, &[0x22; 32], &[0x11; 32]).is_err());
    }
}
