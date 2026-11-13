# Yield Repurchase Facility V2: deployment and launch

This document describes how the YieldRepurchaseFacilityV2 stack is deployed, prepared, launched and operated on Ethereum mainnet: the `YieldRepurchaseFacilityV2` policy with its configuration policy `YieldRepurchaseFacilityV2Config` and config timelock `YieldRepurchaseFacilityV2ConfigTimelock`, the `BackingOracle` policy with its `BackingOracleConfigTimelock`, the one-use `YieldRepurchaseFacilityV2Activator`, and OCG proposal 20, `YieldRepurchaseFacilityV2Proposal`, which migrates the running Yield Repurchase Facility v1.2 into the new facility.

## Overview

The launch is one OCG proposal. Everything before it is preparation that changes no behaviour of the protocol, and everything after it is cleanup.

| Step | Who | What |
| ---- | --- | ---- |
| 1 | Deployer | Verify the launch values of `env.json`, deploy the two sequences |
| 2 | Deployer, repository change | Record the addresses, add the facility to the emergency configuration |
| 3 | DAO MS | Activate the five policies in the Kernel |
| 4 | Safe that owns the Bond Protocol auctioneer | Authorize the facility as a market callback |
| 5 | Anyone | Readiness report: GREEN |
| 6 | Proposer | Recompute the sUSDe next yield, build and submit the proposal |
| 7 | Anyone | Check the preconditions of the activator, execute the proposal |
| 8 | DAO MS | Deactivate v1.2 in the Kernel |
| 9 | Repository change | Retire v1.2 in the emergency configuration |

What the proposal does, in one transaction:

1. Grants `yrf_admin` and `backing_admin` to the DAO MS (each only if it is not held).
2. Grants `admin` and `loop_daddy` to the activator.
3. Calls `YieldRepurchaseFacilityV2Activator.activate(sUSDeNextYield)`.
4. Revokes `admin` and `loop_daddy` from the activator.
5. Revokes `loop_daddy` from the DAO MS and from the OCG timelock (each only if it is held).

What `activate` does, in order:

1. Checks its preconditions (see "Preconditions of the activator") and its two roles.
2. Registers USDe in the PRICE module through PriceConfig v2 with the Chainlink USDe/USD feed, an update threshold of 1 day and an expected price of 1 USD within 100 basis points. Skipped when USDe is already registered.
3. Names `BackingOracleConfigTimelock` as the config operator of `BackingOracle`, enables the timelock, and enables the oracle with the backing of the launch.
4. Binds `YieldRepurchaseFacilityV2Config` and the facility to each other, enables the configuration policy, names `YieldRepurchaseFacilityV2ConfigTimelock` as its config operator and enables the timelock.
5. Enables the facility with the initial discount and the maximum price premium of the launch.
6. Reads the epoch counter, the stored next yield, the two yield snapshots and the USDS and sUSDS balances of v1.2, and calls `shutdown([USDS, sUSDS])` on it, which burns its OHM and transfers both balances to the treasury.
7. Registers sUSDS as the backing vault with the next yield and the snapshots of v1.2, then sUSDe with the next yield of the call and the snapshots the vault reports at that moment.
8. Includes the Clearinghouses declared with `included: true` and sets every non-zero offset.
9. Seeds the weekly cycle: the facility resumes at the epoch counter of v1.2, and the USDS value v1.2 held is withdrawn from the treasury into the buyback pool of sUSDS.
10. Replaces v1.2 with the facility at the same index of the periodic tasks of the Heart.

The contracts and the launch values are constructor arguments of the activator. A value that changes after the activator is deployed requires a new activator, and the proposal refuses to build with an activator whose values differ from `env.json`.

## Pre-requisites

- `cast` set up with the deployer wallet, `.env` with `ALCHEMY_API_KEY` (and `ETHERSCAN_KEY` for verification).
- The toolchain pinned in `mise.toml`. The addresses of the six linked libraries of the facility follow from the compiler settings, the remappings and the Forge version.
- The DAO MS is the Kernel executor, the OCG timelock holds `admin` and administers `RolesAdmin`.

## Step 1: verify the launch values and deploy

### Launch values

The launch values live in `src/scripts/env.json` under `current.mainnet`. Verify each of them before the deployment: the deployment functions copy them into constructors.

| Key | Value at the time of writing | Used by |
| --- | ---------------------------- | ------- |
| `olympus.config.BackingOracle.backing` | `12040000000000000000` (12.04 USD per OHM) | activator |
| `olympus.config.YieldRepurchaseFacilityV2.initialDiscount` | `30000000000000000` (3%) | activator |
| `olympus.config.YieldRepurchaseFacilityV2.maxPricePremium` | `100000000000000000` (10%) | activator |
| `olympus.config.YieldRepurchaseFacilityV2.assets.sUSDS` | enabled, `sellShares: false`, share `1e18` | activator |
| `olympus.config.YieldRepurchaseFacilityV2.assets.sUSDe` | enabled, `sellShares: true`, share `1e18` | activator |
| `olympus.config.YieldRepurchaseFacilityV2.backingVault` | `sUSDS` | activator |
| `olympus.config.YieldRepurchaseFacilityV2.clearinghouses` | three entries, see below | activator |
| `olympus.config.YieldRepurchaseFacilityV2.gracePeriod` | `432000` (5 days) | facility, config, config timelock |
| `olympus.config.YieldRepurchaseFacilityV2.timelockDelay` | `86400` (1 day) | config timelock |
| `olympus.config.YieldRepurchaseFacilityV2.stepGasLimit` | `2000000` | facility |
| `external.chainlink.usdeUsdPriceFeed` | `0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961` | activator |

The values marked TODO in the readiness report are the backing, the grace period, the initial discount, the maximum price premium, the step gas limit and the timelock delay: confirm them with the DAO before this step.

Clearinghouses. The list has to name exactly the Clearinghouses of the CHREG registry, in any order; the activator refuses to launch when the registry holds another set.

| Clearinghouse | `included` | `offset` | Note |
| ------------- | ---------- | -------- | ---- |
| `0xD6A6E8d9e82534bD65821142fcCd91ec9cF31880` | `true` | `0` | Lends DAI and exposes no `reserve()`: it counts toward the backing yield only while included |
| `0xE6343ad0675C9b8D3f32679ae6aDbA0766A2ab4c` | `true` | `0` | Same |
| `0x1e094fE00E13Fd06D64EeA4FB3cD912893606fE0` | `false` | `0` | Lends USDS and counts without an inclusion |

An offset removes that amount of the `principalReceivables` of a Clearinghouse from the yield projection. Both included Clearinghouses are declared with offset 0 while they report receivables: confirm that none of their receivables has to be offset (the readiness report prints a `[TODO]` line for each). An offset must not exceed the `principalReceivables` at execution, and receivables fall as loans are repaid: the activator refuses to launch on an offset above the live receivables. If an offset close to the receivables is needed, launch with a lower offset and raise it afterwards through the config timelock (`increaseClearinghouseOffset`, DAO MS).

### Deploy

```bash
./shell/deployV3.sh --account <cast account> --chain mainnet --broadcast true --verify true \
    --sequence src/scripts/deploy/savedDeployments/backing_oracle.json

./shell/deployV3.sh --account <cast account> --chain mainnet --broadcast true --verify true \
    --script ./src/scripts/deploy/DeployYieldRepurchaseFacilityV2.s.sol:DeployYieldRepurchaseFacilityV2 \
    --sequence src/scripts/deploy/savedDeployments/yieldRepo_v2.json
```

The first sequence deploys `BackingOracle` and `BackingOracleConfigTimelock`. The second deploys `YieldRepurchaseFacilityV2Config`, `YieldRepurchaseFacilityV2ConfigTimelock`, `YieldRepurchaseFacilityV2` (forge deploys its six linked libraries through the CREATE2 factory first), `YieldRepurchaseFacilityV2Lens` and, last, `YieldRepurchaseFacilityV2Activator`.

The deployment function of the activator reads its launch values from `env.json` and refuses a desired state that does not declare exactly the sUSDS and sUSDe vaults, both enabled, with sUSDS as the backing vault. The constructor of the activator refuses a set of contracts that are not bound to each other: the oracle of the oracle timelock and of the facility, the configuration policy of the config timelock, the bond auctioneer and the OHM of the facility, the sUSDS vault of v1.2, the assets of both vaults, and one Kernel for every policy.

`shell/yrf/anvil-deployment/README.md` has the command that verifies the facility with its libraries when it is verified separately.

To change a launch value after this step, change `env.json` and deploy a new activator: put only the `YieldRepurchaseFacilityV2Activator` entry into a copy of the sequence file and run the second command with it. A changed `gracePeriod`, `timelockDelay` or `stepGasLimit` requires the policies themselves to be redeployed (the step gas limit can instead be changed after the launch with `YieldRepurchaseFacilityV2Batch.reconcileStepGasLimit`).

## Step 2: record the addresses

The deployment writes the addresses into `src/scripts/env.json`: the five policies under `olympus.policies`, the lens under `olympus.periphery`, the six libraries under `olympus.libraries` and the activator under `olympus.proposals.YieldRepurchaseFacilityV2Activator`. Record them by hand in:

- `src/proposals/addresses.json`, replacing the zero placeholders of `olympus-policy-backing-oracle`, `olympus-policy-backing-oracle-config-timelock`, `olympus-policy-yieldrepurchasefacility-config-1_0`, `olympus-policy-yieldrepurchasefacility-config-timelock-1_0`, `olympus-policy-yieldrepurchasefacility-2_0`, `olympus-periphery-yieldrepurchasefacility-lens` and `olympus-proposal-yieldrepurchasefacility-v2-activator`. The proposal refuses to build while one of the entries it reads is zero.
- `documentation/emergency/emergency-config.json`, as described below.

Commit `env.json`, `addresses.json`, the `broadcast/` records of both deployment scripts and the emergency configuration.

### Emergency configuration

The facility is added to `documentation/emergency/emergency-config.json` once it has an address, and not before: a `disable` sent to an address without code succeeds and does nothing.

1. Add the address of the facility to `chains.mainnet.contracts`:

    ```json
    "YieldRepurchaseFacilityV2": "<facility>"
    ```

2. Add `"YieldRepurchaseFacilityV2"` to `contractRegistry`.
3. Add the component to `components`:

    ```json
    {
        "availableOn": ["mainnet"],
        "calls": [
            {
                "abi": "periphery_enabler",
                "args": [
                    {
                        "name": "disableData_",
                        "type": "bytes",
                        "value": ""
                    }
                ],
                "contractKey": "olympus.policies.YieldRepurchaseFacilityV2",
                "function": "disable",
                "signature": "disable(bytes)"
            }
        ],
        "category": "reserve",
        "description": "Disables the Yield Repurchase Facility V2: closes its live bond markets and stops the weekly treasury withdrawals and the daily markets. The funds of the buyback pools stay on the facility until returnFundsToTreasury is called",
        "id": "yield-repurchase-facility-v2",
        "name": "Yield Repurchase Facility V2",
        "owner": "emergency",
        "postShutdownSteps": [
            "Verify that isEnabled() of the facility is false and that its bond markets are closed",
            "To return the funds of the buyback pools to TRSRY, run YieldRepurchaseFacilityV2Batch.returnFundsToTreasuryEmergencyMS and set the gas limit of the Safe transaction by hand: before the sweep of each vault the facility requires stepGasLimit + stepGasLimit / 63 + 15000 gas to be left (2,046,746 at a step gas limit of 2,000,000), and an estimate derived from the gas used is too low",
            "Check the batch log for a WARNING about a skipped vault, and run the batch again for a vault that kept its balances",
            "The DAO MS (yrf_admin) can resume the facility with reEnable() within 5 days of the disable; after that only an OCG proposal can enable it again",
            "The configuration policy, its config timelock and the BackingOracle with its config timelock are disabled separately (freezeConfigEmergencyMS and haltAllEmergencyMS of YieldRepurchaseFacilityV2Batch, the levers of BackingOracleBatch)"
        ],
        "severity": "medium",
        "shutdownCriteria": [
            "Yield calculation errors",
            "Unauthorized fund movements",
            "Reserve manipulation",
            "Bond markets opened at a wrong price"
        ]
    }
    ```

4. Bump `version`, set `lastUpdated`, and run `node shell/validate-emergency-config.js`.

Until the proposal executes the facility is disabled, and the component of v1.2 (`yield-repurchase-facility`) stays the emergency action for the facility that is running. It is retired in step 9.

## Step 3: activate the policies in the Kernel (DAO MS)

```bash
./shell/safeBatchV2.sh --contract BackingOracleSetupBatch --function setupKernel --chain mainnet --multisig true --ledger <mnemonic index> --broadcast true
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2SetupBatch --function setupKernel --chain mainnet --multisig true --ledger <mnemonic index> --broadcast true
```

Both batches activate only policies that are not active, and enable nothing. A policy stays disabled until the proposal executes, and a disabled policy of the stack does nothing when the Heart beats.

## Step 4: authorize the market callback (Safe that owns the bond auctioneer)

```bash
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2SetupBatch --function setCallbackAuthStatus --chain mainnet --multisig true --ledger <mnemonic index> --broadcast true
```

The batch is proposed to the Safe that `owner()` of the Bond Protocol auctioneer reports (`0x007BD11FCa0dAaeaDD455b51826F9a015f2f0969` at the time of writing), by one of its signers. Without the authorization the `enable` of the facility reverts, so the activator refuses to launch.

## Step 5: readiness report

```bash
FOUNDRY_PROFILE=deploy forge script src/scripts/ops/batches/YieldRepurchaseFacilityV2SetupBatch.sol:YieldRepurchaseFacilityV2SetupBatch --sig "checkReadiness()" --rpc-url mainnet
```

The report ends with `READINESS RESULT mainnet: GREEN` or `RED`. It checks the desired state of `env.json`, the deployment, the Kernel and the roles, the never-enabled state of the stack, the callback authorization, the Heart slot of v1.2, the PRICE module and the USDe/USD feed, the vaults, the Clearinghouses, and the activator: that it is recorded, accepts the OCG timelock, is bound to the contracts of `env.json`, carries the launch values of `env.json`, is not activated, holds no role, and that its `checkPreconditions()` passes. The registration parameters of the USDe/USD feed are read from the activator.

Do not submit the proposal on a RED report.

## Step 6: build and submit the proposal

### The next yield of sUSDe

The sUSDe vault has no history in v1.2, so its first weekly withdrawal is a constant of the proposal, `YieldRepurchaseFacilityV2Proposal.SUSDE_NEXT_YIELD`, passed to `activate`. It is one week of yield at 4% a year on the USDe value of the sUSDe the treasury holds, each division rounded down:

```text
value  = sUSDe.previewRedeem(sUSDe.balanceOf(TRSRY))
annual = value * 400 / 10000
seed   = annual / 52
```

Read at mainnet block 26,400,405 (2026-11-12):

```text
shares = 21688234987422170095974397
value  = 27281582294757285410552626   (27,281,582.29 USDe)
annual = 1091263291790291416422105
seed   = 20985832534428681085040      (20,985.83 USDe)
```

Recompute the value on a fresh block before the submission:

```bash
TRSRY=0xa8687A15D4BE32CC8F0a8a7B9704a4C3993D9613
SUSDE=0x9D39A5DE30e57443BfF2A8307A4256c8797A3497
SHARES=$(cast call $SUSDE "balanceOf(address)(uint256)" $TRSRY --rpc-url mainnet | awk '{print $1}')
VALUE=$(cast call $SUSDE "previewRedeem(uint256)(uint256)" $SHARES --rpc-url mainnet | awk '{print $1}')
python3 -c "print($VALUE * 400 // 10000 // 52)"
```

If it differs materially, update the constant, the derivation in its NatSpec, the two numbers in `_descriptionParameters()` of the proposal, and the block above. `test_proposalDescription` fails while the description and the constant disagree. The activator rejects a value above 100,000 USDe. The stored next yield of sUSDe can also be lowered after the launch through the config timelock (`queueDecreaseNextYield`) before the first weekly reset withdraws it.

### Build

The build of the proposal fails closed, with a named error, on:

- an address missing from `addresses.json` (`AddressNotRecorded`);
- a recorded activator that is not an activator (`InvalidActivator`), accepts another caller than the OCG timelock, or is bound to another contract or token than the registry records, or to another USDe/USD feed than `env.json` declares (`AddressMismatch`);
- launch values of the activator that differ from `env.json` (`ParameterMismatch`, `FlagMismatch`, `AddressMismatch`), or an `env.json` that does not declare exactly the two enabled vaults with sUSDS as the backing vault (`AssetSetMismatch`, `AssetDeclaredDisabled`);
- an sUSDe next yield above the maximum of the activator (`NextYieldTooHigh`);
- an activator that already holds `admin` or `loop_daddy` (`UnexpectedRole`);
- an OCG timelock that does not hold `admin` (`MissingRole`) or does not administer `RolesAdmin` (`AddressMismatch`);
- a precondition of the activator that does not hold, with the error of the activator.

Run the suites and the rehearsal first:

```bash
FOUNDRY_PROFILE=deploy forge test -j 4 -vv --match-path \
    'src/test/{proposals/YieldRepurchaseFacilityV2*.t.sol,proposals/YieldRepurchaseFacilityV2Activator/**,scripts/deploy/DeployYieldRepurchaseFacilityV2/**}'
./shell/yrf/anvil-deployment/run.sh
```

The first command runs the unit suites of the activator, the test of its deployment function and the fork suites of the activator and of the proposal, under the profile the contracts are deployed with.

Once the addresses are recorded, the fork suites stop deploying the stack themselves and check the live state instead: move `BLOCK` of `YieldRepurchaseFacilityV2ProposalRig` to a block after steps 3 and 4. The first run on a new block is slow: the simulation of the proposal rolls the block number forward by about 93,600 blocks (two voting delays and one voting period), and the fork then fetches the block hash history contract of EIP-2935 slot by slot until the fork cache of the block holds it.

### Submit

```bash
./src/scripts/proposals/submitProposal.sh \
    --file src/proposals/YieldRepurchaseFacilityV2Proposal.sol \
    --contract YieldRepurchaseFacilityV2ProposalScript \
    --account <cast account> --chain mainnet --broadcast true --env .env
```

Read the id of the proposal from the chain: `proposalCount()` of the governor right after the submission, or the `ProposalCreated` event of the submission transaction. The submission script prints `Proposal ID` as the value `propose` returned in its simulation minus one, which is not read from the chain.

```bash
cast call <governor> "proposalCount()(uint256)" --rpc-url mainnet
```

After the submission, set `IS_SUBMITTED` and `BLOCK` of `YieldRepurchaseFacilityV2ProposalRig` to the submission, and copy the desired state of `env.json` into `src/scripts/proposals/snapshots/YieldRepurchaseFacilityV2Proposal.env.json` (the keys the snapshot already holds): from then on the suites compare the simulated calldata with the submitted proposal, and the proposal and the rig read the snapshot and not the tracked file, which is free to move on.

Nothing has to be done by the DAO MS or by the owner of the bond auctioneer during the vote. Do not change the Kernel activation of the five policies, the callback authorization, the roles above or the state of v1.2 until the proposal has executed.

## Step 7: execute the proposal

### When

The proposal can be executed from its `eta` (one day after it is queued) until `eta + 1 day` (`Timelock.GRACE_PERIOD`).

Execute soon after a daily beat of v1.2, that is, after the Heart beat that brings the epoch counter of v1.2 to a multiple of three. On that beat v1.2 burns the OHM it bought the day before against a treasury withdrawal of its backing. The OHM v1.2 buys afterwards is burned by the shutdown without a withdrawal: its backing stays in the treasury and does not enter the buyback pool of the new facility. Right after a daily beat that amount is at its smallest.

### Check first

```bash
cast call <activator> "checkPreconditions()" --rpc-url mainnet
```

The call returns nothing when the launch would execute now and reverts with the error of the first precondition that does not hold. It does not check the two roles of the activator, which the proposal itself grants.

It does not check the other roles either. The role actions of the proposal were chosen from the roles held when it was built, and the ROLES module reverts on the grant of a role that is held and on the revocation of a role that is not. If one of these roles has changed since the submission, the execution reverts at that action. Compare each role with the submitted actions:

```bash
ROLES=$(cast call <kernel> "getModuleForKeycode(bytes5)(address)" 0x524f4c4553 --rpc-url mainnet)
cast call $ROLES "hasRole(address,bytes32)(bool)" <account> $(cast format-bytes32-string <role>) --rpc-url mainnet
```

| Account | Role | Expected before the execution |
| ------- | ---- | ----------------------------- |
| Activator | `admin`, `loop_daddy` | `false` for both |
| DAO MS | `yrf_admin`, `backing_admin` | `false` if the proposal grants the role, `true` if it does not |
| DAO MS, OCG timelock | `loop_daddy` | `true` if the proposal revokes the role, `false` if it does not |
| OCG timelock | `admin` | `true` |

### Execute

```bash
cast send <governor> "execute(uint256)" <proposal id> --gas-limit 6000000 --account <cast account> --rpc-url mainnet
```

The proposal id is the one read from the chain after the submission (step 6). Set the gas limit by hand. The execution of the nine actions through the governor, measured on a fork of block 26,256,437 with the registration of USDe included, uses 2,832,575 gas (`test_givenQueued_whenExecutedThroughTheGovernor_gas`; the call of the activator alone uses 2,264,643). The recommended limit of 6,000,000 is about twice the measurement and stays well below the transaction gas limit of mainnet, 16,777,216 (EIP-7825). An estimate from `eth_estimateGas` is the minimum for the block of the estimate, and the gas of the sUSDS conversions depends on the time since the last accrual of the vault, so a transaction sent with the bare estimate can run out of gas.

A reverted execution changes nothing and leaves the proposal queued: it can be executed again until the grace period ends.

### What a retry cures and what needs a new proposal

The governor reports the failure of any action as `Timelock_InvalidTx_ExecReverted`. `checkPreconditions()`, the role check above and a trace of the transaction name the cause.

| Revert | Cause | Cure |
| ------ | ----- | ---- |
| `UsdeFeedNotReadable` | The answer of the USDe/USD feed is older than 1 day (the feed updates about every 23 hours) | Wait for the next update and execute again |
| `UsdePriceOutOfBounds` | USDe trades more than 1% away from 1 USD | Execute again once the price is back inside the bound; if it stays outside for the whole window, a new activator with other registration parameters and a new proposal are needed |
| `ReserveNotPriceable` | The PRICE module cannot price OHM in USDS or USDe (a stale feed) | Execute again once the feeds are updated |
| `CallbackNotAuthorized` | The owner of the bond auctioneer revoked the authorization | Step 4 again, then execute again |
| `PolicyNotActive` | A policy of the stack, the Heart or PriceConfig was deactivated in the Kernel | The DAO MS activates it again, then execute again |
| `PolicyNotEnabled` | The Heart or PriceConfig is disabled | Enable it again, then execute again |
| Out of gas | The gas limit was too low | Execute again with a higher limit |
| `GovernorBravo_Execute_BelowThreshold` | The votes of the proposer fell below the proposal threshold recorded at the submission | The proposer restores the votes, then execute again |
| `ClearinghouseReceivablesNotReadable` | `principalReceivables()` of an included or offset Clearinghouse reverts | Execute again once the read succeeds; if it does not inside the window, a new activator without that inclusion or offset and a new proposal |
| `ROLES_AddressAlreadyHasRole`, `ROLES_AddressDoesNotHaveRole` at a role action | A role the proposal grants or revokes was granted or revoked by another proposal after the submission | New proposal, built on the roles held then; the same activator can be used |
| `FacilityAlreadyHeartTask` | The facility was added to the periodic tasks of the Heart outside the activator | The OCG timelock removes it, which takes a proposal; then a new proposal for the launch |
| `ClearinghouseRegistryMismatch` | A Clearinghouse joined the CHREG registry | New activator with the new list in `env.json`, new proposal |
| `ClearinghouseOffsetTooHigh` | The receivables of a Clearinghouse fell below its offset | New activator with a lower offset, new proposal |
| `V1ShutDown`, `V1ConversionRateUnset`, `V1NotHeartTask` | v1.2 was shut down, initialized again with a zero conversion rate, or removed from the Heart | Investigate; the migration assumes a running v1.2 |
| `PolicyAlreadyEnabled`, `AlreadyBound` | A policy of the stack was enabled or bound outside the activator | New deployment of the affected policies and of the activator, new proposal |
| `BindingMismatch` | The backing oracle or the bond auctioneer of the facility was changed | Restore it, or deploy a new activator; new proposal in the second case |

A proposal that was not executed inside its window is submitted again as a new proposal. The same activator can be used again as long as `isActivated()` is false and its values still equal `env.json`.

### Verify

After the execution:

- `isActivated()` of the activator is true, and it holds neither `admin` nor `loop_daddy`.
- `isEnabled()` is true for the five policies; `backing()` of the oracle, `initialDiscount()` and `maxPricePremium()` of the facility carry the launch values.
- `getVaults()` of the facility returns sUSDS and sUSDe, `backingVault()` is sUSDS, `epoch()` equals `epoch()` of v1.2 and `isCycleSeedable()` is false.
- `isShutdown()` of v1.2 is true and it holds no USDS, sUSDS or OHM.
- `getPeriodicTaskIndex(facility)` of the Heart is the index v1.2 held, and v1.2 is no periodic task.
- The DAO MS holds `yrf_admin` and `backing_admin`; neither the DAO MS nor the OCG timelock holds `loop_daddy`.
- `YieldRepurchaseFacilityV2ConfigTimelockBatch.reconcile` and `BackingOracleConfigTimelockBatch.reconcileBacking` propose nothing.

The bond market v1.2 opened on the day of the launch stays live until its conclusion, at most a day later: the shutdown moves the USDS of v1.2 to the treasury and does not close the market. v1.2 then holds no USDS, so a purchase on that market reverts in the transfer of the payout. USDS that any account sends to v1.2 before the market concludes is sold on it, and the OHM received stays on v1.2.

## Step 8: deactivate v1.2 in the Kernel (DAO MS)

```bash
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2SetupBatch --function deactivateV1 --chain mainnet --multisig true --ledger <mnemonic index> --broadcast true
```

Build and simulate the batch immediately before signing: its preconditions (v1.2 shut down and no periodic task, the new facility active, enabled and a periodic task) are checked when the batch is built. A token balance on v1.2 is reported as a warning and does not stop the batch.

## Step 9: retire v1.2 in the emergency configuration

A change of the repository, not an action of a multisig. `documentation/emergency/emergency-config.json` carries two components for the facility between step 2 and this step, because v1.2 stays the live facility until the proposal executes:

- `yield-repurchase-facility` (v1.2, owner `dao`, `shutdown`), available on mainnet and Sepolia;
- `yield-repurchase-facility-v2` (owner `emergency`, `disable`), available on mainnet, added in step 2.

After the proposal has executed, remove `mainnet` from `availableOn` of `yield-repurchase-facility` and remove `chains.mainnet.contracts.YieldRepurchaseFacility`, bump `version` and `lastUpdated`, and run `node shell/validate-emergency-config.js`. Do not remove the v1.2 component before the execution: until then it is the only emergency action for the facility that is running. The component stays for Sepolia.

## Preconditions of the activator

`checkPreconditions()` reverts with the first of these that does not hold, and `activate` runs the same check:

- every bound contract still reports the binding the constructor checked (`BindingMismatch`);
- the five policies are active in the Kernel (`PolicyNotActive`), disabled and never enabled before (`PolicyAlreadyEnabled`);
- the configuration policy names no facility, the facility no configurator, and the configuration policy and the oracle no config operator (`AlreadyBound`);
- the facility is authorized as a market callback on its bond auctioneer (`CallbackNotAuthorized`);
- the Heart is active in the Kernel and enabled, v1.2 is one of its periodic tasks and the facility is not (`V1NotHeartTask`, `FacilityAlreadyHeartTask`);
- v1.2 is not shut down and its conversion rate snapshot is not zero (`V1ShutDown`, `V1ConversionRateUnset`); a zero reserve balance snapshot is accepted, and the yield projected from it is zero;
- the Clearinghouse list of the activator is the registry of the CHREG module, the receivables of every included or offset Clearinghouse can be read, and no offset exceeds them (`ClearinghouseRegistryMismatch`, `ClearinghouseReceivablesNotReadable`, `ClearinghouseOffsetTooHigh`);
- the PRICE module prices OHM in USDS, and in USDe if USDe is registered (`ReserveNotPriceable`); if USDe is not registered, PriceConfig is active and enabled, and the USDe/USD feed passes the checks of the registration: an answer at most 1 day old and a price within 100 basis points of 1 USD (`UsdeFeedNotReadable`, `UsdePriceOutOfBounds`).

Read when `activate` runs, and therefore not preconditions: the epoch counter, the stored next yield, the yield snapshots and the USDS and sUSDS balances of v1.2 (a transfer of tokens to v1.2 by any account joins the buyback pool), the sUSDe balance of the treasury and the rate of sUSDe, the PRICE, TRSRY, CHREG and ROLES modules of the Kernel, and whether USDe is registered. A treasury that holds less sUSDS than the seed of the buyback pool does not stop the launch: the facility carries the uncovered part and retries it at the next weekly reset.

## Operation

The batches of the DAO MS and of the Emergency MS are described in `src/scripts/ops/README.md`, section "YieldRepurchaseFacilityV2 and BackingOracle": the desired-state reconciliation through the config timelocks (`reconcile`, `reconcileBacking`, `executeReadyActions`), the step gas limit, the correction of a stored next yield, cancellations, and the lifecycle.

Authority after the launch:

| Authority | Holder | Used for |
| --------- | ------ | -------- |
| `admin` | OCG timelock | Registering and removing vaults, the backing vault, the payout mode of a vault, including a Clearinghouse and lowering an offset, the bond auctioneer, the backing oracle and the configurator of the facility, `enable` after a grace period has passed, a backing update without the timelock |
| `yrf_admin` | DAO MS | Queueing on `YieldRepurchaseFacilityV2ConfigTimelock` (1-day delay, 3-day execution window), `reEnable` of the facility, the configuration policy and the timelock within 5 days of a disable, the step gas limit, `rescue` |
| `backing_admin` | DAO MS | Queueing backing updates on `BackingOracleConfigTimelock` (1-day delay, 7-day execution window, at most 10% per update), `reEnable` of the oracle and its timelock within 7 days of a disable |
| `emergency` | Emergency MS | `disable` of each of the five policies, `returnFundsToTreasury` of a disabled facility, cancellation of queued actions |
| `loop_daddy` | nobody | v1.2 cannot be initialized again |

## Emergency levers

All levers are entry points of `YieldRepurchaseFacilityV2Batch` and `BackingOracleBatch`, run by the Emergency MS:

```bash
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2Batch --function stopPurchasesEmergencyMS --chain mainnet --multisig true --ledger <mnemonic index> --broadcast true
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2Batch --function freezeConfigEmergencyMS --chain mainnet --multisig true --ledger <mnemonic index> --broadcast true
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2Batch --function haltAllEmergencyMS --chain mainnet --multisig true --ledger <mnemonic index> --broadcast true
./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2Batch --function returnFundsToTreasuryEmergencyMS --chain mainnet --multisig true --ledger <mnemonic index> --broadcast true
./shell/safeBatchV2.sh --contract BackingOracleBatch --function freezeUpdatesEmergencyMS --chain mainnet --multisig true --ledger <mnemonic index> --broadcast true
./shell/safeBatchV2.sh --contract BackingOracleBatch --function haltAllEmergencyMS --chain mainnet --multisig true --ledger <mnemonic index> --broadcast true
```

- `stopPurchasesEmergencyMS` disables the facility: its live markets are closed and no new ones open. The funds stay on the facility.
- `freezeConfigEmergencyMS` disables the configuration policy and its timelock; `haltAllEmergencyMS` disables all three.
- A lever validates a Heart beat after its batch. When the Heart fails for a reason the lever does not remove, the validation fails the build of the batch: set `EMERGENCY_SKIP_HEARTBEAT_VALIDATION=true` in the environment to build the lever without it.
- `returnFundsToTreasuryEmergencyMS` runs on a disabled facility only. Set the gas limit of the Safe transaction by hand: before the sweep of each vault the facility requires `stepGasLimit + stepGasLimit / 63 + 15000` gas to be left (2,046,746 at the step gas limit of 2,000,000 the stack is deployed with), while the gas the call uses is far lower, so a limit derived from the gas used makes the call revert. The batch prints the gas that has to be left before every step.
- After `returnFundsToTreasuryEmergencyMS`, read the log of the batch: a vault whose sweep failed is reported with a `WARNING` and keeps its balances, and the batch does not fail on it. Run the batch again for such a vault.
- While the oracle is disabled, the price gate of the facility is closed: live markets stay purchasable until they conclude, no new market opens, and the purchased OHM is not burned. `reEnable` of the facility is refused until the oracle is enabled again.

The DAO MS resumes a disabled policy with `YieldRepurchaseFacilityV2Batch.reEnable` or `BackingOracleBatch.reEnable` inside the grace period (5 days for the facility, the configuration policy and the config timelock, 7 days for the oracle and its timelock). After that only an OCG proposal can enable it.

## Rehearsal

`shell/yrf/anvil-deployment/run.sh` rehearses all of the above on an Anvil fork of mainnet: both deployment sequences, the checks of the deployment, the two batches before the proposal, the readiness report (RED before the callback authorization, GREEN after it), the build of the proposal that fails before the authorization, the replay of the proposal from the impersonated OCG timelock, `deactivateV1`, and every operational and emergency entry point. See its README.
