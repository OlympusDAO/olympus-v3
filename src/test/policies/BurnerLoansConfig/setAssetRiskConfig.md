# BurnerLoansConfig.setAssetRiskConfig coverage plan

Source: [setAssetRiskConfig](../../../policies/burnerloans/BurnerLoansConfig.sol#L386). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCFG-RISK-CONFIG` identifies this contract/function.

Implemented same-value rule: unchanged parameters return without setter writes/events after the concrete checks before equality. Changing-value rows exclude the current value; downstream checks reached only after equality are tested separately.

Own-policy admission: require Kernel-active BurnerLoansConfig; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfig)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Fuzz permitted configuration caller: independently fuzz a nonzero address as ADMIN_ROLE holder, current selected configOperator without ADMIN_ROLE, or both. Guarantee ADMIN-only, operator-only and overlapping seeds. Caller choice is independent of lifecycle flags, inputs and dependency failures. Unauthorized fuzzing excludes all ADMIN_ROLE holders and the selected nonzero configOperator.

ADMIN or configOperator, Config enabled. Full resulting struct validated through selected Risk BEFORE asset lookup. Numeric domains and exact errors are normative in Risk validateRiskConfig plan. No per-field partial update on Config.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

Co-located validator: `validateAssetRiskConfig` is tested in `setAssetRiskConfig.t.sol`, in the same tests as the corresponding setter cases. Call the validator before the mutation against the same relevant state and independently fuzz its caller, including zero and identities without configuration authority. Assert exact input forwarding and no writes/events independently; a successful setter alone does not prove the view. Numeric rejection/success rows and unchanged-value rows must compare both APIs. Use one paired test per behavior. The Caller column describes the setter caller; independently fuzz the permissionless validator caller, including identities without configuration authority.

The validator remains permissionless, but requires the same local enablement and own-policy activity as the setter: BurnerLoans_PolicyNotActive(BurnerLoansConfig) takes precedence over NotEnabled(), and both precede input validation. Shared input and dependency-read failures use the same exact errors. Mutation authorization, the Core settlement guard and downstream writes remain setter-only; validation does not simulate a write. The planned Config validator takes (asset,config), validates the complete struct through the selected Risk, then checks asset registration and canonical market schema/data in the same order as the setter. Risk’s underlying numeric validator remains struct-only; no configuration-operator authority on Risk is required. The additional asset argument and lifecycle checks are acceptance criteria for the implementation pass.

## Scenario setup

Fuzz permitted configuration caller: independently select ADMIN_ROLE or the current nonzero configOperator without ADMIN_ROLE. Guarantee ADMIN-only, operator-only and overlapping identity seeds; caller choice is independent of struct values.

All body inputs and component bindings are compatible unless the row states otherwise. Use the equivalent permitted-caller family above for each applicable row.

## Authorization

Fixed for this table: Local active: true; Local enabled: true; Core active: true; Core enabled: true.

The only permitted identities are every ADMIN_ROLE holder and the current nonzero configOperator. Fuzz the denied caller over EOAs and contracts excluding exactly those identities; retain zero unless it holds ADMIN. Seed a former operator, a BURNER_LOANS_ADMIN_ROLE-only holder, a borrower and an unrelated contract. All inputs are valid and changed, so authorization is the only varying condition.

| ID | Caller | Inputs / pre-state | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-RISK-CONFIG-A01 | Fuzz ADMIN-only, selected nonzero configOperator-only and overlap holders; guarantee each class | Valid changed setting; local/dependency admission satisfied | Success | Exact function-specific canonical update and event; preserve unrelated configuration and accounting | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenAuthorizedCaller_whenCompleteConfigChanged], [test][test_whenPermittedCallerClassesSeeded], [test][test_givenTimelockOperator_whenQueuedAndExecuted] |
| BLCFG-RISK-CONFIG-A02 | Fuzz caller lacking ADMIN_ROLE and unequal to the selected nonzero configOperator | Same otherwise-valid request | NotAuthorised() before input validation or writes | Unchanged; no setter event, Core/FLOAN mutation or token movement | Success for the valid input without requiring setter authority; no writes/events | Covered: [test][test_whenCallerIsUnauthorized_reverts] |

## Lifecycle

Each retained row independently fuzzes Core active/enabled and guarantees all four pairs. These flags do not change this setter's outcome. Local enabled and Kernel membership remain separate fixed conditions with exact errors; no outcome-selecting runner is required.

Use a changed valid setting. Config must itself be active/enabled; existing market lookups remain readable. This setter does not call Core.registerMarket or perform a Core mutation. Core activity/enablement therefore does not gate changed or unchanged values. Keep this distinct from addAsset and setAssetWithdrawAsShares, which synchronize Core.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Input | Execution | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-RISK-CONFIG-L01 | Fuzz permitted configuration caller | true | true | Fuzz false/true | Fuzz false/true | Changed valid setting | Body succeeds | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenIndependentCoreState_whenChanged] |
| BLCFG-RISK-CONFIG-L04 | Fuzz permitted configuration caller | true | false | Fuzz false/true | Fuzz false/true | Changed valid setting | NotEnabled() | NotEnabled(); same error before input validation | Covered: [test][test_givenConfigActiveDisabled_whenSetAndValidated_reverts] |
| BLCFG-RISK-CONFIG-L08 | Fuzz permitted configuration caller | false | true | Fuzz false/true | Fuzz false/true | Changed valid setting | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | BurnerLoans_PolicyNotActive(BurnerLoansConfig); same error before input validation | Covered: [test][test_givenConfigInactiveEnabled_whenSetAndValidated_reverts] |
| BLCFG-RISK-CONFIG-L12 | Fuzz permitted configuration caller | false | false | Fuzz false/true | Fuzz false/true | Changed valid setting | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | BurnerLoans_PolicyNotActive(BurnerLoansConfig); same error before input validation | Covered: [test][test_givenConfigInactiveDisabled_whenSetAndValidated_reverts] |
| BLCFG-VALIDATE-RISK-L05 | Fuzz permitted configuration caller | true | true | Fuzz false/true | Fuzz false/true | maxLtvBps=0 | BurnerLoans_InvalidBps(0) | BurnerLoans_InvalidBps(0); same error and precedence; no writes/events | Covered: [test][test_givenInvalidInputAndConfigActiveEnabled_whenSetAndValidated_reverts] |
| BLCFG-VALIDATE-RISK-L06 | Fuzz permitted configuration caller | true | false | Fuzz false/true | Fuzz false/true | maxLtvBps=0 | NotEnabled() | NotEnabled(); same error before input validation | Covered: [test][test_givenInvalidInputAndConfigActiveDisabled_whenSetAndValidated_reverts] |
| BLCFG-VALIDATE-RISK-L07 | Fuzz permitted configuration caller | false | true | Fuzz false/true | Fuzz false/true | maxLtvBps=0 | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | BurnerLoans_PolicyNotActive(BurnerLoansConfig); same error before input validation | Covered: [test][test_givenInvalidInputAndConfigInactiveEnabled_whenSetAndValidated_reverts] |
| BLCFG-VALIDATE-RISK-L08 | Fuzz permitted configuration caller | false | false | Fuzz false/true | Fuzz false/true | maxLtvBps=0 | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | BurnerLoans_PolicyNotActive(BurnerLoansConfig); same error before input validation | Covered: [test][test_givenInvalidInputAndConfigInactiveDisabled_whenSetAndValidated_reverts] |

Unauthorized fuzz callers exclude ADMIN holders and the selected nonzero configOperator. The local enablement modifier precedes caller authorization. Assert unchanged state for rejection; re-enable/reactivate before retry and verify canonical positions survive. These Core lifecycle rows keep selected Inventory/Custody and required module permissions operational; their separate live failures are tested in the body.

For the invalid-input rows, lifecycle checks precede numerical validation in both APIs. Independently fuzz the validator caller; its permissions do not change the lifecycle or numerical error. No rejected call changes configuration, accounting or committed logs.

## Invalid inputs

Admission passes; earlier fields are valid unless explicitly varied. Numeric rules and exact errors match addAsset and selected Risk. The full struct validator runs before market lookup.

Valid risk domain: maxLtvBps in 1..10000, backingMultiplierBps in 10000..50000, keeperRewardBps in 0..10000, maxKeeperReward in 0..MAX128, termLength in 1..365 days, maxMaturityHorizon in termLength+1..366 days. Fuzz fields independently within those constraints; guarantee each endpoint and maxKeeperReward=0,1,MAX128. Defaults for isolated faults: LTV=7500, backing multiplier=12000, keeper BPS=100, max reward=1, term=30 days, horizon=90 days. For TERM-HIGH, an in-range horizon cannot exceed a MAX48 term; the earlier term-bound rejection is the expected path, so a later term/horizon relationship need not be valid.

| ID | Caller | Invalid field / fuzz domain / seeds | Exact execution error | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-RISK-CONFIG-I01 | Fuzz permitted configuration caller | maxLtvBps=0 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(0)` | Unchanged; no committed logs | `IBurnerLoansRisk.BurnerLoans_InvalidBps(0)`; same numeric rejection before any setter write | Covered: [test][test_whenZeroLtv_reverts] |
| BLCFG-RISK-CONFIG-I02 | Fuzz permitted configuration caller | maxLtvBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(maxLtvBps)` | Unchanged; no committed logs | `IBurnerLoansRisk.BurnerLoans_InvalidBps(maxLtvBps)`; same numeric rejection before any setter write | Covered: [test][test_whenLtvAboveMaximum_reverts], [test][test_whenMaxLtvBpsAboveMaximumEndpointsAreSeeded_reverts] |
| BLCFG-RISK-CONFIG-I03 | Fuzz permitted configuration caller | backingMultiplierBps in 0..9999; seed 0,1,9999 | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | `IBurnerLoansErrors.BurnerLoans_InvalidParam()`; same numeric rejection before any setter write | Covered: [test][test_whenBackingBelowMinimum_reverts], [test][test_whenBackingMultiplierBpsBelowMinimumEndpointsAreSeeded_reverts] |
| BLCFG-RISK-CONFIG-I04 | Fuzz permitted configuration caller | backingMultiplierBps in 50001..MAX16; seed 50001,MAX16 | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | `IBurnerLoansErrors.BurnerLoans_InvalidParam()`; same numeric rejection before any setter write | Covered: [test][test_whenBackingAboveMaximum_reverts], [test][test_whenBackingMultiplierBpsAboveMaximumEndpointsAreSeeded_reverts] |
| BLCFG-RISK-CONFIG-I05 | Fuzz permitted configuration caller | keeperRewardBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(keeperRewardBps)` | Unchanged; no committed logs | `IBurnerLoansRisk.BurnerLoans_InvalidBps(keeperRewardBps)`; same numeric rejection before any setter write | Covered: [test][test_whenKeeperBpsAboveMaximum_reverts], [test][test_whenKeeperRewardBpsAboveMaximumEndpointsAreSeeded_reverts] |
| BLCFG-RISK-CONFIG-I06 | Fuzz permitted configuration caller | termLength=0; horizon=90 days | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | `IBurnerLoansErrors.BurnerLoans_InvalidParam()`; same numeric rejection before any setter write | Covered: [test][test_whenZeroTerm_reverts] |
| BLCFG-RISK-CONFIG-I07 | Fuzz permitted configuration caller | termLength in 365 days+1..MAX48; seed lower bound,MAX48; horizon=366 days | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | `IBurnerLoansErrors.BurnerLoans_InvalidParam()`; same numeric rejection before any setter write | Covered: [test][test_whenTermAboveMaximum_reverts], [test][test_whenTermLengthAboveMaximumEndpointsAreSeeded_reverts] |
| BLCFG-RISK-CONFIG-I08 | Fuzz permitted configuration caller | maxMaturityHorizon=0; termLength=30 days | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | `IBurnerLoansErrors.BurnerLoans_InvalidParam()`; same numeric rejection before any setter write | Covered: [test][test_whenZeroHorizon_reverts] |
| BLCFG-RISK-CONFIG-I09 | Fuzz permitted configuration caller | termLength in 2..365 days; maxMaturityHorizon in 1..termLength-1; seed 1,termLength-1 | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | `IBurnerLoansErrors.BurnerLoans_InvalidParam()`; same numeric rejection before any setter write | Covered: [test][test_whenHorizonBelowTerm_reverts], [test][test_whenHorizonRelationBoundariesSeeded_reverts] |
| BLCFG-RISK-CONFIG-I10 | Fuzz permitted configuration caller | maxMaturityHorizon=termLength; fuzz termLength in 1..365 days; seed 1,365 days | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | `IBurnerLoansErrors.BurnerLoans_InvalidParam()`; same numeric rejection before any setter write | Covered: [test][test_whenHorizonEqualsTerm_reverts], [test][test_whenHorizonRelationBoundariesSeeded_reverts] |
| BLCFG-RISK-CONFIG-I11 | Fuzz permitted configuration caller | maxMaturityHorizon in 366 days+1..MAX48; seed lower bound,MAX48; valid termLength | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | `IBurnerLoansErrors.BurnerLoans_InvalidParam()`; same numeric rejection before any setter write | Covered: [test][test_whenHorizonAboveMaximum_reverts], [test][test_whenMaxMaturityHorizonAboveMaximumEndpointsAreSeeded_reverts] |

| ID | Caller | Asset / competing fault | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-RISK-CONFIG-I12 | Fuzz permitted configuration caller | Unregistered asset; maxLtvBps=0 | IBurnerLoansRisk.BurnerLoans_InvalidBps(0) before asset lookup | No writes or logs | IBurnerLoansRisk.BurnerLoans_InvalidBps(0); same numeric rejection before any setter write | Covered: [test][test_givenInvalidStructAndUnregisteredAsset_whenSetAndValidated_reverts] |
| BLCFG-RISK-CONFIG-I13 | Fuzz permitted configuration caller | Struct valid; unregistered asset | BurnerLoansCore_AssetNotConfigured(asset) | No writes or logs | BurnerLoansCore_AssetNotConfigured(asset); same asset/market rejection; no writes/events | Covered: [test][test_givenValidStructAndUnregisteredAsset_whenSetAndValidated_reverts] |
| BLCFG-RISK-CONFIG-I14 | Fuzz permitted configuration caller | Struct valid; registered market presents another configId after module-state drift | BurnerLoans_IncompatibleMarketConfig(marketId,configId) | No writes or logs | BurnerLoans_IncompatibleMarketConfig(marketId,configId); same asset/market rejection; no writes/events | Covered: [test][test_givenIncompatibleSchema_whenSetAndValidated_reverts] |
| BLCFG-RISK-CONFIG-I15 | Fuzz permitted configuration caller | Struct valid; canonical schema but product data length differs from 224 bytes; fuzz lengths 0..223 and 225..256 | BurnerLoans_InvalidMarketConfigData(marketId,length) | No writes or logs | BurnerLoans_InvalidMarketConfigData(marketId,length); same asset/market rejection; no writes/events | Covered: [test][test_givenMalformedMarketData_whenSetAndValidated_reverts] |

## Configuration transitions

Risk changes affect existing health/seizure rules immediately, without a cohort snapshot. Existing loan maturities remain unchanged; later borrowing/extension follows the new terms. Preserve fee fields, originations, decimals, cap and withdrawal mode.

## Successful execution

Configured asset; independently fuzz the full valid risk domain above and the permitted caller. Assert exact field storage and getters, isolate other assets, and preserve collateral, debt, provider claims, pending payouts and unrelated configuration.

| ID | Caller | Configuration input | Execution / proof | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-RISK-CONFIG-P01 | Fuzz permitted configuration caller | Full valid domain; force at least one selected field to differ from current value | Apply full struct; exact AssetRiskConfigSet event; getters match input | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenAuthorizedCaller_whenCompleteConfigChanged], [test][test_whenFullValidRiskDomainIsUsed], [test][test_givenTimelockOperator_whenQueuedAndExecuted], [test][test_givenExistingLoan_whenRiskTightened] |
| BLCFG-RISK-CONFIG-P02 | Fuzz permitted configuration caller | Identical valid struct | No-op after implemented validation | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_whenConfigurationUnchanged] |
| BLCFG-RISK-CONFIG-P03 | Fuzz permitted configuration caller | Maximum scalar bounds and maxKeeperReward=MAX128; separate min/zero keeper fixtures | Success; same accepted boundaries as initial addAsset | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_whenMinimumRiskFields], [test][test_whenMaximumRiskFields], [test][test_whenMaximumKeeperReward] |
| BLCFG-VALIDATE-RISK-N13 | Fuzz permitted configuration caller | LTV=1, backing=10000, keeper=0, reward=0, term=1 second, horizon=2 seconds | Success; exact canonical update/event, or unchanged-value no-op | Success; exact full struct forwarded to selected Risk; no writes/events | Covered: [test][test_whenMinimumRiskFields] |
| BLCFG-VALIDATE-RISK-N14 | Fuzz permitted configuration caller | LTV=10000, backing=50000, keeper=10000, reward=MAX128, term=365 days, horizon=366 days | Success; exact canonical update/event, or unchanged-value no-op | Success; exact full struct forwarded to selected Risk; no writes/events | Covered: [test][test_whenMaximumRiskFields] |
| BLCFG-VALIDATE-RISK-N15 | Fuzz permitted configuration caller | maxKeeperReward=MAX128 with other valid defaults; no arbitrary reward cap | Success; exact canonical update/event, or unchanged-value no-op | Success; exact full struct forwarded to selected Risk; no writes/events | Covered: [test][test_whenMaximumKeeperReward] |

## Atomic rollback

Fixed for this table: Accounting / events: All multi-setter writes rollback.

| ID | Caller | Input / pre-state | Execution / return | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-RISK-CONFIG-P04 | Fuzz permitted configuration caller | Later required FLOAN write fails | Exact error | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenLateFloanWriteFails_whenChanged] |

## Shared assertions

For risk: existing health and seizure eligibility use new rules immediately; term change does not overwrite loan maturity but next borrow episode/extension uses it. Fee, decimals, originations, cap and withdrawal mode stay preserved. For fee: current debt determines utilization; no custody or fee collection occurs during configuration.

Co-located API assertions: `getAssetConfig`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Equality versus downstream admission

Config must be active/enabled and the caller permitted. Both changed and unchanged values are independent of Core lifecycle because this setter performs no Core mutation. Debt-cap and complete fee/risk validation still run before equality; unchanged originations return before price/custody support revalidation. An unchanged valid value emits no setter event and makes no FLOAN write. Read-only Core market/Risk selection getters and requireNotReentrant remain permitted. The guard is a settlement-state check, not a Core lifecycle requirement.

## Targeted writes and preservation

Config active/enabled; permitted ADMIN/configOperator caller; changed valid input. Seed unrelated fields to distinct nondefault values so a full-market replay or clobbered packed field is detectable.

| ID | Caller | Expected external writes | Execution / effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-RISK-CONFIG-D01 | Fuzz permitted configuration caller | FLOAN.setMarketRiskConfig and FLOAN.setMarketConfigData for complete product risk fields; reject every other FLOAN setter and all Core mutators if called | Success; exact canonical getter/event; preserve Fee curve/base fee, cap, originations, withdrawal mode, Core registry and Inventory/Payout ledgers | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_whenChanged], [test][test_givenNondefaultShareMode_whenConfigurationChanged] |

## Settlement callbacks

Removing Core.registerMarket must not remove the existing rejection of configuration mutation during a guarded Core settlement. Config checks Core.requireNotReentrant before its first FLOAN write; this view remains usable while Core is inactive/disabled. The nested caller otherwise has current ADMIN/configOperator authority and a changed valid setting.

| ID | Caller | Callback / state | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-RISK-CONFIG-C01 | Fuzz permitted configuration caller | Authorized nested setter during a token-transfer callback while Core settlement guard is entered | ReentrancyGuardReentrantCall() | No FLOAN setter, Config setter event or registry update; propagate the callback failure and assert outer transaction rollback | Success; the settlement guard protects mutation only; no writes/events | Covered: [test][test_givenCollateralCallback_whenNestedConfigCaught_reverts], [test][test_givenCollateralCallback_whenNestedConfigPropagated] |

## Public Risk validation without configuration authority

Config active/enabled; permitted caller; canonical market and requested complete struct valid. Risk's public numeric validator is not a configuration mutation. Core's selected Risk is readable; no ADMIN grant is assigned to Config on Risk.

| ID | Caller | Risk operator | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-RISK-CONFIG-D02 | Fuzz permitted configuration caller | Zero, Config, BLCT or another controller; guarantee each identity class | Success | Forward exact struct to the public validator; update only relevant FLOAN fields; no Risk setter/operator write and no Core registry synchronization | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenRiskHasIndependentController_whenChanged] |

| ID | Caller | Dependency state | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-VALIDATE-RISK-D01 | Fuzz permitted configuration caller | Facility bound, Core.risk()=0 before Risk installation | Exact empty external-call revert for absent contract code | No fallback validator | Exact empty external-call revert for absent contract code; same dependency-read failure; no writes/events | Covered: [test][test_givenRiskUnset_whenSetAndValidated_reverts] |
| BLCFG-VALIDATE-RISK-D02 | Fuzz permitted configuration caller | Selected mock Risk raises BurnerLoans_InvalidParam() | Exact injected BurnerLoans_InvalidParam() propagates | After lifecycle checks, stop before market lookup or writes | Exact injected BurnerLoans_InvalidParam() propagates; same dependency-read failure; no writes/events | Covered: [test][test_givenRiskRejectsStruct_whenSetAndValidated] |
| BLCFG-VALIDATE-RISK-D03 | Fuzz permitted configuration caller | OCG installs a valid Core-bound new Risk between calls | Success; validates the exact full struct through newly selected Risk before any FLOAN write | Old validator not called; no cached result | Success; second call forwards to new Risk only; no cached result or writes/events | Covered: [test][test_givenRiskReplaced_whenValidating] |

## Local lifecycle restoration

Permitted caller; initialized bindings; changed valid input. Seed existing loans and unrelated configuration. Recovery restores the same intended caller authority, not an extra ADMIN grant to a forwarding contract.

| ID | Caller | Restoration sequence | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-RISK-CONFIG-L16 | Fuzz ADMIN-only, current configOperator-only or overlap; seed each | Config disabled, then enabled with current direct dependencies ready | Successful setter after local recovery | Same targeted FLOAN fields/event as initial success; loans, unrelated fields and independent operators preserved | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenLocalRecovery_whenChanged] |
| BLCFG-RISK-CONFIG-L17 | Fuzz ADMIN-only, current configOperator-only or overlap; seed each | Previously active Config Kernel-deactivated, then reactivated so module permissions refresh; local enabled state retained | Successful setter after Kernel recovery | Same targeted write set; no permanent permission loss, duplicate registry entry or unrelated accounting change | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenKernelRecovery_whenChanged] |

[test_givenAuthorizedCaller_whenCompleteConfigChanged]: ./setAssetRiskConfig.t.sol#L67
[test_whenCallerIsUnauthorized_reverts]: ./setAssetRiskConfig.t.sol#L78
[test_givenIndependentCoreState_whenChanged]: ./setAssetRiskConfig.t.sol#L90
[test_givenConfigActiveDisabled_whenSetAndValidated_reverts]: ./setAssetRiskConfig.t.sol#L103
[test_givenConfigInactiveEnabled_whenSetAndValidated_reverts]: ./setAssetRiskConfig.t.sol#L121
[test_givenConfigInactiveDisabled_whenSetAndValidated_reverts]: ./setAssetRiskConfig.t.sol#L135
[test_givenInvalidInputAndConfigActiveEnabled_whenSetAndValidated_reverts]: ./setAssetRiskConfig.t.sol#L150
[test_givenInvalidInputAndConfigActiveDisabled_whenSetAndValidated_reverts]: ./setAssetRiskConfig.t.sol#L168
[test_givenInvalidInputAndConfigInactiveEnabled_whenSetAndValidated_reverts]: ./setAssetRiskConfig.t.sol#L187
[test_givenInvalidInputAndConfigInactiveDisabled_whenSetAndValidated_reverts]: ./setAssetRiskConfig.t.sol#L202
[test_whenZeroLtv_reverts]: ./setAssetRiskConfig.t.sol#L218
[test_whenLtvAboveMaximum_reverts]: ./setAssetRiskConfig.t.sol#L233
[test_whenBackingBelowMinimum_reverts]: ./setAssetRiskConfig.t.sol#L252
[test_whenBackingAboveMaximum_reverts]: ./setAssetRiskConfig.t.sol#L268
[test_whenKeeperBpsAboveMaximum_reverts]: ./setAssetRiskConfig.t.sol#L284
[test_whenZeroTerm_reverts]: ./setAssetRiskConfig.t.sol#L303
[test_whenTermAboveMaximum_reverts]: ./setAssetRiskConfig.t.sol#L318
[test_whenZeroHorizon_reverts]: ./setAssetRiskConfig.t.sol#L335
[test_whenHorizonBelowTerm_reverts]: ./setAssetRiskConfig.t.sol#L350
[test_whenHorizonEqualsTerm_reverts]: ./setAssetRiskConfig.t.sol#L368
[test_whenHorizonAboveMaximum_reverts]: ./setAssetRiskConfig.t.sol#L385
[test_givenInvalidStructAndUnregisteredAsset_whenSetAndValidated_reverts]: ./setAssetRiskConfig.t.sol#L401
[test_givenValidStructAndUnregisteredAsset_whenSetAndValidated_reverts]: ./setAssetRiskConfig.t.sol#L417
[test_givenIncompatibleSchema_whenSetAndValidated_reverts]: ./setAssetRiskConfig.t.sol#L435
[test_givenMalformedMarketData_whenSetAndValidated_reverts]: ./setAssetRiskConfig.t.sol#L461
[test_whenConfigurationUnchanged]: ./setAssetRiskConfig.t.sol#L488
[test_givenLateFloanWriteFails_whenChanged]: ./setAssetRiskConfig.t.sol#L505
[test_whenChanged]: ./setAssetRiskConfig.t.sol#L525
[test_givenRiskHasIndependentController_whenChanged]: ./setAssetRiskConfig.t.sol#L555
[test_givenRiskUnset_whenSetAndValidated_reverts]: ./setAssetRiskConfig.t.sol#L570
[test_givenRiskRejectsStruct_whenSetAndValidated]: ./setAssetRiskConfig.t.sol#L582
[test_givenRiskReplaced_whenValidating]: ./setAssetRiskConfig.t.sol#L600
[test_givenLocalRecovery_whenChanged]: ./setAssetRiskConfig.t.sol#L622
[test_givenKernelRecovery_whenChanged]: ./setAssetRiskConfig.t.sol#L634
[test_whenMinimumRiskFields]: ./setAssetRiskConfig.t.sol#L646
[test_whenMaximumRiskFields]: ./setAssetRiskConfig.t.sol#L663
[test_whenMaximumKeeperReward]: ./setAssetRiskConfig.t.sol#L680
[test_whenFullValidRiskDomainIsUsed]: ./setAssetRiskConfig.t.sol#L697
[test_givenCollateralCallback_whenNestedConfigCaught_reverts]: ./setAssetRiskConfig.t.sol#L717
[test_givenCollateralCallback_whenNestedConfigPropagated]: ./setAssetRiskConfig.t.sol#L732
[test_whenPermittedCallerClassesSeeded]: ./setAssetRiskConfig.t.sol#L747
[test_whenMaxLtvBpsAboveMaximumEndpointsAreSeeded_reverts]: ./setAssetRiskConfig.t.sol#L768
[test_whenBackingMultiplierBpsBelowMinimumEndpointsAreSeeded_reverts]: ./setAssetRiskConfig.t.sol#L791
[test_whenBackingMultiplierBpsAboveMaximumEndpointsAreSeeded_reverts]: ./setAssetRiskConfig.t.sol#L814
[test_whenKeeperRewardBpsAboveMaximumEndpointsAreSeeded_reverts]: ./setAssetRiskConfig.t.sol#L831
[test_whenTermLengthAboveMaximumEndpointsAreSeeded_reverts]: ./setAssetRiskConfig.t.sol#L854
[test_whenMaxMaturityHorizonAboveMaximumEndpointsAreSeeded_reverts]: ./setAssetRiskConfig.t.sol#L871
[test_givenTimelockOperator_whenQueuedAndExecuted]: ./setAssetRiskConfig.t.sol#L888
[test_givenExistingLoan_whenRiskTightened]: ./setAssetRiskConfig.t.sol#L918
[test_givenNondefaultShareMode_whenConfigurationChanged]: ./setAssetRiskConfig.t.sol#L965
[test_whenHorizonRelationBoundariesSeeded_reverts]: ./setAssetRiskConfig.t.sol#L979
