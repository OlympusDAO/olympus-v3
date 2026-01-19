# Testing with Anvil Fork

This guide covers the complete workflow for testing protocol changes against a local Anvil fork, avoiding the 20-block limit of Tenderly VNet.

## Flag Distinction: `--tenderly` vs `--fork`

| Flag | Purpose | RPC Target | Execution Method | Use Case |
|------|---------|------------|------------------|----------|
| `--tenderly true` | Execute on actual testnet | Testnet RPC (e.g., Base Sepolia) | Tenderly VNet HTTP API | Actual testnet deployment |
| `--fork true` | Execute on local Anvil fork | `http://localhost:8545` | Foundry `vm.startBroadcast()` | Local testing/dev |

**Key differences:**
- `--tenderly` connects to the real testnet and uses Tenderly's VNet API to simulate transactions
- `--fork` connects to a local Anvil fork and executes transactions directly using Foundry broadcast
- `--fork` requires Anvil running locally; `--tenderly` does not
- `--fork` has no block limit; `--tenderly` (via Tenderly) has 20-block limit

**Both can be used together** (e.g., `--tenderly true --fork true`) - this means "use the testnet deployment state but execute via local fork"

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
  --account <ACCOUNT> \
  --sequence src/scripts/deploy/savedDeployments/<SEQUENCE>.json \
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

### Phase 3: Create OCG Proposal

For governance actions, create and test an OCG proposal:

```bash
./shell/submitProposal.sh \
  --file src/proposals/MyProposal.sol \
  --contract MyProposal \
  --account my_wallet \
  --fork http://localhost:8545 \
  --broadcast true
```

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
./shell/deployV3.sh --target PRICE --chain http://localhost:8545 --broadcast

# 2. MS Batch to activate
./shell/safeBatchV2.sh --contract PriceDeploy --function run --chain http://localhost:8545 --account tester --fork true --broadcast true

# 3. Create proposal
./shell/submitProposal.sh --file src/proposals/UpdatePrice.sol --contract UpdatePrice --account tester --fork http://localhost:8545 --broadcast true

# 4. Execute proposal
src/scripts/proposals/executeOnAnvilFork.sh --file src/proposals/UpdatePrice.sol --contract UpdatePrice
```

## Verification

After each phase, verify state changes:

```bash
# Check deployed contract
cast code <deployed_address> --rpc-url http://localhost:8545

# Check module activation in Kernel
cast call <kernel_address> "getModuleForKeycode(bytes5)" "(0x5052494345)" --rpc-url http://localhost:8545

# Check proposal state
cast call <governor_address> "proposals(uint256)" "<proposal_id>" --rpc-url http://localhost:8545
```

## Mining Blocks (Warping Forward)

To advance the blockchain by a specific number of blocks (e.g., for time-dependent testing):

```bash
# Mine 100 blocks
./shell/anvil_warp.sh 100

# Mine 1000 blocks
./shell/anvil_warp.sh 1000
```

The script will mine the specified number of blocks and display the current block number as verification.

## Resetting the Fork

To start fresh without restarting Anvil:

```bash
# Anvil will reset to the fork block when you restart the process
# Or manually reset within Anvil by sending the anvil_reset transaction
```

## Environment Variables

| Variable | For Anvil Mode | For Tenderly Mode |
|----------|----------------|-------------------|
| `USE_TENDERLY_FORK` | auto-set by `--fork` | set by `--tenderly` |
| `USE_ANVIL_FORK` | auto-set by `--fork` | ✗ |
| `TENDERLY_*` | ✗ | ✓ |
| `RPC_URL` | auto-set to localhost | ✓ |

**Note:** `anvil:fork` uses the `mainnet` RPC endpoint defined in `foundry.toml`. To fork from a different network, set the `TESTNET_RPC_URL` environment variable and run `anvil --fork-url $TESTNET_RPC_URL --port 8545 --auto-impersonate` directly.
