# BurnerLoansRisk.setGracePeriod coverage plan

Source: [setGracePeriod](../../../bases/ReEnablerGracePeriod.sol#L74).

Scenario scope: `BLRISK-GRACE`. ADMIN-only, Risk active; local enablement is required. This inherited setter emits GracePeriodSet even for an unchanged valid value, without changing isEnabled or lastTransitionAt. A future uint48 disable timestamp is not guessed or capped here.

## Authorization

| ID | Caller | Request | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLRISK-GRACE-A01 | Fuzz caller excluding every ADMIN holder | Nonzero uint32 | ROLES_RequireRole(ADMIN_ROLE) | Covered: [test][test_whenUnauthorizedCallerChangesGrace_reverts] |

## Local lifecycle

| ID | Caller | Local active | Local enabled | Expected result | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-GRACE-L01 | ADMIN | true | true | Store and emit | Covered: [test][test_givenOperational_whenGraceChanges] |
| BLRISK-GRACE-L02 | ADMIN | true | false | NotEnabled() | Covered: [test][test_givenDisabled_whenGraceChanges_reverts] |
| BLRISK-GRACE-L03 | ADMIN | false | true | BurnerLoans_PolicyNotActive(Risk) | Covered: [test][test_givenInactive_whenGraceChanges_reverts] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |
| BLRISK-GRACE-L04 | ADMIN | false | false | BurnerLoans_PolicyNotActive(BurnerLoansRisk) | Covered: [test][test_givenInactiveAndDisabled_whenGraceChanges_reverts] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |

## Parameter transitions

| ID | Caller | uint32 period | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-GRACE-I01 | ADMIN | 0 | GracePeriod_ZeroPeriod() | No changes/logs | Covered: [test][test_whenGraceIsZero_reverts] |
| BLRISK-GRACE-N01 | ADMIN | Fuzz 1..MAX32; seed 1,MAX32; distinct value | Success | Exact period and GracePeriodSet | Covered: [test][test_whenGraceIsValid], [test][test_whenGraceEndpoints] |
| BLRISK-GRACE-P01 | ADMIN | Current nonzero value | Success | One GracePeriodSet; no lifecycle/timestamp change | Covered: [test][test_whenGraceIsUnchanged] |

- [x] Complete focused tests and exact mappings.

[test_givenDisabled_whenGraceChanges_reverts]: setGracePeriod.t.sol#L25

[test_givenInactiveAndDisabled_whenGraceChanges_reverts]: setGracePeriod.t.sol#L37

[test_givenInactive_whenGraceChanges_reverts]: setGracePeriod.t.sol#L31

[test_givenOperational_whenGraceChanges]: setGracePeriod.t.sol#L19

[test_whenGraceEndpoints]: setGracePeriod.t.sol#L81

[test_whenGraceIsUnchanged]: setGracePeriod.t.sol#L87

[test_whenGraceIsValid]: setGracePeriod.t.sol#L76

[test_whenGraceIsZero_reverts]: setGracePeriod.t.sol#L58

[test_whenUnauthorizedCallerChangesGrace_reverts]: setGracePeriod.t.sol#L47

[test_givenInactive_whenUnauthorizedAndInvalid_reverts]: setGracePeriod.t.sol#L92
