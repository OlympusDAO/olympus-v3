# YieldRepurchaseFacilityV2 Anvil deployment harness

Deploys the BackingOracle with its config timelock and the YieldRepurchaseFacilityV2 stack with the activator of its launch from scratch on a local Anvil fork of Ethereum mainnet with the real deployment scripts, checks the result, replays the launch proposal, and runs every entry point of the multisig batches of both against the fork. Deployments are signed with Anvil dev account #0; multisig and timelock calls are sent from the real on-chain owners through Anvil account impersonation.

## Requirements

- `anvil`, `forge`, `cast`, `jq`, `git`, `curl`
- `.env` in the repo root with `ALCHEMY_API_KEY`

## Files

- `run.sh`: the whole rehearsal, the deployment and then the batches.
- `lib/common.sh`: the helpers (fork, values, price feeds, batch runs and their assertions).
- `lib/batches.sh`: the rehearsal of the batches, one function per phase.
- `callback-auth.sh`: the batch of the Safe that owns the Bond Protocol auctioneer.

## What the script touches

The run backs up `src/scripts/env.json` and `src/proposals/addresses.json` and restores them on exit. The deployment scripts write the deployed addresses into `env.json`, the harness copies them into `addresses.json`, and the batch phases rewrite keys of the desired state in `env.json`. The records that the run writes under `deployments/` (the generated args files included) and under `broadcast/` and `cache/` for the two deployment scripts, the launch proposal and the six batches are removed on exit, the recovery snapshot of forge included: the fork runs under chain id 1, so an unfinished snapshot left by an interrupted run would make a later mainnet broadcast from this checkout refuse to start. With `--keep-fork`, Anvil keeps running and both files stay modified.

## Run

```bash
./shell/yrf/anvil-deployment/run.sh
```

Deployment:

1. Build under the deploy profile, start an Anvil fork of mainnet, fund the deployer, fill the block hash history contract (see "Block hash history") and carry the answers of the price feeds over to mocks (see "Time and price feeds").
2. Deploy `backing_oracle.json` (the `BackingOracle` and its `BackingOracleConfigTimelock`) through `DeployV3`.
3. Deploy `yieldRepo_v2.json` through `DeployYieldRepurchaseFacilityV2`: the configuration policy, its config timelock, the facility, the lens and the activator of the launch, which takes its launch values from `env.json`. Before the script runs, forge deploys the six linked libraries of the facility through the CREATE2 factory `0x4e59b44847b379578588920cA78FbF26c0B4956C`, skipping a library whose address already holds code. The address of a library follows from its creation code, whose metadata hash covers the sources and the compiler settings, the remappings included. Foundry 1.9.0 writes no path of the checkout into that metadata, so a build of the same sources, dependencies and remappings from another directory yields the same library addresses.
4. Check the libraries: the run links six of them, each linked address equals its `olympus.libraries.<name>` key in `env.json` and holds code.
5. Check the deployed contracts against `env.json`: the Kernel of every contract, the bindings (oracle of the oracle timelock and of the facility, auctioneer and teller, config of the timelock, facility of the lens), the grace periods, the timelock delays, the step gas limit, the unbound configurator, facility and oracle config operator, the disabled state, and no Kernel activation yet; of the activator, the timelock it accepts, the facility it is bound to, its unused state and its code size. The readiness report of step 8 compares every binding and launch value of the activator with `env.json`.
6. Copy the seven deployed addresses and the USDe and sUSDe tokens into `addresses.json`.

Batches:

7. Kernel activation (DAO MS). `deactivateV1` and `reconcile` are refused before the launch, and `setupKernel` from an owner that is not the Kernel executor is refused. `BackingOracleSetupBatch.setupKernel` activates the oracle pair, `YieldRepurchaseFacilityV2SetupBatch.setupKernel` the three policies of the facility; each runs again on the converged state. The five policies end up active and disabled.
8. `checkReadiness` is RED on the missing callback authorization alone: one failed line of the Bond Protocol section, and one of the activator section, whose `checkPreconditions()` reverts with `CallbackNotAuthorized`. The build of the launch proposal fails on the same error. `callback-auth.sh` runs `setCallbackAuthStatus` from the Safe that owns the auctioneer, then again on the converged state. `checkReadiness` is GREEN. With the key of the activator removed from `env.json`, the state before the activator is deployed, `checkReadiness` is RED on its absence in the PRICE section and in the activator section, and prints the price of the USDe/USD feed and the age of its answer as an `[INFO]` line; the key is then restored.
9. The launch (see below): the replay of `YieldRepurchaseFacilityV2Proposal`, the checks of the state it leaves, and a second build that fails with `AlreadyActivated`.
10. `deactivateV1` (DAO MS), then again on the converged state.
11. `YieldRepurchaseFacilityV2ConfigTimelockBatch` (DAO MS as `yrf_admin`): `reconcile` on the converged state; a changed grace period and an undeclared Clearinghouse are refused; four changes of `env.json` are queued as four actions; a second run and an early `executeReadyActions` propose nothing; a pending change that `env.json` takes back is reported in the listing as `CONFLICT:` and is not cancelled; a further change of a pending value yields a run of cancellations and then the replacement; after a warp past the delay, `executeReadyActions` executes the listed ids and then the rest; `reconcile` proposes nothing.
12. Asset status and the next yield: `disableAsset` through the timelock; `queueDecreaseNextYield` from a generated args file, again on the converged state, and refused with other values; `reconcile` is refused while the correction holds the next yield domain that `enableAsset` needs; `cancelQueuedAction` from the DAO MS, refused the second time; `enableAsset` queued, cancelled through `cancelQueuedActionEmergency`, queued again and executed.
13. `YieldRepurchaseFacilityV2Batch`: `reconcileStepGasLimit`; `rescue` of WETH sent to the facility, again on the converged state, and refused for a pool token; `returnFundsToTreasuryEmergencyMS` refused on the enabled facility; `stopPurchasesEmergencyMS`, `returnFundsToTreasuryEmergencyMS`, `reEnable`; `freezeConfigEmergencyMS`, a refused `reconcile`, `reEnable`; `haltAllEmergencyMS` with `EMERGENCY_SKIP_HEARTBEAT_VALIDATION=true`, which builds the lever without the heart beat validation, `reEnable`. Every lever and every `reEnable` runs again on the converged state.
14. The oracle: `reconcileBacking` on the converged state; a value beyond the bound of one update is refused with the bound; a value is queued, superseded (a run of cancellations, then the replacement), cancelled by id from the DAO MS and from the Emergency MS, queued again and executed after a warp; `freezeUpdatesEmergencyMS`, a refused `reconcileBacking`, `reEnable`; `haltAllEmergencyMS`; the `reEnable` of the stopped facility is refused while the oracle is down, and passes after the `reEnable` of the oracle.
15. Print the final state.

Every batch log is asserted: a step that must change state must report `Batch executed successfully on Anvil fork`, a run on a converged state `No batch targets to execute`, and a refused run its message. The batches run with the settings of `shell/safeBatchV2.sh` in fork mode: the deploy profile and `--no-isolate`.

## Launch

Step 9 runs `src/scripts/proposals/executeOnAnvilFork.sh` with `YieldRepurchaseFacilityV2ProposalScript`. The script builds the proposal against the fork, which runs every gate of the build (the activator against `addresses.json` and `env.json`, the roles, `checkPreconditions()`), runs it through the governor in a snapshot (proposal, vote, queue, the timelock delay, execution and the validation of the end state), reverts the snapshot, and then sends every action of the proposal as its own transaction from the impersonated OCG timelock. On mainnet the governor executes the actions in one transaction; the fork suites of the proposal measure that.

The harness then checks the state the launch leaves: the activator is used, the five policies are enabled and bound, the oracle holds the backing of `env.json`, sUSDS is the backing vault and carries the next yield of v1.2, v1.2 is shut down and empty, the facility resumes at the epoch of v1.2 in the Heart slot of v1.2, USDe is registered in the PRICE module, the DAO MS holds `yrf_admin` and `backing_admin`, and neither the DAO MS nor the OCG timelock holds `loop_daddy`.

## Time and price feeds

The fork receives no feed updates, while the PRICE module rejects an answer older than the threshold of its feed. The answers age with the wall clock, which matters for the hourly feeds over the length of a run, and with every warp past a timelock delay. The heart beat validation of a batch raises the thresholds to two days and then warps up to a day ahead, which does not cover a feed that is already a day old after a warp.

The harness therefore places the code of `MockPriceFeed` at the address of every Chainlink-type feed the live PRICE module reads, carries over the answer, the decimals and the round of the feed, and sets the update time to the block timestamp: once right after the fork starts, while every feed still answers (a RedStone feed reverts in `latestRoundData()` once its own data is stale), and after every warp. The USDe/USD feed, which the PRICE module reads only after the launch, is mocked from the start, since the activator checks it before it registers it. Before the replay of the proposal the answers are dated ahead of the timelock delay: the simulation of the proposal passes that delay inside its snapshot.

## Block hash history

The simulation of the launch proposal rolls the block number forward by about 93,600 blocks. Forge 1.9.0 then reads each of the 8,191 slots of the block hash history contract of EIP-2935 (`0x0000F90827F1C53a10cb7A02335B175320002935`), one request at a time, and a fork fetches a slot it does not hold from the upstream RPC. Right after the fork starts, the harness writes zero into every slot of the contract on the fork in one batch request, so the fork answers these reads itself. Nothing the harness runs reads a block hash from the contract.

## Gas of the transactions

The harness sends its own transactions with a fixed gas limit. The gas forge derives for a broadcast transaction from the gas its simulation used is too low for `returnFundsToTreasury`, which requires the step gas limit to be left before the sweep of every vault: that step raises the gas estimate multiplier of forge.

## Options

- `--port <port>`: the Anvil port (default `8545`).
- `--fork-block-number <n>`: fork at a fixed block, so that runs are comparable.
- `--keep-fork`: leave Anvil running and `env.json` and `addresses.json` modified on exit.
- `--deploy-only`: stop after step 6.

Environment overrides: `ANVIL_CUPS` (default `250`) and `ANVIL_BACKOFF_MS` (default `1000`) throttle the upstream RPC of the fork, `TX_FLAGS` (default `--legacy`) is passed to every `forge script` broadcast and `cast send`, and `SEND_GAS_LIMIT` (default `12000000`) is the gas limit of the transactions the harness sends with `cast`. Per-step logs are written to `logs/`.

`callback-auth.sh` takes `--port` and runs against a kept fork on its own.

## Mainnet deployment

`documentation/yield_repurchase_facility_v2_launch_runbook.md` describes the deployment and the launch on mainnet. The same two sequences, through `shell/deployV3.sh`:

```bash
./shell/deployV3.sh --account <cast account> --chain mainnet --broadcast true --verify true \
    --sequence src/scripts/deploy/savedDeployments/backing_oracle.json

./shell/deployV3.sh --account <cast account> --chain mainnet --broadcast true --verify true \
    --script ./src/scripts/deploy/DeployYieldRepurchaseFacilityV2.s.sol:DeployYieldRepurchaseFacilityV2 \
    --sequence src/scripts/deploy/savedDeployments/yieldRepo_v2.json
```

Then record the addresses in `src/proposals/addresses.json` (`olympus-policy-backing-oracle`, `olympus-policy-backing-oracle-config-timelock`, `olympus-policy-yieldrepurchasefacility-config-1_0`, `olympus-policy-yieldrepurchasefacility-config-timelock-1_0`, `olympus-policy-yieldrepurchasefacility-2_0`, `olympus-periphery-yieldrepurchasefacility-lens`, `olympus-proposal-yieldrepurchasefacility-v2-activator`). A contract verified separately afterwards needs the deploy profile, and the facility also needs its six libraries, taken from the `olympus.libraries` keys of `env.json`:

```bash
FOUNDRY_PROFILE=deploy forge verify-contract <facility> \
    src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2.sol:YieldRepurchaseFacilityV2 \
    --chain 1 --verifier sourcify --watch \
    --libraries src/policies/YieldRepurchaseFacility/libraries/linked/<Lib>.sol:<Lib>:<address>
```

The `--libraries` argument is repeated for each of the six libraries.

The batches that follow the deployment are listed in `src/scripts/ops/README.md`.
