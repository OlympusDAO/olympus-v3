# Testing with Anvil Fork

This guide covers the complete workflow for testing protocol changes against a local Anvil fork, avoiding the 20-block limit of Tenderly VNet.

## Anvil vs Tenderly

| Feature     | Anvil Fork              | Tenderly VNet    |
| ----------- | ----------------------- | ---------------- |
| RPC Target  | `http://localhost:8545` | Tenderly RPC URL |
| Block limit | None                    | 20 blocks        |
| Setup       | Requires local Anvil    | Cloud-based      |
| Use case    | Local testing/dev       | Shared testnet   |

## RPC URLs

Pass the RPC URL with `--chain`:

```bash
# Anvil fork
--chain http://localhost:8545

# Tenderly VNet
--chain https://rpc.tenderly.co/vnet/...

# Mainnet (uses foundry.toml endpoint)
--chain mainnet
```

The script automatically detects localhost URLs and applies the `--legacy` flag for EIP-1559 compatibility.

## Prerequisites

```bash
# Start Anvil fork (uses mainnet RPC from foundry.toml)
pnpm run anvil:fork
```

## Full Testing Lifecycle

### Phase 1: Deploy Contracts to Fork

Deploy new or updated contracts to the Anvil fork:

```bash
./shell/deployV3.sh \
    --account my_wallet \
    --sequence src/scripts/deploy/savedDeployments/my_sequence.json \
    --chain http://localhost:8545 \
    --broadcast true
```

### Phase 2: Execute MS Batch

Activate/configure the deployed contracts via multisig batch:

```bash
./shell/safeBatchV2.sh \
    --contract MyBatchScript \
    --function functionName \
    --chain mainnet \
    --account my_wallet \
    --multisig true \
    --broadcast true \
    --fork true
```

**Note:** `--chain mainnet` is still required so the script can look up addresses from `env.json`. When `--fork true` is used, the RPC is automatically overridden to `http://localhost:8545`.

### Phase 3: Create OCG Proposal

For governance actions, create and test an OCG proposal:

```bash
# Using a cast wallet
src/scripts/proposals/submitProposal.sh \
    --file src/proposals/MyProposal.sol \
    --contract MyProposal \
    --account my_wallet \
    --chain http://localhost:8545 \
    --broadcast true

# Using a Ledger
src/scripts/proposals/submitProposal.sh \
    --file src/proposals/MyProposal.sol \
    --contract MyProposal \
    --ledger 0 \
    --chain http://localhost:8545 \
    --broadcast true
```

**Note:** Pass `--chain http://localhost:8545` to use the local Anvil fork.

### Phase 4: Execute Proposal on Fork

Execute the proposal actions via Anvil fork:

```bash
src/scripts/proposals/executeOnAnvilFork.sh \
    --file src/proposals/MyProposal.sol \
    --contract MyProposal
```

## Complete Workflow Example

```bash
# Terminal 1: Start Anvil fork (uses mainnet RPC from foundry.toml)
pnpm run anvil:fork

# Terminal 2: Run full test workflow
# 1. Deploy
./shell/deployV3.sh \
    --account tester \
    --sequence src/scripts/deploy/savedDeployments/price.json \
    --chain http://localhost:8545 \
    --broadcast true

# 2. MS Batch to activate
./shell/safeBatchV2.sh --contract PriceDeploy --function run --chain mainnet --account tester --fork true --broadcast true

# 3. Create proposal
src/scripts/proposals/submitProposal.sh --file src/proposals/UpdatePrice.sol --contract UpdatePrice --account tester --chain http://localhost:8545 --broadcast true

# 4. Execute proposal
src/scripts/proposals/executeOnAnvilFork.sh --file src/proposals/UpdatePrice.sol --contract UpdatePrice
```

## Verification

After each phase, verify state changes:

```bash
# Check deployed contract
cast code 0x1234... --rpc-url http://localhost:8545

# Check module activation in Kernel
cast call 0xKERNEL... "getModuleForKeycode(bytes5)" 0x5052494345 --rpc-url http://localhost:8545

# Check proposal state
cast call 0xGOVERNOR... "proposals(uint256)" 1 --rpc-url http://localhost:8545
```

## Mining Blocks (Warping Forward)

To advance the blockchain by a specific number of blocks (e.g., for time-dependent testing):

```bash
# Mine 100 blocks
./shell/anvil/warp.sh 100

# Mine 1000 blocks
./shell/anvil/warp.sh 1000
```

The script will mine the specified number of blocks and display the current block number as verification.

## Dealing gOHM for Voting Tests

To deal 15 gOHM to a wallet and set up voting checkpoints (useful for testing governance proposals):

```bash
# Deal 15 gOHM to a wallet
./shell/anvil/deal_gohm.sh 0x1234...
```

The script will:

1. Transfer 15 gOHM from a wealthy holder to the target wallet
2. Mine 1 block to create a voting checkpoint
3. Delegate votes to the target wallet (self-delegation)
4. Mine another block to checkpoint the delegation
5. Verify and display the voting power

## Resetting the Fork

Just restart `anvil`.

## Environment Variables

| Variable     | For Anvil Mode       | For Tenderly Mode |
| ------------ | -------------------- | ----------------- |
| `TENDERLY_*` | ✗                    | ✓                 |
| `RPC_URL`    | Passed via `--chain` | ✓                 |

**Note:** `anvil:fork` uses the `mainnet` RPC endpoint defined in `foundry.toml`. To fork from a different network, set the `TESTNET_RPC_URL` environment variable and run `anvil --fork-url $TESTNET_RPC_URL --port 8545 --auto-impersonate` directly.
