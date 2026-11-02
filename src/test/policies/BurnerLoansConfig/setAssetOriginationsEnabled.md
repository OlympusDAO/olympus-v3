# BurnerLoansConfig.setAssetOriginationsEnabled coverage plan

Source: [setAssetOriginationsEnabled](../../../policies/burnerloans/BurnerLoansConfig.sol#L297). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCFG-ORIGINATIONS` identifies this contract/function.

Implemented same-value rule: unchanged parameters return without setter writes/events after the concrete checks before equality. Changing-value rows exclude the current value; downstream checks reached only after equality are tested separately.

Own-policy admission: require Kernel-active BurnerLoansConfig; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfig)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Fuzz permitted configuration caller: independently fuzz a nonzero address as ADMIN_ROLE holder, current selected configOperator without ADMIN_ROLE, or both. Guarantee ADMIN-only, operator-only and overlapping seeds. Caller choice is independent of lifecycle flags, inputs and dependency failures. Unauthorized fuzzing excludes all ADMIN_ROLE holders and the selected nonzero configOperator.

ADMIN or configOperator, Config enabled. asset must be configured; bool field `originationsEnabled` changes only through FLOAN.setMarketOriginationsEnabled; no Core compact-mode synchronization. No grandfathering.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

All body inputs and component bindings are compatible unless the row states otherwise. Use the equivalent permitted-caller family above for each applicable row.

## Authorization

Fixed for this table: Local active: true; Local enabled: true; Core active: true; Core enabled: true.

The only permitted identities are every ADMIN_ROLE holder and the current nonzero configOperator. Fuzz the denied caller over EOAs and contracts excluding exactly those identities; retain zero unless it holds ADMIN. Seed a former operator, a BURNER_LOANS_ADMIN_ROLE-only holder, a borrower and an unrelated contract. All inputs are valid and changed, so authorization is the only varying condition.

| ID | Caller | Inputs / pre-state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ORIGINATIONS-A01 | Fuzz ADMIN-only, selected nonzero configOperator-only and overlap holders; guarantee each class | Valid changed setting; local/dependency admission satisfied | Success | Exact function-specific canonical update and event; preserve unrelated configuration and accounting | Covered: [test][test_givenAuthorizedCaller_whenOriginationsDisabled], [test][test_whenPermittedCallerClassesSeeded] |
| BLCFG-ORIGINATIONS-A02 | Fuzz caller lacking ADMIN_ROLE and unequal to the selected nonzero configOperator | Same otherwise-valid request | NotAuthorised() before input validation or writes | Unchanged; no setter event, Core/FLOAN mutation or token movement | Covered: [test][test_whenCallerIsUnauthorized_reverts] |

## Lifecycle

Each retained row independently fuzzes Core active/enabled and guarantees all four pairs. These flags do not change this setter's outcome. Local enabled and Kernel membership remain separate fixed conditions with exact errors; no outcome-selecting runner is required.

Use a changed valid setting. Config must itself be active/enabled; existing market lookups remain readable. This setter does not call Core.registerMarket or perform a Core mutation. Core activity/enablement therefore does not gate changed or unchanged values. Keep this distinct from addAsset and setAssetWithdrawAsShares, which synchronize Core.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-ORIGINATIONS-L01 | Fuzz permitted configuration caller | true | true | Fuzz false/true | Fuzz false/true | Body succeeds | Covered: [test][test_givenCoreLifecycleVaries_whenFlagChanged] |
| BLCFG-ORIGINATIONS-L04 | Fuzz permitted configuration caller | true | false | Fuzz false/true | Fuzz false/true | NotEnabled() | Covered: [test][test_givenConfigActiveDisabled_whenFlagChanged_reverts] |
| BLCFG-ORIGINATIONS-L08 | Fuzz permitted configuration caller | false | true | Fuzz false/true | Fuzz false/true | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Covered: [test][test_givenConfigInactiveEnabled_whenFlagChanged_reverts] |
| BLCFG-ORIGINATIONS-L12 | Fuzz permitted configuration caller | false | false | Fuzz false/true | Fuzz false/true | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Covered: [test][test_givenConfigInactiveDisabled_whenFlagChanged_reverts] |

Unauthorized fuzz callers exclude ADMIN holders and the selected nonzero configOperator. The local enablement modifier precedes caller authorization. Assert unchanged state for rejection; re-enable/reactivate before retry and verify canonical positions survive. These Core lifecycle rows keep selected Inventory/Custody and required module permissions operational; their separate live failures are tested in the body.

## Invalid inputs

Fixed for this table: Accounting / events: No change.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCFG-ORIGINATIONS-I01 | Fuzz permitted configuration caller | oldfalse/newtrue; PRICE approval or DM support invalid | Exact dependency error | Covered: [test][test_givenUnsupportedPrice_whenOriginationsEnabled_reverts], [test][test_givenDisabledDepositPeriod_whenOriginationsEnabled_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ORIGINATIONS-P01 | Fuzz permitted configuration caller | old==new false/true; live dependencies later broken | Idempotent return BEFORE dependency validation | No event/module/register calls | Covered: [test][test_givenSameFlagAndBrokenDependencies_whenSet] |
| BLCFG-ORIGINATIONS-P02 | Fuzz permitted configuration caller | oldtrue/newfalse; live price/DM broken | Disable allowed if canonical config/modules healthy | No dependency revalidation; existing servicing not blocked by flag | Covered: [test][test_givenPriceSupportBroken_whenOriginationsDisabled] |
| BLCFG-ORIGINATIONS-P03 | Fuzz permitted configuration caller | Actual successful transition, populated/empty loans | Apply and emit field-specific event | All unrelated risk/fee/cap fields preserved | Covered: [test][test_givenAuthorizedCaller_whenOriginationsDisabled], [test][test_givenExistingLoan_whenFlagChanged] |

## Atomic rollback

Fixed for this table: Accounting / events: Canonical market state rolls back; Core registry is untouched.

| ID | Caller | Input / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCFG-ORIGINATIONS-P04 | Fuzz permitted configuration caller | Required FLOAN originations write fails | Exact dependency error | Covered: [test][test_givenOriginationsWriteFails_whenChanged] |

Co-located API assertions: `getAssetConfig`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Same configuration value

| ID | Caller | Proposed value | Execution | Effects | Test |
| --- | --- | --- | --- | --- |--- |
| BLCFG-ORIGINATIONS-P05 | Fuzz ADMIN_ROLE holder or selected nonzero configOperator; guarantee exclusive and overlap seeds | Exactly current complete value; fuzz the valid domain defined above, including its explicit boundary seeds | No-op after required validation | No setter writes/events; positions, obligations, authority and balances unchanged | Covered: [test][test_givenSameFlagAndBrokenDependencies_whenSet] |

## Equality versus downstream admission

Config must be active/enabled and the caller permitted. Both changed and unchanged values are independent of Core lifecycle because this setter performs no Core mutation. Debt-cap and complete fee/risk validation still run before equality; unchanged originations return before price/custody support revalidation. An unchanged valid value emits no setter event and makes no FLOAN write. Read-only Core market/Risk selection getters and requireNotReentrant remain permitted. The guard is a settlement-state check, not a Core lifecycle requirement.

## Targeted writes and preservation

Config active/enabled; permitted ADMIN/configOperator caller; changed valid input. Seed unrelated fields to distinct nondefault values so a full-market replay or clobbered packed field is detectable.

| ID | Caller | Expected external writes | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLCFG-ORIGINATIONS-D01 | Fuzz permitted configuration caller | FLOAN.setMarketOriginationsEnabled(marketId,enabled); reject every other FLOAN setter and all Core mutators if called | Success; exact canonical getter/event; preserve Risk/fee/cap/configData fields, Core registry and Inventory/Payout ledgers | Covered: [test][test_whenFlagChanged] |

## Settlement callbacks

Removing Core.registerMarket must not remove the existing rejection of configuration mutation during a guarded Core settlement. Config checks Core.requireNotReentrant before its first FLOAN write; this view remains usable while Core is inactive/disabled. The nested caller otherwise has current ADMIN/configOperator authority and a changed valid setting.

| ID | Caller | Callback / state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ORIGINATIONS-C01 | Fuzz permitted configuration caller | Authorized nested setter during a token-transfer callback while Core settlement guard is entered | ReentrancyGuardReentrantCall() | No FLOAN setter, Config setter event or registry update; propagate the callback failure and assert outer transaction rollback | Covered: [test][test_givenCollateralCallback_whenNestedFlagChangeCaught], [test][test_givenCollateralCallback_whenNestedFlagChangePropagated] |

## Local lifecycle restoration

Permitted caller; initialized bindings; changed valid input. Seed existing loans and unrelated configuration. Recovery restores the same intended caller authority, not an extra ADMIN grant to a forwarding contract.

| ID | Caller | Restoration sequence | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ORIGINATIONS-L16 | Fuzz ADMIN-only, current configOperator-only or overlap; seed each | Config disabled, then enabled with current direct dependencies ready | Successful setter after local recovery | Same targeted FLOAN fields/event as initial success; loans, unrelated fields and independent operators preserved | Covered: [test][test_givenLocalRecovery_whenFlagChanged] |
| BLCFG-ORIGINATIONS-L17 | Fuzz ADMIN-only, current configOperator-only or overlap; seed each | Previously active Config Kernel-deactivated, then reactivated so module permissions refresh; local enabled state retained | Successful setter after Kernel recovery | Same targeted write set; no permanent permission loss, duplicate registry entry or unrelated accounting change | Covered: [test][test_givenKernelRecovery_whenFlagChanged] |

[test_givenAuthorizedCaller_whenOriginationsDisabled]: ./setAssetOriginationsEnabled.t.sol#L44
[test_whenCallerIsUnauthorized_reverts]: ./setAssetOriginationsEnabled.t.sol#L54
[test_givenCoreLifecycleVaries_whenFlagChanged]: ./setAssetOriginationsEnabled.t.sol#L64
[test_givenConfigActiveDisabled_whenFlagChanged_reverts]: ./setAssetOriginationsEnabled.t.sol#L76
[test_givenConfigInactiveEnabled_whenFlagChanged_reverts]: ./setAssetOriginationsEnabled.t.sol#L93
[test_givenConfigInactiveDisabled_whenFlagChanged_reverts]: ./setAssetOriginationsEnabled.t.sol#L110
[test_givenUnsupportedPrice_whenOriginationsEnabled_reverts]: ./setAssetOriginationsEnabled.t.sol#L128
[test_givenDisabledDepositPeriod_whenOriginationsEnabled_reverts]: ./setAssetOriginationsEnabled.t.sol#L147
[test_givenSameFlagAndBrokenDependencies_whenSet]: ./setAssetOriginationsEnabled.t.sol#L165
[test_givenPriceSupportBroken_whenOriginationsDisabled]: ./setAssetOriginationsEnabled.t.sol#L189
[test_givenExistingLoan_whenFlagChanged]: ./setAssetOriginationsEnabled.t.sol#L208
[test_givenOriginationsWriteFails_whenChanged]: ./setAssetOriginationsEnabled.t.sol#L217
[test_whenFlagChanged]: ./setAssetOriginationsEnabled.t.sol#L236
[test_givenLocalRecovery_whenFlagChanged]: ./setAssetOriginationsEnabled.t.sol#L270
[test_givenKernelRecovery_whenFlagChanged]: ./setAssetOriginationsEnabled.t.sol#L281
[test_givenCollateralCallback_whenNestedFlagChangeCaught]: ./setAssetOriginationsEnabled.t.sol#L292
[test_givenCollateralCallback_whenNestedFlagChangePropagated]: ./setAssetOriginationsEnabled.t.sol#L307
[test_whenPermittedCallerClassesSeeded]: ./setAssetOriginationsEnabled.t.sol#L322
