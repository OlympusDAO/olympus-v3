#!/bin/bash

# deal_gohm.sh - Deal 15 gOHM to a wallet and set up voting checkpoint for anvil

set -e

# Check if wallet address provided
if [ -z "$1" ]; then
    echo "Usage: $0 <wallet_address>"
    echo "Example: $0 0x1A5309F208f161a393E8b5A253de8Ab894A67188"
    echo ""
    echo "Note: Script requires anvil running with --auto-impersonate:"
    echo "  anvil --fork-url <RPC_URL> --auto-impersonate"
    exit 1
fi

WALLET=$1
RPC_URL="http://localhost:8545"

# Check if anvil is running
if ! cast block-number --rpc-url $RPC_URL &> /dev/null; then
    echo "Error: Cannot connect to anvil at $RPC_URL"
    echo "Please start anvil fork first:"
    echo "  anvil --fork-url <RPC_URL> --auto-impersonate"
    exit 1
fi

# Constants
GOHM="0x0ab87046fBb341D058F17CBC4c1133F25a20a52f"
SOURCE="0xD3204Ae00d6599Ba6e182c6D640A79d76CdAad74"
AMOUNT="15000000000000000000" # 15 gOHM in wei (18 decimals)

echo "=== Dealing 15 gOHM to $WALLET ==="
echo ""

# Check current balance
CURRENT_BALANCE=$(cast call $GOHM "balanceOf(address)(uint256)" $WALLET --rpc-url $RPC_URL)
echo "Current gOHM balance: $CURRENT_BALANCE"

# Transfer gOHM using --unlocked (requires --auto-impersonate)
# First, give SOURCE account ETH for gas
echo "Funding $SOURCE with ETH for gas..."
cast rpc --rpc-url $RPC_URL anvil_setBalance "$SOURCE" "0xDE0B6B3A7640000" --silent

echo "Transferring 15 gOHM from $SOURCE..."
cast send --unlocked --from $SOURCE $GOHM "transfer(address,uint256)" $WALLET $AMOUNT \
    --rpc-url $RPC_URL

# Mine 1 block to create new checkpoint
echo "Mining 1 block to create voting checkpoint..."
cast rpc --rpc-url $RPC_URL anvil_mine 0x1

# Delegate votes to self
echo "Delegating votes to $WALLET..."
cast send --unlocked --from $WALLET $GOHM "delegate(address)" $WALLET \
    --rpc-url $RPC_URL

# Mine another block to checkpoint the delegation
echo "Mining 1 block to checkpoint delegation..."
cast rpc --rpc-url $RPC_URL anvil_mine 0x1

# Verify new balance
NEW_BALANCE=$(cast call $GOHM "balanceOf(address)(uint256)" $WALLET --rpc-url $RPC_URL)
echo "New gOHM balance: $NEW_BALANCE"

# Verify current votes
CURRENT_VOTES=$(cast call $GOHM "getCurrentVotes(address)(uint256)" $WALLET --rpc-url $RPC_URL)
echo "Current votes (delegated to self): $CURRENT_VOTES"

# Get current block
BLOCK=$(cast block-number --rpc-url $RPC_URL)
echo "Current block number: $BLOCK"

# Verify prior votes at previous block (getPriorVotes requires block < current block)
PRIOR_BLOCK=$((BLOCK - 1))
echo "Checking prior votes at block $PRIOR_BLOCK..."
PRIOR_VOTES=$(cast call $GOHM "getPriorVotes(address,uint256)(uint256)" $WALLET $PRIOR_BLOCK --rpc-url $RPC_URL)
echo "Prior votes at block $PRIOR_BLOCK: $PRIOR_VOTES"

echo ""
echo "=== SUCCESS ==="
echo "Wallet $WALLET now has 15 gOHM with voting power enabled."
echo ""
echo "To verify voting power at a specific block:"
echo "  cast call $GOHM \"getPriorVotes(address,uint256)(uint256)\" $WALLET <block_number> --rpc-url $RPC_URL"
