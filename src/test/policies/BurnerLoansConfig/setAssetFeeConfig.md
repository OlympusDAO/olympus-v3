# BurnerLoansConfig.setAssetFeeConfig coverage plan

Source: [setAssetFeeConfig](../../../policies/burnerloans/BurnerLoansConfig.sol#L352). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCFG-FEE-CONFIG` identifies this contract/function.

Implemented same-value rule: unchanged parameters return without setter writes/events after the concrete checks before equality. Changing-value rows exclude the current value; downstream checks reached only after equality are tested separately.

Own-policy admission: require Kernel-active BurnerLoansConfig; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfig)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Fuzz permitted configuration caller: independently fuzz a nonzero address as ADMIN_ROLE holder, current selected configOperator without ADMIN_ROLE, or both. Guarantee ADMIN-only, operator-only and overlapping seeds. Caller choice is independent of lifecycle flags, inputs and dependency failures. Unauthorized fuzzing excludes all ADMIN_ROLE holders and the selected nonzero configOperator.

ADMIN or configOperator, Config enabled. Full resulting struct validated through selected Risk BEFORE asset lookup. Numeric domains and exact errors are normative in Risk validateFeeConfig plan. No per-field partial update on Config.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

Co-located validator: `validateFeeConfig` is tested in `setAssetFeeConfig.t.sol`, in the same tests as the corresponding setter cases. Call the validator before the mutation against the same relevant state and independently fuzz its caller, including zero and identities without configuration authority. Assert exact input forwarding and no writes/events independently; a successful setter alone does not prove the view. Numeric rejection/success rows and unchanged-value rows must compare both APIs. Use one paired test per behavior. The Caller column describes the setter caller; independently fuzz the permissionless validator caller, including identities without configuration authority.

The validator remains permissionless, but requires the same local enablement and own-policy activity as the setter: BurnerLoans_PolicyNotActive(BurnerLoansConfig) takes precedence over NotEnabled(), and both precede input validation. Shared input and dependency-read failures use the same exact errors. Mutation authorization, the Core settlement guard and downstream writes remain setter-only; validation does not simulate a write. The planned Config validator takes (asset,config), validates the complete struct through the selected Risk, then checks asset registration and canonical market schema/data in the same order as the setter. Risk’s underlying numeric validator remains struct-only; no configuration-operator authority on Risk is required. The additional asset argument and lifecycle checks are acceptance criteria for the implementation pass.

## Scenario setup

Fuzz permitted configuration caller: independently select ADMIN_ROLE or the current nonzero configOperator without ADMIN_ROLE. Guarantee ADMIN-only, operator-only and overlapping identity seeds; caller choice is independent of struct values.

All body inputs and component bindings are compatible unless the row states otherwise. Use the equivalent permitted-caller family above for each applicable row.

## Authorization

Fixed for this table: Local active: true; Local enabled: true; Core active: true; Core enabled: true.

The only permitted identities are every ADMIN_ROLE holder and the current nonzero configOperator. Fuzz the denied caller over EOAs and contracts excluding exactly those identities; retain zero unless it holds ADMIN. Seed a former operator, a BURNER_LOANS_ADMIN_ROLE-only holder, a borrower and an unrelated contract. All inputs are valid and changed, so authorization is the only varying condition.

| ID | Caller | Inputs / pre-state | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-FEE-CONFIG-A01 | Fuzz ADMIN-only, selected nonzero configOperator-only and overlap holders; guarantee each class | Valid changed setting; local/dependency admission satisfied | Success | Exact function-specific canonical update and event; preserve unrelated configuration and accounting | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenAuthorizedCaller_whenCompleteConfigChanged], [test][test_whenPermittedCallerClassesSeeded], [test][test_givenTimelockOperator_whenQueuedAndExecuted] |
| BLCFG-FEE-CONFIG-A02 | Fuzz caller lacking ADMIN_ROLE and unequal to the selected nonzero configOperator | Same otherwise-valid request | NotAuthorised() before input validation or writes | Unchanged; no setter event, Core/FLOAN mutation or token movement | Success for the valid input without requiring setter authority; no writes/events | Covered: [test][test_whenCallerIsUnauthorized_reverts] |

## Lifecycle

Each retained row independently fuzzes Core active/enabled and guarantees all four pairs. These flags do not change this setter's outcome. Local enabled and Kernel membership remain separate fixed conditions with exact errors; no outcome-selecting runner is required.

Use a changed valid setting. Config must itself be active/enabled; existing market lookups remain readable. This setter does not call Core.registerMarket or perform a Core mutation. Core activity/enablement therefore does not gate changed or unchanged values. Keep this distinct from addAsset and setAssetWithdrawAsShares, which synchronize Core.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Input | Execution | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-FEE-CONFIG-L01 | Fuzz permitted configuration caller | true | true | Fuzz false/true | Fuzz false/true | Changed valid setting | Body succeeds | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenIndependentCoreState_whenChanged] |
| BLCFG-FEE-CONFIG-L04 | Fuzz permitted configuration caller | true | false | Fuzz false/true | Fuzz false/true | Changed valid setting | NotEnabled() | NotEnabled(); same error before input validation | Covered: [test][test_givenConfigActiveDisabled_whenSetAndValidated_reverts] |
| BLCFG-FEE-CONFIG-L08 | Fuzz permitted configuration caller | false | true | Fuzz false/true | Fuzz false/true | Changed valid setting | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | BurnerLoans_PolicyNotActive(BurnerLoansConfig); same error before input validation | Covered: [test][test_givenConfigInactiveEnabled_whenSetAndValidated_reverts] |
| BLCFG-FEE-CONFIG-L12 | Fuzz permitted configuration caller | false | false | Fuzz false/true | Fuzz false/true | Changed valid setting | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | BurnerLoans_PolicyNotActive(BurnerLoansConfig); same error before input validation | Covered: [test][test_givenConfigInactiveDisabled_whenSetAndValidated_reverts] |
| BLCFG-VALIDATE-FEE-L05 | Fuzz permitted configuration caller | true | true | Fuzz false/true | Fuzz false/true | baseFeeBps=10001 | BurnerLoans_InvalidBps(10001) | BurnerLoans_InvalidBps(10001); same error and precedence; no writes/events | Covered: [test][test_givenInvalidInputAndConfigActiveEnabled_whenSetAndValidated_reverts] |
| BLCFG-VALIDATE-FEE-L06 | Fuzz permitted configuration caller | true | false | Fuzz false/true | Fuzz false/true | baseFeeBps=10001 | NotEnabled() | NotEnabled(); same error before input validation | Covered: [test][test_givenInvalidInputAndConfigActiveDisabled_whenSetAndValidated_reverts] |
| BLCFG-VALIDATE-FEE-L07 | Fuzz permitted configuration caller | false | true | Fuzz false/true | Fuzz false/true | baseFeeBps=10001 | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | BurnerLoans_PolicyNotActive(BurnerLoansConfig); same error before input validation | Covered: [test][test_givenInvalidInputAndConfigInactiveEnabled_whenSetAndValidated_reverts] |
| BLCFG-VALIDATE-FEE-L08 | Fuzz permitted configuration caller | false | false | Fuzz false/true | Fuzz false/true | baseFeeBps=10001 | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | BurnerLoans_PolicyNotActive(BurnerLoansConfig); same error before input validation | Covered: [test][test_givenInvalidInputAndConfigInactiveDisabled_whenSetAndValidated_reverts] |

Unauthorized fuzz callers exclude ADMIN holders and the selected nonzero configOperator. The local enablement modifier precedes caller authorization. Assert unchanged state for rejection; re-enable/reactivate before retry and verify canonical positions survive. These Core lifecycle rows keep selected Inventory/Custody and required module permissions operational; their separate live failures are tested in the body.

For the invalid-input rows, lifecycle checks precede numerical validation in both APIs. Independently fuzz the validator caller; its permissions do not change the lifecycle or numerical error. No rejected call changes configuration, accounting or committed logs.

## Invalid inputs

Admission passes; earlier fields are valid unless explicitly varied. Numeric rules and exact errors match addAsset and selected Risk. The full struct validator runs before market lookup.

Valid fee domain: baseFeeBps, preKinkSlopeBps and postKinkSlopeBps each in 0..10000; their sum is <=10000; kinkBps in 0..9999, with kink=0 allowed only when both slopes are zero. Fuzz base first, then pre within the remaining budget, then post within the remaining budget; choose kink=0..9999 for zero slopes and 1..9999 otherwise. Guarantee zero, one, exact BPS-cap and kink=9999 seeds. Defaults for isolated faults: base=100, kink=5000, pre=200, post=300. Slopes need not be monotonic; seed pre>post as a valid example.

| ID | Caller | Invalid field / fuzz domain / seeds | Exact execution error | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-FEE-CONFIG-I01 | Fuzz permitted configuration caller | baseFeeBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(baseFeeBps)` | Unchanged; no committed logs | `IBurnerLoansRisk.BurnerLoans_InvalidBps(baseFeeBps)`; same numeric rejection before any setter write | Covered: [test][test_whenBaseFeeAboveMaximum_reverts], [test][test_whenBaseFeeBpsAboveMaximumEndpointsAreSeeded_reverts] |
| BLCFG-FEE-CONFIG-I02 | Fuzz permitted configuration caller | preKinkSlopeBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(preKinkSlopeBps)` | Unchanged; no committed logs | `IBurnerLoansRisk.BurnerLoans_InvalidBps(preKinkSlopeBps)`; same numeric rejection before any setter write | Covered: [test][test_whenPreKinkSlopeAboveMaximum_reverts], [test][test_whenPreKinkSlopeBpsAboveMaximumEndpointsAreSeeded_reverts] |
| BLCFG-FEE-CONFIG-I03 | Fuzz permitted configuration caller | postKinkSlopeBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(postKinkSlopeBps)` | Unchanged; no committed logs | `IBurnerLoansRisk.BurnerLoans_InvalidBps(postKinkSlopeBps)`; same numeric rejection before any setter write | Covered: [test][test_whenPostKinkSlopeAboveMaximum_reverts], [test][test_whenPostKinkSlopeBpsAboveMaximumEndpointsAreSeeded_reverts] |
| BLCFG-FEE-CONFIG-I04 | Fuzz permitted configuration caller | kinkBps in 10000..MAX16; seed 10000,MAX16; other BPS fields valid | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()` | Unchanged; no committed logs | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()`; same numeric rejection before any setter write | Covered: [test][test_whenKinkAtOrAboveMaximum_reverts], [test][test_whenKinkBpsAtOrAboveMaximumEndpointsAreSeeded_reverts] |
| BLCFG-FEE-CONFIG-I05 | Fuzz permitted configuration caller | kinkBps=0; preKinkSlopeBps in 1..10000; postKinkSlopeBps=0; baseFeeBps=0 | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()` | Unchanged; no committed logs | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()`; same numeric rejection before any setter write | Covered: [test][test_whenZeroKinkAndPositivePreSlope_reverts] |
| BLCFG-FEE-CONFIG-I06 | Fuzz permitted configuration caller | kinkBps=0; preKinkSlopeBps=0; postKinkSlopeBps in 1..10000; baseFeeBps=0 | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()` | Unchanged; no committed logs | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()`; same numeric rejection before any setter write | Covered: [test][test_whenZeroKinkAndPositivePostSlope_reverts] |
| BLCFG-FEE-CONFIG-I07 | Fuzz permitted configuration caller | Each component in 0..10000; kinkBps in 1..9999; sum=base+pre+post in 10001..30000; seed totals 10001,30000 and single-slope tuples (5000,5001,0), (5000,0,5001) | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()` | Unchanged; no committed logs | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()`; same numeric rejection before any setter write | Covered: [test][test_whenTotalAboveMaximum_reverts] |

| ID | Caller | Asset / competing fault | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-FEE-CONFIG-I08 | Fuzz permitted configuration caller | Unregistered asset; baseFeeBps=10001 | IBurnerLoansRisk.BurnerLoans_InvalidBps(10001) before asset lookup | No writes or logs | IBurnerLoansRisk.BurnerLoans_InvalidBps(10001); same numeric rejection before any setter write | Covered: [test][test_givenInvalidStructAndUnregisteredAsset_whenSetAndValidated_reverts] |
| BLCFG-FEE-CONFIG-I09 | Fuzz permitted configuration caller | Struct valid; unregistered asset | BurnerLoansCore_AssetNotConfigured(asset) | No writes or logs | BurnerLoansCore_AssetNotConfigured(asset); same asset/market rejection; no writes/events | Covered: [test][test_givenValidStructAndUnregisteredAsset_whenSetAndValidated_reverts] |
| BLCFG-FEE-CONFIG-I10 | Fuzz permitted configuration caller | Struct valid; registered market presents another configId after module-state drift | BurnerLoans_IncompatibleMarketConfig(marketId,configId) | No writes or logs | BurnerLoans_IncompatibleMarketConfig(marketId,configId); same asset/market rejection; no writes/events | Covered: [test][test_givenIncompatibleSchema_whenSetAndValidated_reverts] |
| BLCFG-FEE-CONFIG-I11 | Fuzz permitted configuration caller | Struct valid; canonical schema but product data length differs from 224 bytes; fuzz lengths 0..223 and 225..256 | BurnerLoans_InvalidMarketConfigData(marketId,length) | No writes or logs | BurnerLoans_InvalidMarketConfigData(marketId,length); same asset/market rejection; no writes/events | Covered: [test][test_givenMalformedMarketData_whenSetAndValidated_reverts] |

## Configuration transitions

Update the full four-field fee curve without collecting fees or moving tokens. Preserve risk/term fields, originations, decimals, cap and withdrawal mode. Existing utilization determines quotes under the new curve.

## Successful execution

Configured asset; independently fuzz the full valid fee domain above and the permitted caller. Assert exact field storage and getters, isolate other assets, and preserve collateral, debt, provider claims, pending payouts and unrelated configuration.

| ID | Caller | Configuration input | Execution / proof | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-FEE-CONFIG-P01 | Fuzz permitted configuration caller | Full valid domain; force at least one selected field to differ from current value | Apply full struct; exact AssetFeeConfigSet event; getters match input | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenAuthorizedCaller_whenCompleteConfigChanged], [test][test_whenFullValidFeeDomainIsUsed], [test][test_givenTimelockOperator_whenQueuedAndExecuted], [test][test_givenExistingLoan_whenConfigurationChanged] |
| BLCFG-FEE-CONFIG-P02 | Fuzz permitted configuration caller | Identical valid struct | No-op after implemented validation | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_whenConfigurationUnchanged] |
| BLCFG-FEE-CONFIG-P03 | Fuzz permitted configuration caller | Zero-kink flat fees and total=10000 with pre>post | Success; same accepted boundaries as initial addAsset | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_whenZeroFee], [test][test_whenMaximumFlatFee], [test][test_whenMaximumPreSlope], [test][test_whenMaximumKink], [test][test_whenDecreasingSlopes] |
| BLCFG-VALIDATE-FEE-N09 | Fuzz permitted configuration caller | base=pre=post=kink=0 | Success; exact canonical update/event, or unchanged-value no-op | Success; exact full struct forwarded to selected Risk; no writes/events | Covered: [test][test_whenZeroFee] |
| BLCFG-VALIDATE-FEE-N10 | Fuzz permitted configuration caller | base=10000, pre=post=kink=0 | Success; exact canonical update/event, or unchanged-value no-op | Success; exact full struct forwarded to selected Risk; no writes/events | Covered: [test][test_whenMaximumFlatFee] |
| BLCFG-VALIDATE-FEE-N11 | Fuzz permitted configuration caller | base=0,pre=10000,post=0,kink=1; exact total10000 | Success; exact canonical update/event, or unchanged-value no-op | Success; exact full struct forwarded to selected Risk; no writes/events | Covered: [test][test_whenMaximumPreSlope] |
| BLCFG-VALIDATE-FEE-N12 | Fuzz permitted configuration caller | kink=9999, otherwise valid defaults | Success; exact canonical update/event, or unchanged-value no-op | Success; exact full struct forwarded to selected Risk; no writes/events | Covered: [test][test_whenMaximumKink] |
| BLCFG-VALIDATE-FEE-N13 | Fuzz permitted configuration caller | base=0,pre=6000,post=4000,kink=5000; pre>post valid | Success; exact canonical update/event, or unchanged-value no-op | Success; exact full struct forwarded to selected Risk; no writes/events | Covered: [test][test_whenDecreasingSlopes] |

## Atomic rollback

Fixed for this table: Accounting / events: All multi-setter writes rollback.

| ID | Caller | Input / pre-state | Execution / return | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-FEE-CONFIG-P04 | Fuzz permitted configuration caller | Later required FLOAN write fails | Exact error | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenLateFloanWriteFails_whenChanged] |

## Shared assertions

For risk: existing health and seizure eligibility use new rules immediately; term change does not overwrite loan maturity but next borrow episode/extension uses it. Fee, decimals, originations, cap and withdrawal mode stay preserved. For fee: current debt determines utilization; no custody or fee collection occurs during configuration.

Co-located API assertions: `getAssetFeeConfig`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Equality versus downstream admission

Config must be active/enabled and the caller permitted. Both changed and unchanged values are independent of Core lifecycle because this setter performs no Core mutation. Debt-cap and complete fee/risk validation still run before equality; unchanged originations return before price/custody support revalidation. An unchanged valid value emits no setter event and makes no FLOAN write. Read-only Core market/Risk selection getters and requireNotReentrant remain permitted. The guard is a settlement-state check, not a Core lifecycle requirement.

## Targeted writes and preservation

Config active/enabled; permitted ADMIN/configOperator caller; changed valid input. Seed unrelated fields to distinct nondefault values so a full-market replay or clobbered packed field is detectable.

| ID | Caller | Expected external writes | Execution / effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-FEE-CONFIG-D01 | Fuzz permitted configuration caller | FLOAN.setMarketBaseFee and FLOAN.setMarketConfigData for the complete fee curve; reject every other FLOAN setter and all Core mutators if called | Success; exact canonical getter/event; preserve Non-fee packed data, risk terms/LTV, cap, originations, Core registry and Inventory/Payout ledgers | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_whenChanged], [test][test_givenNondefaultShareMode_whenConfigurationChanged] |

## Settlement callbacks

Removing Core.registerMarket must not remove the existing rejection of configuration mutation during a guarded Core settlement. Config checks Core.requireNotReentrant before its first FLOAN write; this view remains usable while Core is inactive/disabled. The nested caller otherwise has current ADMIN/configOperator authority and a changed valid setting.

| ID | Caller | Callback / state | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-FEE-CONFIG-C01 | Fuzz permitted configuration caller | Authorized nested setter during a token-transfer callback while Core settlement guard is entered | ReentrancyGuardReentrantCall() | No FLOAN setter, Config setter event or registry update; propagate the callback failure and assert outer transaction rollback | Success; the settlement guard protects mutation only; no writes/events | Covered: [test][test_givenCollateralCallback_whenNestedConfigCaught_reverts], [test][test_givenCollateralCallback_whenNestedConfigPropagated] |

## Public Risk validation without configuration authority

Config active/enabled; permitted caller; canonical market and requested complete struct valid. Risk's public numeric validator is not a configuration mutation. Core's selected Risk is readable; no ADMIN grant is assigned to Config on Risk.

| ID | Caller | Risk operator | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-FEE-CONFIG-D02 | Fuzz permitted configuration caller | Zero, Config, BLCT or another controller; guarantee each identity class | Success | Forward exact struct to the public validator; update only relevant FLOAN fields; no Risk setter/operator write and no Core registry synchronization | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenRiskHasIndependentController_whenChanged] |

| ID | Caller | Dependency state | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-VALIDATE-FEE-D01 | Fuzz permitted configuration caller | Facility bound, Core.risk()=0 before Risk installation | Exact empty external-call revert for absent contract code | No fallback validator | Exact empty external-call revert for absent contract code; same dependency-read failure; no writes/events | Covered: [test][test_givenRiskUnset_whenSetAndValidated_reverts] |
| BLCFG-VALIDATE-FEE-D02 | Fuzz permitted configuration caller | Selected mock Risk raises BurnerLoans_InvalidParam() | Exact injected BurnerLoans_InvalidParam() propagates | After lifecycle checks, stop before market lookup or writes | Exact injected BurnerLoans_InvalidParam() propagates; same dependency-read failure; no writes/events | Covered: [test][test_givenRiskRejectsStruct_whenSetAndValidated] |
| BLCFG-VALIDATE-FEE-D03 | Fuzz permitted configuration caller | OCG installs a valid Core-bound new Risk between calls | Success; validates the exact full struct through newly selected Risk before any FLOAN write | Old validator not called; no cached result | Success; second call forwards to new Risk only; no cached result or writes/events | Covered: [test][test_givenRiskReplaced_whenValidating] |

## Local lifecycle restoration

Permitted caller; initialized bindings; changed valid input. Seed existing loans and unrelated configuration. Recovery restores the same intended caller authority, not an extra ADMIN grant to a forwarding contract.

| ID | Caller | Restoration sequence | Execution | Effects | Validator / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-FEE-CONFIG-L16 | Fuzz ADMIN-only, current configOperator-only or overlap; seed each | Config disabled, then enabled with current direct dependencies ready | Successful setter after local recovery | Same targeted FLOAN fields/event as initial success; loans, unrelated fields and independent operators preserved | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenLocalRecovery_whenChanged] |
| BLCFG-FEE-CONFIG-L17 | Fuzz ADMIN-only, current configOperator-only or overlap; seed each | Previously active Config Kernel-deactivated, then reactivated so module permissions refresh; local enabled state retained | Successful setter after Kernel recovery | Same targeted write set; no permanent permission loss, duplicate registry entry or unrelated accounting change | Success for the same valid input after local lifecycle checks; no writes/events | Covered: [test][test_givenKernelRecovery_whenChanged] |

[test_givenAuthorizedCaller_whenCompleteConfigChanged]: ./setAssetFeeConfig.t.sol#L60
[test_whenCallerIsUnauthorized_reverts]: ./setAssetFeeConfig.t.sol#L71
[test_givenIndependentCoreState_whenChanged]: ./setAssetFeeConfig.t.sol#L83
[test_givenConfigActiveDisabled_whenSetAndValidated_reverts]: ./setAssetFeeConfig.t.sol#L96
[test_givenConfigInactiveEnabled_whenSetAndValidated_reverts]: ./setAssetFeeConfig.t.sol#L114
[test_givenConfigInactiveDisabled_whenSetAndValidated_reverts]: ./setAssetFeeConfig.t.sol#L128
[test_givenInvalidInputAndConfigActiveEnabled_whenSetAndValidated_reverts]: ./setAssetFeeConfig.t.sol#L143
[test_givenInvalidInputAndConfigActiveDisabled_whenSetAndValidated_reverts]: ./setAssetFeeConfig.t.sol#L161
[test_givenInvalidInputAndConfigInactiveEnabled_whenSetAndValidated_reverts]: ./setAssetFeeConfig.t.sol#L180
[test_givenInvalidInputAndConfigInactiveDisabled_whenSetAndValidated_reverts]: ./setAssetFeeConfig.t.sol#L195
[test_whenBaseFeeAboveMaximum_reverts]: ./setAssetFeeConfig.t.sol#L211
[test_whenPreKinkSlopeAboveMaximum_reverts]: ./setAssetFeeConfig.t.sol#L230
[test_whenPostKinkSlopeAboveMaximum_reverts]: ./setAssetFeeConfig.t.sol#L249
[test_whenKinkAtOrAboveMaximum_reverts]: ./setAssetFeeConfig.t.sol#L268
[test_whenZeroKinkAndPositivePreSlope_reverts]: ./setAssetFeeConfig.t.sol#L284
[test_whenZeroKinkAndPositivePostSlope_reverts]: ./setAssetFeeConfig.t.sol#L300
[test_whenTotalAboveMaximum_reverts]: ./setAssetFeeConfig.t.sol#L316
[test_givenInvalidStructAndUnregisteredAsset_whenSetAndValidated_reverts]: ./setAssetFeeConfig.t.sol#L337
[test_givenValidStructAndUnregisteredAsset_whenSetAndValidated_reverts]: ./setAssetFeeConfig.t.sol#L353
[test_givenIncompatibleSchema_whenSetAndValidated_reverts]: ./setAssetFeeConfig.t.sol#L371
[test_givenMalformedMarketData_whenSetAndValidated_reverts]: ./setAssetFeeConfig.t.sol#L397
[test_whenConfigurationUnchanged]: ./setAssetFeeConfig.t.sol#L424
[test_givenLateFloanWriteFails_whenChanged]: ./setAssetFeeConfig.t.sol#L441
[test_whenChanged]: ./setAssetFeeConfig.t.sol#L461
[test_givenRiskHasIndependentController_whenChanged]: ./setAssetFeeConfig.t.sol#L491
[test_givenRiskUnset_whenSetAndValidated_reverts]: ./setAssetFeeConfig.t.sol#L506
[test_givenRiskRejectsStruct_whenSetAndValidated]: ./setAssetFeeConfig.t.sol#L518
[test_givenRiskReplaced_whenValidating]: ./setAssetFeeConfig.t.sol#L536
[test_givenLocalRecovery_whenChanged]: ./setAssetFeeConfig.t.sol#L558
[test_givenKernelRecovery_whenChanged]: ./setAssetFeeConfig.t.sol#L570
[test_whenZeroFee]: ./setAssetFeeConfig.t.sol#L582
[test_whenMaximumFlatFee]: ./setAssetFeeConfig.t.sol#L592
[test_whenMaximumPreSlope]: ./setAssetFeeConfig.t.sol#L607
[test_whenMaximumKink]: ./setAssetFeeConfig.t.sol#L622
[test_whenDecreasingSlopes]: ./setAssetFeeConfig.t.sol#L637
[test_whenFullValidFeeDomainIsUsed]: ./setAssetFeeConfig.t.sol#L652
[test_givenCollateralCallback_whenNestedConfigCaught_reverts]: ./setAssetFeeConfig.t.sol#L675
[test_givenCollateralCallback_whenNestedConfigPropagated]: ./setAssetFeeConfig.t.sol#L690
[test_whenPermittedCallerClassesSeeded]: ./setAssetFeeConfig.t.sol#L705
[test_whenBaseFeeBpsAboveMaximumEndpointsAreSeeded_reverts]: ./setAssetFeeConfig.t.sol#L720
[test_whenPreKinkSlopeBpsAboveMaximumEndpointsAreSeeded_reverts]: ./setAssetFeeConfig.t.sol#L743
[test_whenPostKinkSlopeBpsAboveMaximumEndpointsAreSeeded_reverts]: ./setAssetFeeConfig.t.sol#L766
[test_whenKinkBpsAtOrAboveMaximumEndpointsAreSeeded_reverts]: ./setAssetFeeConfig.t.sol#L789
[test_givenTimelockOperator_whenQueuedAndExecuted]: ./setAssetFeeConfig.t.sol#L806
[test_givenExistingLoan_whenConfigurationChanged]: ./setAssetFeeConfig.t.sol#L831
[test_givenNondefaultShareMode_whenConfigurationChanged]: ./setAssetFeeConfig.t.sol#L844
