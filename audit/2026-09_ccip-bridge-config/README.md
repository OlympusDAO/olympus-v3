# CCIP Bridge Configuration Audit

## Purpose

Review the new control plane for Olympus's Chainlink CCIP token pools and its rollout across
Ethereum, Arbitrum, Optimism, Base and Berachain.

The change moves each pool's owner authority into a typed `CCIPTokenPoolConfig` policy. Routine
route changes are queued through `CCIPTokenPoolConfigTimelock`, while governance retains direct
authority and the emergency, admin, bridge-admin and optional rate-limiter paths can immediately
contain one or all routes.

## Design

- `CCIPTokenPoolConfig` owns one local pool and exposes only supported pool-owner operations. It does
    not forward arbitrary calls.
- Root authority remains with `admin`; `bridge_admin` queues route changes through the timelock and
    may contain routes; `bridge_rate_limiter` may change rate limits directly and contain routes if
    assigned; and `emergency` may contain routes or disable the control-plane policies.
- `CCIPTokenPoolConfigTimelock` accepts typed route, remote-pool, allowlist and rate-limit changes. It
    validates them at queue time and permits execution after an initial one-day delay.
- `ConfigTimelockBatchQueue` reserves the configuration domains touched by an action and records
    their state hashes. Execution fails if the destination or guarded state changed after queueing.
    This shared abstraction and `ConfigOperatorSingleStep` originated in Burner Loans PR
    [#330](https://github.com/OlympusDAO/olympus-v3/pull/330) and were copied into this branch.
- Ethereum uses Chainlink's lock/release pool. The other production EVM chains use the existing
    Olympus burn/mint pool. The same config and timelock policies manage both pool types.
- Deployment, proposal and multisig scripts reconcile the on-chain state with `src/scripts/env.json`
    and perform the ownership, registry, role, route, funding and periphery handovers.

## Scope

Branch: `feat/ccip-config-timelock-n-evm-chains`

Code commit: `f654427b54f01af65987d08dbd7e151e856f0bb9`. See
[scopefile.txt](./scopefile.txt) for the machine-readable list.

This supersedes the original `765ead2a` audit pin. The later target renames the config pair and
their proposal/batch/interfaces from `CCIPBridgeConfig*` to `CCIPTokenPoolConfig*`, expands route
containment to `bridge_admin` and `bridge_rate_limiter`, deploys the timelock with Solidity `new`
under the `deploy` profile, tightens rollout preconditions, and adds unit, invariant and migration
scenario coverage.

### Core Contracts

- [CCIPTokenPoolConfig](../../src/policies/bridge/CCIPTokenPoolConfig.sol) and its
    [interface](../../src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol)
- [CCIPTokenPoolConfigTimelock](../../src/policies/bridge/CCIPTokenPoolConfigTimelock.sol) and its
    [interface](../../src/policies/interfaces/bridge/ICCIPTokenPoolConfigTimelock.sol)
- [ConfigOperatorSingleStep](../../src/policies/utils/ConfigOperatorSingleStep.sol) and its
    [interface](../../src/policies/interfaces/utils/IConfigOperator.sol)
- [ConfigTimelockBatchQueue](../../src/policies/utils/ConfigTimelockBatchQueue.sol) and its
    [interface](../../src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol)
- The execution-completion hook added to
    [TimelockBatchQueue](../../src/policies/utils/TimelockBatchQueue.sol)

The four new shared abstraction files are in scope because no completed external audit was found
for them. The CCIP copies match PR #330 except for Solidity pragma normalization. For
`TimelockBatchQueue`, only the post-audit `_onActionExecuted` hook and its invocation are in scope.

### Partial-File Scope

The Solidity metrics extension accepts file paths, not line ranges. It will therefore count each
file below in full. Audit scope is limited to these ranges at commit
[`f654427b`](https://github.com/OlympusDAO/olympus-v3/commit/f654427b54f01af65987d08dbd7e151e856f0bb9):

| File                     | In-scope code                                                                                                                                                       | Baseline                                                                                                                   |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `TimelockBatchQueue.sol` | Interaction in `executeQueuedAction`, lines 134-154; `_onActionExecuted`, lines 389-397. The new call is line 149 and the new hook is line 397.                                 | Audited version at [`0b7e6138`](https://github.com/OlympusDAO/olympus-v3/commit/0b7e61388c7da4fc443f814228ea234a185e76cc)  |
| `DeployV3.s.sol`         | `_readDeploymentArgUint256OrEnv`, lines 384-404; `deployCCIPTokenPoolConfig`, lines 526-558; `deployCCIPTokenPoolConfigTimelock`, lines 560-605; supporting imports           | `origin/develop` at [`ad2a6a04`](https://github.com/OlympusDAO/olympus-v3/commit/ad2a6a04263da4e8644a96708dbfa4474b59afbf) |
| `BatchScriptV2.sol`      | `setUpWithEmergencyMS`, lines 133-147                                                                                                                                         | `origin/develop` at [`ad2a6a04`](https://github.com/OlympusDAO/olympus-v3/commit/ad2a6a04263da4e8644a96708dbfa4474b59afbf) |
| `CCIPBridge.sol`         | All changes in the audit-commit diff: declarative trusted-remote and gas-limit reconciliation, lifecycle and ownership entry points                                 | `origin/develop` at [`ad2a6a04`](https://github.com/OlympusDAO/olympus-v3/commit/ad2a6a04263da4e8644a96708dbfa4474b59afbf) |
| `CCIPTokenPool.sol`      | All changes in the audit-commit diff: bootstrap authority checks, registry and ownership handover, liquidity and direct pool-owner entry points                     | `origin/develop` at [`ad2a6a04`](https://github.com/OlympusDAO/olympus-v3/commit/ad2a6a04263da4e8644a96708dbfa4474b59afbf) |

Line numbers are informational and pinned to the audit commit. The named functions and commit diff
define the scope if later edits move the lines.

### Chainlink Pool Interfaces

The local interfaces under [src/external/bridge](../../src/external/bridge) define the exact
Chainlink pool, registry, rate-limiter and liquidity calls used by the config policy and rollout
scripts. Their selectors, struct layouts and compatibility with the deployed Chainlink contracts
are in scope.

### Deployment and Configuration

- [CCIPTokenPoolConfigProposal](../../src/proposals/CCIPTokenPoolConfigProposal.sol)
- [DeployV3](../../src/scripts/deploy/DeployV3.s.sol)
- [CCIPTokenPoolConfigBatch](../../src/scripts/ops/batches/CCIPTokenPoolConfigBatch.sol)
- [CCIPNonEthereumSetupBatch](../../src/scripts/ops/batches/CCIPNonEthereumSetupBatch.sol)
- [CCIPRouteReconcileBatch](../../src/scripts/ops/batches/CCIPRouteReconcileBatch.sol)
- The modified [CCIPBridge](../../src/scripts/ops/batches/CCIPBridge.sol) and
    [CCIPTokenPool](../../src/scripts/ops/batches/CCIPTokenPool.sol) batch scripts
- [CCIPConfigLib](../../src/scripts/ops/lib/CCIPConfigLib.sol),
    [CCIPFeeBudgetLib](../../src/scripts/ops/lib/CCIPFeeBudgetLib.sol) and the Emergency Multisig
    setup added to [BatchScriptV2](../../src/scripts/ops/lib/BatchScriptV2.sol)

### Out of Scope

- Chainlink CCIP contracts and infrastructure, including the router, on/off-ramps,
    `TokenAdminRegistry` and `LockReleaseTokenPool`, except for compatibility with the local
    interfaces and assumptions made by the in-scope code.
- The unchanged transfer-plane implementations `CCIPBurnMintTokenPool` and
    `CCIPCrossChainBridge`; both were reviewed in the 2025 CCIP audit.
- [RoleDefinitions](../../src/policies/utils/RoleDefinitions.sol). CCIP reuses the existing
    `bridge_admin` and `bridge_rate_limiter` constants and changes only their explanatory comments.
- [DeployV2](../../src/scripts/deploy/DeployV2.sol). Its executable code is unchanged; only the
    general deploy-profile guidance in comments was updated.
- Shell scripts, tests, deployment JSON, `env.json` values and Anvil rehearsal tooling. They are
    supporting evidence for the intended rollout, not production contracts.
- Solana program changes. This branch only configures the EVM side of the existing Solana lane.

## Previous Audits

- **CCIP Bridge (05/2025)** — [audit package](../2025-05_ccip/README.md). Covers
    `CCIPBurnMintTokenPool`, `CCIPCrossChainBridge` and their supporting base contracts.
- **Olympus Bridge (06/2026)** —
    [report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2026-06-Bridge.pdf)
    and [audit package](../2026-03_lz-bridge-upgrade/README.md). Covers `TimelockBatchQueue`,
    `ITimelockBatchQueue`, `PolicyAdminOptimized` and the LayerZero V2 bridge architecture. Only the
    new `TimelockBatchQueue` execution hook is part of this audit's scope.

## Architecture

```mermaid
flowchart LR
  OCG([OCG timelock / local admin]) -->|root and direct config| CFG[CCIPTokenPoolConfig]
  DAO([DAO Multisig]) -->|queue / re-enable| TL[CCIPTokenPoolConfigTimelock]
  TL -->|delayed typed config| CFG
  DAO -->|contain routes| CFG
  RATE([bridge_rate_limiter]) -->|rate limits / contain, if assigned| CFG
  EM([Emergency Multisig]) -->|contain routes| CFG
  EM -->|disable / cancel| TL
  CFG -->|owner calls| POOL{{Local CCIP token pool}}
  REG{{TokenAdminRegistry}} -.->|selects pool for OHM| POOL
  ROUTER{{CCIP router}} -->|on/off-ramp calls| POOL
```

On Ethereum, `admin` and the pool rebalancer are the OCG timelock. On the non-canonical EVM
chains, the local DAO Multisig holds `admin`, `bridge_admin` and the Kernel executor authority. The
Emergency Multisig is the same address on every production chain. The native pool
`rateLimitAdmin` and the `bridge_rate_limiter` role are unassigned at launch.

## Key Flows

### Delayed Route Change

1. `bridge_admin` queues a typed action while both policies are enabled and the timelock is the
   config operator.
2. The config policy's `validate*` mirror checks the request. The timelock reserves the affected
   route domains and stores their current state hashes.
3. After the delay, anyone may execute before the three-day execution window closes.
4. Execution rechecks the destination, operator relationship and guarded state, then dispatches to
   the config policy. All keys are released only after the whole action succeeds or is cancelled.

Each route has separate rate-limit, remote-pool and route-identity domains; the allowlist is one
pool-wide domain. One unresolved action may own a domain at a time.

### Emergency Containment and Recovery

`emergency`, `admin`, `bridge_admin` or `bridge_rate_limiter` can set both buckets of one or every
route to an enabled capacity of two and a refill rate of one, even while the config policy is
disabled. This blocks transfers of any real OHM amount. Only the timelock, `admin` or
`bridge_rate_limiter` can restore or expand capacity; `emergency` and `bridge_admin` cannot.

Recovery re-enables the control-plane policies, cancels stale or unwanted actions, and queues the
approved limits through the normal timelock. Restoring a limiter does not refill its bucket: it
starts from the contained balance and refills at the restored rate. Messages that failed an inbound
limiter require permissionless manual execution after recovery.

### Initial Rollout

The rollout transfers the OHM registry administrator and pool ownership away from deployer EOAs,
deploys and activates the config policies on five chains, establishes roles and operators, opens
the EVM routes, funds the Ethereum lock/release pool, registers and enables the non-Ethereum pools,
and reconciles the optional periphery.

The mainnet OCG proposal is capped at twelve conditional actions and fails closed unless its
deployment bindings, Solana route, exact set of four missing EVM routes, lock/release backing and
per-lane delivery budgets match the desired state. On each burn/mint chain, setup runs during the
voting window but leaves the pool disabled and unregistered. Finalization enables the pool and then
registers it immediately after the mainnet proposal executes. This ordering keeps a failed vote
recoverable, at the cost of a short post-execution window in which messages to a not-yet-finalized
destination require permissionless manual execution.

### Deployment Profile

`CCIPTokenPoolConfig` and `CCIPTokenPoolConfigTimelock` must be deployed under the Foundry `deploy`
profile, which enables the optimizer at 400 runs. `shell/deployV3.sh` sets that profile. Both runtime
artifacts exceed the EIP-170 code-size limit without optimization, so a bare deployment invocation
must set `FOUNDRY_PROFILE=deploy`. The timelock is now created with Solidity `new`; its constructor
still validates the config policy's Kernel and required interfaces.

## Verification Evidence

The target branch adds focused unit suites for every external function of the config policy and
timelock, stateful invariants for lifecycle, authorization, route state, accounting/custody and
queue-domain behavior, and scenario tests for:

- first-time Ethereum and non-Ethereum bootstrap;
- replacing a config pair while retaining the pool;
- replacing a pool and config pair together; and
- forked Ethereum and non-Ethereum migration over live deployments.

The tests and Anvil rehearsal scripts are supporting evidence and remain outside the production
audit scope. Reviewers should nevertheless use them to confirm the intended authorization and
migration properties.

## Access Control

The complete, source-verified authority matrix is maintained in
[CCIP Access Control Matrix](../../documentation/bridge/ccip/ACCESS_CONTROL.md). It covers the
intended post-rollout holders, framework roles, policy lifecycle, token-pool authority, Chainlink
registry authority and every state-changing entry point.

## Known Risks and Assumptions

- **Governance bypasses the delay.** `admin` can call every route function directly. This is
    intentional for OCG authority on Ethereum and local administration on the other EVM chains.
- **The optional rate-limiter role bypasses the delay.** If assigned, `bridge_rate_limiter` can
    change limits directly and contain routes. The native pool `rateLimitAdmin` must remain zero to
    avoid another bypass.
- **The DAO Multisig can contain routes directly.** Its `bridge_admin` role can call
    `disableChain` and `disableAllChains` without the timelock, but cannot restore capacity without a
    delayed action or additional authority.
- **Expired and stale actions retain their domains.** They must be cancelled before a replacement
    can be queued. Actions also survive policy disable/re-enable unless cancelled.
- **Containment does not cancel a queued restore.** If a restore action was already queued when a
    route is contained again, its state hash may remain valid and later lift containment. Incident
    response must cancel such actions.
- **Policy shutdown is not transfer shutdown.** Disabling the config policy, timelock or periphery
    does not stop direct CCIP sends; only pool rate-limit containment does.
- **Pool ownership and operator rotation invalidate queued execution.** An action remains reserved
    until cancellation if the config loses pool ownership or the timelock ceases to be its operator.
- **Chainlink state layout is trusted.** State-hash guards depend on the local interfaces matching
    the deployed CCIP 1.6 pool getters, structs and semantics on every chain.
- **Non-Ethereum** `admin` **is chain-wide.** Granting it to a local DAO Multisig applies to every policy
    attached to that Kernel, not only the CCIP policies.
- **The burn/mint pool uses the legacy lifecycle.** After it is disabled on a non-canonical chain,
    only local `admin` can enable it; the config and timelock grace-window recovery does not apply.
- **Rollout has a short destination gap.** After Ethereum opens a route and before a destination
    pool is finalized, messages may enter CCIP failure state and require manual execution.
- **Ethereum solvency depends on pool backing.** The lock/release pool bounds releases by its OHM
    balance. The rollout scripts assume the configured backing target covers supply previously minted
    on the non-canonical chains.
- **Burn/mint delivery needs a raised Chainlink fee budget.** Each lane into a burn/mint pool needs
    an enabled OHM fee entry with `destGasOverhead >= 175000`; the rollout scripts refuse to proceed
    without it.
