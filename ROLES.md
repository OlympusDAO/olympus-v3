# ROLES

This document describes the roles that are used in the Olympus protocol.

## Role Definitions

| Role | Policy | Actions |
|------|----------|-------------|
| admin | CCIPBurnMintTokenPool | Enable/disable contract |
| admin | CCIPTokenPoolConfig | Accept/transfer the token pool ownership, set the config operator, set the router, set the rate-limit admin, set the rebalancer and transfer liquidity (lock/release pool only), set the grace period, call the route configuration functions directly (add/remove chain, set remote token, add/remove remote pool, apply allowlist updates, set chain rate limits), contain routes through `disableChain` / `disableAllChains` (also while the policy is disabled), enable/disable contract |
| admin | CCIPTokenPoolConfigTimelock | Set the timelock delay, set the grace period, cancel queued actions (also while the policy is disabled), enable/disable contract. Not a queue proposer |
| admin | ChainlinkOracleFactory | Allows create/enable/disable of oracles, enable/disable of new oracle creation, enable/disable contract |
| admin | ConvertibleDepositAuctioneer | Set tracking period, set tick step, enable/disable deposit periods, enable/disable contract |
| admin | ConvertibleDepositFacility | Authorize/deauthorize operators, enable/disable contract |
| admin | CoolerLtvOracle | Allows setting parameters on the CoolerLtvOracle |
| admin | CoolerTreasuryBorrower | Allows setting parameters on the CoolerTreasuryBorrower |
| admin | DepositManager | Add asset definition, set asset deposit cap, add/enable/disable asset periods, set deposit reclaim rate, enable/disable contract |
| admin | DepositRedemptionVault | Set max borrow percentage, set interest rate, set claim default reward percentage, authorize/deauthorize facilities, enable/disable contract |
| admin | EmissionManager | Adjust yield, set configuration parameters, enable/disable contract |
| admin | Heart | Reset the heartbeat, enable/disable the contract,set the distributor, set auction rewards |
| admin | LZBridgeAndDelegateConfig | Enable / disable the policy, queue timelocked actions on the bridge stack, rotate the policy's gateway / delegate / facilitator target variables, and change the timelock delay |
| admin | LZBridgeGateway | Set peers, set enforced options, set whether receiving is enabled, enable / disable the gateway, rescue accidentally-sent assets, and the one-shot `initializeBridgedSupply` bootstrap |
| admin | LZEndpointDelegate | Enable / disable the policy and call the inbound-channel management primitives (skip, nilify, burn, clear) directly on the LayerZero endpoint |
| admin | MonoCooler | Allows setting parameters on the MonoCooler |
| admin | MorphoOracleFactory | Allows create/enable/disable of oracles, enable/disable of new oracle creation, enable/disable contract |
| admin | PriceConfig v2 | Add asset configuration, queue asset removal, queue asset price feed/strategy/moving average configuration updates, queue submodule upgrades, queue submodule calls, queue timelock delay changes, install submodules, store observations, enable/disable contract |
| admin | ReserveWrapper | Enable/disable contract |
| bondmanager_admin | BondManager | Create/close bond markets, set parameters |
| bridge_admin | CCIPTokenPoolConfig | Contain routes through `disableChain` / `disableAllChains`, also while the policy is disabled. Call `reEnable` within the grace period |
| bridge_admin | CCIPTokenPoolConfigTimelock | Queue the timelocked route configuration actions (`queueAddChain`, `queueRemoveChain`, `queueSetRemoteToken`, `queueAddRemotePool`, `queueRemoveRemotePool`, `queueApplyAllowListUpdates`, `queueSetChainRateLimits`, `queueBatch`). Call `reEnable` within the grace period |
| bridge_admin | CrossChainBridge | Allows configuring the CrossChainBridge |
| bridge_admin | LZBridgeGateway | Call the one-shot `initializeBridgedSupply` bootstrap |
| bridge_admin | LZBridgeAndDelegateConfig | Queue most timelocked actions (gateway delegate/supply, delegate libraries/configs, periphery setGateway/setReEnabler/setGracePeriod) on the config policy |
| bridge_admin | LZEndpointDelegate | Call the inbound-channel management primitives (skip, nilify, burn, clear) directly on the LayerZero endpoint; intentionally not timelocked |
| bridge_channel_manager | LZEndpointDelegate | Call the inbound-channel management primitives (skip, nilify, burn, clear) directly on the LayerZero endpoint |
| bridge_configurator | LZBridgeGateway | Set the LZ endpoint delegate, increase / decrease the bridged supply, set inbound / outbound rate limits, clear inbound / outbound in-flight amounts, and set the grace period. Expected to be granted exclusively to the LZBridgeAndDelegateConfig policy so these mutators are reached only through the policy's timelock queue |
| bridge_configurator | LZEndpointDelegate | Set send / receive libraries and the receive-library timeout, and set ULN / Executor endpoint config on the LayerZero endpoint. Expected to be granted exclusively to the LZBridgeAndDelegateConfig policy so these mutators are reached only through the policy's timelock queue |
| bridge_facilitator | LZBridgeGateway | Burn OHM and send cross-chain via burnAndSend |
| bridge_rate_limiter | CCIPTokenPoolConfig | Set the rate limits of routes that the pool already serves through `setChainRateLimits`, without the timelock. This also restores the capacity of a contained route. Contain routes through `disableChain` / `disableAllChains`, also while the policy is disabled. Governance leaves this role unassigned unless it appoints a dedicated rate-limit operator |
| bridge_rate_limiter | LZBridgeAndDelegateConfig | Queue rate-limit and in-flight-clear sub-actions on the config policy |
| callback_admin | BondCallback | Administers the policy |
| callback_whitelist | BondCallback | Whitelists/blacklists tellers for callback |
| cd_auctioneer | ConvertibleDepositFacility | Calls the createPosition() function |
| cd_emissionmanager | ConvertibleDepositAuctioneer | Calls the setAuctionParameters() function |
| contract_registry_admin | ContractRegistryAdmin | Allows registering/deregistering contracts |
| cooler_overseer | Clearinghouse | Allows activating the Clearinghouse |
| custodian | TreasuryCustodian | Deposit/withdraw reserves and grant/revoke approvals |
| deposit_operator | DepositManager | Allows a caller to manage deposits on behalf of depositors |
| distributor_admin | Distributor | Set reward rate, bounty, and other parameters |
| em_manager | EmissionManager | Allows setting parameters on the EmissionManager |
| emergency | CCIPBurnMintTokenPool | Disable contract |
| emergency | CCIPTokenPoolConfig | Disable contract. Contain routes through `disableChain` / `disableAllChains`, also while the policy is disabled |
| emergency | CCIPTokenPoolConfigTimelock | Disable contract. Cancel queued actions, also while the policy is disabled |
| emergency | ChainlinkOracleFactory | Allows disable of oracles, disable of new oracle creation, enable/disable the contract |
| emergency | ConvertibleDepositAuctioneer | Disable the contract |
| emergency | ConvertibleDepositFacility | Deauthorize operators, disable contract |
| emergency | CoolerLtvOracle | Allows enable/disable on the CoolerLtvOracle |
| emergency | CoolerTreasuryBorrower | Allows enable/disable on the CoolerTreasuryBorrower |
| emergency | DepositManager | Disable contract |
| emergency | DepositRedemptionVault | Deauthorize facilities, disable contract |
| emergency | EmissionManager | Disable the contract |
| emergency | Heart | Disable the contract |
| emergency | LZEndpointDelegate | Disable the contract |
| emergency | MonoCooler | Allows enable/disable on the MonoCooler |
| emergency | MorphoOracleFactory | Allows disable of oracles, disable of new oracle creation, disable the contract |
| emergency | PriceConfig v2 | Disable contract, cancel queued timelock actions |
| emergency | ReserveWrapper | Disable contract |
| emergency_restart | Emergency | Reactivates the TRSRY and/or MINTR modules |
| emergency_shutdown | Clearinghouse | Allows shutting down the protocol in an emergency |
| emergency_shutdown | Emergency | Deactivates the TRSRY and/or MINTR modules |
| heart | ConvertibleDepositFacility | Calls the execute() function |
| heart | EmissionManager | Calls the execute() function |
| heart | Operator | Call the operate() function |
| heart | ReserveMigrator | Allows migrating reserves from one reserve token to another |
| heart | YieldRepurchaseFacility | Creates a new YRF market |
| legacy_migration_admin | V1Migrator | Set the merkle root and rescue tokens |
| loan_consolidator_admin | LoanConsolidator | Allows configuring the LoanConsolidator |
| manager | ConvertibleDepositAuctioneer | Set tracking period, set tick step, enable/disable deposit periods |
| manager | DepositManager | Add asset definition, set asset deposit cap, add/enable/disable asset periods, set deposit reclaim rate |
| manager | DepositRedemptionVault | Set max borrow percentage, set interest rate, set claim default reward percentage |
| manager | LZBridgeGateway | Rescue accidentally-sent assets |
| manager | Heart | Reset the heartbeat |
| manager | LZBridgeGateway | Re-enable the gateway after a disable, within the grace window |
| operator_admin | Operator | Activate/deactivate the functionality |
| operator_policy | Operator | Set spreads, threshold factor, and cushion factor |
| operator_reporter | Operator | Report bond purchases |
| oracle_manager | ChainlinkOracleFactory | Allows create/enable/disable of oracles, enable/disable of new oracle creation |
| oracle_manager | MorphoOracleFactory | Allows create/enable/disable of oracles, enable/disable of new oracle creation |
| poly_admin | pOLY | Allows migrating pOLY terms to another contract |
| price_admin | PriceConfig v2 | Add asset configuration, queue asset removal, queue asset price feed/strategy/moving average configuration updates, queue submodule upgrades, queue submodule calls, install submodules, store observations |
| reserve_migrator_admin | ReserveMigrator | Activate/deactivate the functionality |
| treasuryborrower_cooler | CoolerTreasuryBorrower | Assigned to the MonoCooler contract to allow borrowing of funds from TRSRY |

## Role Allocations

The current role allocations can be determined by viewing the [Protocol Visualizer](https://olympus-protocol-visualizer.up.railway.app) tool.

## PriceConfig v2 Timelock Notes

The `admin` and `price_admin` roles can queue protected PriceConfig v2 changes, but they cannot bypass the timelock. Queued actions can be executed by any address after the configured delay and before expiry while the policy is enabled.

The `emergency` role is the independent veto path for PriceConfig v2 queued actions. It can cancel queued actions, including while the policy is disabled.

## CCIP Token Pool Config Notes

`CCIPTokenPoolConfig` owns the local CCIP token pool. The config operator is an address, not a ROLES role. The `admin` role sets it through `setConfigOperator`. The intended config operator is the local `CCIPTokenPoolConfigTimelock`.

The `bridge_admin` role queues route configuration changes on `CCIPTokenPoolConfigTimelock`. Any address can execute a queued action from the end of the delay until the expiry time, both inclusive. Queueing and execution require both policies to be enabled. The config policy must also name the timelock as its config operator.

The `admin` role is not a queue proposer, because it can call each target function on `CCIPTokenPoolConfig` directly. The `admin` role, the `emergency` role and the proposer can cancel a queued action, including while the timelock is disabled. Any address can cancel an expired action.

`reEnable` accepts only the `bridge_admin` role, within the grace period. The `admin` role restarts a disabled policy through `enable`. `CCIPBurnMintTokenPool` has no `reEnable` and no grace period.

For the holders on each chain and the full function matrix, see [documentation/bridge/ccip/ACCESS_CONTROL.md](documentation/bridge/ccip/ACCESS_CONTROL.md).
