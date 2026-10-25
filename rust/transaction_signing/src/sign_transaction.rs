use definitions::crypto::Encryption;
use parity_scale_codec::Encode;
use sp_core::blake2_256;
use sp_runtime::MultiSignature;
use zeroize::Zeroize;

use db_handling::db_transactions::{SignContent, TrDbColdSign};

use crate::sign_message::sign_as_address_key;
use crate::{Error, Result};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SignatureType {
    Transaction,
    Message,
}

pub struct SignatureAndChecksum {
    signature_type: SignatureType,
    signature: MultiSignature,
    new_checksum: u32,
}

impl SignatureAndChecksum {
    pub fn new_checksum(&self) -> u32 {
        self.new_checksum
    }

    pub fn signature(&self) -> &MultiSignature {
        &self.signature
    }

    pub fn signature_type(&self) -> SignatureType {
        self.signature_type
    }
}

#[allow(clippy::to_string_trait_impl)]
impl ToString for SignatureAndChecksum {
    fn to_string(&self) -> String {
        match self.signature_type {
            SignatureType::Transaction => hex::encode(self.signature.encode()),
            SignatureType::Message => match &self.signature {
                MultiSignature::Ed25519(a) => hex::encode(a),
                MultiSignature::Sr25519(a) => hex::encode(a),
                MultiSignature::Ecdsa(a) => hex::encode(a),
            },
        }
    }
}

/// Function to create signatures using RN output action line, and user entered pin and password.
/// Also needs database name to fetch saved transaction and key.
pub fn create_signature(
    database: &sled::Db,
    seed_phrase: &str,
    pwd_entry: &str,
    user_comment: &str,
    checksum: u32,
    idx: usize,
    encryption: Encryption,
) -> Result<SignatureAndChecksum> {
    let sign =
        TrDbColdSign::from_storage(database, Some(checksum))?.ok_or(db_handling::Error::Sign)?;
    let pwd = {
        if sign.signing_bulk[idx].has_pwd() {
            Some(pwd_entry)
        } else {
            None
        }
    };
    let content = sign.signing_bulk[idx].content().to_owned();
    let content_vec = match &content {
        SignContent::Transaction { method, extensions } => {
            [method.to_vec(), extensions.to_vec()].concat()
        }
        SignContent::Message(a) => a.to_vec(),
    };

    // For larger transactions, their hash should be signed instead; this is not implemented
    // upstream so we put it here
    let content_vec = match &content {
        SignContent::Transaction {
            method: _,
            extensions: _,
        } if content_vec.len() > 257 => blake2_256(&content_vec).to_vec(),
        _ => content_vec,
    };
    let mut full_address = seed_phrase.to_owned() + &sign.signing_bulk[idx].path();
    let signature = match sign_as_address_key(
        &content_vec,
        &sign.signing_bulk[idx].multisigner(),
        &full_address,
        pwd,
        encryption,
    ) {
        Ok(s) => {
            full_address.zeroize();
            let c = sign.apply(database, false, user_comment, idx)?;
            Ok((s.multi_signature(), c))
        }
        Err(e) => {
            full_address.zeroize();
            if let Error::WrongPassword = e {
                let checksum = sign.apply(database, true, user_comment, idx)?;
                Err(Error::WrongPasswordNewChecksum(checksum))
            } else {
                Err(e)
            }
        }
    }?;

    let signature_type = match &content {
        SignContent::Transaction {
            method: _,
            extensions: _,
        } => SignatureType::Transaction,
        SignContent::Message(_) => SignatureType::Message,
    };
    Ok(SignatureAndChecksum {
        signature_type,
        signature: signature.0,
        new_checksum: signature.1,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use constants::ALICE_SEED_PHRASE;
    use db_handling::cold_default::populate_cold;
    use definitions::navigation::TransactionAction;
    use definitions::network_specs::Verifier;
    use sp_core::crypto::AccountId32;

    use sp_runtime::traits::Verify;
    use tempfile::tempdir;
    use transaction_parsing::produce_output;

    #[test]
    fn signs_typed_credential_consent_digest_through_real_parser_and_key_owner() {
        let directory = tempdir().unwrap();
        let db = sled::open(&directory).unwrap();
        db_handling::cold_default::populate_cold_no_metadata(&db, Verifier { v: None }).unwrap();
        let network = db_handling::helpers::get_all_networks(&db)
            .unwrap()
            .remove(0)
            .specs;
        let network_key = definitions::keyring::NetworkSpecsKey::from_parts(
            &network.genesis_hash,
            &Encryption::Sr25519,
        );
        db_handling::identities::try_create_seed(&db, "Alice", ALICE_SEED_PHRASE, false).unwrap();
        db_handling::identities::try_create_address(
            &db,
            "Alice",
            ALICE_SEED_PHRASE,
            "//Alice",
            &network_key,
        )
        .unwrap();
        let account =
            hex::decode("d43593c715fdd31c61141abd04a99fd6822c8558854ccde39a5684e7a56da27d")
                .unwrap();
        let genesis = network.genesis_hash.as_bytes().to_vec();
        let mut message = vec![1];
        message.extend_from_slice(&hex::decode("123456781234423482341234567890ab").unwrap());
        message.extend_from_slice(&1_800_000_000_000u64.to_le_bytes());
        message.push(21);
        message.extend_from_slice(&genesis);
        message.push(1);
        message.extend_from_slice(&account);
        message.extend_from_slice(&7u32.to_le_bytes());
        let frame = [vec![0x53, 1, 9], account.clone(), message.clone(), genesis].concat();
        let output = produce_output(&db, &hex::encode(&frame)).unwrap();
        if let TransactionAction::Sign { actions, checksum } = output {
            assert_eq!(actions.len(), 1);
            let displayed = format!("{:?}", actions[0].content);
            assert!(displayed.contains("issue one credential"));
            assert!(displayed.contains("Attestation service: 7"));
            assert!(displayed.contains("12345678-1234-4234-8234-1234567890ab"));
            let signed = create_signature(
                &db,
                ALICE_SEED_PHRASE,
                "",
                "",
                checksum,
                0,
                Encryption::Sr25519,
            )
            .unwrap();
            let public = AccountId32::new(account.try_into().unwrap());
            let digest = sp_core::blake2_256(&message);
            assert!(signed.signature.verify(digest.as_slice(), &public));
            assert!(!signed.signature.verify(message.as_slice(), &public));
            let tagged = [
                b"<Bytes>".as_slice(),
                digest.as_slice(),
                b"</Bytes>".as_slice(),
            ]
            .concat();
            assert!(!signed.signature.verify(tagged.as_slice(), &public));
        } else {
            panic!("Typed consent was not signable: {output:?}");
        }
        let mut generic = frame;
        generic[2] = 3;
        assert!(produce_output(&db, &hex::encode(&generic)).is_err());
        let tagged = b"<Bytes>existing command03 remains exact</Bytes>";
        let legacy = [
            vec![0x53, 1, 3],
            generic[3..35].to_vec(),
            tagged.to_vec(),
            generic[130..].to_vec(),
        ]
        .concat();
        if let TransactionAction::Sign { checksum, .. } =
            produce_output(&db, &hex::encode(legacy)).unwrap()
        {
            let signed = create_signature(
                &db,
                ALICE_SEED_PHRASE,
                "",
                "",
                checksum,
                0,
                Encryption::Sr25519,
            )
            .unwrap();
            let public = AccountId32::new(generic[3..35].try_into().unwrap());
            assert!(signed.signature.verify(tagged.as_slice(), &public));
        } else {
            panic!("Existing tagged message no longer signs");
        }
        generic[2] = 9;
        generic[1] = 0;
        assert!(produce_output(&db, &hex::encode(generic)).is_err());
    }

    #[test]
    fn sign_long_msg() {
        let tmp_dir = tempdir().unwrap();
        let db = sled::open(&tmp_dir).unwrap();

        populate_cold(&db, Verifier { v: None }).unwrap();
        let message = format!("<Bytes>{}bbb</Bytes>", "a".repeat(256));
        let line = format!("530103d43593c715fdd31c61141abd04a99fd6822c8558854ccde39a5684e7a56da27d{}e143f23803ac50e8f6f8e62695d1ce9e4e1d68aa36c1cd2cfd15340213f3423e", hex::encode(&message));
        let output = produce_output(&db, &line).unwrap();
        let public = sp_core::sr25519::Public::try_from(
            hex::decode("d43593c715fdd31c61141abd04a99fd6822c8558854ccde39a5684e7a56da27d")
                .unwrap()
                .as_ref(),
        )
        .unwrap();
        if let TransactionAction::Sign {
            actions: _,
            checksum,
        } = output
        {
            let signature = create_signature(
                &db,
                ALICE_SEED_PHRASE,
                "",
                "",
                checksum,
                0,
                Encryption::Sr25519,
            )
            .unwrap();
            assert!(signature
                .signature
                .verify(message.as_bytes(), &AccountId32::new(public.0)));
        } else {
            panic!("Wrong action: {output:?}")
        }
    }
}
