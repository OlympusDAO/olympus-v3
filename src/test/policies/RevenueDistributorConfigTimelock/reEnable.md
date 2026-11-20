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

Admin or Revenue Distributor Admin, separately; fuzz unauthorized callers excluding both permitted role classes. RD.kernel must equal RDT.kernel; mismatch gives PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel). RD must also be active in this timelock’s Kernel and select this timelock as configOperator. RD local enablement is not an activation prerequisite and isEnabled is never read. `NeverEnabled()` is the upstream `ReEnabler` error for `lastTransitionAt == 0`.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=true and lastTransitionAt to the uint48 timestamp; emits Enabled plus Transition(caller,true,emptyData,timestamp). Preserve configuration/debt/custody. Grace starts at the prior disable timestamp; its exact deadline is allowed.

## Authorization

Fixed for this table: Effects and events: Unchanged.

| ID | Caller | Inputs / competing fault | Expected result | Test |
| --- | --- | --- | --- | --- |
| RDCT-REENABLE-A02 | Fuzz callers excluding every ADMIN_ROLE and REVENUE_DISTRIBUTOR_ADMIN_ROLE holder | Disabled within grace; excludes admin and every granted Revenue Distributor Admin | NotAuthorised() | Covered: [evidence][test_whenUnauthorizedCallerReEnables_reverts] |

## Lifecycle

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. Bound RevenueDistributor reports the same Kernel; its activity and selection of this timelock as operator are activation gates; local enablement is irrelevant. No bytes argument; prior transition L>0, G>0 and now<=L+G except explicit timing/history cases.

| ID | Caller | Local active | Local enabled | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDCT-REENABLE-L01 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | true | false | Success; concrete activation requires own Kernel membership | Only local enabled/timestamp changes; exact lifecycle events; configuration, payouts and balances preserved | Covered: [test][test_givenRepresentableDeadline_whenAuthorizedCallerReEnables], [test][test_givenReEnableBoundarySeeds] |
| RDCT-REENABLE-L02 | Fuzz all callers | true | true | NotDisabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenEnabled_whenAnyCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |
| RDCT-REENABLE-L03 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | false | false | RevenueDistributorConfigTimelock_PolicyNotActive(this policy) | Unchanged; no activation, timestamp change or committed logs | Covered: [test][test_givenInactive_whenAuthorizedCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |
| RDCT-REENABLE-L04 | Fuzz all callers | false | true | NotDisabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenEnabled_whenAnyCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |

## Dependency compatibility

The named distributor identity cases below own this check. Both activation routes require the consumed interfaces, matching Kernel, active target membership and selection of this timelock as configOperator. Neither activation route reads target isEnabled.

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

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. Bound RevenueDistributor reports the same Kernel; its activity and selection of this timelock as operator are activation gates; local enablement is irrelevant. No bytes argument; prior transition L>0, G>0 and now<=L+G except explicit timing/history cases. Local active=true, local enabled=false. Define MAX48=type(uint48).max and MAX32=type(uint32).max.

| ID | Caller | Prior transition / duration | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDCT-REENABLE-N02 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | L in 1..MAX48-G; G in 1..MAX32; D=L+G; D>L | Independently fuzz L..D-1; seed L,D-1 | Success | Local transition and exact events; no accounting changes | Covered: [test][test_givenRepresentableDeadline_whenAuthorizedCallerReEnables], [test][test_givenReEnableBoundarySeeds]  [existing revenue role][test_givenExistingRevenueAdmin_whenPermittedCallerReEnables], [existing overlap][test_givenExistingOverlappingRoles_whenPermittedCallerReEnables] |
| RDCT-REENABLE-N03 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | Same representable L,G; D=L+G | D | Success; deadline inclusive | Local transition and exact events | Covered: [test][test_givenRepresentableDeadline_whenAuthorizedCallerReEnables], [test][test_givenReEnableBoundarySeeds] |
| RDCT-REENABLE-N04 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | Same L,G; require D<MAX48 | Independently fuzz D+1..MAX48; seed D+1,MAX48 | GracePeriod_Expired(D) | Unchanged; no logs | Covered: [test][test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |

## Dependency identity and lifecycle

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. Bound RevenueDistributor reports the same Kernel; its activity and selection of this timelock as operator are activation gates; local enablement is irrelevant. No bytes argument; prior transition L>0, G>0 and now<=L+G except explicit timing/history cases. Local enabled=false, own Kernel active=true; reEnable within grace if applicable.

| ID | Caller | Distributor active | Distributor enabled | Kernel binding | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-REENABLE-D01 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | true | true | Same Kernel | Success | Only local lifecycle transition; RD state and queue preserved | Covered: [test][test_givenRepresentableDeadline_whenAuthorizedCallerReEnables], [test][test_givenReEnableBoundarySeeds] |
| RDCT-REENABLE-D02 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | true | false | Same Kernel | Success; active paused target accepted | Exact lifecycle events; target, queue and accounting preserved | Covered: [test][test_givenActivePausedDistributor_whenAuthorizedCallerReEnables] |
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

Dependency classification: RD is a direct configuration and recovery target. Construction retains its existing compatibility checks. Activation checks the consumed interfaces, canonical matching Kernel, authoritative target membership and selected operator. Missing interfaces or malformed operator metadata give `RevenueDistributorConfigTimelock_InvalidDistributor(RD)`; malformed Kernel metadata gives `PolicyDependency_InvalidDependency(RD)`; a readable foreign Kernel gives `PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel)`. An inactive target gives `PolicyDependency_NotActive(RD)`. A zero or different selected operator gives `ConfigOperator_Unauthorized(RDT)`. An active paused target succeeds, without reading isEnabled. Enable and reEnable use the same predicate.

## Kernel drift and restoration

| ID | Caller | Local active | Local enabled | Distributor active | Distributor enabled | Kernel binding | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-REENABLE-D06 | Admin | true | false | Fuzz false/true | true | Different reported Kernel after construction | PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel) before readiness | No transition | Covered: [test][test_givenDistributorKernelDrift_whenActivation_reverts] |
| RDCT-REENABLE-P03 | Admin | true | false | Restored false to true | Restored false to true | Same Kernel | Failed activation then successful retry | Pending accounting preserved | Covered: [test][test_givenRestoredDistributor_whenActivation_succeeds] |

## Activation interface and operator metadata

Own policy is active and locally disabled; caller is permitted, payload is empty, and reEnable history/grace pass when applicable. The target reports the intended Kernel and is active. These checks do not depend on target local enablement. Earlier lifecycle, authorization, payload and grace checks retain their order.

| ID | Target metadata | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| RDCT-REENABLE-D14 | Each consumed interface missing; isolated deterministic seed for every interface | RevenueDistributorConfigTimelock_InvalidDistributor(RD) | No lifecycle transition | Covered: [test][test_givenMissingConsumedInterface_whenActivation_reverts], [seeds][test_givenMissingConsumedInterfaceSeeds_whenActivation_reverts] |
| RDCT-REENABLE-D15 | Operator getter reverts, returns noncanonical address, or returns a non-word length | RevenueDistributorConfigTimelock_InvalidDistributor(RD) | No lifecycle transition | Covered: [revert][test_givenOperatorReadReverts_whenActivation_reverts], [canonical word][test_givenNoncanonicalOperator_whenActivation_reverts], [length fuzz][test_givenMalformedOperatorLength_whenActivation_reverts] |
| RDCT-REENABLE-D16 | Canonical zero or different operator; fuzz every address except this timelock | ConfigOperator_Unauthorized(this timelock) | No lifecycle transition | Covered: [fuzz][test_givenUnselectedOperator_whenActivation_reverts], [zero][test_givenZeroOperator_whenActivation_reverts] |

[test_whenUnauthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L90
[test_givenNeverEnabledPolicy_whenAnyCallerReEnables_reverts]: ./reEnable.t.sol#L294
[test_givenDistributorKernelDrift_whenActivation_reverts]: ./reEnable.t.sol#L341
[test_givenRestoredDistributor_whenActivation_succeeds]: ./reEnable.t.sol#L455
[test_givenRepresentableDeadline_whenAuthorizedCallerReEnables]: ./reEnable.t.sol#L530
[test_givenReEnableBoundarySeeds]: ./reEnable.t.sol#L659
[test_givenEnabled_whenAnyCallerReEnables_reverts]: ./reEnable.t.sol#L466
[test_givenInactive_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L493
[test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L571
[test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L615
[test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L845
[test_givenRestoredDistributor_whenAuthorizedCallerReEnables]: ./reEnable.t.sol#L883
[test_givenDependencyAndRoleSeeds_whenReEnabled_reverts]: ./reEnable.t.sol#L913
[test_givenDistributorKernelDrift_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L996
[test_givenKernelDriftRoleSeeds_whenReEnabled_reverts]: ./reEnable.t.sol#L1033
[test_givenOwnPolicyInactive_whenPermittedCallerReEnables_reverts]: ./reEnable.t.sol#L135
[test_whenPermittedCallerReEnablesWithinGrace_recordsTransition]: ./reEnable.t.sol#L37
[test_whenNeverEnabled_reverts]: ./reEnable.t.sol#L78
[test_whenExactGraceDeadline_reenables]: ./reEnable.t.sol#L64
[test_whenDistributorKernelMismatches_reverts]: ./reEnable.t.sol#L155
[test_whenAlreadyEnabled_revertsBeforeAuthorization]: ./reEnable.t.sol#L104
[test_whenGracePeriodExpired_reverts]: ./reEnable.t.sol#L115
[test_givenMissingConsumedInterface_whenActivation_reverts]: ./reEnable.t.sol#L1081
[test_givenMissingConsumedInterfaceSeeds_whenActivation_reverts]: ./reEnable.t.sol#L1117
[test_givenOperatorReadReverts_whenActivation_reverts]: ./reEnable.t.sol#L1130
[test_givenNoncanonicalOperator_whenActivation_reverts]: ./reEnable.t.sol#L1167
[test_givenMalformedOperatorLength_whenActivation_reverts]: ./reEnable.t.sol#L1150
[test_givenUnselectedOperator_whenActivation_reverts]: ./reEnable.t.sol#L1187
[test_givenZeroOperator_whenActivation_reverts]: ./reEnable.t.sol#L1206
[test_givenActivePausedDistributor_whenAuthorizedCallerReEnables]: ./reEnable.t.sol#L1044

[test_givenExistingRevenueAdmin_whenPermittedCallerReEnables]: ./reEnable.t.sol#L176
[test_givenExistingOverlappingRoles_whenPermittedCallerReEnables]: ./reEnable.t.sol#L188
