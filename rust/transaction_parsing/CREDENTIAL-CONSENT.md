# Regular-account credential consent

The concrete-network scanner command `53 01 09` accepts one typed attestation
consent. Its frame is prelude (3 bytes), sr25519 public key (32), complete SCALE
message (95), and trailing genesis hash (32). Existing transaction and tagged
message commands keep their formats and signing rules.

The message contains version1, RFC4122 UUIDv4, issuance milliseconds as little
endian u64, scope21, genesis32, payload version1, regular-account32 and
attestation-service ID as little endian u32. The parser requires the account and
genesis to match the frame, a positive service and issuance time, and a
nonoverflowing seven-day expiry. Other algorithms, scopes, versions, lengths,
UUID variants and digest-only inputs fail before a signing action is stored.

Vault displays purpose, account, network, service, UUID, issue/expiry timestamps
and digest. It signs Blake2b-256 of the exact 95 bytes through the ordinary local
network/account and key owner. It does not sign the full message, add Bytes tags
or accept a supplied arbitrary digest. Its ordinary message signature output is
raw64 bytes; the adapter proof is `01 || publicKey32 || signature64`. Local
message history retains the signed digest; the adapter's immutable consent record
retains the original message/proof. Device clock is not expiry authority: the
adapter and runtime enforce freshness and one-time use independently.

Focused validation uses `cargo test --locked -p transaction_parsing --features
db_handling/active,definitions/active credential_consent` from the Rust workspace,
plus the `transaction_signing` test filter `signs_typed_credential_consent` under
the same features. The latter uses shipped Trevo network initialization, real
local account creation, public parsing/cards and production signature creation.
It also checks that command03 still signs its exact tagged bytes and that
ed25519 consent is refused.

The historical full parser suite currently encounters 42 Westend metadata/default
fixture failures on both the unchanged bf7af48 baseline and this derivative.
Focused consent checks do not make that suite PASS. Native adapter/worker/browser
acceptance, release artifacts and physical phone/camera verification remain
separate.
