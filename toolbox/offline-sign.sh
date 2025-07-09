#!/bin/bash

# Pell Network Message Signing Script
# Usage: ./pell_sign.sh <message> [wallet_name] [output_file]

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_WALLET="admin"
DEFAULT_KEYRING="test"
DEFAULT_CHAIN_ID="pell_ignite-1"

# Show help information
show_help() {
    echo -e "${BLUE}Pell Network Message Signing Tool${NC}"
    echo
    echo "Usage:"
    echo "  $0 <message> [wallet_name] [output_file]"
    echo
    echo "Parameters:"
    echo "  message      Message to sign (required)"
    echo "  wallet_name  Wallet name (optional, default: $DEFAULT_WALLET)"
    echo "  output_file  Output file path (optional, default: output to console)"
    echo
    echo "Examples:"
    echo "  $0 \"Hello Pell Network!\""
    echo "  $0 \"My message\" admin"
    echo "  $0 \"Important data\" admin signature.json"
    echo
    echo "Environment variables:"
    echo "  PELL_KEYRING_BACKEND  keyring backend (default: $DEFAULT_KEYRING)"
    echo "  PELL_CHAIN_ID         chain ID (default: $DEFAULT_CHAIN_ID)"
}

# Check parameters
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# Get parameters
MESSAGE="$1"
WALLET_NAME="${2:-$DEFAULT_WALLET}"
OUTPUT_FILE="$3"

# Get environment variables or use defaults
KEYRING_BACKEND="${PELL_KEYRING_BACKEND:-$DEFAULT_KEYRING}"
CHAIN_ID="${PELL_CHAIN_ID:-$DEFAULT_CHAIN_ID}"

# Temporary files
TEMP_DIR=$(mktemp -d)
UNSIGNED_TX="$TEMP_DIR/unsigned_tx.json"
SIGNED_TX="$TEMP_DIR/signed_tx.json"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Check pellcored command
if ! command -v pellcored &> /dev/null; then
    echo -e "${RED}❌ Error: pellcored command not found${NC}"
    echo "Please ensure pellcored is installed and added to PATH"
    exit 1
fi

# Check if wallet exists
if ! pellcored keys show "$WALLET_NAME" --keyring-backend="$KEYRING_BACKEND" &> /dev/null; then
    echo -e "${RED}❌ Error: Wallet '$WALLET_NAME' does not exist${NC}"
    echo "Available wallets:"
    pellcored keys list --keyring-backend="$KEYRING_BACKEND" 2>/dev/null || echo "  (No available wallets)"
    exit 1
fi

# Get wallet address
WALLET_ADDRESS=$(pellcored keys show "$WALLET_NAME" --keyring-backend="$KEYRING_BACKEND" --address 2>/dev/null)
if [ -z "$WALLET_ADDRESS" ]; then
    echo -e "${RED}❌ Error: Unable to get wallet address${NC}"
    exit 1
fi

# Create unsigned transaction
if ! pellcored tx bank send "$WALLET_ADDRESS" "$WALLET_ADDRESS" 1upell \
    --chain-id="$CHAIN_ID" \
    --keyring-backend="$KEYRING_BACKEND" \
    --generate-only \
    --note="$MESSAGE" \
    --node="tcp://35.186.145.237:26657" \
    > "$UNSIGNED_TX" 2>/dev/null; then
    echo -e "${RED}❌ Error: Failed to create unsigned transaction${NC}"
    exit 1
fi

# Sign transaction
if ! pellcored tx sign "$UNSIGNED_TX" \
    --from="$WALLET_NAME" \
    --keyring-backend="$KEYRING_BACKEND" \
    --chain-id="$CHAIN_ID" \
    --node="tcp://35.186.145.237:26657" \
    > "$SIGNED_TX" 2>/dev/null; then
    echo -e "${RED}❌ Error: Failed to sign transaction${NC}"
    exit 1
fi

# Extract signature information
SIGNATURE=$(jq -r '.signatures[0]' "$SIGNED_TX" 2>/dev/null)
if [ -z "$SIGNATURE" ] || [ "$SIGNATURE" = "null" ]; then
    echo -e "${RED}❌ Error: Unable to extract signature${NC}"
    exit 1
fi

# Get public key information
PUBKEY_INFO=$(jq -r '.auth_info.signer_infos[0].public_key' "$SIGNED_TX" 2>/dev/null)
PUBKEY_TYPE=$(echo "$PUBKEY_INFO" | jq -r '.["@type"]' 2>/dev/null)
PUBKEY_VALUE=$(echo "$PUBKEY_INFO" | jq -r '.key' 2>/dev/null)

# Create signature result - use jq to ensure proper JSON format
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SIGNATURE_RESULT=$(jq -n \
  --arg message "$MESSAGE" \
  --arg signature "$SIGNATURE" \
  --arg signer_address "$WALLET_ADDRESS" \
  --arg pubkey_type "$PUBKEY_TYPE" \
  --arg pubkey_value "$PUBKEY_VALUE" \
  --arg chain_id "$CHAIN_ID" \
  --arg timestamp "$TIMESTAMP" \
  --argjson signed_tx "$(cat "$SIGNED_TX")" \
  '{
    message: $message,
    signature: $signature,
    signer_address: $signer_address,
    public_key: {
      type: $pubkey_type,
      value: $pubkey_value
    },
    chain_id: $chain_id,
    timestamp: $timestamp,
    signed_tx: $signed_tx
  }')

# Encode signature result to base64
SIGNATURE_BASE64=$(echo "$SIGNATURE_RESULT" | base64)

# Output results
if [ -n "$OUTPUT_FILE" ]; then
    # Save base64 encoded result to file
    echo "$SIGNATURE_BASE64" > "$OUTPUT_FILE"
else
    # Output base64 encoded result to console
    echo "$SIGNATURE_BASE64"
fi
