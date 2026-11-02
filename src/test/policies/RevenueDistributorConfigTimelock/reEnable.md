# RevenueDistributorConfigTimelock.reEnable scenario plan

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: inherited reEnable action and co-located isEnabled/lastTransitionAt assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Scenario scope: `RDCT-REENABLE` identifies this contract/function.

Required policy lifecycle: reEnable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive.

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each: independently fuzz a nonzero caller and grant ADMIN_ROLE or REVENUE_DISTRIBUTOR_ADMIN_ROLE. Guarantee seeds with ADMIN_ROLE only, REVENUE_DISTRIBUTOR_ADMIN_ROLE only and both roles; select the role independently from time and dependency inputs. These roles follow the same reEnable behavior, so each equivalent validation/time case has one row. Fuzz permitted callback caller uses a callback contract holding the selected role, with the outer operation initiated by its separately authorized caller.

For grace fuzzing, `L=lastTransitionAt>0`, `G=gracePeriod>0`, `D=L+G`. Use compatible setup with `L<=MAX48-G`; fuzz valid now in L..D and expired now in D+1..MAX48 only when D<MAX48. Seed L,D-1,D,D+1,MAX48 where each belongs to the selected outcome. Vary time independently from the configured deadline; no single-boundary test substitutes for interval coverage.

`reEnable()` is parameterless; its Transition always carries empty data.

Admin or Revenue Distributor Admin, separately; fuzz unauthorized callers excluding both permitted role classes. RD.kernel must equal RDT.kernel; mismatch gives PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel). RD must also be active in this timelock’s Kernel and locally enabled. `NeverEnabled()` is the upstream `ReEnabler` error for `lastTransitionAt == 0`.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=true and lastTransitionAt to the uint48 timestamp; emits Enabled plus Transition(caller,true,emptyData,timestamp). Preserve configuration/debt/custody. Grace starts at the prior disable timestamp; its exact deadline is allowed.

## Authorization

Fixed for this table: Effects and events: Unchanged.

| ID | Caller | Inputs / competing fault | Expected result | Test |
| --- | --- | --- | --- | --- |
| RDCT-REENABLE-A02 | Fuzz callers excluding every ADMIN_ROLE and REVENUE_DISTRIBUTOR_ADMIN_ROLE holder | Disabled within grace; excludes admin and every granted Revenue Distributor Admin | NotAuthorised() | Covered: [evidence][test_whenUnauthorizedCallerReEnables_reverts] |

## Lifecycle

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. Bound RevenueDistributor reports the same Kernel; its activity and enablement are required operational activation gates. No bytes argument; prior transition L>0, G>0 and now<=L+G except explicit timing/history cases.

| ID | Caller | Local active | Local enabled | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDCT-REENABLE-L01 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | true | false | Success; concrete activation requires own Kernel membership | Only local enabled/timestamp changes; exact lifecycle events; configuration, payouts and balances preserved | Covered: [test][test_givenRepresentableDeadline_whenAuthorizedCallerReEnables], [test][test_givenReEnableBoundarySeeds] |
| RDCT-REENABLE-L02 | Fuzz all callers | true | true | NotDisabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenEnabled_whenAnyCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |
| RDCT-REENABLE-L03 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | false | false | RevenueDistributorConfigTimelock_PolicyNotActive(this policy) | Unchanged; no activation, timestamp change or committed logs | Covered: [test][test_givenInactive_whenAuthorizedCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |
| RDCT-REENABLE-L04 | Fuzz all callers | false | true | NotDisabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenEnabled_whenAnyCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |

## Dependency compatibility

The named distributor identity cases below own this check; selection as configOperator is a queue/execution prerequisite, not an activation gate.

[test_whenUnauthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L87

## Grace deadline overflow

Initialized, locally disabled; otherwise compatible dependencies. Configure G while enabled, disable at L and assert the stored transition timestamp before attempting reEnable. This is an inherited numeric boundary, separate from an ordinary expired deadline.

| ID | Caller | Prior transition L | Grace G | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-REENABLE-N01 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | Fuzz MAX48-G+1..MAX48 | Configured G in 1..MAX32; seed1,MAX32 | L | `SafeCastOverflowedUintDowncast(48, uint256(L)+uint256(G))` | Unchanged; no committed transition logs | Covered: [test][test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |

Implemented lifecycle payload rule: the setter accepts a valid uint32 duration; reEnable calculates D=uint256(L)+uint256(G) and rejects D>MAX48 with SafeCastOverflowedUintDowncast(48,D) from checked uint48 narrowing. The product-local override widens the addition before checked narrowing; the shared ReEnabler remains unchanged. Require unchanged lifecycle/accounting state and no logs; do not accept a successful re-enable with an out-of-range deadline.

## First activation

| ID | Caller | Local active | Local enabled | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-REENABLE-P01 | Fuzz all callers | true | false | 0 | NeverEnabled() before authorization | Unchanged; no logs | Covered: [test][test_givenNeverEnabledPolicy_whenAnyCallerReEnables_reverts] |
| RDCT-REENABLE-P02 | Fuzz all callers | false | false | 0 | NeverEnabled() | Unchanged; no activation, timestamp change or committed logs | Covered: [test][test_givenNeverEnabledPolicy_whenAnyCallerReEnables_reverts] |

## Grace timing

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. Bound RevenueDistributor reports the same Kernel; its activity and enablement are required operational activation gates. No bytes argument; prior transition L>0, G>0 and now<=L+G except explicit timing/history cases. Local active=true, local enabled=false. Define MAX48=type(uint48).max and MAX32=type(uint32).max.

| ID | Caller | Prior transition / duration | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDCT-REENABLE-N02 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | L in 1..MAX48-G; G in 1..MAX32; D=L+G; D>L | Independently fuzz L..D-1; seed L,D-1 | Success | Local transition and exact events; no accounting changes | Covered: [test][test_givenRepresentableDeadline_whenAuthorizedCallerReEnables], [test][test_givenReEnableBoundarySeeds] |
| RDCT-REENABLE-N03 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | Same representable L,G; D=L+G | D | Success; deadline inclusive | Local transition and exact events | Covered: [test][test_givenRepresentableDeadline_whenAuthorizedCallerReEnables], [test][test_givenReEnableBoundarySeeds] |
| RDCT-REENABLE-N04 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | Same L,G; require D<MAX48 | Independently fuzz D+1..MAX48; seed D+1,MAX48 | GracePeriod_Expired(D) | Unchanged; no logs | Covered: [test][test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |

## Dependency identity and lifecycle

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. Bound RevenueDistributor reports the same Kernel; its activity and enablement are required operational activation gates. No bytes argument; prior transition L>0, G>0 and now<=L+G except explicit timing/history cases. Local enabled=false, own Kernel active=true; reEnable within grace if applicable.

| ID | Caller | Distributor active | Distributor enabled | Kernel binding | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-REENABLE-D01 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | true | true | Same Kernel | Success | Only local lifecycle transition; RD state and queue preserved | Covered: [test][test_givenRepresentableDeadline_whenAuthorizedCallerReEnables], [test][test_givenReEnableBoundarySeeds] |
| RDCT-REENABLE-D02 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | true | false | Same Kernel | PolicyDependency_NotActive(RD) | Unchanged; no transition or committed logs; restore target readiness and retry | Covered: [test][test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts], [test][test_givenRestoredDistributor_whenAuthorizedCallerReEnables], [test][test_givenDependencyAndRoleSeeds_whenReEnabled_reverts] |
| RDCT-REENABLE-D03 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | false | true | Same Kernel | PolicyDependency_NotActive(RD) | Unchanged; no transition or committed logs; restore target readiness and retry | Covered: [test][test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts], [test][test_givenRestoredDistributor_whenAuthorizedCallerReEnables], [test][test_givenDependencyAndRoleSeeds_whenReEnabled_reverts] |
| RDCT-REENABLE-D04 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | false | false | Same Kernel | PolicyDependency_NotActive(RD) | Unchanged; no transition or committed logs; restore target readiness and retry | Covered: [test][test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts], [test][test_givenRestoredDistributor_whenAuthorizedCallerReEnables], [test][test_givenDependencyAndRoleSeeds_whenReEnabled_reverts] |
| RDCT-REENABLE-D05 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | true | true | Different Kernel | PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel) | Unchanged; no logs | Covered: [test][test_givenDistributorKernelDrift_whenAuthorizedCallerReEnables_reverts], [test][test_givenKernelDriftRoleSeeds_whenReEnabled_reverts] |

## Additional existing test evidence

- [test_whenPermittedCallerReEnablesWithinGrace_recordsTransition][test_whenPermittedCallerReEnablesWithinGrace_recordsTransition] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_whenExactGraceDeadline_reenables][test_whenExactGraceDeadline_reenables] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_whenNeverEnabled_reverts][test_whenNeverEnabled_reverts] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_whenAlreadyEnabled_revertsBeforeAuthorization][test_whenAlreadyEnabled_revertsBeforeAuthorization] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_whenGracePeriodExpired_reverts][test_whenGracePeriodExpired_reverts] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_givenOwnPolicyInactive_whenPermittedCallerReEnables_reverts][test_givenOwnPolicyInactive_whenPermittedCallerReEnables_reverts] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_whenDistributorKernelMismatches_reverts][test_whenDistributorKernelMismatches_reverts] — existing regression evidence; review generators and assertions before mapping the expanded cases.

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-REENABLE-L05 | Fuzz all callers | false | false | 0 | 0 | `NeverEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test][test_givenNeverEnabledPolicy_whenAnyCallerReEnables_reverts] |

## Current focused implementation evidence

The product hooks now enforce empty lifecycle payloads, inactive-disable availability and active enable/reEnable (where supported). [Function-specific lifecycle tests](reEnable.t.sol) exercise ADMIN transitions and nonempty fuzz inputs against real fixtures. This is partial coverage: emergency/secondary-role transitions, all dependency drifts, exact events and overflow drivers remain independently mapped. Existing inactive-enable success tests are historical regression inputs, not proof of the new expectation.

Dependency classification: RD is a direct operational Policy service. Construction validates compatibility without requiring readiness. Activation requires a canonical Kernel/status response, reported Kernel equal to this consumer's Kernel, authoritative membership in that Kernel and local enablement. Malformed metadata gives `RevenueDistributorConfigTimelock_InvalidDistributor(RD)`; a readable foreign Kernel gives `PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel)` before readiness; a compatible paused/inactive target gives `PolicyDependency_NotActive(RD)`. Enable and reEnable use the same predicate.

[test_givenNeverEnabledPolicy_whenAnyCallerReEnables_reverts]: ./reEnable.t.sol#L265

## Kernel drift and restoration

| ID | Caller | Local active | Local enabled | Distributor active | Distributor enabled | Kernel binding | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-REENABLE-D06 | Admin | true | false | Fuzz false/true | true | Different reported Kernel after construction | PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel) before readiness | No transition | Covered: [test][test_givenDistributorKernelDrift_whenActivation_reverts] |
| RDCT-REENABLE-P03 | Admin | true | false | Restored false to true | Restored false to true | Same Kernel | Failed activation then successful retry | Pending accounting preserved | Covered: [test][test_givenRestoredDistributor_whenActivation_succeeds] |

[test_givenDistributorKernelDrift_whenActivation_reverts]: ./reEnable.t.sol#L312
[test_givenRestoredDistributor_whenActivation_succeeds]: ./reEnable.t.sol#L426

[test_givenRepresentableDeadline_whenAuthorizedCallerReEnables]: ./reEnable.t.sol#L501

[test_givenReEnableBoundarySeeds]: ./reEnable.t.sol#L630

[test_givenEnabled_whenAnyCallerReEnables_reverts]: ./reEnable.t.sol#L437

[test_givenInactive_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L464

[test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L542

[test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L586

[test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L816

[test_givenRestoredDistributor_whenAuthorizedCallerReEnables]: ./reEnable.t.sol#L854

[test_givenDependencyAndRoleSeeds_whenReEnabled_reverts]: ./reEnable.t.sol#L884

[test_givenDistributorKernelDrift_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L985

[test_givenKernelDriftRoleSeeds_whenReEnabled_reverts]: ./reEnable.t.sol#L1022

[test_givenOwnPolicyInactive_whenPermittedCallerReEnables_reverts]: ./reEnable.t.sol#L132

[test_whenPermittedCallerReEnablesWithinGrace_recordsTransition]: ./reEnable.t.sol#L34

[test_whenNeverEnabled_reverts]: ./reEnable.t.sol#L75

[test_whenExactGraceDeadline_reenables]: ./reEnable.t.sol#L61

[test_whenDistributorKernelMismatches_reverts]: ./reEnable.t.sol#L152

[test_whenAlreadyEnabled_revertsBeforeAuthorization]: ./reEnable.t.sol#L101

[test_whenGracePeriodExpired_reverts]: ./reEnable.t.sol#L112
