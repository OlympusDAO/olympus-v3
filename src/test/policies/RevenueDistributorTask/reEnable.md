# RevenueDistributorTask.reEnable scenario plan

Source: [RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol).

Scope: inherited reEnable action and co-located isEnabled/lastTransitionAt assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Scenario scope: `RDTASK-REENABLE` identifies this contract/function.

Required policy lifecycle: reEnable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive.

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each: independently fuzz a nonzero caller and grant ADMIN_ROLE or REVENUE_DISTRIBUTOR_ADMIN_ROLE. Guarantee seeds with ADMIN_ROLE only, REVENUE_DISTRIBUTOR_ADMIN_ROLE only and both roles; select the role independently from time and dependency inputs. These roles follow the same reEnable behavior, so each equivalent validation/time case has one row. Fuzz permitted callback caller uses a callback contract holding the selected role, with the outer operation initiated by its separately authorized caller.

For grace fuzzing, `L=lastTransitionAt>0`, `G=gracePeriod>0`, `D=L+G`. Use compatible setup with `L<=MAX48-G`; fuzz valid now in L..D and expired now in D+1..MAX48 only when D<MAX48. Seed L,D-1,D,D+1,MAX48 where each belongs to the selected outcome. Vary time independently from the configured deadline; no single-boundary test substitutes for interval coverage.

`reEnable()` is parameterless; its Transition always carries empty data.

Admin or Revenue Distributor Admin, separately; fuzz unauthorized callers excluding both permitted
role classes. Bound RD must be Kernel-active and locally enabled or give
`PolicyDependency_NotActive(RD)`. The re-enable hook validates both independent RD
lifecycle axes. `NeverEnabled()` is the upstream `ReEnabler`
error for `lastTransitionAt == 0`.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=true and lastTransitionAt to the uint48 timestamp; emits Enabled plus Transition(caller,true,emptyData,timestamp). Preserve configuration/debt/custody. Grace starts at the prior disable timestamp; its exact deadline is allowed.

## Authorization

Fixed for this table: Effects and events: Unchanged.

| ID | Caller | Inputs / competing fault | Expected result | Test |
| --- | --- | --- | --- | --- |
| RDTASK-REENABLE-A02 | Fuzz callers excluding every ADMIN_ROLE and REVENUE_DISTRIBUTOR_ADMIN_ROLE holder | Disabled within grace; excludes admin and every granted Revenue Distributor Admin | NotAuthorised() | Covered: [test][test_givenDisabled_whenUnauthorizedCallerReEnables_reverts] |

## Lifecycle

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. Bound RevenueDistributor active=true and enabled=true. No bytes argument; prior transition L>0, G>0 and now<=L+G except explicit timing/history cases.

| ID | Caller | Local active | Local enabled | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDTASK-REENABLE-L01 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | true | false | Success after own-activity/dependency checks | Only local enabled/timestamp changes; exact lifecycle events; configuration, payouts and balances preserved | Covered: [test][test_givenRepresentableDeadline_whenAuthorizedCallerReEnables], [test][test_givenReEnableBoundarySeeds] |
| RDTASK-REENABLE-L02 | Fuzz all callers | true | true | NotDisabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenEnabled_whenAnyCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |
| RDTASK-REENABLE-L03 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | false | false | RevenueDistributorTask_PolicyNotActive(Task) | Unchanged; no activation, timestamp change or committed logs | Covered: [test][test_givenInactive_whenAuthorizedCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |
| RDTASK-REENABLE-L04 | Fuzz all callers | false | true | NotDisabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenEnabled_whenAnyCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |

## Dependency lifecycle

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. Bound RevenueDistributor active=true and enabled=true. No bytes argument; prior transition L>0, G>0 and now<=L+G except explicit timing/history cases. Local enabled=false, own Kernel active=true; reEnable within grace if applicable.

| ID | Caller | Distributor active | Distributor enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDTASK-REENABLE-D01 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | false | true | PolicyDependency_NotActive(RD) | Unchanged; no lifecycle logs | Covered: [test][test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts], [test][test_givenRestoredDistributor_whenAuthorizedCallerReEnables], [test][test_givenDependencyAndRoleSeeds_whenReEnabled_reverts] |
| RDTASK-REENABLE-D02 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | false | false | PolicyDependency_NotActive(RD) | Unchanged; no lifecycle logs | Covered: [test][test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts], [test][test_givenRestoredDistributor_whenAuthorizedCallerReEnables], [test][test_givenDependencyAndRoleSeeds_whenReEnabled_reverts] |
| RDTASK-REENABLE-D03 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | true | false | PolicyDependency_NotActive(RD) | Unchanged; no lifecycle logs | Covered: [test][test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts], [test][test_givenRestoredDistributor_whenAuthorizedCallerReEnables], [test][test_givenDependencyAndRoleSeeds_whenReEnabled_reverts] |

## Grace deadline overflow

Initialized, locally disabled; otherwise compatible dependencies. Configure G while enabled, disable at L and assert the stored transition timestamp before attempting reEnable. This is an inherited numeric boundary, separate from an ordinary expired deadline.

| ID | Caller | Prior transition L | Grace G | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-REENABLE-N01 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | Fuzz MAX48-G+1..MAX48 | Configured G in 1..MAX32; seed1,MAX32 | L | `SafeCastOverflowedUintDowncast(48, uint256(L)+uint256(G))` | Unchanged; no committed transition logs | Covered: [test][test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |

Required behavior: the setter accepts a valid uint32 duration; reEnable calculates D=uint256(L)+uint256(G) and rejects D>MAX48 with SafeCastOverflowedUintDowncast(48,D) from checked uint48 narrowing. Require unchanged lifecycle/accounting state and no logs; do not accept a successful re-enable with an out-of-range deadline.

## First activation

| ID | Caller | Local active | Local enabled | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-REENABLE-P01 | Fuzz all callers | true | false | 0 | NeverEnabled() before authorization | Unchanged; no logs | Covered: [test][test_givenNeverEnabledPolicy_whenAnyCallerReEnables_reverts] |
| RDTASK-REENABLE-P02 | Fuzz all callers | false | false | 0 | NeverEnabled() before authorization or own-activity checks | Unchanged; no activation, timestamp change or committed logs | Covered: [test][test_givenNeverEnabledPolicy_whenAnyCallerReEnables_reverts] |

## Grace timing

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. Bound RevenueDistributor active=true and enabled=true. No bytes argument; prior transition L>0, G>0 and now<=L+G except explicit timing/history cases. Local active=true, local enabled=false. Define MAX48=type(uint48).max and MAX32=type(uint32).max.

| ID | Caller | Prior transition / duration | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDTASK-REENABLE-N02 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | L in 1..MAX48-G; G in 1..MAX32; D=L+G; D>L | Independently fuzz L..D-1; seed L,D-1 | Success | Local transition and exact events; no accounting changes | Covered: [test][test_givenRepresentableDeadline_whenAuthorizedCallerReEnables], [test][test_givenReEnableBoundarySeeds] |
| RDTASK-REENABLE-N03 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | Same representable L,G; D=L+G | D | Success; deadline inclusive | Local transition and exact events | Covered: [test][test_givenRepresentableDeadline_whenAuthorizedCallerReEnables], [test][test_givenReEnableBoundarySeeds] |
| RDTASK-REENABLE-N04 | Fuzz ADMIN-only, REVENUE_DISTRIBUTOR_ADMIN-only and overlap holders; seed each | Same L,G; require D<MAX48 | Independently fuzz D+1..MAX48; seed D+1,MAX48 | GracePeriod_Expired(D) | Unchanged; no logs | Covered: [test][test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts], [test][test_givenReEnableBoundarySeeds] |

## Additional existing test evidence

- [test_givenDisabledWithinGrace_whenPermittedCallerReEnables][test_givenDisabledWithinGrace_whenPermittedCallerReEnables] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_givenNeverEnabled_whenAuthorizedCallerReEnables_reverts][test_givenNeverEnabled_whenAuthorizedCallerReEnables_reverts] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_givenEnabled_whenReEnabled_reverts][test_givenEnabled_whenReEnabled_reverts] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_givenGraceExpired_whenAdminReEnables_reverts][test_givenGraceExpired_whenAdminReEnables_reverts] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_givenDistributorInactive_whenPermittedCallerReEnables_reverts][test_givenDistributorInactive_whenPermittedCallerReEnables_reverts] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_givenDistributorDisabled_whenPermittedCallerReEnables_reverts][test_givenDistributorDisabled_whenPermittedCallerReEnables_reverts] — existing regression evidence; review generators and assertions before mapping the expanded cases.

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-REENABLE-L05 | Fuzz all callers | false | false | 0 | 0 | `NeverEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test][test_givenNeverEnabledPolicy_whenAnyCallerReEnables_reverts] |

The tests require own-policy activity, empty lifecycle payloads and checked grace deadlines. Scheduler execute retains its intentional silent no-op while unavailable.

Dependency classification: RD is a direct operational Policy service. Construction validates compatibility without requiring readiness. Activation requires a canonical Kernel/status response, reported Kernel equal to this consumer's Kernel, authoritative membership in that Kernel and local enablement. Malformed metadata gives `RevenueDistributorTask_InvalidDistributor(RD)`; a readable foreign Kernel gives `PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel)` before readiness; a compatible paused/inactive target gives `PolicyDependency_NotActive(RD)`. Enable and reEnable use the same predicate.

## Kernel drift and restoration

| ID | Caller | Local active | Local enabled | Distributor active | Distributor enabled | Kernel binding | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-REENABLE-D06 | Admin | true | false | Fuzz false/true | true | Different reported Kernel after construction | PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel) before readiness | No transition | Covered: [test][test_givenDistributorKernelDrift_whenActivation_reverts] |
| RDTASK-REENABLE-P03 | Admin | true | false | Restored false to true | Restored false to true | Same Kernel | Failed activation then successful retry | Pending accounting preserved | Covered: [test][test_givenRestoredDistributor_whenActivation_succeeds] |

[test_givenDisabled_whenUnauthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L66
[test_givenNeverEnabledPolicy_whenAnyCallerReEnables_reverts]: ./reEnable.t.sol#L219
[test_givenDistributorKernelDrift_whenActivation_reverts]: ./reEnable.t.sol#L267
[test_givenRestoredDistributor_whenActivation_succeeds]: ./reEnable.t.sol#L382
[test_givenRepresentableDeadline_whenAuthorizedCallerReEnables]: ./reEnable.t.sol#L457
[test_givenReEnableBoundarySeeds]: ./reEnable.t.sol#L586
[test_givenEnabled_whenAnyCallerReEnables_reverts]: ./reEnable.t.sol#L394
[test_givenInactive_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L421
[test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L496
[test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L541
[test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L772
[test_givenRestoredDistributor_whenAuthorizedCallerReEnables]: ./reEnable.t.sol#L811
[test_givenDependencyAndRoleSeeds_whenReEnabled_reverts]: ./reEnable.t.sol#L842
[test_givenGraceExpired_whenAdminReEnables_reverts]: ./reEnable.t.sol#L87
[test_givenNeverEnabled_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L54
[test_givenDisabledWithinGrace_whenPermittedCallerReEnables]: ./reEnable.t.sol#L26
[test_givenDistributorInactive_whenPermittedCallerReEnables_reverts]: ./reEnable.t.sol#L104
[test_givenEnabled_whenReEnabled_reverts]: ./reEnable.t.sol#L81
[test_givenDistributorDisabled_whenPermittedCallerReEnables_reverts]: ./reEnable.t.sol#L119
