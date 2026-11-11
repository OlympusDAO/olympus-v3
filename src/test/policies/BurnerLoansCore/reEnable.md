# BurnerLoansCore.reEnable coverage plan

Source: [reEnable](../../../bases/ReEnabler.sol#L46). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-REENABLE` identifies this contract/function.

Required policy lifecycle: reEnable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive.

For grace fuzzing, `L=lastTransitionAt>0`, `G=gracePeriod>0`, `D=L+G`. Use compatible setup with `L<=MAX48-G`; fuzz valid now in L..D and expired now in D+1..MAX48 only when D<MAX48. Seed L,D-1,D,D+1,MAX48 where each belongs to the selected outcome. Vary time independently from the configured deadline; no single-boundary test substitutes for interval coverage.

`reEnable()` is parameterless. Successful Transition always carries empty data; there is no bytes argument to validate.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each: independently fuzz a nonzero caller and grant ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE. Guarantee seeds with ADMIN_ROLE only, BURNER_LOANS_ADMIN_ROLE only and both roles; select the role independently from time and dependency inputs. These roles follow the same reEnable behavior, so each equivalent validation/time case has one row. Fuzz permitted callback caller uses a callback contract holding the selected role, with the outer operation initiated by its separately authorized caller.

DepositManager, Inventory, Payout and Risk are active/enabled services in the same Kernel. Config is an upstream authority whose lifecycle and Kernel are not checked. Core must be Kernel-active; its concrete hook checks this. ROLES initialized. The permitted caller fuzz family above names every accepted role; unauthorized fuzzing excludes all holders of those roles. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Dependency validation contract

Check selected Inventory, Payout and Risk as required Core-bound services: required interfaces, canonical core()=this Core, reported Kernel identity, authoritative membership in this Kernel, then enabled state. DepositManager is a required same-Kernel Policy service with no Core binding. Config, actions and Lens are not Core activation dependencies.

Keep enable and reEnable on the same compatibility/readiness predicates. Core uses `PolicyDependency_KernelMismatch(dependency,expectedKernel,reportedKernel)` for readable foreign-Kernel metadata. Unset or otherwise invalid dependencies use their component-specific `InvalidDependency(candidate)` error; compatible selected services that become inactive or disabled use `PolicyDependency_NotActive(dependency)`. These Core-specific error choices take precedence over the general [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Unset pointers, missing interfaces and incompatible Core bindings use component errors; failed/malformed Kernel/status reads use `PolicyDependency_InvalidDependency(dependency)`. Component error ownership: DepositManager → `BurnerLoansCore_InvalidDepositManager(DepositManager)`; Inventory → `BurnerLoansCore_InvalidInventory(Inventory)`; Payout → `BurnerLoansCore_InvalidPayout(Payout)`; Risk → `BurnerLoansCore_InvalidRisk(Risk)`.

## Authorization

Fixed for this table: Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-REENABLE-A01 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; within grace | `NotAuthorised()` | Unchanged | Covered: [test][test_givenUnauthorized_whenEnabled_reverts] |
| BLCORE-REENABLE-A02 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; expired grace; one failed dependency | `NotAuthorised()` | Unchanged; authorization before grace/dependency | Covered: [test][test_givenUnauthorizedAndExpiredGrace_whenReEnabled_reverts] |

## Timing and transition history

Local enabled=false; L=lastTransitionAt>0; G=gracePeriod>0; D=L+G<=MAX48. DepositManager, Inventory, Payout and Risk are active/enabled services in the same Kernel. Config is an upstream authority whose lifecycle and Kernel are not checked. Core must be Kernel-active; its concrete hook checks this. Core settlement guard is not entered. Seed boundaries through the same case assertions; no now/deadline correlation.

| ID | Caller | Time domain / boundary seeds | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-REENABLE-P01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Independently fuzz L,G with 0<L<=MAX48-G; fuzz now in L..D-1; seed L,D-1 and D=MAX48 | Success | Enabled then Transition(caller,true,0x,now); lastTransitionAt=now | Covered: [test][test_givenReadyGraph_whenEnabled], [test][test_givenInclusiveGrace_whenReEnabled], [test][test_whenGraceBoundarySeeds] |
| BLCORE-REENABLE-P02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz compatible L,G; now=D; seed D=MAX48 | Success | Inclusive deadline; exact local transition/events | Covered: [test][test_givenInclusiveGrace_whenReEnabled], [test][test_whenGraceBoundarySeeds] |
| BLCORE-REENABLE-P03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz compatible L,G with D<MAX48; fuzz now in D+1..MAX48; seed D+1,MAX48 | GracePeriod_Expired(D) | Unchanged; no committed logs | Covered: [test][test_givenExpiredGrace_whenReEnabled_reverts], [test][test_whenGraceBoundarySeeds] |

## Grace deadline overflow

Initialized, locally disabled; otherwise compatible dependencies. Configure G while enabled, disable at L and assert the stored transition timestamp before attempting reEnable. Checked uint48 deadline narrowing is the required behavior: the deadline must fit in uint48. The setter stores a nonzero uint32 duration; the future disable timestamp is not known when it is set.

| ID | Caller | Prior transition L | Grace G | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCORE-REENABLE-N01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz MAX48-G+1..MAX48 | Configured G in 1..MAX32; seed1,MAX32 | L | `SafeCastOverflowedUintDowncast(48, uint256(L)+uint256(G))` | Unchanged; no committed transition logs | Covered: [test][test_givenDeadlineOverflow_whenReEnabled_reverts], [test][test_whenGraceBoundarySeeds] |

Implemented lifecycle payload rule: calculate D=uint256(L)+uint256(G), then use checked SafeCast narrowing to uint48. If D exceeds MAX48, revert with SafeCastOverflowedUintDowncast(48,D). The product-local _requireGrace override uses widened addition and checked uint48 narrowing; it leaves shared ReEnabler behavior unchanged. Preserve local enabled state, transition timestamp, configuration and balances; commit no lifecycle events. The duration setter cannot validate an unknown future disable timestamp.

## Guard precedence

Local enabled=false; initialized; authorized caller.

| ID | Caller | Competing faults | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-REENABLE-I01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Grace expired; Core.rescue guard entered while disabled; ADMIN callback calls reEnable | ReentrancyGuardReentrantCall() | Unchanged; guard precedes inherited grace check | Covered: [test][test_givenBusyCoreAndExpiredGrace_whenReEnabled_reverts] |

## Local transition state

ROLES initialized. Data=0x for enable; for reEnable, L>0 and a representable unexpired grace deadline unless the row states otherwise. The own enabled-state check precedes authorization; own activity is checked before operational dependencies.

| ID | Caller | Local active | Local enabled | History | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCORE-REENABLE-L01 | Fuzz all callers | Fuzz false/true | true | Any reachable history | NotDisabled() | Unchanged; before authorization and hooks | Covered: [test][test_givenAlreadyEnabled_whenEnabled_reverts] |
| BLCORE-REENABLE-L02 | Fuzz all callers | Fuzz false/true | false | lastTransitionAt=0 | NeverEnabled() | Unchanged; before authorization and hooks | Covered: [test][test_givenNeverEnabled_whenReEnabled_reverts] |
| BLCORE-REENABLE-L03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | false | false | Valid history/grace if reEnable | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Unchanged; no committed logs | Covered: [test][test_givenCoreInactive_whenEnabled_reverts] |

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCORE-REENABLE-L04 | Fuzz all callers | false | false | 0 | 0 | `NeverEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test][test_givenNeverEnabled_whenReEnabled_reverts] |

## Dependency lifecycle

Local active=true; Local enabled=false; initialized ROLES; authorized caller; Core guard idle; data=0x for enable, valid history/grace for reEnable. DepositManager, Inventory, Payout and Risk must be active in Core’s Kernel, report that Kernel and be locally enabled. Inventory, Payout and Risk have the selected Core binding; DepositManager is shared and has no Core binding. Other services stay ready.

Seed a live position and pending payout. After each failure, restore only the failed flag and retry successfully; preserve loans, balances and obligations. An inactive candidate that falsely reports Core’s Kernel still fails the authoritative `kernel.isPolicyActive(candidate)` lookup. Successful authorization/timing cases cover all services ready.

| ID | Caller | Dependency | Dependency active | Dependency enabled | Execution | Effects / recovery | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCORE-REENABLE-D01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | DepositManager | false | true | PolicyDependency_NotActive(DepositManager) | Unchanged; restore failed flag and retry | Covered: [test][test_givenDepositManagerUnavailable_whenEnabled_reverts] |
| BLCORE-REENABLE-D02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | DepositManager | true | false | PolicyDependency_NotActive(DepositManager) | Unchanged; restore failed flag and retry | Covered: [test][test_givenDepositManagerUnavailable_whenEnabled_reverts] |
| BLCORE-REENABLE-D03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | DepositManager | false | false | PolicyDependency_NotActive(DepositManager) | Unchanged; restore failed flag and retry | Covered: [test][test_givenDepositManagerUnavailable_whenEnabled_reverts] |
| BLCORE-REENABLE-D04 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Inventory | false | true | PolicyDependency_NotActive(Inventory) | Unchanged; restore failed flag and retry | Covered: [test][test_givenInventoryUnavailable_whenEnabled_reverts] |
| BLCORE-REENABLE-D05 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Inventory | true | false | PolicyDependency_NotActive(Inventory) | Unchanged; restore failed flag and retry | Covered: [test][test_givenInventoryUnavailable_whenEnabled_reverts] |
| BLCORE-REENABLE-D06 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Inventory | false | false | PolicyDependency_NotActive(Inventory) | Unchanged; restore failed flag and retry | Covered: [test][test_givenInventoryUnavailable_whenEnabled_reverts] |
| BLCORE-REENABLE-D07 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Payout | false | true | PolicyDependency_NotActive(Payout) | Unchanged; restore failed flag and retry | Covered: [test][test_givenPayoutUnavailable_whenEnabled_reverts] |
| BLCORE-REENABLE-D24 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Payout | true | false | PolicyDependency_NotActive(Payout) | Unchanged; restore failed flag and retry | Covered: [test][test_givenPayoutUnavailable_whenEnabled_reverts] |
| BLCORE-REENABLE-D26 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Payout | false | false | PolicyDependency_NotActive(Payout) | Unchanged; restore failed flag and retry | Covered: [test][test_givenPayoutUnavailable_whenEnabled_reverts] |
| BLCORE-REENABLE-D20 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Risk | true | false | PolicyDependency_NotActive(Risk) | Unchanged; restore failed flag and retry | Covered: [test][test_givenRiskUnavailable_whenEnabled_reverts] |
| BLCORE-REENABLE-D21 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Risk | false | true | PolicyDependency_NotActive(Risk) | Unchanged; restore failed flag and retry | Covered: [test][test_givenRiskUnavailable_whenEnabled_reverts] |
| BLCORE-REENABLE-D22 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Risk | false | false | PolicyDependency_NotActive(Risk) | Unchanged; restore failed flag and retry | Covered: [test][test_givenRiskUnavailable_whenEnabled_reverts] |

## Dependency compatibility

Core active and locally disabled; other prerequisites pass. Use reachable pre-link setup for missing pointers. For reported-Kernel drift, migrate each real provider to another Kernel while the old Kernel retains stale active membership. A mismatch must reject; restoring only the Kernel permits retry. Interface and immutable Core-binding failures belong to pointer-installation tests; do not erase validated code to create unreachable activation inputs. Config is not inspected.

| ID | Caller | Dependency | Fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-REENABLE-D08 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | DepositManager | Reports another Kernel | PolicyDependency_KernelMismatch(DepositManager,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenDepositManagerWrongKernel_whenEnabled_reverts] |
| BLCORE-REENABLE-D09 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Inventory | Reports another Kernel | PolicyDependency_KernelMismatch(Inventory,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenInventoryWrongKernel_whenEnabled_reverts] |
| BLCORE-REENABLE-D10 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Payout | Reports another Kernel | PolicyDependency_KernelMismatch(Payout,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenPayoutWrongKernel_whenEnabled_reverts] |
| BLCORE-REENABLE-D11 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Risk | Selected address zero | BurnerLoansCore_InvalidRisk(0) | Unchanged | Covered: [test][test_givenRiskUnset_whenEnabled_reverts] |
| BLCORE-REENABLE-D32 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Risk | Reports another Kernel | PolicyDependency_KernelMismatch(Risk,expectedKernel,reportedKernel) | No transition or accounting/log change | Covered: [test][test_givenRiskWrongKernel_whenEnabled_reverts] |
| BLCORE-REENABLE-D33 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Inventory | Unset address zero | BurnerLoansCore_InvalidInventory(0) | No transition or accounting/log change | Covered: [test][test_givenInventoryUnset_whenEnabled_reverts] |
| BLCORE-REENABLE-D34 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Payout | Unset address zero | BurnerLoansCore_InvalidPayout(0) | No transition or accounting/log change | Covered: [test][test_givenPayoutUnset_whenEnabled_reverts] |

## Upstream Config independence

Core active and locally disabled; downstream services ready; selected Config address retained. Config is an upstream authority, not an operational dependency. Guarantee all four Config flag pairs.

| ID | Caller | Config active | Config enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-REENABLE-D14 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz false/true | Fuzz false/true | Success | Normal transition; no Config lifecycle getter | Covered: [test][test_givenConfigUnavailable_whenEnabled] |
| BLCORE-REENABLE-D18 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz false/true | Fuzz false/true | Success even if Config reports another Kernel | No Config Kernel/interface getter; upstream installation owns correctness | Covered: [test][test_givenConfigUnavailable_whenEnabled] |

## Callbacks and reentrancy

An authorized callback calls reEnable during Core.rescue while Core is disabled. Other admission conditions pass; use the permitted caller family above.

| ID | Caller | Nested call handling | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-REENABLE-C01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each (callback contract) | Catch nested rejection | ReentrancyGuardReentrantCall() | Outer rescue completes once; no lifecycle transition | Covered: [test][test_givenBusyCore_whenCaughtEnable_reverts] |
| BLCORE-REENABLE-C02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each (callback contract) | Propagate nested rejection | ReentrancyGuardReentrantCall() | Outer rescue and lifecycle mutation roll back; no committed logs | Covered: [test][test_givenBusyCore_whenPropagatedEnable_reverts] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Malformed provider status

Core is active and paused; all other services are ready. A selected provider returns a non-32-byte Kernel or enabled-status result. Reject with the shared error, preserve Core state, then restore the getter and retry.

| ID | Provider | Execution | Test |
| --- | --- | --- | --- |
| BLCORE-REENABLE-D35 | Inventory | PolicyDependency_InvalidDependency(Inventory) | Covered: [test][test_givenInventoryMalformedStatus_whenEnabled_reverts] |
| BLCORE-REENABLE-D36 | Payout | PolicyDependency_InvalidDependency(Payout) | Covered: [test][test_givenPayoutMalformedStatus_whenEnabled_reverts] |
| BLCORE-REENABLE-D37 | Risk | PolicyDependency_InvalidDependency(Risk) | Covered: [test][test_givenRiskMalformedStatus_whenEnabled_reverts] |

[test_givenAlreadyEnabled_whenEnabled_reverts]: reEnable.t.sol#L64
[test_givenBusyCoreAndExpiredGrace_whenReEnabled_reverts]: reEnable.t.sol#L645
[test_givenBusyCore_whenCaughtEnable_reverts]: reEnable.t.sol#L508
[test_givenBusyCore_whenPropagatedEnable_reverts]: reEnable.t.sol#L524
[test_givenConfigUnavailable_whenEnabled]: reEnable.t.sol#L483
[test_givenCoreInactive_whenEnabled_reverts]: reEnable.t.sol#L72
[test_givenDeadlineOverflow_whenReEnabled_reverts]: reEnable.t.sol#L619
[test_givenDepositManagerUnavailable_whenEnabled_reverts]: reEnable.t.sol#L92
[test_givenDepositManagerWrongKernel_whenEnabled_reverts]: reEnable.t.sol#L126
[test_givenExpiredGrace_whenReEnabled_reverts]: reEnable.t.sol#L592
[test_givenInclusiveGrace_whenReEnabled]: reEnable.t.sol#L564
[test_givenInventoryUnavailable_whenEnabled_reverts]: reEnable.t.sol#L146
[test_givenInventoryUnset_whenEnabled_reverts]: reEnable.t.sol#L439
[test_givenInventoryWrongKernel_whenEnabled_reverts]: reEnable.t.sol#L180
[test_givenNeverEnabled_whenReEnabled_reverts]: reEnable.t.sol#L536
[test_givenPayoutUnavailable_whenEnabled_reverts]: reEnable.t.sol#L237
[test_givenPayoutUnset_whenEnabled_reverts]: reEnable.t.sol#L461
[test_givenPayoutWrongKernel_whenEnabled_reverts]: reEnable.t.sol#L271
[test_givenReadyGraph_whenEnabled]: reEnable.t.sol#L32
[test_givenRiskUnavailable_whenEnabled_reverts]: reEnable.t.sol#L328
[test_givenRiskUnset_whenEnabled_reverts]: reEnable.t.sol#L419
[test_givenRiskWrongKernel_whenEnabled_reverts]: reEnable.t.sol#L362
[test_givenUnauthorizedAndExpiredGrace_whenReEnabled_reverts]: reEnable.t.sol#L550
[test_givenUnauthorized_whenEnabled_reverts]: reEnable.t.sol#L50
[test_whenGraceBoundarySeeds]: reEnable.t.sol#L658

[test_givenInventoryMalformedStatus_whenEnabled_reverts]: reEnable.t.sol#L209

[test_givenPayoutMalformedStatus_whenEnabled_reverts]: reEnable.t.sol#L300

[test_givenRiskMalformedStatus_whenEnabled_reverts]: reEnable.t.sol#L391
