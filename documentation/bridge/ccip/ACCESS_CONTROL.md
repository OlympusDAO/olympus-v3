# CCIP Access Control Matrix

## Holders

| Authority | Holder | Address |
| --- | --- | --- |
| `admin` role | OCG timelock | `0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39` |
| `bridge_admin` role | DAO MS | `0x245cc372C84B3645Bf0Ffe6538620B04a217988B` |
| `emergency` role | Emergency MS | `0xa8A6ff2606b24F61AFA986381D8991DFcCCd2D55` |
| `bridge_rate_limiter` role | Unassigned at launch | - |
| Config policy configurator | `CCIPBridgeConfigTimelock` | deployed |
| Token pool owner | `CCIPBridgeConfig` | deployed |
| Lock/release pool rebalancer | OCG timelock | `0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39` |
| Native pool `rateLimitAdmin` | Zero address | `0x0000000000000000000000000000000000000000` |
| `CCIPCrossChainBridge` owner | DAO MS | `0x245cc372C84B3645Bf0Ffe6538620B04a217988B` |
| OHM administrator in `TokenAdminRegistry` | OCG timelock | `0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39` |

Holders above are the Ethereum end state. `CCIPBridgeConfig`, `CCIPBridgeConfigTimelock`, and the burn/mint pool are also deployed on Arbitrum, Optimism, Base, and Berachain, where `admin` and `bridge_admin` are held by the local DAO MS, a different address on each chain. The Emergency MS is deployed at the same address everywhere.

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

### `CCIPBridgeConfig` policy

Owns the local CCIP token pool.

| Function | Access | Holder |
| --- | --- | --- |
| `acceptPoolOwnership` | `admin` | OCG timelock |
| `transferPoolOwnership` | `admin` | OCG timelock |
| `setConfigurator` | `admin` | OCG timelock |
| `setRouter` | `admin` | OCG timelock |
| `setRateLimitAdmin` | `admin` | OCG timelock |
| `setGracePeriod` | `admin` | OCG timelock |
| `enable` | `admin` | OCG timelock |
| `addChain` | configurator or `admin` | `CCIPBridgeConfigTimelock`; OCG timelock |
| `removeChain` | configurator or `admin` | `CCIPBridgeConfigTimelock`; OCG timelock |
| `setRemoteToken` | configurator or `admin` | `CCIPBridgeConfigTimelock`; OCG timelock |
| `addRemotePool` | configurator or `admin` | `CCIPBridgeConfigTimelock`; OCG timelock |
| `removeRemotePool` | configurator or `admin` | `CCIPBridgeConfigTimelock`; OCG timelock |
| `applyAllowListUpdates` | configurator or `admin` | `CCIPBridgeConfigTimelock`; OCG timelock |
| `setChainRateLimits` | `bridge_rate_limiter`, configurator, or `admin` | unassigned; timelock; OCG timelock |
| `disable` | `emergency` or `admin` | Emergency MS; OCG timelock |
| `disableChain` | `emergency` or `admin`; works while disabled | Emergency MS; OCG timelock |
| `disableAllChains` | `emergency` or `admin`; works while disabled | Emergency MS; OCG timelock |
| `reEnable` | `bridge_admin`; within the grace period | DAO MS |
| `changeKernel` | Kernel | Kernel |
| `configureDependencies` | unrestricted, invoked by Kernel | - |

All functions require the policy to be enabled, except `enable` and `reEnable` (require disabled), the two containment functions, and the Kernel-invoked ones.

The two functions below are present on every deployment of the config policy, but revert unless the owned pool supports `ILiquidityContainer`, which only `LockReleaseTokenPool` does.

| Function | Access | Holder |
| --- | --- | --- |
| `setRebalancer` | `admin` | OCG timelock |
| `transferLiquidity` | `admin` | OCG timelock |

### `CCIPBridgeConfigTimelock` policy

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

All functions require the timelock to be enabled, except `enable` and `reEnable` (require disabled), `cancelQueuedAction`, and the Kernel-invoked ones. Queueing also requires the timelock to be the config policy's configurator; execution also requires the config policy to be enabled and the timelock to still be its configurator.

The `admin` role is not a queue proposer: every queued action targets a function it can call directly on the config policy.

### `CCIPBurnMintTokenPool` policy (non-Ethereum chains)

Deployed with an empty allowlist, so `applyAllowListUpdates` reverts with `AllowListNotEnabled`.

| Function | Access | Holder |
| --- | --- | --- |
| `acceptOwnership` | pending owner | local `CCIPBridgeConfig` |
| `transferOwnership` | owner | local `CCIPBridgeConfig` |
| `applyChainUpdates` | owner | local `CCIPBridgeConfig` |
| `addRemotePool` | owner | local `CCIPBridgeConfig` |
| `removeRemotePool` | owner | local `CCIPBridgeConfig` |
| `applyAllowListUpdates` | owner | local `CCIPBridgeConfig` |
| `setRouter` | owner | local `CCIPBridgeConfig` |
| `setRateLimitAdmin` | owner | local `CCIPBridgeConfig` |
| `setChainRateLimiterConfig` | owner or `rateLimitAdmin` | local `CCIPBridgeConfig`; zero |
| `setChainRateLimiterConfigs` | owner or `rateLimitAdmin` | local `CCIPBridgeConfig`; zero |
| `enable` | local `admin` | local DAO MS |
| `disable` | `emergency` or local `admin` | Emergency MS; local DAO MS |
| `lockOrBurn` | on-ramp of the configured router | Chainlink |
| `releaseOrMint` | off-ramp of the configured router | Chainlink |
| `changeKernel` | Kernel  | Kernel |
| `configureDependencies` | unrestricted, invoked by Kernel | - |

If implemented:

| Function | Access | Holder |
| --- | --- | --- |
| `setGracePeriod` | local `admin` | local DAO MS |
| `reEnable` | local `bridge_admin` | local DAO MS |

### `LockReleaseTokenPool` (deployed on Ethereum)

Its owner changes from the DAO MS to `CCIPBridgeConfig`. Deployed with an empty allowlist, so `applyAllowListUpdates` reverts with `AllowListNotEnabled`.

| Function | Access | Holder |
| --- | --- | --- |
| `acceptOwnership` | pending owner | `CCIPBridgeConfig` |
| `transferOwnership` | owner | `CCIPBridgeConfig` |
| `applyChainUpdates` | owner | `CCIPBridgeConfig` |
| `addRemotePool` | owner | `CCIPBridgeConfig` |
| `removeRemotePool` | owner | `CCIPBridgeConfig` |
| `applyAllowListUpdates` | owner | `CCIPBridgeConfig` |
| `setRouter` | owner | `CCIPBridgeConfig` |
| `setRateLimitAdmin` | owner | `CCIPBridgeConfig` |
| `setRebalancer` | owner | `CCIPBridgeConfig` |
| `transferLiquidity` | owner | `CCIPBridgeConfig` |
| `setChainRateLimiterConfig` | owner or `rateLimitAdmin` | `CCIPBridgeConfig`; zero |
| `setChainRateLimiterConfigs` | owner or `rateLimitAdmin` | `CCIPBridgeConfig`; zero |
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
