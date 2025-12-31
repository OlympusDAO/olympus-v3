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
| admin | MonoCooler | Allows setting parameters on the MonoCooler |
| admin | MorphoOracleFactory | Allows create/enable/disable of oracles, enable/disable of new oracle creation, enable/disable contract |
| admin | PriceConfig v2 | Install/upgrade/exec on submodules, add/remove asset configuration, update asset price feed/strategy/moving average configuration, enable/disable contract |
| admin | ReserveWrapper | Enable/disable contract |
| bondmanager_admin | BondManager | Create/close bond markets, set parameters |
| bridge_admin | CrossChainBridge | Allows configuring the CrossChainBridge |
| callback_admin | BondCallback | Administers the policy |
| callback_whitelist | BondCallback | Whitelists/blacklists tellers for callback |
| cd_auctioneer | ConvertibleDepositFacility | Calls the createPosition() function |
| cd_emissionmanager | ConvertibleDepositAuctioneer | Calls the setAuctionParameters() function |
| contract_registry_admin | ContractRegistryAdmin | Allows registering/deregistering contracts |
| cooler_overseer | Clearinghouse | Allows activating the Clearinghouse |
| custodian | TreasuryCustodian | Deposit/withdraw reserves and grant/revoke approvals |
| deposit_operator | DepositManager | Allows a caller to manage deposits on behalf of depositors |
| distributor_admin | Distributor | Set reward rate, bounty, and other parameters |
| emergency | ChainlinkOracleFactory | Allows disable of oracles, disable of new oracle creation, enable/disable the contract |
| emergency | ConvertibleDepositAuctioneer | Disable the contract |
| emergency | ConvertibleDepositFacility | Deauthorize operators, disable contract |
| emergency | CoolerLtvOracle | Allows enable/disable on the CoolerLtvOracle |
| emergency | CoolerTreasuryBorrower | Allows enable/disable on the CoolerTreasuryBorrower |
| emergency | DepositManager | Disable contract |
| emergency | DepositRedemptionVault | Deauthorize facilities, disable contract |
| emergency | EmissionManager | Disable the contract |
| emergency | Heart | Disable the contract |
| emergency | MonoCooler | Allows enable/disable on the MonoCooler |
| emergency | MorphoOracleFactory | Allows disable of oracles, disable of new oracle creation, disable the contract |
| emergency | PriceConfig v2 | Disable contract |
| emergency | ReserveWrapper | Disable contract |
| emergency_restart | Emergency | Reactivates the TRSRY and/or MINTR modules |
| emergency_shutdown | Clearinghouse | Allows shutting down the protocol in an emergency |
| emergency_shutdown | Emergency | Deactivates the TRSRY and/or MINTR modules |
| em_manager | EmissionManager | Allows setting parameters on the EmissionManager |
| heart | ConvertibleDepositFacility | Calls the execute() function |
| heart | EmissionManager | Calls the execute() function |
| heart | Operator | Call the operate() function |
| heart | ReserveMigrator | Allows migrating reserves from one reserve token to another |
| heart | YieldRepurchaseFacility | Creates a new YRF market |
| loan_consolidator_admin | LoanConsolidator | Allows configuring the LoanConsolidator |
| manager | ConvertibleDepositAuctioneer | Set tracking period, set tick step, enable/disable deposit periods |
| manager | DepositManager | Add asset definition, set asset deposit cap, add/enable/disable asset periods, set deposit reclaim rate |
| manager | DepositRedemptionVault | Set max borrow percentage, set interest rate, set claim default reward percentage |
| manager | Heart | Reset the heartbeat |
| operator_admin | Operator | Activate/deactivate the functionality |
| operator_policy | Operator | Set spreads, threshold factor, and cushion factor |
| operator_reporter | Operator | Report bond purchases |
| oracle_manager | ChainlinkOracleFactory | Allows create/enable/disable of oracles, enable/disable of new oracle creation |
| oracle_manager | MorphoOracleFactory | Allows create/enable/disable of oracles, enable/disable of new oracle creation |
| poly_admin | pOLY | Allows migrating pOLY terms to another contract |
| price_admin | PriceConfig v2 | Exec on submodules, add/remove asset configuration, update asset price feed/strategy/moving average configuration |
| reserve_migrator_admin | ReserveMigrator | Activate/deactivate the functionality |
| treasuryborrower_cooler | CoolerTreasuryBorrower | Assigned to the MonoCooler contract to allow borrowing of funds from TRSRY |

## Role Allocations

The current role allocations can be determined by viewing the [Protocol Visualizer](https://olympus-protocol-visualizer.up.railway.app) tool.
