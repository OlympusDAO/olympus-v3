# BurnerLoansSeizerTask.reEnable coverage plan

Implemented scan binding: read the constructor-bound Lens directly. Core owns no Lens pointer. Lens has no local enabled state or Kernel membership prerequisite; Seize is the direct operational Policy dependency. Core is derived from Seize and must match Lens.

Source: [reEnable](../../../bases/ReEnabler.sol#L46). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Normalized scenario scope: `BLSEIZ-REENABLE` identifies this contract/function. State and caller variations belong in table columns; case numbers identify distinct rows.

Required policy lifecycle: reEnable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive.

For grace fuzzing, `L=lastTransitionAt>0`, `G=gracePeriod>0`, `D=L+G`. Use compatible setup with `L<=MAX48-G`; fuzz valid now in L..D and expired now in D+1..MAX48 only when D<MAX48. Seed L,D-1,D,D+1,MAX48 where each belongs to the selected outcome. Vary time independently from the configured deadline; no single-boundary test substitutes for interval coverage.

`reEnable()` is parameterless. Successful Transition always carries empty data; there is no bytes argument to validate.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each: independently fuzz a nonzero caller and grant ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE. Guarantee seeds with ADMIN_ROLE only, BURNER_LOANS_ADMIN_ROLE only and both roles; select the role independently from time and dependency inputs. These roles follow the same reEnable behavior, so each equivalent validation/time case has one row. Fuzz permitted callback caller uses a callback contract holding the selected role, with the outer operation initiated by its separately authorized caller.

Seize must be active/enabled. Seize must report this Kernel, and Lens must report the same Core as Seize. Task validates Core interface compatibility at construction and activation; Seize owns Core Kernel and operational-readiness checks. Core has no independent Task lifecycle gate. SeizerTask must be Kernel-active. ROLES initialized. The permitted caller fuzz family above names every accepted role; unauthorized fuzzing excludes all holders of those roles. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Dependency validation contract

Constructor-bound Seize is the required operational Policy. Derive Core from Seize and require Lens.core() to match. Core readiness is enforced by Seize during settlement, without a separate Task activation gate. Lens is a plain constructor-bound helper: verify its interface/Core identity without inventing Kernel membership or enablement. Required settlement/task roles remain separate authorization prerequisites.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Readable Kernel mismatches use PolicyDependency_KernelMismatch(Seize,expectedKernel,reportedKernel); a zero or incompatible Seize target uses BurnerLoansSeizer_InvalidSeize(Seize); Lens mismatch uses BurnerLoansSeizer_InvalidLens; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility errors: readable Seize Kernel mismatch → `PolicyDependency_KernelMismatch(Seize,expectedKernel,reportedKernel)`; zero or incompatible Seize → `BurnerLoansSeizer_InvalidSeize(Seize)`; Lens/Core mismatch → `BurnerLoansSeizer_InvalidLens(Lens)`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-REENABLE-A01 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; within grace | `NotAuthorised()` | Unchanged | Unmapped |
| BLSEIZ-REENABLE-A02 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; expired grace; one failed dependency | `NotAuthorised()` | Unchanged; authorization before grace/dependency | Unmapped |

## Grace deadline overflow

Initialized, locally disabled; otherwise compatible dependencies. Configure G while enabled, disable at L and assert the stored transition timestamp before attempting reEnable. Checked uint48 deadline narrowing is the required behavior: the deadline must fit in uint48. The setter stores a nonzero uint32 duration; the future disable timestamp is not known when it is set.

| ID | Caller | Prior transition L | Grace G | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-REENABLE-N01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz MAX48-G+1..MAX48 | Configured G in 1..MAX32; seed1,MAX32 | L | `SafeCastOverflowedUintDowncast(48, uint256(L)+uint256(G))` | Unchanged; no committed transition logs | Unmapped |

Implemented lifecycle payload rule: calculate D=uint256(L)+uint256(G), then use checked SafeCast narrowing to uint48. If D exceeds MAX48, revert with SafeCastOverflowedUintDowncast(48,D). The product-local _requireGrace override uses widened addition and checked uint48 narrowing; it leaves shared ReEnabler behavior unchanged. Preserve local enabled state, transition timestamp, configuration and balances; commit no lifecycle events. The duration setter cannot validate an unknown future disable timestamp.

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Local transition state

| ID | Caller | Local active | Local enabled | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-REENABLE-L01 | Fuzz all callers | Fuzz false/true | true | Fuzz zero/nonzero | NotDisabled() | Unchanged; before authorization and hook reads | Unmapped |
| BLSEIZ-REENABLE-L02 | Fuzz all callers | Fuzz false/true | false | 0 | NeverEnabled() | Unchanged; before authorization and hook reads | Unmapped |

## Timing and transition history

Local enabled=false; L=lastTransitionAt>0; G=gracePeriod>0; D=L+G<=MAX48. Seize must be active/enabled. Seize must report this Kernel, and Lens must report the same Core as Seize. Task validates Core interface compatibility at construction and activation; Seize owns Core Kernel and operational-readiness checks. Core has no independent Task lifecycle gate. SeizerTask must be Kernel-active. Core settlement guard is not entered. Seed boundaries through the same case assertions; no now/deadline correlation.

| ID | Caller | Time domain / boundary seeds | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-REENABLE-P01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Independently fuzz L,G with 0<L<=MAX48-G; fuzz now in L..D-1; seed L,D-1 and D=MAX48 | Success | Enabled then Transition(caller,true,0x,now); lastTransitionAt=now | Unmapped |
| BLSEIZ-REENABLE-P02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz compatible L,G; now=D; seed D=MAX48 | Success | Inclusive deadline; exact local transition/events | Unmapped |
| BLSEIZ-REENABLE-P03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz compatible L,G with D<MAX48; fuzz now in D+1..MAX48; seed D+1,MAX48 | GracePeriod_Expired(D) | Unchanged; no committed logs | Unmapped |

## Dependency lifecycle

For policy-service dependencies, active means membership in this consumer’s Kernel via `kernel.isPolicyActive(dependency)`, separately from a matching reported kernel(). Inactive-dependency cases retain a matching reported Kernel to prove that self-reporting alone cannot pass. A bound action or helper must report the consumer’s expected Core through core(); shared services such as DepositManager have no invented Core binding. Constructor identity binding may precede activation.

Local enabled=false; prior L>0; independently fuzz a representable valid grace interval. Seize must be active/enabled. Seize must report this Kernel, and Lens must report the same Core as Seize. Task validates Core interface compatibility at construction and activation; Seize owns Core Kernel and operational-readiness checks. Core has no independent Task lifecycle gate. SeizerTask must be Kernel-active. Fuzz both permitted role classes through every enable prerequisite. All dependencies except the one named in each row retain those explicit defaults. Local state/time and authorization are fixed above; activity and enablement are independent columns.

| ID | Caller | Dependency | Dependency active | Dependency enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-REENABLE-D02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Seize | false | true | PolicyDependency_NotActive(Seize) | Exact local transition/events on Success; otherwise Unchanged | Partial: [test][test_givenSeizeInactiveOrDisabled_whenReEnabled_reverts]; other permitted caller partitions remain planned |
| BLSEIZ-REENABLE-D05 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Seize | false | false | PolicyDependency_NotActive(Seize) | Exact local transition/events on Success; otherwise Unchanged | Partial: [test][test_givenSeizeInactiveOrDisabled_whenReEnabled_reverts]; other permitted caller partitions remain planned |
| BLSEIZ-REENABLE-D06 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Seize | true | false | PolicyDependency_NotActive(Seize) | Unchanged; no logs | Partial: [test][test_givenSeizeInactiveOrDisabled_whenReEnabled_reverts]; other permitted caller partitions remain planned |

Retired IDs: BLSEIZ-REENABLE-D01, BLSEIZ-REENABLE-D03, BLSEIZ-REENABLE-D04. Core lifecycle does not gate Task activation; P10 proves that independence. Task validates Core interface compatibility alongside Seize readiness/Kernel and the Lens/Core binding.

Retired ID: BLSEIZ-REENABLE-D07. Core interface compatibility is covered by D12-D14. Core Kernel validation remains owned by Seize.

## Dependency compatibility

Local active=true; local enabled=false; initialized ROLES; all operational dependencies active/enabled; data=0x for enable, valid grace/history for reEnable. Vary one binding fault at a time. Validate these bindings directly; no additional registry or validator contract is needed.

| ID | Caller | Binding fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-REENABLE-D08 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Seize Kernel differs | PolicyDependency_KernelMismatch(Seize,expectedKernel,reportedKernel) | Unchanged; no committed transition/logs | Partial: [test][test_givenKernelDrift_whenReEnabled_reverts]; other permitted caller partitions remain planned |
| BLSEIZ-REENABLE-D09 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Lens reports a Core different from Seize.core() | BurnerLoansSeizer_InvalidLens(Lens) | Unchanged; no committed transition/logs | Partial: [test][test_givenLensCoreDrift_whenReEnabled_reverts]; other permitted caller partitions remain planned |

## Local activity

Local enabled=false; prior L>0; independently fuzz a representable valid grace interval. Seize must be active/enabled. Seize must report this Kernel, and Lens must report the same Core as Seize. Task validates Core interface compatibility at construction and activation; Seize owns Core Kernel and operational-readiness checks. Core has no independent Task lifecycle gate. SeizerTask must be Kernel-active. Fuzz both permitted role classes through every enable prerequisite. Own policy activity is required; the concrete hook checks local activity.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-REENABLE-L03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | false | false | BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask) | Unchanged; no activation, timestamp change or committed logs | Unmapped |

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-REENABLE-L04 | Fuzz all callers | false | false | 0 | 0 | `NeverEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Unmapped; fresh deployment, no dependency configuration |

## Test organization

[reEnable.t.sol](./reEnable.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.

## Core compatibility revalidation

The same compatibility predicate runs at construction, enable and reEnable. The consumer is active and paused, its caller is ADMIN, and all other prerequisites pass. Core Kernel metadata, membership and local enablement are not admission requirements here.

| ID | Fault or state | Result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-REENABLE-D12 | Core lacks IBurnerLoansCore | BurnerLoansSeizerTask_InvalidCore(Core) | Remain paused; timestamp unchanged; restoring the interface permits retry | Covered: [test][test_givenMissingCoreInterface_whenActivated_reverts] |
| BLSEIZ-REENABLE-D13 | Core interface probe reverts | BurnerLoansSeizerTask_InvalidCore(Core) | Remain paused; timestamp unchanged; restoring the interface permits retry | Covered: [test][test_givenRevertingCoreInterface_whenActivated_reverts] |
| BLSEIZ-REENABLE-D14 | Core interface probe returns short data | BurnerLoansSeizerTask_InvalidCore(Core) | Remain paused; timestamp unchanged; restoring the interface permits retry | Covered: [test][test_givenMalformedCoreInterface_whenActivated_reverts] |
| BLSEIZ-REENABLE-P10 | Compatible Core; active/enabled flags independently false/true; all four seeded | Success | Consumer becomes enabled | Covered: [test][test_givenCoreLifecycle_whenActivated]; [seeds][test_whenCoreLifecycleStatesSeeded_thenActivated] |

[test_givenKernelDrift_whenReEnabled_reverts]: ./reEnable.t.sol#L112
[test_givenLensCoreDrift_whenReEnabled_reverts]: ./reEnable.t.sol#L136
[test_givenSeizeInactiveOrDisabled_whenReEnabled_reverts]: ./reEnable.t.sol#L158

[test_givenMissingCoreInterface_whenActivated_reverts]: ./reEnable.t.sol#L201

[test_givenRevertingCoreInterface_whenActivated_reverts]: ./reEnable.t.sol#L224

[test_givenMalformedCoreInterface_whenActivated_reverts]: ./reEnable.t.sol#L247

[test_givenCoreLifecycle_whenActivated]: ./reEnable.t.sol#L270
[test_whenCoreLifecycleStatesSeeded_thenActivated]: ./reEnable.t.sol#L281
