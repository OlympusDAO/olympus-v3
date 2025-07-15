# ROLES

This document describes the roles that are used in the Olympus protocol.

## Role Definitions

| Role | Policy | Actions |
|------|----------|-------------|
| admin | ConvertibleDepositAuctioneer | Set tracking period, set tick step, enable/disable deposit periods, enable/disable contract |
| admin | ConvertibleDepositFacility | Authorize/deauthorize operators, enable/disable contract |
| admin | CoolerLtvOracle | Allows setting parameters on the CoolerLtvOracle |
| admin | CoolerTreasuryBorrower | Allows setting parameters on the CoolerTreasuryBorrower |
| admin | DepositManager | Add asset definition, set asset deposit cap, add/enable/disable asset periods, set deposit reclaim rate, enable/disable contract |
| admin | DepositRedemptionVault | Set max borrow percentage, set interest rate, set claim default reward percentage, authorize/deauthorize facilities, enable/disable contract |
| admin | EmissionManager | Adjust yield, set configuration parameters, enable/disable contract |
| admin | Heart | Reset the heartbeat, enable/disable the contract,set the distributor, set auction rewards |
| admin | MonoCooler | Allows setting parameters on the MonoCooler |
| admin | YieldDepositFacility | Set yield fee, enable/disable contract |
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
| emergency | ConvertibleDepositAuctioneer | Disable the contract |
| emergency | ConvertibleDepositFacility | Deauthorize operators, disable contract |
| emergency | ConvertibleDepositFacility | Disable the contract |
| emergency | CoolerLtvOracle | Allows enable/disable on the CoolerLtvOracle |
| emergency | CoolerTreasuryBorrower | Allows enable/disable on the CoolerTreasuryBorrower |
| emergency | DepositManager | Disable contract |
| emergency | DepositRedemptionVault | Deauthorize facilities, disable contract |
| emergency | EmissionManager | Disable the contract |
| emergency | Heart | Disable the contract |
| emergency | MonoCooler | Allows enable/disable on the MonoCooler |
| emergency | YieldDepositFacility | Disable the contract |
| emergency_restart | Emergency | Reactivates the TRSRY and/or MINTR modules |
| emergency_shutdown | Clearinghouse | Allows shutting down the protocol in an emergency |
| emergency_shutdown | Emergency | Deactivates the TRSRY and/or MINTR modules |
| heart | ConvertibleDepositFacility | Calls the execute() function |
| heart | EmissionManager | Calls the execute() function |
| heart | Operator | Call the operate() function |
| heart | ReserveMigrator | Allows migrating reserves from one reserve token to another |
| heart | YieldDepositFacility | Calls the execute() function |
| heart | YieldRepurchaseFacility | Creates a new YRF market |
| loan_consolidator_admin | LoanConsolidator | Allows configuring the LoanConsolidator |
| manager | ConvertibleDepositAuctioneer | Set tracking period, set tick step, enable/disable deposit periods |
| manager | DepositManager | Add asset definition, set asset deposit cap, add/enable/disable asset periods, set deposit reclaim rate |
| manager | DepositRedemptionVault | Set max borrow percentage, set interest rate, set claim default reward percentage |
| manager | Heart | Reset the heartbeat |
| manager | YieldDepositFacility | Set yield fee |
| operator_admin | Operator | Activate/deactivate the functionality |
| operator_policy | Operator | Set spreads, threshold factor, and cushion factor |
| operator_reporter | Operator | Report bond purchases |
| poly_admin | pOLY | Allows migrating pOLY terms to another contract |
| reserve_migrator_admin | ReserveMigrator | Activate/deactivate the functionality |
| treasuryborrower_cooler | CoolerTreasuryBorrower | Assigned to the MonoCooler contract to allow borrowing of funds from TRSRY |

## Role Allocations

```json
{
    "0x0AE561226896dA978EaDA0Bec4a7d3CfAE04f506": [ // Current Operator contract
        "callback_whitelist"
    ],
    "0x245cc372C84B3645Bf0Ffe6538620B04a217988B": [ // DAO MS
        "operator_operate",
        "operator_admin",
        "callback_admin",
        "price_admin",
        "custodian",
        "emergency_restart",
        "bridge_admin",
        "heart_admin",
        "cooler_overseer",
        "operator_policy",
        "bondmanager_admin",
        "loop_daddy"
    ],
    "0x73df08CE9dcC8d74d22F23282c4d49F13b4c795E": [ // Current BondCallback contract
        "operator_reporter"
    ],
    "0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39": [ // OCG Timelock
        "cooler_overseer",
        "emergency_admin",
        "emergency_shutdown",
        "operator_admin",
        "callback_admin",
        "price_admin",
        "custodian",
        "emergency_restart",
        "bridge_admin",
        "heart_admin",
        "operator_policy",
        "loop_daddy"
    ],
    "0xda9fEDBcAF319Ecf8AB11fe874Fb1AbFc2181766": [ // pOly MS
        "poly_admin"
    ],
    "0xa8A6ff2606b24F61AFA986381D8991DFcCCd2D55": [ // Emergency MS
        "emergency_shutdown",
        "emergency_admin"
    ],
    "0x39F6AA3d445e6Dd8eC232c6Bd589889A88E3034d": [ // Current Heart contract
        "heart",
        "operator_operate"
    ]
}
```

The current role allocations can be determined by running the [role-viewer](https://github.com/OlympusDAO/role-viewer/) tool.
