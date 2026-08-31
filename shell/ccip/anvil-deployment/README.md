# CCIP config Anvil deployment harness

Deploys the CCIP config policies from scratch on a local Anvil fork of Ethereum mainnet (`run-ethereum.sh`) or of one burn/mint L2 (`run-l2.sh`) and runs the real deploy / batch / OCG-proposal scripts against it. Deploys are signed with an Anvil dev key; DAO MS, Emergency MS, deployer EOA and timelock actions are sent from the real on-chain owners via Anvil impersonation. The OHM fee budgets that only Chainlink can set are mocked on the fork by impersonating the owners of the live fee contracts (FeeQuoter 2.0.0 on the 1.6 lanes, the dedicated on-ramp on the 1.5 lanes); the negative runs first assert that the scripts fail closed without the mock.

## Requirements

- `anvil`, `forge`, `cast`, `jq`, `git`
- `.env` in the repo root with `ALCHEMY_API_KEY`

## What the scripts touch

Each run backs up and, on exit, restores `src/scripts/env.json` and `src/proposals/addresses.json`. Deployed addresses are written into `env.json` by the deploy script and synced into `addresses.json` for the proposal. With `--keep-fork` the fork stays up and these files are left populated so you can keep sending transactions; otherwise they are restored and Anvil is stopped. The per-deploy records that `DeployV3` writes under `deployments/` and `broadcast/DeployV3.s.sol/` during the run are removed.

## Ethereum

```bash
./run-ethereum.sh
```

Steps:

1. Inject placeholder pools and peripheries for the four burn/mint chains into `env.json` (the proposal encodes them into its route actions; the mainnet fork cannot see the real ones). Start an Anvil fork of mainnet; fund the deployer and the timelock.
2. Deploy `ccip_config_mainnet.json` (`CCIPBridgeConfig`, then `CCIPBridgeConfigTimelock`) and print the binding (`config.pool()`, `timelock.config()`, delay, grace periods).
3. Sync the deployed addresses into `addresses.json`.
4. Phase B (DAO MS as Kernel executor, pool owner and OHM administrator): `CCIPBridgeConfigBatch.prepareHandover`, then a second run that must propose nothing. Then `CCIPTokenPool.fundPool` tops the pool up to `olympus.config.CCIP.minimumPoolBacking` (minting to the DAO MS from the impersonated MINTR module first if its balance were ever short), with an empty re-run.
5. Negative checks: the mainnet readiness report is RED and the proposal build fails naming a lane while the OHM fee budgets read the 90k default; then the four mainnet lanes are mocked to 175k and the readiness report turns GREEN.
6. Phase C (OCG): `executeOnAnvilFork.sh` replays `CCIPBridgeConfigProposal` (12 actions: the handover plus four `addChain`) from the timelock. The replay first runs the proposal through the governance simulation and its own `_validate` inside a snapshot, then sends the actions from the impersonated timelock. The four routes must exist on the pool afterwards.
7. Post-OCG (DAO MS as `bridge_admin`): `CCIPRouteReconcileBatch.reconcileRoutes` on the converged routes must propose nothing. `CCIPBridge.reconcileTrustedRemotes` adds the four EVM trusted remotes and gas limits (and must propose nothing for solana), with an empty re-run. The timelock path is then exercised end to end: the desired outbound rate in `env.json` is changed, `reconcileRoutes` queues `setChainRateLimits`, a second run proposes nothing (the change is already queued), `executeReadyActions` proposes nothing before the delay, the clock is warped past the delay, `executeReadyActions` executes, and `reconcileRoutes` proposes nothing again. The original rate is then restored through the same cycle.
8. Containment: `CCIPBridgeConfigBatch.disableChain` from the DAO MS as `bridge_admin` contains the Solana route, a re-run through the Emergency MS variant (`disableChainEmergencyMS`) proposes nothing, and the declarative recovery (`reconcileRoutes` -> warp -> `executeReadyActions` -> `reconcileRoutes`) restores the approved limits.
9. Print the final authority state: pool owner and pending owner, rebalancer, rate limit admin, config operator, enabled flags, registry entry, DAO MS roles, routes and buckets.

Every batch log is asserted: steps that must change state must report `Batch executed successfully on Anvil fork`, and re-runs on a converged state must report `No batch targets to execute`.

## Burn/mint L2

```bash
./run-l2.sh --chain arbitrum   # or optimism | base | berachain
```

Steps:

1. Inject placeholder pools and peripheries for the other burn/mint chains; fork the L2.
2. Registry handover with the real entry points: `CCIPTokenPool.transferTokenPoolAdminRoleToDaoMS` from the impersonated Olympus deployer EOA, `CCIPTokenPool.acceptAdminRole` from the DAO MS.
3. Deploy `ccip_full_not_mainnet.json` (pool, periphery, config policy, timelock) and print the binding.
4. Ownership handover from the deployer: `CCIPTokenPool.transferTokenPoolOwnershipToConfig` and `CCIPBridge.transferOwnership`.
5. Negative checks: the chain's readiness report is RED and `CCIPNonEthereumSetupBatch.setup` fails naming a lane while the fee budgets read the 90k default; then the outgoing burn/mint lanes are mocked to 175k and the readiness report turns GREEN.
6. `CCIPNonEthereumSetupBatch.setup` (legacy LZ deactivation, activations, roles, config/timelock enablement, pool acceptance, `addChain` per route), with an empty re-run; the pool must still be disabled and unregistered afterwards.
7. `CCIPNonEthereumSetupBatch.finalize` (`pool.enable`, `setPool`), with an empty re-run.
8. Periphery: `CCIPBridge.reconcileTrustedRemotes` and `CCIPBridge.enable`, each with an empty re-run.
9. Containment and recovery on the local pool: `CCIPBridgeConfigBatch.disableChain` from the DAO MS as `bridge_admin` contains the mainnet route (args file `CCIPBridgeConfigBatch_disableChain_mainnet.json`), a re-run through `disableChainEmergencyMS` from the Emergency MS proposes nothing, and the declarative recovery (`reconcileRoutes` -> warp -> `executeReadyActions` -> `reconcileRoutes`) restores the approved limits through the local config timelock.
10. Control plane: `CCIPBridgeConfigBatch.disablePolicies` from the DAO MS as the local `admin` freezes the config policy and the timelock, and `CCIPBridgeConfigBatch.reEnable` from the DAO MS as `bridge_admin` restores them inside the grace window, each with an empty re-run.
11. Print the final authority state.

## Rehearse against the already-deployed contracts

Once the config policies are live on mainnet (their addresses recorded in `env.json` / `addresses.json`) but the DAO MS batch and the OCG proposal have not executed yet, pass `--use-deployed` to skip the deploy step and run the handover flow against those addresses instead of a fresh throwaway set:

```bash
./run-ethereum.sh --use-deployed
```

## Options

- `--port <port>`: Anvil port (default `8545`).
- `--keep-fork`: leave Anvil running and the env/addresses files populated on exit.
- `--use-deployed`: skip the deploy step and run against the config addresses already in `env.json` / `addresses.json`.

Env overrides: `ANVIL_CUPS` (default `250`) and `ANVIL_BACKOFF_MS` (default `1000`) throttle the fork's upstream RPC. Per-step logs are written to `logs/`.

## After a `--keep-fork` run

The fork stays on `http://localhost:<port>` with the contracts deployed and the addresses in `env.json` / `addresses.json`. Send further transactions with `cast` against that RPC, impersonating any address (the fork runs with `--auto-impersonate`), or run the batches with `./shell/safeBatchV2.sh --fork true` (`--owner emergency` for the Emergency MS entry points). Stop it with `kill <pid>` (printed on exit).
