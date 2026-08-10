# CCIP Access Control Matrix

## Holders

| Authority | Holder | Address |
| --- | --- | --- |
| `admin` role | OCG timelock | `0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39` |
| `bridge_admin` role | DAO MS | `0x245cc372C84B3645Bf0Ffe6538620B04a217988B` |
| `emergency` role | Emergency MS | `0xa8A6ff2606b24F61AFA986381D8991DFcCCd2D55` |
| Grace-period re-enabler | DAO MS | `0x245cc372C84B3645Bf0Ffe6538620B04a217988B` |
| `bridge_rate_limiter` role | Unassigned at launch | - |
| Config policy configurator | `CCIPBridgeConfigTimelock` | deployed |
| Token pool owner | `CCIPBridgeConfig` | deployed |
| Lock/release pool rebalancer | DAO MS | `0x245cc372C84B3645Bf0Ffe6538620B04a217988B` |
| Native pool `rateLimitAdmin` | Zero address | `0x0000000000000000000000000000000000000000` |
| `CCIPCrossChainBridge` owner | DAO MS | `0x245cc372C84B3645Bf0Ffe6538620B04a217988B` |
| OHM administrator in `TokenAdminRegistry` | OCG timelock | `0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39` |

## New contracts

### `CCIPBridgeConfig` policy

Owns the local CCIP token pool.

| Function | Access | Holder |
| --- | --- | --- |
| `acceptPoolOwnership` | `admin` | OCG timelock |
| `transferPoolOwnership` | `admin` | OCG timelock |
| `setConfigurator` | `admin` | OCG timelock |
| `setRouter` | `admin` | OCG timelock |
| `setRebalancer` | `admin` | OCG timelock |
| `setRateLimitAdmin` | `admin` | OCG timelock |
| `setReEnabler` | `admin` | OCG timelock |
| `setGracePeriod` | `admin` | OCG timelock |
| `transferLiquidity` | `admin` | OCG timelock |
| `enable` | `admin` | OCG timelock |
| `setRemoteToken` | `admin` | OCG timelock |
| `addChain` | configurator or `admin` | `CCIPBridgeConfigTimelock`; OCG timelock |
| `removeChain` | configurator or `admin` | `CCIPBridgeConfigTimelock`; OCG timelock |
| `addRemotePool` | configurator or `admin` | `CCIPBridgeConfigTimelock`; OCG timelock |
| `removeRemotePool` | configurator or `admin` | `CCIPBridgeConfigTimelock`; OCG timelock |
| `applyAllowListUpdates` | configurator or `admin` | `CCIPBridgeConfigTimelock`; OCG timelock |
| `setChainRateLimits` | `bridge_rate_limiter`, configurator, or `admin` | unassigned; timelock; OCG timelock |
| `disable` | `emergency` or `admin` | Emergency MS; OCG timelock |
| `disableChain` | `emergency` or `admin` | Emergency MS; OCG timelock |
| `disableAllChains` | `emergency` or `admin` | Emergency MS; OCG timelock |
| `reEnable` | re-enabler | DAO MS |
| `changeKernel` | Kernel | Kernel |
| `configureDependencies` | unrestricted, invoked by Kernel | - |

### `CCIPBridgeConfigTimelock` policy

| Function | Access | Holder |
| --- | --- | --- |
| `enable` | `admin` | OCG timelock |
| `setGracePeriod` | `admin` | OCG timelock |
| `setTimelockDelay` | `admin` | OCG timelock |
| `queueAddChain` | `bridge_admin` | DAO MS |
| `queueRemoveChain` | `bridge_admin` | DAO MS |
| `queueAddRemotePool` | `bridge_admin` | DAO MS |
| `queueRemoveRemotePool` | `bridge_admin` | DAO MS |
| `queueApplyAllowListUpdates` | `bridge_admin` | DAO MS |
| `queueSetChainRateLimits` | `bridge_admin` | DAO MS |
| `queueBatch` | `bridge_admin` | DAO MS |
| `executeQueuedAction` | permissionless after the delay | any address |
| `cancelQueuedAction` | `admin`, `emergency`, or the original proposer | OCG timelock; Emergency MS; DAO MS |
| `disable` | `emergency` or `admin` | Emergency MS; OCG timelock |
| `reEnable` | re-enabler | DAO MS |
| `changeKernel` | Kernel  | Kernel |
| `configureDependencies` | unrestricted, invoked by Kernel | - |

## Existing contracts

### `CCIPBurnMintTokenPool` policy (for non-Ethereum chains; not deployed on main networks)

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
| `setChainRateLimiterConfig` | owner or `rateLimitAdmin` | `CCIPBridgeConfig`; zero |
| `setChainRateLimiterConfigs` | owner or `rateLimitAdmin` | `CCIPBridgeConfig`; zero |
| `enable` | local `admin` | local DAO MS |
| `disable` | `emergency` or local `admin` | Emergency MS; local DAO MS |
| `lockOrBurn` | on-ramp of the configured router | Chainlink |
| `releaseOrMint` | off-ramp of the configured router | Chainlink |
| `changeKernel` | Kernel  | Kernel |
| `configureDependencies` | unrestricted, invoked by Kernel | - |

If implemented:

| Function | Access | Holder |
| --- | --- | --- |
| `reEnable` | re-enabler | local DAO MS |
| `setGracePeriod` | local `admin` | local DAO MS |

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
| `provideLiquidity` | rebalancer | DAO MS |
| `withdrawLiquidity` | rebalancer | DAO MS |
| `lockOrBurn` | on-ramp of the configured router | Chainlink |
| `releaseOrMint` | off-ramp of the configured router | Chainlink |

### `CCIPCrossChainBridge` periphery (deployed on Ethereum)

No changes.

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
| `withdraw` | owner | DAO MS |
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
