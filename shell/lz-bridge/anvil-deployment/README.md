<!-- SPDX-FileCopyrightText: Contributors to OlympusDAO -->
<!-- SPDX-License-Identifier: Unlicense -->

# LZ bridge Anvil deployment harness

Deploys the LayerZero bridge from scratch on a local Anvil fork and runs the real deploy / batch / OCG-proposal scripts against it. Deploys are signed with an Anvil dev key; DAO MS and timelock actions are sent from the real on-chain owners via Anvil impersonation.

## Requirements

- `anvil`, `forge`, `cast`, `jq`, `git`
- `.env` in the repo root with `ALCHEMY_API_KEY`

## What the scripts touch

Each run backs up and, on exit, restores: `src/scripts/env.json`, `src/proposals/addresses.json`, and the `initBridgedSupply` args file. Deployed addresses are written into `env.json` by the deploy script and synced into `addresses.json` for the proposal. With `--keep-fork` the fork stays up and these files are left populated so you can keep sending transactions; otherwise they are restored and Anvil is stopped.

## Real-network deploy order

The topology is a full mesh: every chain sets every other chain's gateway as a peer, and on Ethereum the `LZBridgeActivator` takes the four L2 gateway addresses as constructor arguments. So on real networks all gateways are deployed first to collect addresses, then peers/config are wired. A single fork only holds one chain, so the harness injects non-zero placeholder addresses for the other chains' gateways; `setPeer` and the activator only store these as data, so the config and validation pass.

## L2 (Arbitrum / Optimism / Base / Berachain)

The L2 batch performs the entire LZ configuration, so deploy + batches is a complete rollout.

```bash
./run-l2.sh --chain arbitrum
```

Steps:

1. Inject placeholder gateways for the four remote chains into `env.json`.
2. Start an Anvil fork of the chain; fund the deployer.
3. Deploy `lz_bridge_noncanonical.json` (gateway, delegate, periphery bridge, config).
4. `LZBridgeGatewayL2Batch`: `activateGateway` -> `grantRoles` -> `configureAndEnable` -> `wireConfig` -> `revokeSetupRoles`.
5. `LZCrossChainBridgeL2Batch`: `initializeConfigurator` -> `setupL2`.
6. Print gateway / delegate / config / periphery enabled state.

## Ethereum

Mainnet does the LZ configuration through the OCG proposal, not the batch, so the flow adds the proposal and the registry sync.

```bash
./run-ethereum.sh
```

Steps:

1. Inject placeholder L2 gateways and set `initialBridgedSupply`.
2. Start an Anvil fork of mainnet; fund the deployer and the timelock.
3. Deploy `lz_bridge_canonical.json` (gateway, delegate, periphery bridge, config, activator).
4. Sync the deployed addresses into `addresses.json`.
5. Pre-OCG (DAO MS as Kernel executor): `LZBridgeGatewayBatch.activateGateway`, then activate the config policy.
6. Grant the timelock `admin` + `bridge_admin` (a proposal prerequisite).
7. OCG: `executeOnAnvilFork.sh` replays `LZBridgeSecurityUpgradeProposal` from the timelock.
8. Post-OCG (DAO MS): `LZBridgeGatewayBatch.initBridgedSupply`, `LZCrossChainBridgeBatch.initializeConfigurator`, `LZCrossChainBridgeBatch.setup`.
9. Print enabled state, `activator.isActivated`, and `bridgedSupply`.

### The OCG proposal

The proposal is executed directly from the timelock via impersonation (`executeOnAnvilFork`), which builds the action list and replays each action. It does not simulate the governor vote and does not mint OHM or gOHM. To exercise the full governance path instead (propose, deal gOHM, vote, queue, execute), use `src/scripts/proposals/submitProposal.sh` with `shell/anvil/deal_gohm.sh` and `shell/anvil/warp.sh`; the bridge state reached is the same.

## Rehearse against the already-deployed contracts

Once the bridge contracts are live on the real networks (their addresses recorded in `env.json` / `addresses.json`) but the OCG proposal has not been submitted yet, pass `--use-deployed` to skip the deploy step and run the activation flow against those real addresses instead of a fresh throwaway set:

```bash
./run-ethereum.sh --use-deployed              # OCG proposal against the deployed mainnet contracts
./run-l2.sh --chain arbitrum --use-deployed   # L2 batches against the deployed Arbitrum contracts
```

The fork is taken at the latest block (after the contracts were deployed), so their bytecode is present. The flow still runs the pre-OCG `activateGateway` batch and the post-OCG steps, so it assumes the deployed contracts are still in their pre-activation state (the DAO MS batch and the OCG proposal have not executed on chain yet).

## Options

- `--chain <name>` (L2 only): `arbitrum` (default), `optimism`, `base`, `berachain`.
- `--port <port>`: Anvil port (default `8545`; Ethereum requires `8545`).
- `--supply <uint>` (Ethereum only): initial bridged supply (default `1000000000000`).
- `--keep-fork`: leave Anvil running and the env/addresses files populated on exit.
- `--use-deployed`: skip the deploy step and run against the bridge addresses already in `env.json` / `addresses.json`. See "Rehearse against the already-deployed contracts".

Env overrides: `ANVIL_CUPS` (default `250`) and `ANVIL_BACKOFF_MS` (default `1000`) throttle the fork's upstream RPC. Per-step logs are written to `logs/`.

## After a `--keep-fork` run

The fork stays on `http://localhost:<port>` — the `--port` value, `8545` by default — with the contracts deployed and the addresses in `env.json` / `addresses.json`. Send further transactions with `cast` against that RPC, impersonating any address (the fork runs with `--auto-impersonate`). Stop it with `kill <pid>` (printed on exit).
