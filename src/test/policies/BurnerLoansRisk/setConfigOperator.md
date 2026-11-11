# BurnerLoansRisk.setConfigOperator coverage plan

Source: [ConfigOperatorSingleStep.setConfigOperator](../../../policies/utils/ConfigOperatorSingleStep.sol#L27), with Risk's ADMIN/own-activity authorization hook.

Scenario scope: `BLRISK-CONFIGURATOR`. Only ADMIN may install or clear this upstream authority. Risk must be active, but may be disabled for repair. Getter configOperator() and event ConfigOperatorSet(address) come from IConfigOperator; Risk's domain interface need not inherit that interface. The operator may differ from Core's Config and Config's timelock operator. Do not inspect the selected controller's Kernel, activity, enablement or interface. Core has no special authority over Risk.

## Authorization

Risk is active; input is a distinct controller.

| ID | Caller | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLRISK-CONFIGURATOR-A01 | Core without ADMIN | ROLES_RequireRole(ADMIN_ROLE) | No changes | Covered: [test][test_whenNonAdminChangesOperator_reverts], [test][test_givenCoreWithoutAdmin_whenRiskOperatorIsChanged_reverts] |
| BLRISK-CONFIGURATOR-A02 | Fuzz ADMIN holder | Success | Store exact configOperator; ConfigOperatorSet once | Covered: [test][test_givenEnabled_whenAdminSelectsOperator] |
| BLRISK-CONFIGURATOR-A03 | Fuzz caller excluding all ADMIN holders | ROLES_RequireRole(ADMIN_ROLE) | No changes | Covered: [test][test_whenNonAdminChangesOperator_reverts], [test][test_whenNonAdminChangesRiskOperator_reverts] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-CONFIGURATOR-L01 | ADMIN | true | true | Success | configOperator()==next; ConfigOperatorSet(next) once | Covered: [test][test_givenEnabled_whenAdminSelectsOperator] |
| BLRISK-CONFIGURATOR-L02 | ADMIN | true | false | Success | configOperator()==next; ConfigOperatorSet(next) once; repair while paused | Covered: [test][test_givenDisabled_whenAdminSelectsOperator] |
| BLRISK-CONFIGURATOR-L03 | ADMIN | false | true | BurnerLoans_PolicyNotActive(Risk) | No changes | Covered: [test][test_givenInactive_whenOperatorChanges_reverts] |
| BLRISK-CONFIGURATOR-L04 | ADMIN | false | false | BurnerLoans_PolicyNotActive(Risk) | No changes | Covered: [test][test_givenInactiveAndDisabled_whenOperatorChanges_reverts] |

## Pointer transitions and authority

| ID | Caller | Request / sequence | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-CONFIGURATOR-I01 | ADMIN | Same address, including initial zero | IConfigOperator.ConfigOperator_Unchanged() | No writes/events | Covered: [test][test_givenZero_whenUnchanged_reverts], [test][test_givenSelected_whenUnchanged_reverts] |
| BLRISK-CONFIGURATOR-I02 | ADMIN | Distinct nonzero address; all candidate identity/lifecycle views revert if called | Success | No introspection of upstream authority | Covered: [test][test_whenControllerGettersRevert] |
| BLRISK-CONFIGURATOR-I03 | ADMIN | Nonzero operator to zero | Success | configOperator()==0; ConfigOperatorSet(0) once; previous operator loses access; ADMIN remains authorized | Covered: [test][test_givenOperator_whenRevoked] |
| BLRISK-CONFIGURATOR-P01 | ADMIN | Set controller A then B; A calls cache-age setter without ADMIN | NotAuthorised() | Former controller loses delegated authority; B and ADMIN retain it | Covered: [test][test_givenOperator_whenReplaced] |

- [x] Complete focused tests and mappings.

## Authority independence and unchanged precedence

Risk active; ADMIN role lookup initialized. Core is an upstream consumer and is not read by this setter. Fuzz ADMIN callers independently of operator addresses. Retired P02/P03 required coordination with Core; that requirement is removed.

| ID | Caller | Input / competing condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-CONFIGURATOR-P04 | Fuzz ADMIN_ROLE holder | Distinct operator with no Core deployed; no Core authority relationship | Success | Exact configOperator() and one ConfigOperatorSet(next); no Core/FLOAN/Inventory/Payout reads or writes | Covered: [test][test_givenEnabled_whenAdminSelectsOperator], [test][test_whenControllerGettersRevert] |
| BLRISK-CONFIGURATOR-A04 | Fuzz caller excluding every ADMIN_ROLE holder | Same operator as stored; include initial zero | ROLES_RequireRole(ADMIN_ROLE) | Authorization before unchanged-value rejection; no event or write | Covered: [test][test_givenOperator_whenUnauthorizedCallerRequestsSameOperator_reverts], [test][test_givenNoOperator_whenUnauthorizedCallerRequestsZero_reverts], [test][test_whenNonAdminChangesOperator_reverts] |
| BLRISK-CONFIGURATOR-P05 | Fuzz ADMIN_ROLE holder | Zero to a distinct nonzero operator | Success | Delegated cache-age authority granted; oracle/cache pointer replacements remain ADMIN-only; Core Config unchanged | Covered: [test][test_whenOperatorGrantedCacheAgeAuthority], [test][test_givenEnabled_whenAdminSelectsOperator] |

## Stateful authority model

Risk stays Kernel-active. The handler interleaves operator replacement/revocation, ADMIN and selected-operator age changes, unauthorized attempts and pause/enable transitions. Unit cases above cover Kernel deactivation, same-value errors and exact events.

| ID | Sequence | Required relationship | Test |
| --- | --- | --- | --- |
| BLRISK-CONFIGURATOR-S01 | Arbitrary authorized configuration and lifecycle calls, plus unauthorized age attempts | Stored controller, age and enablement match the independent handler model; oracle/cache stay unchanged | Covered: [test][invariant_selectedAuthorityAndAgeFollowAuthorizedActions] |

## Existing authorization evidence

The [integration tests](setConfigOperatorIntegration.t.sol) retain the Core-without-ADMIN and fuzzed unauthorized-caller regressions for the current selector.

[invariant_selectedAuthorityAndAgeFollowAuthorizedActions]: setConfigOperator.invariant.t.sol#L30

[test_givenCoreWithoutAdmin_whenRiskOperatorIsChanged_reverts]: setConfigOperatorIntegration.t.sol#L13

[test_givenDisabled_whenAdminSelectsOperator]: setConfigOperator.t.sol#L64

[test_givenEnabled_whenAdminSelectsOperator]: setConfigOperator.t.sol#L52

[test_givenInactiveAndDisabled_whenOperatorChanges_reverts]: setConfigOperator.t.sol#L86

[test_givenInactive_whenOperatorChanges_reverts]: setConfigOperator.t.sol#L79

[test_givenNoOperator_whenUnauthorizedCallerRequestsZero_reverts]: setConfigOperator.t.sol#L28

[test_givenOperator_whenReplaced]: setConfigOperator.t.sol#L147

[test_givenOperator_whenRevoked]: setConfigOperator.t.sol#L134

[test_givenOperator_whenUnauthorizedCallerRequestsSameOperator_reverts]: setConfigOperator.t.sol#L17

[test_givenSelected_whenUnchanged_reverts]: setConfigOperator.t.sol#L114

[test_givenZero_whenUnchanged_reverts]: setConfigOperator.t.sol#L106

[test_whenControllerGettersRevert]: setConfigOperator.t.sol#L122

[test_whenNonAdminChangesOperator_reverts]: setConfigOperator.t.sol#L97

[test_whenNonAdminChangesRiskOperator_reverts]: setConfigOperatorIntegration.t.sol#L20

[test_whenOperatorGrantedCacheAgeAuthority]: setConfigOperator.t.sol#L38
