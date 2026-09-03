# CCIP Access Control Matrix

This document describes the intended state after the complete rollout.

## Holders

| Authority | Ethereum | Non-Ethereum EVM chains |
| --- | --- | --- |
| Kernel executor | DAO MS | Local DAO MS  |
| `RolesAdmin.admin` | OCG timelock | Local DAO MS |
| `admin` role | OCG timelock | Local DAO MS |
| `bridge_admin` role | DAO MS | Local DAO MS |
| `emergency` role | Emergency MS | Emergency MS |
| `bridge_rate_limiter` role | Unassigned | Unassigned |
| OHM administrator in `TokenAdminRegistry` | OCG timelock | Local DAO MS |
| Token pool owner | `CCIPTokenPoolConfig` | Local `CCIPTokenPoolConfig` |
| Config operator | `CCIPTokenPoolConfigTimelock` | Local `CCIPTokenPoolConfigTimelock` |
| Native pool `rateLimitAdmin` | Zero address | Zero address |
| Lock/release pool rebalancer | OCG timelock | Not applicable; burn/mint pool |
| `CCIPCrossChainBridge` owner | DAO MS | Local DAO MS |

| Holder | Address |
| ---| --- |
| OCG timelock | `0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39` |
| Ethereum DAO MS | `0x245cc372C84B3645Bf0Ffe6538620B04a217988B` |
| Arbitrum DAO MS | `0x012BBf0481b97170577745D2167ee14f63E2aD4C` |
| Optimism DAO MS | `0x559a14a2219Ae81f9a9f857CF31407de2b07F36c` |
| Base DAO MS | `0x18a390bD45bCc92652b9A91AD51Aed7f1c1358f5` |
| Berachain DAO MS | `0x91494D1BC2286343D51c55E46AE80C9356D099b5` |
| Emergency MS | `0xa8A6ff2606b24F61AFA986381D8991DFcCCd2D55` |
| Zero address | `0x0000000000000000000000000000000000000000` |

The non-Ethereum EVM chains are Arbitrum, Optimism, Base and Berachain. Each carries its own `CCIPTokenPoolConfig`, `CCIPTokenPoolConfigTimelock`, `CCIPBurnMintTokenPool` and `CCIPCrossChainBridge`, and its own DAO MS.

## Timelock parameters

| Parameter | Value |
| --- | --- |
| Initial delay | 1 day |
| Delay bounds | 1 to 30 days |
| Execution window | 3 days |
| Max sub-actions per batch | 15 |
| Max configuration keys per batch | 24 |
| Grace period | 3 days |

## Contracts

### `CCIPTokenPoolConfig` policy

Owns the local CCIP token pool.

| Function | Access | Holder |
| --- | --- | --- |
| `acceptPoolOwnership` | `admin` | OCG timelock |
| `transferPoolOwnership` | `admin` | OCG timelock |
| `setConfigOperator` | `admin` | OCG timelock |
| `setRouter` | `admin` | OCG timelock |
| `setRateLimitAdmin` | `admin` | OCG timelock |
| `setGracePeriod` | `admin` | OCG timelock |
| `enable` | `admin` | OCG timelock |
| `addChain` | config operator or `admin` | `CCIPTokenPoolConfigTimelock`; OCG timelock |
| `removeChain` | config operator or `admin` | `CCIPTokenPoolConfigTimelock`; OCG timelock |
| `setRemoteToken` | config operator or `admin` | `CCIPTokenPoolConfigTimelock`; OCG timelock |
| `addRemotePool` | config operator or `admin` | `CCIPTokenPoolConfigTimelock`; OCG timelock |
| `removeRemotePool` | config operator or `admin` | `CCIPTokenPoolConfigTimelock`; OCG timelock |
| `applyAllowListUpdates` | config operator or `admin` | `CCIPTokenPoolConfigTimelock`; OCG timelock |
| `setChainRateLimits` | `bridge_rate_limiter`, config operator, or `admin` | unassigned; timelock; OCG timelock |
| `disable` | `emergency` or `admin` | Emergency MS; OCG timelock |
| `disableChain` | `emergency`, `admin`, `bridge_admin`, or `bridge_rate_limiter`; works while disabled | Emergency MS; OCG timelock; DAO MS; unassigned |
| `disableAllChains` | `emergency`, `admin`, `bridge_admin`, or `bridge_rate_limiter`; works while disabled | Emergency MS; OCG timelock; DAO MS; unassigned |
| `reEnable` | `bridge_admin`; within the grace period | DAO MS |
| `changeKernel` | Kernel | Kernel |
| `configureDependencies` | unrestricted, invoked by Kernel | - |

All functions require the policy to be enabled, except `enable` and `reEnable` (require disabled), the two containment functions, and the Kernel-invoked ones.

The two functions below are present on every deployment of the config policy, but revert unless the owned pool supports `ILiquidityContainer`, which only `LockReleaseTokenPool` does.

| Function | Access | Holder |
| --- | --- | --- |
| `setRebalancer` | `admin` | OCG timelock |
| `transferLiquidity` | `admin` | OCG timelock |

### `CCIPTokenPoolConfigTimelock` policy

| Function | Access | Holder |
| --- | --- | --- |
| `enable` | `admin` | OCG timelock |
| `setGracePeriod` | `admin` | OCG timelock |
| `setTimelockDelay` | `admin` | OCG timelock |
| `queueAddChain` | `bridge_admin` | DAO MS |
| `queueRemoveChain` | `bridge_admin` | DAO MS |
| `queueSetRemoteToken` | `bridge_admin` | DAO MS |
| `queueAddRemotePool` | `bridge_admin` | DAO MS |
| `queueRemoveRemotePool` | `bridge_admin` | DAO MS |
| `queueApplyAllowListUpdates` | `bridge_admin` | DAO MS |
| `queueSetChainRateLimits` | `bridge_admin` | DAO MS |
| `queueBatch` | `bridge_admin` | DAO MS |
| `executeQueuedAction` | permissionless after the delay | any address |
| `cancelQueuedAction` | `admin`, `emergency`, or the original proposer; works while disabled and after expiry | OCG timelock; Emergency MS; DAO MS |
| `disable` | `emergency` or `admin` | Emergency MS; OCG timelock |
| `reEnable` | `bridge_admin`; within the grace period | DAO MS |
| `changeKernel` | Kernel  | Kernel |
| `configureDependencies` | unrestricted, invoked by Kernel | - |

All functions require the timelock to be enabled, except `enable` and `reEnable` (require disabled), `cancelQueuedAction`, and the Kernel-invoked ones. Queueing and execution both additionally require the config policy to be enabled and to still name this timelock as its config operator.

The `admin` role is not a queue proposer: every queued action targets a function it can call directly on the config policy.

### `CCIPBurnMintTokenPool` policy (non-Ethereum chains)

Deployed with an empty allowlist, so `applyAllowListUpdates` reverts with `AllowListNotEnabled`. The pool keeps the legacy enabler, so it has no `reEnable` and no grace period: once disabled, only the local `admin` restores it through `enable`.

| Function | Access | Holder |
| --- | --- | --- |
| `acceptOwnership` | pending owner | local `CCIPTokenPoolConfig` |
| `transferOwnership` | owner | local `CCIPTokenPoolConfig` |
| `applyChainUpdates` | owner | local `CCIPTokenPoolConfig` |
| `addRemotePool` | owner | local `CCIPTokenPoolConfig` |
| `removeRemotePool` | owner | local `CCIPTokenPoolConfig` |
| `applyAllowListUpdates` | owner | local `CCIPTokenPoolConfig` |
| `setRouter` | owner | local `CCIPTokenPoolConfig` |
| `setRateLimitAdmin` | owner | local `CCIPTokenPoolConfig` |
| `setChainRateLimiterConfig` | owner or `rateLimitAdmin` | local `CCIPTokenPoolConfig`; zero |
| `setChainRateLimiterConfigs` | owner or `rateLimitAdmin` | local `CCIPTokenPoolConfig`; zero |
| `enable` | local `admin` | local DAO MS |
| `disable` | `emergency` or local `admin` | Emergency MS; local DAO MS |
| `lockOrBurn` | on-ramp of the configured router | Chainlink |
| `releaseOrMint` | off-ramp of the configured router | Chainlink |
| `changeKernel` | Kernel  | Kernel |
| `configureDependencies` | unrestricted, invoked by Kernel | - |

### `LockReleaseTokenPool` (deployed on Ethereum)

Its owner changes from the DAO MS to `CCIPTokenPoolConfig`. Deployed with an empty allowlist, so `applyAllowListUpdates` reverts with `AllowListNotEnabled`.

| Function | Access | Holder |
| --- | --- | --- |
| `acceptOwnership` | pending owner | `CCIPTokenPoolConfig` |
| `transferOwnership` | owner | `CCIPTokenPoolConfig` |
| `applyChainUpdates` | owner | `CCIPTokenPoolConfig` |
| `addRemotePool` | owner | `CCIPTokenPoolConfig` |
| `removeRemotePool` | owner | `CCIPTokenPoolConfig` |
| `applyAllowListUpdates` | owner | `CCIPTokenPoolConfig` |
| `setRouter` | owner | `CCIPTokenPoolConfig` |
| `setRateLimitAdmin` | owner | `CCIPTokenPoolConfig` |
| `setRebalancer` | owner | `CCIPTokenPoolConfig` |
| `transferLiquidity` | owner | `CCIPTokenPoolConfig` |
| `setChainRateLimiterConfig` | owner or `rateLimitAdmin` | `CCIPTokenPoolConfig`; zero |
| `setChainRateLimiterConfigs` | owner or `rateLimitAdmin` | `CCIPTokenPoolConfig`; zero |
| `provideLiquidity` | rebalancer | OCG timelock |
| `withdrawLiquidity` | rebalancer | OCG timelock |
| `lockOrBurn` | on-ramp of the configured router | Chainlink |
| `releaseOrMint` | off-ramp of the configured router | Chainlink |

Depositing does not require the rebalancer role: a direct ERC20 transfer has the same effect as `provideLiquidity` minus the `LiquidityAdded` event.

### `CCIPCrossChainBridge` periphery

Disabling it does not stop CCIP transfers of OHM: the pool only checks that the caller is an on-ramp of the configured router, so any address can call `Router.ccipSend` directly.

| Function | Access | Holder |
| --- | --- | --- |
| `transferOwnership` | owner | DAO MS |
| `setTrustedRemoteEVM` | owner | DAO MS |
| `unsetTrustedRemoteEVM` | owner | DAO MS |
| `setTrustedRemoteSVM` | owner | DAO MS |
| `unsetTrustedRemoteSVM` | owner | DAO MS |
| `setGasLimit` | owner | DAO MS |
| `enable` | owner | DAO MS |
| `disable` | owner | DAO MS |
| `withdraw` | owner; native balance only, not OHM | DAO MS |
| `ccipReceive` | configured router | Chainlink |
| `receiveMessage` | this contract | self |
| `sendToEVM` payable | unrestricted | any user |
| `sendToSVM` payable | unrestricted | any user |
| `retryFailedMessage` | unrestricted | any address |

### `TokenAdminRegistry` (Chainlink global registry)

| Function | Access | Holder |
| --- | --- | --- |
| `setPool` | administrator of the token | OCG timelock for OHM |
| `transferAdminRole` | administrator of the token | OCG timelock for OHM |
| `acceptAdminRole` | pending administrator of the token | OCG timelock during migration |
| `proposeAdministrator` | registry module or registry owner | Chainlink |
| `addRegistryModule` | registry owner | Chainlink |
| `removeRegistryModule` | registry owner | Chainlink |
| `transferOwnership` | registry owner | Chainlink |
| `acceptOwnership` | pending registry owner | Chainlink |
