# BurnerLoansConfig.setAssetDebtCap coverage plan

Source: [setAssetDebtCap](../../../policies/burnerloans/BurnerLoansConfig.sol#L244). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCFG-DEBT-CAP` identifies this contract/function.

Implemented same-value rule: unchanged parameters return without setter writes/events after the concrete checks before equality. Changing-value rows exclude the current value; downstream checks reached only after equality are tested separately.

Own-policy admission: require Kernel-active BurnerLoansConfig; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfig)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Fuzz permitted configuration caller: independently fuzz a nonzero address as ADMIN_ROLE holder, current selected configOperator without ADMIN_ROLE, or both. Guarantee ADMIN-only, operator-only and overlapping seeds. Caller choice is independent of lifecycle flags, inputs and dependency failures. Unauthorized fuzzing excludes all ADMIN_ROLE holders and the selected nonzero configOperator.

ADMIN or selected configOperator; Config active/enabled. Per-asset cap is canonical FLOAN market state. Inventory owns only the global cap and aggregate principal/funding/provider claims; no per-asset Inventory setter exists. Core supplies a read-only market lookup; its registry is neither rewritten nor synchronized by this setter. Market principal D is canonical; cap uint128 must be >=D.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

Co-located validator: `validateAssetDebtCap` is tested in `setAssetDebtCap.t.sol`, in the same tests as the corresponding setter cases. Call the validator before the mutation against the same relevant state and independently fuzz its caller, including zero and identities without configuration authority. Assert exact input forwarding and no writes/events independently; a successful setter alone does not prove the view. Numeric rejection/success rows and unchanged-value rows must compare both APIs. Use one paired test per behavior. The Caller column describes the setter caller; independently fuzz the permissionless validator caller, including identities without configuration authority.

The validator remains permissionless, but requires the same local enablement and own-policy activity as the setter: BurnerLoans_PolicyNotActive(BurnerLoansConfig) takes precedence over NotEnabled(), and both precede input validation. Shared input and dependency-read failures use the same exact errors. Mutation authorization, the Core settlement guard and downstream writes remain setter-only; validation does not simulate a write. Both APIs read live canonical FLOAN principal and validate market schema/data; neither calls Risk or Inventory.

## Scenario setup

All body inputs and component bindings are compatible unless the row states otherwise. Use the equivalent permitted-caller family above for each applicable row.

## Authorization

Fixed for this table: Local active: true; Local enabled: true; Core active: true; Core enabled: true.

The only permitted identities are every ADMIN_ROLE holder and the current nonzero configOperator. Fuzz the denied caller over EOAs and contracts excluding exactly those identities; retain zero unless it holds ADMIN. Seed a former operator, a BURNER_LOANS_ADMIN_ROLE-only holder, a borrower and an unrelated contract. All inputs are valid and changed, so authorization is the only varying condition.

| ID | Caller | Inputs / pre-state | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-DEBT-CAP-A01 | Fuzz ADMIN-only, selected nonzero configOperator-only and overlap holders; guarantee each class | Valid changed setting; local/dependency admission satisfied | Success | Exact function-specific canonical update and event; preserve unrelated configuration and accounting | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenAuthorizedCaller_whenCapChanged], [test][test_whenPermittedCallerClassesSeeded] |
| BLCFG-DEBT-CAP-A02 | Fuzz caller lacking ADMIN_ROLE and unequal to the selected nonzero configOperator | Same otherwise-valid request | NotAuthorised() before input validation or writes | Unchanged; no setter event, Core/FLOAN mutation or token movement | Success for the valid input without requiring setter authority; no writes/events | Covered: [test][test_whenCallerIsUnauthorized_reverts] |

## Lifecycle

Each retained row independently fuzzes Core active/enabled and guarantees all four pairs. These flags do not change this setter's outcome. Local enabled and Kernel membership remain separate fixed conditions with exact errors; no outcome-selecting runner is required.

Use a changed valid setting. Config must itself be active/enabled; existing market lookups remain readable. This setter does not call Core.registerMarket or perform a Core mutation. Core activity/enablement therefore does not gate changed or unchanged values. Keep this distinct from addAsset and setAssetWithdrawAsShares, which synchronize Core.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Input | Execution | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-DEBT-CAP-L01 | Fuzz permitted configuration caller | true | true | Fuzz false/true | Fuzz false/true | Changed valid setting | Body succeeds | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenIndependentCoreState_whenCapChanged] |
| BLCFG-DEBT-CAP-L04 | Fuzz permitted configuration caller | true | false | Fuzz false/true | Fuzz false/true | Changed valid setting | NotEnabled() | NotEnabled(); same error before input validation | Covered: [test][test_givenConfigActiveDisabled_whenCapSetAndValidated_reverts] |
| BLCFG-DEBT-CAP-L08 | Fuzz permitted configuration caller | false | true | Fuzz false/true | Fuzz false/true | Changed valid setting | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | BurnerLoans_PolicyNotActive(BurnerLoansConfig); same error before input validation | Covered: [test][test_givenConfigInactiveEnabled_whenCapSetAndValidated_reverts] |
| BLCFG-DEBT-CAP-L12 | Fuzz permitted configuration caller | false | false | Fuzz false/true | Fuzz false/true | Changed valid setting | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | BurnerLoans_PolicyNotActive(BurnerLoansConfig); same error before input validation | Covered: [test][test_givenConfigInactiveDisabled_whenCapSetAndValidated_reverts] |
| BLCFG-VALIDATE-CAP-L05 | Fuzz permitted configuration caller | true | true | Fuzz false/true | Fuzz false/true | D=1; cap=0 | BurnerLoans_InvalidCap() | BurnerLoans_InvalidCap(); same error and precedence; no writes/events | Covered: [test][test_givenInvalidCapAndConfigActiveEnabled_whenSetAndValidated_reverts] |
| BLCFG-VALIDATE-CAP-L06 | Fuzz permitted configuration caller | true | false | Fuzz false/true | Fuzz false/true | D=1; cap=0 | NotEnabled() | NotEnabled(); same error before input validation | Covered: [test][test_givenInvalidCapAndConfigActiveDisabled_whenSetAndValidated_reverts] |
| BLCFG-VALIDATE-CAP-L07 | Fuzz permitted configuration caller | false | true | Fuzz false/true | Fuzz false/true | D=1; cap=0 | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | BurnerLoans_PolicyNotActive(BurnerLoansConfig); same error before input validation | Covered: [test][test_givenInvalidCapAndConfigInactiveEnabled_whenSetAndValidated_reverts] |
| BLCFG-VALIDATE-CAP-L08 | Fuzz permitted configuration caller | false | false | Fuzz false/true | Fuzz false/true | D=1; cap=0 | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | BurnerLoans_PolicyNotActive(BurnerLoansConfig); same error before input validation | Covered: [test][test_givenInvalidCapAndConfigInactiveDisabled_whenSetAndValidated_reverts] |

Unauthorized fuzz callers exclude ADMIN holders and the selected nonzero configOperator. The local enablement modifier precedes caller authorization. Assert unchanged state for rejection; re-enable/reactivate before retry and verify canonical positions survive. These Core lifecycle rows keep selected Inventory/Custody and required module permissions operational; their separate live failures are tested in the body.

For the invalid-input rows, lifecycle checks precede numerical validation in both APIs. Independently fuzz the validator caller; its permissions do not change the lifecycle or numerical error. No rejected call changes configuration, accounting or committed logs.

## Invalid inputs

Admission passes; Config/Core active; selected Inventory is valid. Each row varies one fault and snapshots both FLOAN and Inventory.

| ID | Caller | Input / pre-state | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-DEBT-CAP-I01 | Fuzz permitted configuration caller | Unregistered asset; seed zero and nonzero unsupported address | BurnerLoansCore_AssetNotConfigured(asset) | Unchanged | BurnerLoansCore_AssetNotConfigured(asset); validator makes no writes/events | Covered: [test][test_whenAssetIsNotRegistered_reverts] |
| BLCFG-DEBT-CAP-I02 | Fuzz permitted configuration caller | Market configId incompatible with LoanMarket.CONFIG_ID | BurnerLoans_IncompatibleMarketConfig(marketId,configId) | Unchanged | BurnerLoans_IncompatibleMarketConfig(marketId,configId); validator makes no writes/events | Covered: [test][test_givenIncompatibleSchema_whenSetAndValidated_reverts] |
| BLCFG-DEBT-CAP-I03 | Fuzz permitted configuration caller | D>0; fuzz cap in 0..D-1; seed 0,D-1 and D=MAX128 | BurnerLoans_InvalidCap() | FLOAN cap, Core registry and all Inventory ledgers unchanged | BurnerLoans_InvalidCap(); validator makes no writes/events | Covered: [test][test_givenPrincipal_whenCapIsBelowDebt_reverts], [test][test_whenBelowDebtEndpointsSeeded_reverts] |
| BLCFG-DEBT-CAP-I04 | Fuzz permitted configuration caller | Compatible schema but product data length differs from 224 bytes; fuzz 0..223 and 225..256 with a cap covering current debt | BurnerLoans_InvalidMarketConfigData(marketId,length) | Unchanged; no committed logs | BurnerLoans_InvalidMarketConfigData(marketId,length); same error after cap validation; no writes/events | Covered: [test][test_givenMalformedMarketData_whenSetAndValidated_reverts] |

## Numeric boundaries and successful execution

Admission passes. Independently fuzz D in 0..MAX128 and cap in D..MAX128; guarantee zero when D=0, one when D=0 or D=1, cap=D, D+1 when representable and cap=MAX128. Market debt, unrelated assets and economic config fields remain fixed except for the explicit transition rows. Compare a mutating setter and its validator from equal EVM snapshots; restore the higher existing cap before the intervening borrowing, so the trial cap update does not prevent it.

| ID | Caller | Input / transition | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-DEBT-CAP-N01 | Fuzz permitted configuration caller | Changed valid cap; seeded boundaries above | Success | FLOAN.getMarket(marketId).debtCap equals input; market principal and other config fields unchanged; getAssetConfig/validateAssetDebtCap agree; AssetDebtCapSet | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenAuthorizedCaller_whenCapChanged], [test][test_givenValidFullWidthCap_whenValidated], [test][test_whenCapBoundaryValuesAreSeeded], [test][test_givenExistingLoan_whenConfigurationChanged] |
| BLCFG-DEBT-CAP-N02 | Fuzz permitted configuration caller | Same valid cap | No-op after implemented validation | Same canonical cap; no Inventory/module/registry mutation or event | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_whenCapUnchanged] |
| BLCFG-DEBT-CAP-N03 | Fuzz permitted configuration caller | Asset cap above Inventory global cap; both caps cover their independent principal ledgers | Success | Only this FLOAN market cap changes; global cap is an independent aggregate limit | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_whenAssetCapAboveGlobalCap] |
| BLCFG-VALIDATE-CAP-P01 | Fuzz permitted configuration caller | Proposed cap=D; existing cap permits borrowing D+1; compare both APIs before and after that borrowing | Success before borrowing; BurnerLoans_InvalidCap() after principal becomes D+1 | Both calls use current canonical principal; rejected setters make no cap write | Success before borrowing; BurnerLoans_InvalidCap() afterward; no cached result or writes/events | Covered: [test][test_givenPrincipalChanges_whenOldCapRevalidated] |
| BLCFG-VALIDATE-CAP-P02 | Fuzz permitted configuration caller | Compatible market becomes incompatible, then restores same schema | BurnerLoans_IncompatibleMarketConfig(marketId,configId) while incompatible; success after restoration | Current market metadata is authoritative | BurnerLoans_IncompatibleMarketConfig(marketId,configId) while incompatible; success after restoration; no writes/events | Covered: [test][test_givenIncompatibleSchema_whenSetAndValidated_reverts] |

## Inventory isolation

Config/Core active/enabled; changed valid cap. Inventory is a validated selected identity, but is not called by this per-market setter. Its lifecycle flags vary independently after Config activation; no new Inventory interface-invalid fixture is needed here.

| ID | Caller | Inventory active | Inventory enabled | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-DEBT-CAP-P01 | Fuzz permitted configuration caller | true | true | Success | FLOAN cap changes; global cap, principal, supplied/idle amounts, every provider claim, OHM balance and mint approval unchanged; no Inventory setter call | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenInventoryStateVaries_whenAssetCapChanged] |
| BLCFG-DEBT-CAP-P02 | Fuzz permitted configuration caller | true | false | Success | Same Inventory isolation assertions | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenInventoryStateVaries_whenAssetCapChanged] |
| BLCFG-DEBT-CAP-P03 | Fuzz permitted configuration caller | false | true | Success | Same Inventory isolation assertions | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenInventoryStateVaries_whenAssetCapChanged] |
| BLCFG-DEBT-CAP-P04 | Fuzz permitted configuration caller | false | false | Success | Same Inventory isolation assertions | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenInventoryStateVaries_whenAssetCapChanged] |

## Dependency failures and rollback

Config/Core active, Config enabled; changed valid cap. Keep the market and Inventory ledgers otherwise compatible.

For a changed cap, the validator checks Config's FLOAN authority, independently of its own permissionless caller: Kernel permission for setMarketPrincipalCap and the market's current manager. Both APIs reject the same authority failure without attempting a write in the validator. An unchanged valid cap retains the setter's no-op behavior and skips these downstream authority checks in both APIs. Isolate each fault below; if both fail, FLOAN's selector-permission check precedes its manager check.

| ID | Caller | Failing boundary | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-DEBT-CAP-D01 | Fuzz permitted configuration caller | FLOAN market manager transferred away from Config; Config retains setMarketPrincipalCap permission | FLOAN_NotManager(marketId,Config) | No cap/config/registry/Inventory change or committed events | FLOAN_NotManager(marketId,Config); same Config identity, independent of validator caller; no writes/events | Covered: [test][test_givenConfigNoLongerMarketManager_whenSetAndValidated_reverts] |
| BLCFG-DEBT-CAP-D02 | Fuzz permitted configuration caller | FLOAN setMarketPrincipalCap permission revoked while Config remains active and the market manager | Module_PolicyNotPermitted(Config) | This is a permission failure, not an own-policy inactivity test; all earlier writes roll back | Module_PolicyNotPermitted(Config); checks Config's permission for the setter selector, not the validator caller/selector; no writes/events | Covered: [test][test_givenSetterPermissionRevoked_whenSetAndValidated_reverts] |

Co-located API assertions: `getAssetConfig`, `validateAssetDebtCap`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

| ID | Caller | Fault | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-VALIDATE-CAP-D03 | Fuzz permitted configuration caller | Cached FLOAN principal getter reverts with a mocked typed read error | Exact injected getter error propagates | No cap mutation or alternative fallback | Same exact injected getter error; no writes/events | Covered: [test][test_givenPrincipalReadFails_whenSetAndValidated] |

## Equality versus downstream admission

Config must be active/enabled and the caller permitted. Both changed and unchanged values are independent of Core lifecycle because this setter performs no Core mutation. Debt-cap and complete fee/risk validation still run before equality; unchanged originations return before price/custody support revalidation. An unchanged valid value emits no setter event and makes no FLOAN write. Read-only Core market/Risk selection getters and requireNotReentrant remain permitted. The guard is a settlement-state check, not a Core lifecycle requirement.

## Targeted writes and preservation

Config active/enabled; permitted ADMIN/configOperator caller; changed valid input. Seed unrelated fields to distinct nondefault values so a full-market replay or clobbered packed field is detectable.

| ID | Caller | Expected external writes | Execution / effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-DEBT-CAP-D04 | Fuzz permitted configuration caller | FLOAN.setMarketPrincipalCap(marketId,cap); reject every other FLOAN setter and all Core mutators if called | Success; exact canonical getter/event; preserve Risk/base-fee/originations/configData fields, Core registry, Inventory global cap and claims | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_whenCapChanged] |

## Settlement callbacks

Removing Core.registerMarket must not remove the existing rejection of configuration mutation during a guarded Core settlement. Config checks Core.requireNotReentrant before its first FLOAN write; this view remains usable while Core is inactive/disabled. The nested caller otherwise has current ADMIN/configOperator authority and a changed valid setting.

| ID | Caller | Callback / state | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-DEBT-CAP-C01 | Fuzz permitted configuration caller | Authorized nested setter during a token-transfer callback while Core settlement guard is entered | ReentrancyGuardReentrantCall() | No FLOAN setter, Config setter event or registry update; propagate the callback failure and assert outer transaction rollback | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenCollateralCallback_whenNestedConfigCaught_reverts], [test][test_givenCollateralCallback_whenNestedConfigPropagated] |

## Local lifecycle restoration

Permitted caller; initialized bindings; changed valid input. Seed existing loans and unrelated configuration. Recovery restores the same intended caller authority, not an extra ADMIN grant to a forwarding contract.

| ID | Caller | Restoration sequence | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-DEBT-CAP-L16 | Fuzz ADMIN-only, current configOperator-only or overlap; seed each | Config disabled, then enabled with current direct dependencies ready | Successful setter after local recovery | Same targeted FLOAN fields/event as initial success; loans, unrelated fields and independent operators preserved | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenLocalRecovery_whenCapSet] |
| BLCFG-DEBT-CAP-L17 | Fuzz ADMIN-only, current configOperator-only or overlap; seed each | Previously active Config Kernel-deactivated, then reactivated so module permissions refresh; local enabled state retained | Successful setter after Kernel recovery | Same targeted write set; no permanent permission loss, duplicate registry entry or unrelated accounting change | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenKernelRecovery_whenCapSet] |

## Additional admission coverage

| ID | Caller | Pre-state | Expected behavior | Test |
| --- | --- | --- | --- | --- |
| BLCFG-DEBT-CAP-P05 | Unauthorized caller | Core settlement busy; fuzz own activity/enablement; unchanged cap | ReentrancyGuardReentrantCall before own lifecycle, caller or no-op checks; state unchanged | Covered: [test][test_givenCoreBusy_whenUnauthorizedSetsUnchangedCap_reverts] |

[test_givenAuthorizedCaller_whenCapChanged]: ./setAssetDebtCap.t.sol#L69
[test_whenCallerIsUnauthorized_reverts]: ./setAssetDebtCap.t.sol#L81
[test_givenIndependentCoreState_whenCapChanged]: ./setAssetDebtCap.t.sol#L92
[test_givenConfigActiveDisabled_whenCapSetAndValidated_reverts]: ./setAssetDebtCap.t.sol#L103
[test_givenConfigInactiveEnabled_whenCapSetAndValidated_reverts]: ./setAssetDebtCap.t.sol#L121
[test_givenConfigInactiveDisabled_whenCapSetAndValidated_reverts]: ./setAssetDebtCap.t.sol#L139
[test_givenInvalidCapAndConfigActiveEnabled_whenSetAndValidated_reverts]: ./setAssetDebtCap.t.sol#L158
[test_givenInvalidCapAndConfigActiveDisabled_whenSetAndValidated_reverts]: ./setAssetDebtCap.t.sol#L176
[test_givenInvalidCapAndConfigInactiveEnabled_whenSetAndValidated_reverts]: ./setAssetDebtCap.t.sol#L195
[test_givenInvalidCapAndConfigInactiveDisabled_whenSetAndValidated_reverts]: ./setAssetDebtCap.t.sol#L214
[test_whenAssetIsNotRegistered_reverts]: ./setAssetDebtCap.t.sol#L234
[test_givenIncompatibleSchema_whenSetAndValidated_reverts]: ./setAssetDebtCap.t.sol#L253
[test_givenPrincipal_whenCapIsBelowDebt_reverts]: ./setAssetDebtCap.t.sol#L281
[test_givenMalformedMarketData_whenSetAndValidated_reverts]: ./setAssetDebtCap.t.sol#L300
[test_givenValidFullWidthCap_whenValidated]: ./setAssetDebtCap.t.sol#L326
[test_whenCapBoundaryValuesAreSeeded]: ./setAssetDebtCap.t.sol#L339
[test_whenCapUnchanged]: ./setAssetDebtCap.t.sol#L351
[test_whenAssetCapAboveGlobalCap]: ./setAssetDebtCap.t.sol#L367
[test_givenPrincipalChanges_whenOldCapRevalidated]: ./setAssetDebtCap.t.sol#L379
[test_givenInventoryStateVaries_whenAssetCapChanged]: ./setAssetDebtCap.t.sol#L399
[test_givenConfigNoLongerMarketManager_whenSetAndValidated_reverts]: ./setAssetDebtCap.t.sol#L431
[test_givenSetterPermissionRevoked_whenSetAndValidated_reverts]: ./setAssetDebtCap.t.sol#L447
[test_givenPrincipalReadFails_whenSetAndValidated]: ./setAssetDebtCap.t.sol#L473
[test_whenCapChanged]: ./setAssetDebtCap.t.sol#L488
[test_givenLocalRecovery_whenCapSet]: ./setAssetDebtCap.t.sol#L531
[test_givenKernelRecovery_whenCapSet]: ./setAssetDebtCap.t.sol#L543
[test_givenCollateralCallback_whenNestedConfigCaught_reverts]: ./setAssetDebtCap.t.sol#L555
[test_givenCollateralCallback_whenNestedConfigPropagated]: ./setAssetDebtCap.t.sol#L570
[test_whenPermittedCallerClassesSeeded]: ./setAssetDebtCap.t.sol#L585
[test_givenExistingLoan_whenConfigurationChanged]: ./setAssetDebtCap.t.sol#L597
[test_whenBelowDebtEndpointsSeeded_reverts]: ./setAssetDebtCap.t.sol#L606

[test_givenCoreBusy_whenUnauthorizedSetsUnchangedCap_reverts]: setAssetDebtCap.t.sol#L25
