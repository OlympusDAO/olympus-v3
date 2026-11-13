# Batch Scripts

This directory contains batch scripts for the Olympus DAO multisig.

## Fork Testing

To run the scripts on an anvil fork, provide the `--fork` flag to the `safeBatchV2.sh` script. This requires certain environment variables to be set, which are documented in the `batch.sh` file.

For example:

```bash
./shell/safeBatchV2.sh --contract ContractRegistryInstall --function function_name --broadcast true --fork true --env .env.testnet
```

## Signing and proposing Safe batches

Use `--multisig true` and choose one signer: `--ledger` or `--account`.
The script simulates and validates the batch before signing it.
Add `--broadcast true` to sign and submit the proposal to the Safe transaction service.
Other Safe owners then approve and execute the transaction in Safe.

With Ledger mnemonic index 5:

```bash
./shell/safeBatchV2.sh --contract CCIPNonEthereumSetupBatch --function setup --chain robinhood --multisig true --ledger 5 --broadcast true
```

With an imported Cast wallet account:

```bash
./shell/safeBatchV2.sh --contract CCIPNonEthereumSetupBatch --function setup --chain robinhood --multisig true --account dao-signer --broadcast true
```

Run these commands only after the setup prerequisites in the CCIP runbook are complete.
Omit `--broadcast true` to simulate without signing or submitting a proposal.
Use `--nonce N` to select a Safe nonce; otherwise the script uses the on-chain Safe nonce.
Pending proposals do not advance the on-chain nonce, so choose an unused nonce when queueing multiple batches.

For Ledger Safe proposals, the wrapper reads the signer address, then starts Forge without its Ledger flags.
The batch signs through the existing `safe-utils` FFI call to `cast wallet sign --ledger --data`.
The signature passes directly to the Safe API call in the same run.
For Cast accounts, Forge unlocks the account and the batch signs through `vm.sign`.

Batch entry points take `(bool useDaoMS, string argsFile, string ledgerDerivationPath)`.
The wrapper supplies these arguments; operators do not need to provide a signature.
The former `--signonly` and `--signature` options have been removed.
Without `--multisig true`, EOA transactions continue to use Forge's selected wallet for signing.

## YieldRepurchaseFacilityV2 and BackingOracle

These batches prepare the launch of the YieldRepurchaseFacilityV2 stack (the facility, its configuration policy and its config timelock, and the BackingOracle with its config timelock) and operate it afterwards. The launch itself is OCG proposal 20, `YieldRepurchaseFacilityV2Proposal`, which calls the one-use `YieldRepurchaseFacilityV2Activator`; `documentation/yield_repurchase_facility_v2_launch_runbook.md` describes the whole rollout.

Every entry point reads the live state and adds only the calls that are missing, so a second run on a converged state ends with `No batch targets to execute`. Preconditions are checked while the batch is built; a failed one stops the run with a message that names the way out. Every non-empty batch is simulated and validated before it is proposed.

### Desired state

The batches read the desired state from `src/scripts/env.json`, through `YieldRepurchaseFacilityV2ConfigLib` and `BackingOracleConfigLib`, which stop a run on a missing key or a value the contracts would reject:

- `olympus.config.BackingOracle.backing`: the backing (USD per OHM, 18 decimals).
- `olympus.config.YieldRepurchaseFacilityV2`:
    - `gracePeriod`, `stepGasLimit`, `timelockDelay`: the deployment parameters;
    - `initialDiscount`, `maxPricePremium` (`1e18` = 100%);
    - `assets.<name>.{enabled, sellShares, yieldBuybackShare}`, with the vault address under `external.tokens.<name>`;
    - `backingVault`: the name of the asset that is the backing vault;
    - `clearinghouses[]`: one `{address, included, offset}` entry per Clearinghouse of the CHREG registry.
- `external.chainlink.usdeUsdPriceFeed`: the feed the launch registers USDe with in the PRICE module.

### Batches and entry points

| Batch | Entry point | Batch owner | Authority | Args file |
|---|---|---|---|---|
| `YieldRepurchaseFacilityV2SetupBatch` | `setupKernel` | DAO MS | Kernel executor | none |
| | `setCallbackAuthStatus` | the Safe that owns the bond auctioneer | owner of the auctioneer | none |
| | `checkReadiness` | any sender, read-only | none | none |
| | `deactivateV1` | DAO MS | Kernel executor | none |
| `YieldRepurchaseFacilityV2ConfigTimelockBatch` | `reconcile` | DAO MS | `yrf_admin` | none |
| | `queueDecreaseNextYield` | DAO MS | `yrf_admin` | `asset`, `expectedNextYield`, `newNextYield` |
| | `executeReadyActions` | any owner | none | optional `actionIds` |
| | `cancelQueuedAction` | DAO MS | proposer of the action, or any owner once it has expired | `actionId` |
| | `cancelQueuedActionEmergency` | Emergency MS | `emergency` | `actionId` |
| `YieldRepurchaseFacilityV2Batch` | `reEnable` | DAO MS | `yrf_admin` | none |
| | `reconcileStepGasLimit` | DAO MS | `yrf_admin` | none |
| | `rescue` | DAO MS | `yrf_admin` | `token` |
| | `stopPurchasesEmergencyMS` | Emergency MS | `emergency` | none |
| | `freezeConfigEmergencyMS` | Emergency MS | `emergency` | none |
| | `haltAllEmergencyMS` | Emergency MS | `emergency` | none |
| | `returnFundsToTreasuryEmergencyMS` | Emergency MS | `emergency` | none |
| `BackingOracleSetupBatch` | `setupKernel` | DAO MS | Kernel executor | none |
| `BackingOracleConfigTimelockBatch` | `reconcileBacking` | DAO MS | `backing_admin` | none |
| | `executeReadyActions` | any owner | none | optional `actionIds` |
| | `cancelQueuedAction` | DAO MS | proposer of the action, or any owner once it has expired | `actionId` |
| | `cancelQueuedActionEmergency` | Emergency MS | `emergency` | `actionId` |
| `BackingOracleBatch` | `reEnable` | DAO MS | `backing_admin` | none |
| | `freezeUpdatesEmergencyMS` | Emergency MS | `emergency` | none |
| | `haltAllEmergencyMS` | Emergency MS | `emergency` | none |

An entry point without an args file rejects one. Example args files are in `src/scripts/ops/batches/args/`, named `<Contract>_<function>.json`; the file of `cancelQueuedAction` also carries the entry of `cancelQueuedActionEmergency`.

The heart beat is simulated after every batch that changes what a beat reads. It is skipped for the batches that only queue or cancel, for the activations and the callback authorization before the launch, and for the levers that touch only a config timelock or the configuration policy. An emergency lever that is validated can be built without the simulation by setting `EMERGENCY_SKIP_HEARTBEAT_VALIDATION=true`, for a Heart that fails for a reason the lever does not remove.

### Before the launch proposal

```bash
# DAO MS: activate the five policies in the Kernel
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2SetupBatch --function setupKernel --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true

# A signer of the Safe that owns the Bond Protocol auctioneer: authorize the facility as a market callback
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2SetupBatch --function setCallbackAuthStatus --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true

# Anyone: the readiness report; the proposal is not submitted until the verdict is GREEN
FOUNDRY_PROFILE=deploy forge script src/scripts/ops/batches/YieldRepurchaseFacilityV2SetupBatch.sol:YieldRepurchaseFacilityV2SetupBatch --sig "checkReadiness()" --rpc-url mainnet
```

The report prints `[ OK ]`, `[FAIL]`, `[INFO]` and `[TODO]` lines and ends with `READINESS RESULT mainnet: GREEN` or `RED`. Its Activator section checks the activator recorded under `olympus.proposals.YieldRepurchaseFacilityV2Activator`: it accepts the OCG timelock, is bound to the contracts and tokens of `env.json`, carries the launch values of `env.json`, is not activated, holds neither `admin` nor `loop_daddy`, and its `checkPreconditions()` passes, that is, the launch would execute on the state of the report. The registration parameters of the USDe/USD feed (update threshold, expected price, tolerance) are read from the activator; until the activator is recorded, the PRICE section fails on its absence and prints the price of the feed and the age of its answer as an `[INFO]` line. The last section, the `[TODO]` lines, lists the values of `env.json` to verify again before the proposal contracts are deployed, since a later change means a redeployment:

- `olympus.config.BackingOracle.backing`;
- `olympus.config.YieldRepurchaseFacilityV2.gracePeriod`, `initialDiscount`, `maxPricePremium`, `stepGasLimit` and `timelockDelay`;
- every included Clearinghouse declared with offset 0 while it reports receivables.

### After the launch proposal

```bash
# DAO MS: deactivate YieldRepurchaseFacility v1.2 in the Kernel; build and simulate immediately before signing
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2SetupBatch --function deactivateV1 --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true
```

### Configuration (DAO MS)

Change the desired state in `env.json`, then queue the difference, wait for the delay and execute:

```bash
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2ConfigTimelockBatch --function reconcile --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2ConfigTimelockBatch --function executeReadyActions --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true
```

`reconcile` queues the initial discount, the max price premium, the yield buyback share and the enabled state of an asset, the exclusion of a Clearinghouse and an increase of its offset. It stops when a field that only the admin role changes differs from `env.json`, and when the chain holds a vault or a registry Clearinghouse that `env.json` does not declare. When a pending action holds a needed key with another value, or has expired, the run holds its cancellations only; run it again once they have landed.

The step gas limit and the backing are reconciled by their own entry points:

```bash
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2Batch --function reconcileStepGasLimit --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true
./shell/safeBatchV2.sh --contract BackingOracleConfigTimelockBatch --function reconcileBacking --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true
./shell/safeBatchV2.sh --contract BackingOracleConfigTimelockBatch --function executeReadyActions --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true
```

One update moves the backing by at most 10% of the live value. A larger difference stops `reconcileBacking` with the accepted interval in the message: declare an intermediate value, queue and execute it, then declare the next one.

A correction of the stored next yield is not derived from `env.json`:

```bash
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2ConfigTimelockBatch --function queueDecreaseNextYield --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true --args src/scripts/ops/batches/args/YieldRepurchaseFacilityV2ConfigTimelockBatch_queueDecreaseNextYield.json
```

### Emergency (Emergency MS) and recovery (DAO MS)

```bash
# Stop the purchases, freeze the configuration, or both
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2Batch --function stopPurchasesEmergencyMS --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2Batch --function freezeConfigEmergencyMS --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2Batch --function haltAllEmergencyMS --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true

# Return the funds of the disabled facility to the treasury
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2Batch --function returnFundsToTreasuryEmergencyMS --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true

# Freeze the backing updates, or halt the oracle
./shell/safeBatchV2.sh --contract BackingOracleBatch --function freezeUpdatesEmergencyMS --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true
./shell/safeBatchV2.sh --contract BackingOracleBatch --function haltAllEmergencyMS --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true
```

`returnFundsToTreasury` sweeps each vault in an isolated step and requires `stepGasLimit + stepGasLimit / 63 + 15000` gas to be left before every step, whatever the step consumes. The batch prints the gas this takes. A gas limit estimated from the gas the call uses is too low and the transaction reverts with `InsufficientStepGas`, so set the gas limit of the executing Safe transaction explicitly.

A disabled BackingOracle closes the price gate of the facility: its daily cycles open no markets and keep the purchased OHM accumulated, and its `enable` and `reEnable` revert. A market that is already live stays purchasable until it concludes; the hard stop is `stopPurchasesEmergencyMS`.

Inside the grace windows (the `gracePeriod` of `env.json` for the facility stack, 7 days for the oracle pair) the DAO MS restores the policies; afterwards the path is the admin `enable`, an OCG proposal. The oracle comes first, since the `reEnable` of the facility requires it:

```bash
./shell/safeBatchV2.sh --contract BackingOracleBatch --function reEnable --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2Batch --function reEnable --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true
```

Queued actions survive a disable and keep their configuration keys. Before a `reEnable`, cancel the ones that must not execute:

```bash
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2ConfigTimelockBatch --function cancelQueuedAction --chain mainnet --multisig true --ledger < mnemonic index > --broadcast true --args src/scripts/ops/batches/args/YieldRepurchaseFacilityV2ConfigTimelockBatch_cancelQueuedAction.json
```

### Rehearsal

`shell/yrf/anvil-deployment/run.sh` deploys the stack and the activator on an Anvil fork of mainnet, replays the launch proposal from the OCG timelock and runs every entry point above against the fork; see its README.
