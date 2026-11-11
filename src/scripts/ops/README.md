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

## Burner Loans and shared services

Follow the [launch runbook](../../../documentation/burner_loans_launch_runbook.md) for deployment,
setup and OCG ordering. Populate the reviewed deployment addresses in `src/scripts/env.json`.
Every batch uses the latest Safe wrapper ABI `(bool,string,string)`, accepts a supplied args file
where needed, simulates real target calls and retains standard heartbeat validation.
Authorization, lifecycle, queue admission and execution checks are enforced by the target contracts.

| Script | Entry points | Authority |
| --- | --- | --- |
| `BurnerLoansKernelSetupBatch` | `setupKernel`: FLOAN, fourteen Burner Loans policies and PriceCache | Kernel executor |
| `DepositManagerSetupBatch` | `setupKernel`: shared DepositManager v1.1 | Kernel executor |
| `RevenueDistributorSetupBatch` | `setupKernel`: distributor, timelock and task | Kernel executor |
| `BackingOracleSetupBatch` | `setupKernel`: oracle and timelock | Kernel executor |
| `PriceConfigV2Batch` | `addAsset`, `queueUpdateAsset`, `queueRemoveAsset`, execute/cancel | `price_admin` or ADMIN; anyone/Emergency for execute/cancel |
| `EnablerBatch` | `enable`, `disable`, `reEnable` for supplied targets | Target-specific authority; Emergency for disable |
| `BurnerLoansInventoryBatch` | `supply`, `withdraw`; `syncMintApproval` | `burner_loans_inventory_provider`; `burner_loans_admin` |
| Four `BurnerLoans*TimelockBatch` scripts | Typed `queue*`, admitted `queueBatch` where supported; `executeQueuedAction`, `cancelQueuedAction` | ADMIN/`burner_loans_admin`; anyone, Emergency |
| `BurnerLoansSeizerTaskBatch` | `setScanLimits`, `setExecutionGasLimit`, `setNextAssetIndex`, `setNextAssetBorrowerIndex` | ADMIN/`burner_loans_admin` |
| `BurnerLoansYieldClaimerTaskBatch` | `setExecutionGasLimit`, `setMinimumGasToAttempt`, `setGasReserve`, `setNextAssetIndex` | ADMIN/`burner_loans_admin` |
| `RevenueDistributorBatch` | `distribute`, `transferPendingPayout` | Anyone |
| `RevenueDistributorConfigTimelockBatch` | Asset routes, yield recipient, rescue, pending rescue, admitted `queueBatch`; execute/cancel | ADMIN/`revenue_distributor_admin`; anyone/Emergency |
| `BackingOracleBatch` | `initialize` | ADMIN |
| `BackingOracleConfigTimelockBatch` | `queueSetBacking`; execute/cancel | ADMIN/`backing_admin`; anyone/Emergency |

Setup batches log already-active policies and leave them unchanged. Initialization, enablement,
asset registration and role grants belong to governance. `BackingOracleBatch.initialize` selects
the deployed queue and enables both contracts with the reviewed initial backing value.

`EnablerBatch` centralizes lifecycle calls for all compatible policies and periphery contracts.
Supply `targets` as an address array in the order to execute. `enable` and `disable` also take a
parallel `data` array of hex payloads, using `"0x"` for empty payloads. `reEnable` only needs targets.
Initial enable requires the target's administrator; fast re-enable preserves configuration and
uses its delegated role/grace rules. These calls run the standard heartbeat simulation.

For a complete Burner Loans shutdown/recovery, use the dependency order in the
[runbook](../../../documentation/burner_loans_launch_runbook.md#5-confirm-launch-and-operate).
Shared services have separate lifecycles and can be included in a reviewed target list as needed.

### Args files and delayed operations

Create task/timelock args files when needed. Use a `functions` array with a matching entry-point
`name` and an `args` object. Field names are read by each script's `_readBatchArg*` calls.
Terminal operations use `actionId` with the actual queue ID. `queueBatch` takes ABI-encoded `(address,bytes4,bytes)[]` in `encodedActions`. Distributor routes
use ABI-encoded `(address,uint16)[]` in `encodedRoutes`. Supply reads `amount` in OHM base units; withdrawal also reads
`recipient`. The provider Safe supplies and withdraws its own OHM claim.

Queueing, execution and cancellation are separate runs. Burner Loans and distributor queues have
one-day notice and a three-day execution window. The backing queue has one-day notice and a
seven-day window. Read IDs and timestamps from queue events or `getQueuedAction`.

```bash
./shell/safeBatchV2.sh --contract BurnerLoansConfigTimelockBatch --function queueSetAssetDebtCap --chain mainnet --multisig true --ledger 5 --args path/to/reviewed-queue.json
./shell/safeBatchV2.sh --contract BurnerLoansConfigTimelockBatch --function executeQueuedAction --chain mainnet --multisig true --ledger 5 --args path/to/reviewed-actions.json
```

The proposal grants DAO `backing_admin`. Provider whitelist changes still use the governance
RolesAdmin; holding an operational role does not permit granting it to others.

### PRICE configuration

The OCG activator admits USDe when needed. No USDe args file or separate preparation batch is
required. `PriceConfigV2Batch` remains a generic single-asset admission script for future operations;
its inputs come from an operator-supplied args file. sUSDe needs no separate PRICE admission.

`PriceConfigV2Batch.queueUpdateAsset` takes `asset` and `encodedUpdate`, the ABI encoding of
`(IPRICEv2.UpdateAssetParams, IPriceConfigv2.PriceFeedExpectation[])`. `queueRemoveAsset` takes
`asset`. Execute/cancel use `actionId` after the real PriceConfigv2 notice period. Updates and
removals use its configuration queue; they do not bypass it.
