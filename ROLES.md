# ROLES

This document describes the roles that are used in the Olympus protocol.

## Role Definitions

| Role | Policy | Actions |
|------|----------|-------------|
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
| bridge_admin | CrossChainBridge | Allows configuring the CrossChainBridge |
| bridge_admin | LZBridgeGateway | Call the one-shot `initializeBridgedSupply` bootstrap |
| bridge_admin | LZBridgeAndDelegateConfig | Queue most timelocked actions (gateway delegate/supply, delegate libraries/configs, periphery setGateway/setReEnabler/setGracePeriod) on the config policy |
| bridge_admin | LZEndpointDelegate | Call the inbound-channel management primitives (skip, nilify, burn, clear) directly on the LayerZero endpoint; intentionally not timelocked |
| bridge_channel_manager | LZEndpointDelegate | Call the inbound-channel management primitives (skip, nilify, burn, clear) directly on the LayerZero endpoint |
| bridge_configurator | LZBridgeGateway | Set the LZ endpoint delegate, increase / decrease the bridged supply, set inbound / outbound rate limits, clear inbound / outbound in-flight amounts, and set the grace period. Expected to be granted exclusively to the LZBridgeAndDelegateConfig policy so these mutators are reached only through the policy's timelock queue |
| bridge_configurator | LZEndpointDelegate | Set send / receive libraries and the receive-library timeout, and set ULN / Executor endpoint config on the LayerZero endpoint. Expected to be granted exclusively to the LZBridgeAndDelegateConfig policy so these mutators are reached only through the policy's timelock queue |
| bridge_facilitator | LZBridgeGateway | Burn OHM and send cross-chain via burnAndSend |
| bridge_rate_limiter | LZBridgeAndDelegateConfig | Queue rate-limit and in-flight-clear sub-actions on the config policy |
| burner_loans_admin | BurnerLoans, BurnerLoansConfig, BurnerLoansConfigTimelock, BurnerLoansInventory, BurnerLoansSeizer, BurnerLoansYieldClaimer | Re-enable Burner Loans policies, queue bounded configuration updates through BurnerLoansConfigTimelock, reconcile the Inventory MINTR approval, and update bounded Seizer or YieldClaimer execution settings |
| burner_loans_inventory_provider | BurnerLoansInventory | Supply protocol-owned OHM and withdraw the provider's idle supplied-OHM claim |
| burner_loans_seizer | BurnerLoans | Allows the BurnerLoansSeizer Heart task to execute protocol-operated seizures without receiving keeper rewards |
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
