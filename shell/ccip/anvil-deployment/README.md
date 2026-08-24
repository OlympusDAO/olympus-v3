# CCIP config Anvil deployment harness

Deploys the CCIP config policies from scratch on a local Anvil fork of Ethereum mainnet and runs the real deploy / batch / OCG-proposal scripts against it. Deploys are signed with an Anvil dev key; DAO MS, Emergency MS and timelock actions are sent from the real on-chain owners via Anvil impersonation.

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

1. Start an Anvil fork of mainnet; fund the deployer and the timelock.
2. Deploy `ccip_config_mainnet.json` (`CCIPBridgeConfig`, then `CCIPBridgeConfigTimelock` from its artifact) and print the binding (`config.pool()`, `timelock.config()`, delay, grace periods).
3. Sync the deployed addresses into `addresses.json`.
4. Phase B (DAO MS as Kernel executor, pool owner and OHM administrator): `CCIPBridgeConfigBatch.prepareHandover`, then a second run that must propose nothing.
5. Phase C (OCG): `executeOnAnvilFork.sh` replays `CCIPBridgeConfigProposal` from the timelock. The replay first runs the proposal through the governance simulation and its own `_validate` inside a snapshot, then sends the actions from the impersonated timelock.
6. Post-OCG (DAO MS as `bridge_admin`): `CCIPRouteReconcileBatch.reconcileRoutes` on the converged Solana route must propose nothing. The timelock path is then exercised end to end: the desired outbound rate in `env.json` is changed, `reconcileRoutes` queues `setChainRateLimits`, a second run proposes nothing (the change is already queued), `executeReadyActions` proposes nothing before the delay, the clock is warped past the delay, `executeReadyActions` executes, and `reconcileRoutes` proposes nothing again. The original rate is then restored through the same cycle.
7. Containment (Emergency MS): `CCIPBridgeConfigBatch.disableChain` contains the Solana route, a second run proposes nothing, and the declarative recovery (`reconcileRoutes` -> warp -> `executeReadyActions` -> `reconcileRoutes`) restores the approved limits.
8. Print the final authority state: pool owner and pending owner, rebalancer, rate limit admin, config operator, enabled flags, registry entry, DAO MS roles, routes and buckets.

Every batch log is asserted: steps that must change state must report `Batch executed successfully on Anvil fork`, and re-runs on a converged state must report `No batch targets to execute`.

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
