#! /bin/bash

# Function to generate QRs for a chain
generate_chain_qr() {
    local CHAIN_NAME=$1
    local RPC_URL=$2
    local RUNTIME_VERSION=$3

    echo "Generating QR codes for $CHAIN_NAME..."
    echo $pwd

    # generate specs
    cargo run load-metadata -d -u $RPC_URL

    # copy specs to for_signing
    cp "../files/in_progress/sign_me_load_metadata_${CHAIN_NAME}V${RUNTIME_VERSION}" .

    # sign specs
    SIGNATURE=$(cat sign_me_load_metadata_${CHAIN_NAME}V${RUNTIME_VERSION} | subkey sign --suri "$SIGNER_URI")
    
    # generate qr
    cargo run --release make --goal qr --crypto sr25519 --msg load-metadata --payload sign_me_load_metadata_${CHAIN_NAME}V${RUNTIME_VERSION} --verifier-hex $VERIFIER_HEX --signature-hex $SIGNATURE

    # copy qr to trevo_assets
    cp "../files/completed/load_metadata_${CHAIN_NAME}V${RUNTIME_VERSION}" ../../trevo_assets/load_metadata_${CHAIN_NAME}V${RUNTIME_VERSION}.png
    rm -rf "sign_me_load_metadata_${CHAIN_NAME}V${RUNTIME_VERSION}"
}

# Load environment variables
if [ -f ".env" ]; then
    source .env
elif [ -f "env.local" ]; then
    source env.local
else
    echo "Error: Environment file not found!"
    echo "Please create .env or env.local file with SIGNER_URI and VERIFIER_HEX variables"
    echo "You can use env.example as a template"
    exit 1
fi

# Check if required variables are set
if [ -z "$SIGNER_URI" ]; then
    echo "Error: SIGNER_URI is not set in environment file"
    exit 1
fi

if [ -z "$VERIFIER_HEX" ]; then
    echo "Error: VERIFIER_HEX is not set in environment file"
    exit 1
fi

# Chain-specific configurations
# RELAY_RPC="ws://51.91.74.113:15260"
ASSET_HUB_RPC="wss://rpc.api.trevo.finance"

cd ../rust/generate_message

# Generate QRs for relay chain
# generate_chain_qr "trevo-relay" $RELAY_RPC "1000"

# Generate QRs for asset-hub chain
generate_chain_qr "trevo-asset-hub" $ASSET_HUB_RPC "1011"
