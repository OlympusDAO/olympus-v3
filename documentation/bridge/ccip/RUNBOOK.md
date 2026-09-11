# CCIP Bridging Infrastructure

This document describes how the Olympus CCIP bridging infrastructure is deployed, configured and operated: the Chainlink token pools, the `CCIPTokenPoolConfig` policy that owns the local pool, the `CCIPTokenPoolConfigTimelock` policy through which route changes are queued, the OHM entry in the Chainlink `TokenAdminRegistry`, and the `CCIPCrossChainBridge` periphery.

## Pre-requisites

- Chainlink must have proposed an administrator for the OHM token in the chain's `TokenAdminRegistry` (done on every production chain).
- `cast` must be set up with your wallet.
- `.env` with `ALCHEMY_API_KEY` (and `ETHERSCAN_KEY` for verification).
- The multisig addresses filled in `env.json`: `<chain>.olympus.multisig.dao` and `<chain>.olympus.multisig.emergency`.

## Definitions

- Canonical chain: the chain on which new OHM supply is minted. Currently `mainnet` (production) and `sepolia` (testnet).
- Non-canonical chain: every other chain.
- OCG timelock: the Olympus Governor Bravo timelock on mainnet (`olympus.governance.Timelock`). It holds the `admin` role, and after the handover it is the OHM administrator in the `TokenAdminRegistry` and the rebalancer of the lock/release pool.

## Concepts

- Token pool: the contract that locks or burns OHM when bridging out and releases or mints OHM when bridging in. On a canonical chain it is a Chainlink `LockReleaseTokenPool`; on a non-canonical chain it is the `CCIPBurnMintTokenPool` policy.
- `CCIPTokenPoolConfig`: the policy that owns the local token pool. It exposes a typed, role-separated subset of the pool owner surface. Root settings (pool ownership, router, rebalancer, native rate limit admin, config operator, grace period, liquidity transfer) are `admin` functions. Route functions (`addChain`, `removeChain`, `setRemoteToken`, `addRemotePool`, `removeRemotePool`, `applyAllowListUpdates`) and `setChainRateLimits` are callable by the config operator or by `admin`; `setChainRateLimits` is also callable by the `bridge_rate_limiter` role, which is unassigned at launch. Containment (`disableChain`, `disableAllChains`) is callable by the `emergency`, `admin`, `bridge_admin` or `bridge_rate_limiter` role whether or not the policy is enabled, and only reduces capacity. There is no arbitrary call forwarding.
- `CCIPTokenPoolConfigTimelock`: the policy that the `bridge_admin` role queues typed route changes on. Each queued action names a config function and its arguments, is validated at queue time with the config policy's `validate*` mirror, reserves the configuration domains it touches (rate limits, remote pools and route identity per route, the pool-wide allowlist) together with their state hashes, and executes permissionlessly after the delay (1 day initial, 3-day execution window). A domain can have one unresolved action at a time; keys are released only by execution or cancellation, never by expiry. The reserved key of a domain is derived by `src/policies/utils/CCIPTokenPoolConfigKeyLib.sol` (the domain constant, keyed by chain selector for a route domain, scoped to the config policy), which is what the reconciler and the setup batch pass to `pendingActionId`; the timelock exposes the domain constants but no key getter. Execution reverts if the route moved since queueing (`ConfigStateChanged`), if the config policy no longer names the timelock as config operator, or if either policy is disabled.
- Bridge: `CCIPCrossChainBridge`, a convenience periphery contract owned by the DAO MS for bridging OHM from an EVM chain to another chain (including SVM). It is not a mandatory path for transfers and disabling it does not stop the pool.

## CCIP lane generations

Chainlink runs three ramp generations across the lanes in scope, and moves lanes between them without notice. Read on 2026-09-04 from every source router: `OnRamp` / `OffRamp` 2.0.0 serve most lanes between mainnet, Arbitrum, Optimism and Base (including mainnet to Arbitrum and to Optimism); `OnRamp` / `OffRamp` 1.6.0 serve mainnet to Base, Base to mainnet and every lane to Solana; `EVM2EVMOnRamp` / `EVM2EVMOffRamp` 1.5.0 serve every EVM lane touching Berachain, with a 2.0.0 Arbitrum to Berachain lane already staged behind a test router. Optimism to Berachain has no lane in either direction. Re-read before an incident or a rollout step, since the generation of a lane can change between two runs.

What depends on the generation:

- The pools are v1 pools (`LockReleaseTokenPool 1.5.1` on mainnet, `CCIPBurnMintTokenPool` on the vendored 1.6 `TokenPool` elsewhere) and every generation serves them: the 2.0.0 on-ramp calls `lockOrBurn` and the 2.0.0 off-ramp `releaseOrMint` on a v1 pool exactly as the 1.6 ramps do, verified against the 2.0.0 sources, against live v1 pools on the mainnet and Arbitrum 2.0.0 lanes, and by sending OHM from the live pool through the mainnet 2.0.0 on-ramp on a fork (both the router and the periphery shapes). No pool change is needed for a lane migration.
- The OHM fee entry of step 0 of the non-Ethereum rollout lives on the source chain's `FeeQuoter 2.0.0` for a 1.6 or 2.0 lane (one quoter per chain, shared by both on-ramps) and on the lane's dedicated `EVM2EVMOnRamp` for a 1.5 lane. The scripts dispatch on the contract family and the major version of the on-ramp and of its fee quoter (`OnRamp` 1.x or 2.x with a `FeeQuoter` 2.x, or `EVM2EVMOnRamp` 1.5) and check the shape of every return they read (word counts, field ranges, the EVM chain family selector), so a patch or minor release that keeps the layouts passes without a code change, while a new family, a new major, a moved fee quoter or a changed layout fails closed with a message naming the lane and what was read; only then does the readiness report or the proposal build stop until the reader is extended.
- Manual execution of a stranded message differs (see Recovery below): `OffRamp.manuallyExecute` on the 1.5 and 1.6 lanes, a permissionless `OffRamp.execute` re-submission on the 2.0.0 lanes.
- The Anvil harness mocks the fee entry per generation (`shell/ccip/anvil-deployment/README.md`). `chainlink-local` 0.2.9 cannot deliver a message sent through a 2.0.0 on-ramp (it drops it without a revert), so a fork test of a 2.0.0 lane needs blocks from before the lane's upgrade or a different delivery path.

## Authority model on mainnet

| Authority                                 | Holder                | Used for                                                                                                                                                       |
| ----------------------------------------- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| OHM administrator in `TokenAdminRegistry` | OCG timelock          | `setPool`, `transferAdminRole` (OCG proposals)                                                                                                                 |
| Token pool owner                          | `CCIPTokenPoolConfig` | every pool owner call, through the policy                                                                                                                      |
| `admin` role                              | OCG timelock          | root config settings, direct route calls, `enable` of both policies, timelock delay                                                                            |
| `bridge_admin` role                       | DAO MS                | `queue*` on the config timelock, cancellation of its own actions, `reEnable()` of both policies within the grace window, `disableChain` and `disableAllChains` |
| `emergency` role                          | Emergency MS          | `disableChain`, `disableAllChains`, `disable()` of both policies, cancellation of queued actions                                                               |
| `bridge_rate_limiter` role                | unassigned            | direct `setChainRateLimits`, `disableChain` and `disableAllChains`, for a future monitoring operator appointed by OCG                                          |
| Lock/release pool rebalancer              | OCG timelock          | `withdrawLiquidity` (OCG proposals); depositing needs no role (a plain transfer credits the pool)                                                              |
| Native pool `rateLimitAdmin`              | zero                  | kept unset so that every rate limit change passes through the policy                                                                                           |
| `CCIPCrossChainBridge` owner              | DAO MS                | periphery configuration (`src/scripts/ops/batches/CCIPBridgeBatch.sol`)                                                                                        |
| Kernel executor                           | DAO MS                | policy activation (`Kernel.executeAction`)                                                                                                                     |

## Authority model on non-canonical chains

There is no OCG timelock on Arbitrum, Optimism, Base and Berachain, so the local DAO MS stands in for it: it is the Kernel executor, the `RolesAdmin` admin, and holds both `admin` and `bridge_admin`. Note that the `admin` role is chain wide: granting it to the DAO MS applies to every policy of that Kernel, not only to CCIP.

| Authority                                 | Holder                      | Notes                                                                                     |
| ----------------------------------------- | --------------------------- | ----------------------------------------------------------------------------------------- |
| OHM administrator in `TokenAdminRegistry` | local DAO MS                | moved off the deployer EOA as the first rollout step                                      |
| Token pool owner                          | local `CCIPTokenPoolConfig` | the pool is the `CCIPBurnMintTokenPool` policy                                            |
| `admin`, `bridge_admin` roles             | local DAO MS                | granted by the setup batch; `admin` is chain wide; `bridge_admin` may also contain routes |
| `emergency` role                          | Emergency MS                | same address on every production chain                                                    |
| `bridge_rate_limiter` role                | unassigned                  | as on mainnet (direct rate limits and containment)                                        |
| `CCIPCrossChainBridge` owner              | local DAO MS                | transferred from the deployer after the deploy sequence                                   |

The pool burns and mints through MINTR and reports `isLiquidityContainer()` false, so it has no rebalancer and no liquidity functions; the config policy refuses `setRebalancer` and `transferLiquidity` on it.

One deliberate launch limitation: the deployed `CCIPBurnMintTokenPool` uses the legacy `PolicyEnabler` lifecycle and has **no `reEnable` and no grace window**. After a `disable` of the pool policy (Emergency MS or admin), only the local `admin` role can restore it through `enable`; the `bridge_admin` grace-window recovery applies to the config policy and the timelock only.

## Desired state in `env.json`

The scripts treat `env.json` as the desired state and the chain as the live state, and produce only the transactions that converge the two. Per chain, under `current.<chain>.olympus`:

```json
{
    "config": {
        "CCIP": {
            "minimumPoolBacking": "130721000000000",
            "routes": {
                "arbitrum": {
                    "enabled": true,
                    "inboundRateLimit": {
                        "capacity": "55000000000000",
                        "isEnabled": true,
                        "rate": "636574074"
                    },
                    "outboundRateLimit": {
                        "capacity": "100000000000000",
                        "isEnabled": true,
                        "rate": "1157407407"
                    },
                    "periphery": {"gasLimit": 275000}
                },
                "solana": {
                    "enabled": true,
                    "inboundRateLimit": {
                        "capacity": "11000000000000",
                        "isEnabled": true,
                        "rate": "127314814"
                    },
                    "outboundRateLimit": {
                        "capacity": "10000000000000",
                        "isEnabled": true,
                        "rate": "115740740"
                    },
                    "periphery": {
                        "gasLimit": 0,
                        "svmReceiver": "0x0000000000000000000000000000000000000000000000000000000000000000"
                    }
                }
            }
        },
        "CCIPTokenPoolConfig": {
            "gracePeriod": 259200,
            "rateLimitAdmin": "0x0000000000000000000000000000000000000000",
            "rebalancer": "0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39",
            "timelockDelay": 86400
        },
        "CCIPCrossChainBridge": {"chains": ["arbitrum", "base", "berachain", "optimism", "solana"]}
    },
    "policies": {
        "CCIPTokenPoolConfig": "0x...",
        "CCIPTokenPoolConfigTimelock": "0x..."
    }
}
```

- `olympus.config.CCIPTokenPoolConfig` holds the deployment parameters (`gracePeriod` of both policies, `timelockDelay` of the timelock) and the desired pool authority (`rebalancer`, `rateLimitAdmin`). The deploy script reads the parameters, the batches and the proposal validate against them. On mainnet `rebalancer` is the explicit OCG timelock address and the proposal requires it to equal `olympus.governance.Timelock`; on sepolia it is the local admin. On the burn/mint chains `rebalancer` is the zero address: the field does not apply there, since the pool is not a liquidity container.
- `olympus.config.CCIP.routes.<remoteChain>` declares one route per remote chain. `enabled` is required and doubles as the removal marker: `enabled: false` means the route must not exist, so the reconciler queues `removeChain` for it while it is live, and the entry stays in the file as the record of the decision; no other field of such an entry is read. A live route that is absent from the file fails the reconciler and the setup batch closed, since removal is never derived from absence: declare it with `enabled: true` and its limits, or with `enabled: false` to remove it. To pause a live route without removing it, use containment (`CCIPTokenPoolConfigBatch.disableChain`), not `enabled: false`. Capacities and rates are in OHM base units (9 decimals); both limiters must be enabled with `0 < rate < capacity`. Optional `remoteToken` and `remotePools` (hex bytes, each exactly 32 bytes: the ABI encoding of an EVM address or the raw account address of an SVM chain, the only length the CCIP ramps accept on every generation in service; the config policy and the reader reject any other length) override the defaults, which are `current.<remoteChain>.olympus.legacy.OHM` and the remote chain's pool (`olympus.periphery.CCIPLockReleaseTokenPool` on a canonical chain, `olympus.policies.CCIPBurnMintTokenPool` on another EVM chain, `olympus.periphery.TokenPool` on Solana), ABI-encoded for EVM chains and packed from the base58 public key for SVM chains. The shared reader is `src/scripts/ops/lib/CCIPConfigLib.sol`. Every production EVM chain declares its Solana route, the burn/mint chains included (sepolia declares no route yet): the EVM side of a burn/mint chain to Solana pair is opened by the setup batch at bootstrap through the same SVM remote path of the pool that serves the live mainnet to Solana route, and the Solana side of the pair is configured from the Solana repository against the same `env.json` entries (the Solana pool's per-chain config names the burn/mint chain's pool and OHM). Declare the route before the setup batch of that chain runs: the setup validator and `finalize` require every declared route to be live, so a route added to the file between `setup` and `finalize` makes `finalize` fail closed until it is opened through the timelock.
- `olympus.config.CCIP.routes.<remoteChain>.periphery` is the desired periphery state toward that chain, consumed by `CCIPBridgeBatch.reconcileTrustedRemotes`. Its presence means the remote must be trusted: for an EVM remote the block requires `gasLimit` (the `ccipReceive` budget on the destination; 275000 everywhere today) and defaults the trusted remote to the remote chain's `olympus.periphery.CCIPCrossChainBridge`, overridable with an explicit `trustedRemote`; for an SVM remote it requires `gasLimit` and an explicit `svmReceiver` (bytes32; the zero value is the intended token-only configuration). Removal is explicit: `enabled: false` on the route, or on the `periphery` block itself, unsets the trusted remote; a live trusted remote without a block fails the reconciler closed, since removal is never derived from absence: declare the block, or declare it with `enabled: false` to unset the remote.
- The 275000 EVM gas limit is sized for the failure path of `CCIPCrossChainBridge._ccipReceive`, not for the happy path. When `receiveMessage` reverts (disabled periphery, untrusted or unset source), the catch branch stores the message in `_failedMessages` (about nine cold storage slots), which meters at about 215000 gas cold against the live mainnet periphery; the happy path meters at about 35000. Under the previous 90000 limit the catch branch itself ran out of gas, the whole `ccipReceive` reverted and the message parked in CCIP `FAILURE` (recoverable only by a manual execution with a raised receiver gas override: `manuallyExecute` on the 1.5 and 1.6 lanes, `execute` with `gasLimitOverride` on the 2.0.0 lanes) instead of the periphery's own retryable store. Re-measure both paths before lowering the value.
- `olympus.config.CCIP.minimumPoolBacking` (mainnet only, OHM base units) is the funding target of the lock/release pool: the sum of the OHM `totalSupply` of the burn/mint chains, rounded up to a whole OHM. It backs tokens that the legacy LayerZero bridge minted there against burns on mainnet. Re-compute it with `shell/calc_bridged_supply.sh` immediately before funding and update the value; `CCIPTokenPoolBatch.fundPool` tops the pool up to it and the proposal refuses to build below it. The Solana-side backing (about 9.76 OHM) is deliberately not part of the target: the lock/release mechanics keep it in balance on their own, and including it would make the static threshold flap whenever OHM flows back from Solana.
- `olympus.config.CCIPCrossChainBridge.chains` is a legacy list: the periphery reconciler ignores it (the `periphery` blocks are the desired state) but warns when the two diverge, and the direct pool owner functions of `CCIPTokenPoolBatch.sol` still read it, on the testnets included. Keep it in sync with the set of `periphery` blocks. A testnet periphery has no `periphery` blocks yet and is reconfigured by declaring them.
- `olympus.policies.CCIPTokenPoolConfig` and `olympus.policies.CCIPTokenPoolConfigTimelock` (and, on the burn/mint chains, `olympus.policies.CCIPBurnMintTokenPool` and `olympus.periphery.CCIPCrossChainBridge`) are written by the deploy script; the zero values in the tracked file are placeholders.
- Sepolia carries the same `CCIPTokenPoolConfig` block (its rebalancer is the local admin) and an empty `routes` object: the live sepolia routes run with disabled limiters, which the config policy rejects, so their desired limits must be chosen and declared before a config policy is deployed there.

Removing a route or a remote pool rejects in-flight messages from that remote; the reconciler prints a warning whenever it queues one.

## Deployment

### Token pool and periphery

For canonical chains (mainnet and sepolia):

```bash
./shell/deployV3.sh --account < cast account > --sequence src/scripts/deploy/savedDeployments/ccip_bridge_mainnet.json --chain <CHAIN> --broadcast false --verify false
```

For non-canonical chains, the full triad plus the periphery deploys as one sequence (`_getAddressNotZero` resolves the pool for the config policy from the same run):

```bash
./shell/deployV3.sh --account < cast account > --sequence src/scripts/deploy/savedDeployments/ccip_full_not_mainnet.json --chain <CHAIN> --broadcast false --verify false
```

`<CHAIN>` is `arbitrum`, `optimism`, `base` or `berachain`. (`ccip_bridge_not_mainnet.json` deploys only the pool and the periphery, for a chain that already has its config policies.)

### Config policy and config timelock

The config policy is bound to the local pool at construction, and the timelock to the config policy, so the sequence deploys `CCIPTokenPoolConfig` first and `CCIPTokenPoolConfigTimelock` second:

```bash
./shell/deployV3.sh --account < cast account > --sequence src/scripts/deploy/savedDeployments/ccip_config_mainnet.json --chain mainnet --broadcast false --verify false
```

(`ccip_config_not_mainnet.json` is the equivalent for non-canonical chains.) `gracePeriod` and `initialTimelockDelay` default to `olympus.config.CCIPTokenPoolConfig.gracePeriod` and `.timelockDelay` of the chain and can be overridden per entry in the sequence `args`. The timelock constructor requires the config policy to report the same Kernel and to advertise `ICCIPTokenPoolConfig`, `IConfigOperator` and `IEnabler`, so a wrong config address fails at deployment.

**Run the deployment under the `deploy` profile.** Deployment bytecode comes from that profile of `foundry.toml` (optimizer on, 400 runs) for every contract, and `shell/deployV3.sh` sets `FOUNDRY_PROFILE=deploy`, so the command above is safe; a bare `forge script` invocation should carry the prefix. Under the everyday profile the optimizer is off and the settings follow the import graph, because a `compilation_restrictions` entry covers the whole connected graph: `DeployV3` lands in the same 400-runs job through its `src/proposals/*.sol` imports and currently produces the same bytecode. That is incidental rather than guaranteed, and compiled outside such a graph the two config policies measure 28,528 B and 35,381 B against the 24,576 B runtime limit (18,515 B and 21,320 B optimized), which no `CREATE` accepts. A source that is built in both jobs also keeps two artifacts (`CCIPTokenPoolConfig.json` and `CCIPTokenPoolConfig.optimized.json`), so read sizes under the deploy profile rather than from a default build.

`--verify true` is expected to verify the deployed contracts from their artifacts (not exercised by the rehearsal, which deploys with `--verify false`). A contract verified separately afterwards needs the same compiler settings, so run `forge verify-contract` under the profile too:

```bash
FOUNDRY_PROFILE=deploy forge verify-contract <address> src/policies/bridge/CCIPTokenPoolConfigTimelock.sol:CCIPTokenPoolConfigTimelock \
    --chain mainnet --constructor-args $(cast abi-encode "constructor(address,address,uint48,uint32)" <kernel> <config> 86400 259200) \
    --etherscan-api-key $ETHERSCAN_KEY
```

The settings are the same for all four CCIP contracts (the pool, the config policy, the config timelock and the periphery), so the only per-contract inputs are the path, the name and the constructor arguments.

After the deployment, record the two addresses in `src/proposals/addresses.json` (`olympus-policy-ccip-token-pool-config`, `olympus-policy-ccip-token-pool-config-timelock`) for the OCG proposal.

## Mainnet rollout

The rollout moves the pool and the registry authority from the DAO MS to the model above in three phases. Each step is gated by the authority that can perform it, so the phases cannot be merged.

### Phase A: deploy and verify

Deploy the config policy and the timelock as above and check `config.pool()`, `timelock.config()`, `timelockDelay()`, `gracePeriod()` and `isLiquidityContainer()`.

### Phase B: DAO MS batch

The DAO MS is the Kernel executor, the pool owner and the OHM administrator, so only it can activate the policies, propose the new pool owner and nominate the new OHM administrator:

```bash
./shell/safeBatchV2.sh --contract CCIPTokenPoolConfigBatch --function prepareHandover --multisig true --account < cast account > --chain mainnet --broadcast false
```

The batch adds `Kernel.executeAction(ActivatePolicy, ...)` for each policy that is not active, `pool.transferOwnership(config)` unless the config policy already owns or is pending owner of the pool, and `TokenAdminRegistry.transferAdminRole(OHM, OCG timelock)` unless the OCG timelock is already the administrator or the pending administrator. Neither transfer is accepted here. A second run on a converged state proposes nothing (`No batch targets to execute`).

### Phase C: OCG proposal

`src/proposals/CCIPTokenPoolConfigProposal.sol` (id 19, `CCIP Bridge Activation`) accepts both transfers, wires the policies and opens the four routes to the burn/mint chains. Every handover action is conditional on the live state: accept the OHM administrator role (the proposal reverts at build time if the OCG timelock is not the pending administrator), grant `bridge_admin` to the DAO MS, enable the config policy, accept the pool ownership (reverts if the config policy is not the pending owner), set the timelock as config operator, set the OCG timelock as rebalancer, clear the native rate limit admin, and enable the timelock. Then one `addChain` per new route (Arbitrum, Base, Berachain, Optimism), after the handover actions because `addChain` requires the enabled config policy to own the pool: at most 12 actions.

The build fails closed unless: the live routes (Solana) match `env.json` exactly; the set of desired routes missing from the pool equals exactly the four expected chains; the pool balance covers `olympus.config.CCIP.minimumPoolBacking` (run `CCIPTokenPoolBatch.fundPool` first); and every mainnet lane toward the four chains carries an enabled OHM fee entry with `destGasOverhead >= 175000` (a request to Chainlink; see the non-Ethereum rollout below). `_validate` asserts the complete end state (authority, roles, parameters, all five routes, backing, budgets, periphery owner). Before submission the aggregated readiness report must be green on every chain: `./shell/ccip/check_rollout_readiness.sh`.

```bash
./src/scripts/proposals/printInputs.sh --file src/proposals/CCIPTokenPoolConfigProposal.sol --contract CCIPTokenPoolConfigProposalScript --chain mainnet
./src/scripts/proposals/submitProposal.sh --file src/proposals/CCIPTokenPoolConfigProposal.sol --contract CCIPTokenPoolConfigProposalScript --account < cast account > --chain mainnet --broadcast true --env .env
```

### After the proposal

- `CCIPRouteReconcileBatch.reconcileRoutes` (DAO MS) must propose nothing.
- Route changes go through the timelock (next section); registry changes, rebalancer changes, router changes, pool ownership transfers and liquidity withdrawals are OCG proposals.
- The address setters of the config policy (`setConfigOperator`, `setRouter`, `setRebalancer`, `setRateLimitAdmin`) and `setRemoteToken` reject the value already held, the zero address included, so a proposal or batch step reads the live value and skips the call when it already matches.
- The pre-handover entry points of `src/scripts/ops/batches/CCIPTokenPoolBatch.sol` that act directly on the pool or on the registry revert with the path to use instead.

## Non-Ethereum rollout

Opens Arbitrum, Optimism, Base and Berachain, coordinated with the mainnet proposal: mainnet opens its four routes in the proposal, each burn/mint chain configures itself during the voting window and switches on immediately after the proposal executes. Optimism-Berachain stays closed in both directions (Chainlink serves no lane there). The Solana route of each burn/mint chain is part of the same rollout: its EVM side is opened by the setup batch together with the EVM routes, and its Solana side (one per-chain config on the Solana pool per burn/mint chain) is applied from the Solana repository between the proposal execution and the finalize of the burn/mint chains, so that both sides of every pair open at finalize. The two repositories read the desired values from the same `env.json` entries, and the Solana repository's readiness report is the second half of the submission gate.

Sequence (each script is idempotent and fails closed on a missing precondition):

0. **Chainlink fee budgets (outside the repository).** Every lane toward a burn/mint chain must carry an enabled OHM fee entry with `destGasOverhead >= 175000` (the destination mint runs two MINTR calls and does not fit the 90000 default). Only Chainlink can set it; request it for the four mainnet lanes and every open L2-to-L2 lane. The entry sits on the source chain's `FeeQuoter 2.0.0` for a 1.6 or 2.0 lane and on the dedicated `EVM2EVMOnRamp` for a 1.5 lane (Berachain); the scripts read the live fee contracts and refuse to proceed until the entries exist. On 2.0.0 lanes the budget is billed and summed into the message's execution gas limit but not enforced per token on-chain, so it still decides what the executor pays for and supplies; the request is the same on every generation. The four lanes from Solana toward a burn/mint chain need the same entry on the Solana side: an enabled OHM entry with `destGasOverhead >= 175000` on the Solana `FeeQuoter` program for each burn/mint destination, requested from Chainlink together with the EVM ones and checked by the Solana tooling, since the EVM scripts cannot read it. The four lanes from a burn/mint chain toward Solana need no request: the delivery on Solana is billed under the fee quoter's default budget for the SVM destination (150000 on every EVM chain, read 2026-09-04), which is what the live mainnet to Solana route runs under without an OHM entry, so `setup` and `checkReadiness` print a note for these lanes instead of a check (the figure lives here, not in the scripts, since it is a live value; re-read it with the lane generations). The mainnet readiness report prints the same note for its Solana route, with the reverse lane needing no raise since the lock/release pool releases with a plain transfer.
1. **Registry handover (per chain).** The OHM administrator in each local `TokenAdminRegistry` is the deployer EOA `0x1A5309F2...`. From that EOA: `CCIPTokenPoolBatch.transferTokenPoolAdminRoleToDaoMS`; from the DAO MS: `CCIPTokenPoolBatch.acceptAdminRole`. These entry points do not use the standard five-argument batch signature, so they run through `forge script` directly rather than `safeBatchV2.sh`:

    ```bash
    FOUNDRY_PROFILE=multisig forge script src/scripts/ops/batches/CCIPTokenPoolBatch.sol:CCIPTokenPoolBatch \
        --sig "transferTokenPoolAdminRoleToDaoMS()" --rpc-url <CHAIN> --account < cast account > --sender <deployer EOA> --slow --broadcast
    FOUNDRY_PROFILE=multisig forge script src/scripts/ops/batches/CCIPTokenPoolBatch.sol:CCIPTokenPoolBatch \
        --sig "acceptAdminRole(bool)" true --rpc-url <CHAIN> --account < cast account > --sender <signer> --slow --broadcast
    ```

    Confirm custody of the EOA key before starting; after the acceptance the key is no longer needed for CCIP.

2. **Deploy (per chain).** `ccip_full_not_mainnet.json` as above (pool, periphery, config policy, timelock in one sequence). Hand the four `CCIPBurnMintTokenPool` addresses to the Solana repository as soon as they are recorded in `env.json`: each Solana per-chain config names the burn/mint chain's pool as the accepted remote pool and its OHM (`current.<chain>.olympus.legacy.OHM`) as the remote token, and the Solana readiness report cannot be produced without them.
3. **Ownership handover (per chain, from the deployer).** `CCIPTokenPoolBatch.transferTokenPoolOwnershipToConfig` proposes the config policy as the pool owner (accepted later by the setup batch), and `CCIPBridgeBatch.transferOwnership` moves the periphery to the DAO MS:

    ```bash
    FOUNDRY_PROFILE=multisig forge script src/scripts/ops/batches/CCIPTokenPoolBatch.sol:CCIPTokenPoolBatch \
        --sig "transferTokenPoolOwnershipToConfig()" --rpc-url <CHAIN> --account < cast account > --sender <deployer> --slow --broadcast
    ./shell/safeBatchV2.sh --contract CCIPBridgeBatch --function transferOwnership --account < cast account > --chain <CHAIN> --broadcast true
    ```

4. **Funding (mainnet, DAO MS).** Re-read `shell/calc_bridged_supply.sh`, update `olympus.config.CCIP.minimumPoolBacking`, then `CCIPTokenPoolBatch.fundPool` transfers the shortfall from the DAO MS to the pool. This backs the OHM already minted on the L2s by the legacy LayerZero bridge (about 130,721 OHM; Optimism is zero).
5. **Readiness gate and submission.** `./shell/ccip/check_rollout_readiness.sh` must be green for mainnet and all four chains (deployment bindings, ownership, registry, roles, backing, and every EVM lane budget), and the Solana repository's readiness report must be green for the four lanes from Solana toward a burn/mint chain (the OHM fee entries on the Solana fee quoter and the per-chain configs it will apply); then submit proposal id 19. Both halves gate the submission because the EVM side of every burn/mint chain to Solana pair opens at finalize: with the Solana side unconfigured, a send from a burn/mint chain toward Solana would burn at the source and park on Solana until the per-chain config exists.
6. **Setup (per chain, DAO MS, during the voting window).**

    ```bash
    ./shell/safeBatchV2.sh --contract CCIPNonEthereumSetupBatch --function setup --multisig true --account < cast account > --chain <CHAIN> --broadcast false
    ```

    Deactivates the legacy LayerZero `CrossChainBridge` in the Kernel (asserting `bridgeActive` false and zero mint approval first), activates the three policies, grants `admin` (chain wide!) and any missing `bridge_admin`/`emergency`, enables the config policy and the timelock, accepts the pool ownership, sets the config operator, clears the native rate limit admin when it is set, and adds the routes from `env.json` directly under `admin`: the EVM routes and the Solana route, whose remote token and remote pool are packed from the base58 keys under `current.solana`. The Solana lane is the one outgoing lane the fee budget gate does not cover (see step 0); the batch prints a note for it. It does **not** enable the pool and does not register it, so the chain stays inert: no outbound send and no inbound delivery can touch the pool yet.

7. **Vote, queue, execute the proposal.** If the vote fails, the L2s simply stay dormant; nothing needs to be rolled back.
8. **Solana per-chain configs (Solana repository, Squads, after the proposal executes and before finalize).** On the Solana pool, one config per burn/mint chain (Arbitrum, Optimism, Base, Berachain): the remote token (that chain's OHM), the accepted remote pool (its `CCIPBurnMintTokenPool` from step 2) and both rate limits at the Solana values of `env.json` (10,000 OHM per day outbound and 11,000 OHM per day inbound on the Solana side, the same pair of figures the burn/mint chain declares on its side). Prepare the Squads proposal during the voting window and execute it only once the OCG proposal has executed: a config applied earlier would let a send from Solana burn there and park on the still unregistered burn/mint chain for the whole voting window, and would need a rollback on a failed vote. Executed after the proposal and before finalize, the exposure is the tail of step 11, and its length is the gap between the Squads execution and each chain's finalize batch: three multisigs act in sequence here (the OCG execution, Squads, the four DAO MS finalize batches), so the window is as long as that sequencing takes, not minutes by itself; have the Squads proposal fully approved before the OCG execution and run the finalize batches right after it. A send from a burn/mint chain toward Solana cannot strand before finalize: its pool is not registered yet, so the send reverts at the source.
9. **Finalize (per chain, DAO MS, immediately after execution).**

    ```bash
    ./shell/safeBatchV2.sh --contract CCIPNonEthereumSetupBatch --function finalize --multisig true --account < cast account > --chain <CHAIN> --broadcast false
    ```

    `pool.enable` and `TokenAdminRegistry.setPool(OHM, pool)`, in that order, which opens the chain in both directions toward mainnet, the other burn/mint chains and Solana. The order between the chains does not matter.

10. **Periphery (mainnet and per chain, DAO MS).** `CCIPBridgeBatch.reconcileTrustedRemotes` converges the trusted remotes and gas limits to the `periphery` blocks: on a burn/mint chain the EVM remotes with their 275000 gas limit and the SVM trusted remote with the zero receiver and a zero gas limit, the token-only configuration that the mainnet periphery already carries. `CCIPBridgeBatch.enable` then switches the peripheries of the burn/mint chains on.
11. **Stranded-message tails.** Between the proposal execution and a chain's finalize, a send toward that chain (from mainnet, from an already finalized chain, or from Solana once its per-chain config of step 8 is in place) burns or locks at the source and parks in `FAILURE` on the destination (`NotACompatiblePool`). That window is minutes long when the batches run back to back (for the Solana direction it is the gap between the Squads execution of step 8 and the chain's finalize), and the messages are recovered permissionlessly once the destination is finalized: `OffRamp.manuallyExecute` with the execution report on a 1.5 or 1.6 lane (and a raised token gas override if the delivery ran out of budget), or a re-submission of `OffRamp.execute` with the same encoded message and CCV attestations on a 2.0.0 lane, where a `FAILURE` message can be re-executed at once and the pool call is bounded only by the transaction gas; the CCIP Explorer's manual execution covers both. The raised fee budget from step 0 already covers the delivery. The same recovery applies to any message that trips a contained inbound bucket later.

After a chain has finalized, it is operated with the shared tooling under `--chain <CHAIN>`: route and rate-limit changes are queued by the local DAO MS on the local config timelock (`CCIPRouteReconcileBatch`), containment and the control-plane freeze (`disableChain`, `disableAllChains`, `disablePolicies`) are available to the local DAO MS, which holds `bridge_admin` and `admin`, and to the Emergency MS through the `EmergencyMS` variants, and the periphery is reconciled with `CCIPBridgeBatch`. Recovery differs from mainnet in one respect: the pool policy has no `reEnable`, so a disabled pool is restored by the local `admin` through `enable` rather than within a grace window.

The deliberate ordering deviation: the chains are opened source-first (mainnet routes exist for the whole voting period while the L2 pools are unregistered), not destination-first. Registering and enabling an L2 pool before the vote would let users burn L2 OHM toward mainnet into `FAILURE` for the entire voting period, and would need a rollback if the vote failed; the reverse window (mainnet to L2 after execution, before finalize) is minutes and is recovered by manual execution. The Solana side of each burn/mint chain's pair follows the same rule: its per-chain config is applied after the proposal executes (step 8), never during the vote, so that a send from Solana cannot strand on an unregistered pool for the voting window.

## Configuration after the handover

The batches below run against any chain that carries the triad: `--chain mainnet` after the OCG proposal, `--chain <CHAIN>` on a burn/mint chain once its rollout has finalized. The authority differs only in who holds `admin`: the OCG timelock on mainnet, the local DAO MS elsewhere.

### Routes and rate limits (DAO MS, through the timelock)

```bash
./shell/safeBatchV2.sh --contract CCIPRouteReconcileBatch --function reconcileRoutes --multisig true --account < cast account > --chain mainnet --broadcast false
```

The reconciler compares every route of `olympus.config.CCIP.routes` with the pool field by field (existence, remote token, the set of accepted remote pools, both rate limits) and queues the minimal set of typed actions: `queueAddChain` for a missing route, `queueSetRemoteToken`, `queueAddRemotePool` / `queueRemoveRemotePool`, `queueSetChainRateLimits`, and `queueRemoveChain` only for a route declared with `enabled: false`. It prints the live state, the desired state and the plan. Before queueing it reads `pendingActionId` for every domain it touches: an action that already carries the same change is left alone, an action that holds the domain with another intent or has expired is cancelled and replaced. Each change is its own action, so a queued action that turned stale does not block the execution of the others; the reconcile run itself fails closed as a whole on the first invalid desired route. The timelock admits one unresolved action per domain, so a route that needs several remote-pool changes, or a remote token change together with other changes, converges over several runs; the reconciler says what it deferred.

Once the delay has elapsed, anyone can execute:

```bash
./shell/safeBatchV2.sh --contract CCIPRouteReconcileBatch --function executeReadyActions --account < cast account > --chain mainnet --broadcast false
```

This runs from the cast account (the EOA path, no multisig); flip `--broadcast` to `true` to send. Readiness and expiry are evaluated when the script runs, so run it once the delay has elapsed rather than ahead of time. It dry-runs every ready action and reports the ones that would revert (stale after a direct `admin` change or a containment, disabled policy, lost pool ownership) instead of including them. A stale or expired action keeps its keys until it is cancelled:

```bash
./shell/safeBatchV2.sh --contract CCIPRouteReconcileBatch --function cancelQueuedAction --multisig true --account < cast account > --chain mainnet --broadcast false --args src/scripts/ops/batches/args/CCIPRouteReconcileBatch_cancelQueuedAction.json
```

(`cancelQueuedActionEmergency` is the same with the Emergency MS as owner.) Running `reconcileRoutes` again after a cancellation re-queues whatever is still missing.

### Direct admin changes

The `admin` role (OCG) can call the route functions of the config policy directly in a proposal. Doing so invalidates the state hash of any queued action on the same domain, which then reverts with `ConfigStateChanged` and keeps its keys: cancel it and run the reconciler again. The same applies after a containment.

### Periphery (DAO MS)

`src/scripts/ops/batches/CCIPBridgeBatch.sol` is a declarative reconciler:

```bash
./shell/safeBatchV2.sh --contract CCIPBridgeBatch --function reconcileTrustedRemotes --multisig true --account < cast account > --chain <CHAIN> --broadcast false
```

It compares the trusted remote and the gas limit of every declared `periphery` block independently (a matching remote does not mask a stale gas limit), adds only the differing fields, unsets a remote only for a route or `periphery` block declared with `enabled: false`, fails closed on a live trusted remote whose route has no `periphery` block, and proposes nothing on a converged state. `enable`, `disable` and `transferOwnership` (to the DAO MS) are the remaining entry points, each conditional and gated on the periphery owner. Disabling the periphery does not stop pool transfers.

### Adding a new chain

Declare the route under `olympus.config.CCIP.routes.<remoteChain>` with both limits (and a `periphery` block if the periphery should trust the chain), make sure the remote chain's OHM and pool addresses are in `env.json`, and run `reconcileRoutes` and `reconcileTrustedRemotes`; configure the destination side before the source side, and check the lane's OHM fee budget first when the destination is a burn/mint chain (`checkReadiness` reads it). The deployment of the remote chain's own pool, config policy and timelock is the non-Ethereum rollout above; the Solana-side changes are applied from the Solana repository. The Solana pool is an Anchor program whose state Foundry cannot read or write; its configuration is applied there (through the Squads multisig) and checked against the same `env.json` entries.

## Emergency

Disabling the config policy, the timelock or the periphery does not stop transfers: the pool keeps processing messages until a route is contained. Use the right lever:

- Contain one route (writes `{isEnabled: true, capacity: 2, rate: 1}` to both buckets, so every real transfer fails immediately; not gated on the config policy being enabled). The `emergency`, `admin`, `bridge_admin` and `bridge_rate_limiter` roles can all call it, so either multisig acts on its own. Emergency MS:

    ```bash
    ./shell/safeBatchV2.sh --contract CCIPTokenPoolConfigBatch --function disableChainEmergencyMS --multisig true --account < cast account > --chain <CHAIN> --broadcast false --args src/scripts/ops/batches/args/CCIPTokenPoolConfigBatch_disableChain.json
    ```

    DAO MS as `bridge_admin`: the same batch without the `EmergencyMS` suffix (`--function disableChain`), which reads the args entry of that name. The `remoteChain` argument names the route to contain, so the args file is chain specific: the unsuffixed file names the Solana route (live on mainnet and, after the rollout, on every burn/mint chain), and `CCIPTokenPoolConfigBatch_disableChain_mainnet.json` names the mainnet route, which only a burn/mint chain has.

- Contain every route (same roles, no args file): `--function disableAllChains` from the DAO MS, `--function disableAllChainsEmergencyMS` from the Emergency MS.
- Containment stays one way whoever calls it: restoring the approved limits needs `setChainRateLimits`, which only the config timelock (after its delay), `admin` or a `bridge_rate_limiter` holder can reach. See Recovery below.
- Freeze the control plane: `--function disablePolicies` (DAO MS) or `--function disablePoliciesEmergencyMS` (Emergency MS) disables the timelock and the config policy, which stops queueing and execution but not transfers; containment stays available. Both owners need `emergency` or `admin`, the gate of `disable()`: the DAO MS variant serves the burn/mint chains, where the local DAO MS holds `admin`, while on mainnet the freeze is the Emergency MS variant or an OCG proposal.
- Stop the periphery (DAO MS): `./shell/safeBatchV2.sh --contract CCIPBridgeBatch --function disable --multisig true --account < cast account > --chain <CHAIN> --broadcast false` (messages received while disabled are marked failed and can be retried).
- Withdraw the pool liquidity (OCG proposal): `withdrawLiquidity` is gated on the rebalancer, which is the OCG timelock after the handover; the `CCIPTokenPoolBatch.sol` withdrawal entry points only work while the batch owner is the rebalancer.

On a fork, run the Emergency MS entry points with `--fork true --owner emergency`.

### Recovery

1. Re-enable the policies (DAO MS as `bridge_admin`, within the 3-day grace window that starts at the disable): `CCIPTokenPoolConfigBatch --function reEnable`. After the window, only the `admin` `enable` path (an OCG proposal on mainnet, the local DAO MS elsewhere) restores them. Re-enabling restores only the lifecycle flag. The re-enable path covers the config policy and the timelock only: the deployed `CCIPBurnMintTokenPool` has no `reEnable`, so a disabled pool policy is restored by the local `admin` through `enable` at any time.
2. Restore the approved limits declaratively: `reconcileRoutes` queues `setChainRateLimits` from `env.json` for every contained route; execute after the delay with `executeReadyActions`. Restoring the configuration does not refill the bucket: it resumes from 2 units and refills at the configured rate. Any action that was queued before the containment is stale and must be cancelled first. The exception is a queued restore itself: containing the route again writes the same contained values, so the restore's state hash still matches and it will execute after its delay and lift the new containment; when re-containing during a pending restore, cancel the restore as well (`cancelQueuedAction` from the DAO MS as its proposer, or `cancelQueuedActionEmergency`).
3. Messages that tripped a contained inbound bucket are in the `FAILURE` state on this chain and are never retried by Chainlink (the 1.6 DON acts only on `UNTOUCHED`, the 2.0.0 executor marks its job done on a `FAILURE`); they need a permissionless manual execution once the limits are restored: `manuallyExecute` on the 1.5 and 1.6 lanes, a re-submitted `execute` on the 2.0.0 lanes. On the 1.6 lanes the commit root never expires; on the 2.0.0 lanes the execution state is keyed by message id and the CCV attestations are what a re-submission needs.

Before re-enabling, cancel any queued action that should not survive the incident; an action whose window passed while the timelock was disabled has expired and must be cancelled and queued again.

## Rehearsal on an Anvil fork

`shell/ccip/anvil-deployment/run-ethereum.sh` runs the whole mainnet sequence on a fork: deployment, Phase B and its empty re-run, the pool funding, the negative fee-budget checks and the fee mock, the readiness report, the OCG proposal (with the four route actions) replayed from the timelock, the pool and periphery reconcilers on the converged state, a full queue / wait / execute cycle through the timelock, a containment by the DAO MS with an empty Emergency MS re-run, its declarative recovery, and the final authority state. `shell/ccip/anvil-deployment/run-l2.sh --chain <CHAIN>` rehearses one burn/mint chain end to end (registry handover, deploy, ownership handovers, fee mock with negative checks, setup, finalize, periphery, a containment of the mainnet route from the DAO MS with its declarative recovery through the local timelock, and the control-plane freeze from the DAO MS as the local `admin` with its grace-window `reEnable`); the Solana route is added by the setup batch without a fee mock, and its buckets, the SVM trusted remote and the gas limit are asserted after finalize and the periphery reconcile. The Solana side of the pair is not rehearsed here. See `shell/ccip/anvil-deployment/README.md`.

## Bridging

For EVM -> EVM, use `./shell/bridge_ccip_to_evm.sh`.

For EVM -> SVM, use `./shell/bridge_ccip_to_svm.sh`.

For SVM -> EVM, follow the [SVM tutorial](https://docs.chain.link/ccip/tutorials/svm/source).

## Bootstrap and legacy entry points

`src/scripts/ops/batches/CCIPTokenPoolBatch.sol` holds the entry points that act directly on the pool from its owner (`install`, `configureRemoteChainEVM`, `configureRemoteChainSVM`, `configureAllRemoteChains`, `setRateLimits`, `emergencyShutdown`, `emergencyShutdownAll`), on the registry from the OHM administrator (`acceptAdminRole`, `setPool`, `transferTokenPoolAdminRoleToDaoMS`), on the pool ownership (`transferTokenPoolOwnershipToDaoMS`, `acceptTokenPoolOwnership`) and on the liquidity from the rebalancer (`withdrawLiquidity`, `withdrawAllLiquidity`). They serve the bootstrap of a new chain before its config policy takes the pool over, and testnets. Each of them checks that the batch owner holds the authority it needs and reverts with the replacement path otherwise.
