# BurnerLoansPayoutConfigTimelock.reEnable coverage plan

Coverage records implemented domains and assertions independently of pass/fail status.

Source: [reEnable](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol).

## Domains and notation

Scenario scope: `BLCUCT-REENABLE`. Valid default: real same-Kernel Payout, stored controller=this timelock, cached ROLES initialized, Local active=true and Local enabled=false. Payout has IEnabler, but recovery ignores its paused state; Core lifecycle and Core selection do not block recovery; the Payout Policy must be active. Core must be idle for target mutations. Proposers fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap; distributor replacement is direct ADMIN-only and is not admitted by this queue or batches.

Unchanged means authoritative state, balances, allowances and committed logs applicable to this function remain unchanged. Faults are isolated with all other prerequisites satisfied. Use [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md); preserve independent lifecycle columns and guaranteed numeric boundary seeds.

## Dependency validation contract

The immutable Payout target must remain interface/Kernel/controller-compatible; target activity is required for activation; target enablement and current Core selection are not required. Validate own timelock readiness. Do not require Core operation or current Core selection, and do not reuse the stricter Core.setPayout operational requirement here.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: Payout → `BurnerLoansPayoutTimelock_InvalidPayout(Payout)`.

## Authorization

ROLES initialized; valid history/grace for reEnable. Shared local-state/sentinel checks precede authorization.

| ID | Caller | Local active | Local enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-REENABLE-A01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only, overlap | true | false | Success with valid prerequisites | Exact local transition/timestamp/events; no target/accounting mutation | Covered: [test][test_givenReadyBinding_whenActivated_thenExactTransition] |
| BLCUCT-REENABLE-A02 | Fuzz outside every accepted role class | true | false | NotAuthorised() | Unchanged | Covered: [test][test_givenUnauthorizedCaller_whenActivated_reverts] |

## Local lifecycle

Data=0x for enable/disable; reEnable is parameterless. For reEnable fix lastTransitionAt>0 and a representable unexpired deadline.

| ID | Caller | Local active | Local enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-REENABLE-L01 | Fuzz all callers | true | true | NotDisabled() | Exact transition on success; unchanged on failure | Covered: [test][test_givenAlreadyEnabled_whenActivated_reverts] |
| BLCUCT-REENABLE-L02 | Fuzz all callers | false | true | NotDisabled() | Exact transition on success; unchanged on failure | Covered: [test][test_givenAlreadyEnabled_whenActivated_reverts] |
| BLCUCT-REENABLE-L03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only, overlap | true | false | Success with ready bindings | Exact transition on success; unchanged on failure | Covered: [test][test_givenReadyBinding_whenActivated_thenExactTransition] |
| BLCUCT-REENABLE-L04 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only, overlap | false | false | BurnerLoans_PolicyNotActive(BurnerLoansPayoutConfigTimelock) | Exact transition on success; unchanged on failure | Covered: [test][test_givenInactivePolicy_whenActivated_reverts] |

## Target identity and controller

Local active=true, Local enabled=false; Core paused/inactive is permitted. Enable and reEnable use identical binding checks.

| ID | Caller | Fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-REENABLE-D01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only, overlap | Bound Payout reports another Kernel | PolicyDependency_KernelMismatch(Payout,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenWrongKernel_whenActivated_reverts] |
| BLCUCT-REENABLE-D02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only, overlap | Stored controller=another address | BurnerLoansPayoutTimelock_NotController() | Unchanged | Covered: [test][test_givenControllerChanged_whenActivated_reverts] |
| BLCUCT-REENABLE-D03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only, overlap | Bound Payout Policy inactive; fuzz its enabled flag; Kernel and controller remain valid | PolicyDependency_NotActive(Payout) | Unchanged; no activation or accounting change | Covered: [test][test_givenInactivePayout_whenActivated_reverts] |
| BLCUCT-REENABLE-D04 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only, overlap | Payout Kernel getter raises configured error | PolicyDependency_InvalidDependency(Payout) | Unchanged | Covered: [test][test_givenKernelGetterReverts_whenActivated_reverts] |
| BLCUCT-REENABLE-D05 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only, overlap | Payout controller getter raises configured error | BurnerLoansPayoutTimelock_InvalidPayout(Payout) | Unchanged | Covered: [test][test_givenControllerGetterReverts_whenActivated_reverts] |

## Initialization

| ID | Caller | History | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-REENABLE-I01 | Fuzz all callers | Local disabled; lastTransitionAt=0 | NeverEnabled() before role lookup | Unchanged | Covered: [test][test_givenNeverEnabled_whenReEnabled_reverts] |

## Grace interval

Otherwise initialized, disabled, active, authorized and valid bindings.

| ID | Caller | Time / history | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-REENABLE-N01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only, overlap | L>0; G>0; L+G<=MAX48; fuzz now in L..L+G-1, seed both edges | Success | lastTransitionAt=now; one Enabled/Transition pair | Covered: [test][test_givenWithinGrace_whenReEnabled_thenExactTransition], [test][test_whenGraceBoundarySeedsUsed] |
| BLCUCT-REENABLE-N02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only, overlap | now=L+G, including maximum representable deadline | Success | Inclusive grace deadline | Covered: [test][test_givenWithinGrace_whenReEnabled_thenExactTransition], [test][test_whenGraceBoundarySeedsUsed] |
| BLCUCT-REENABLE-N03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only, overlap | Fuzz now>L+G; seed deadline+1 and MAX48 | GracePeriod_Expired(deadline) | Unchanged | Covered: [test][test_givenExpiredGrace_whenReEnabled_reverts], [test][test_whenGraceBoundarySeedsUsed] |
| BLCUCT-REENABLE-N04 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only, overlap | Fuzz L>MAX48-G; G in1..MAX32; widened L+G overflows uint48 | SafeCastOverflowedUintDowncast(48,L+G) | No arithmetic panic or transition | Covered: [test][test_givenGraceOverflow_whenReEnabled_reverts], [test][test_whenGraceBoundarySeedsUsed] |

- [x] Derive concrete acceptance criteria from the implemented call path.
- [x] Implement focused tests and map exact domains/effects; execution results are tracked separately.

## Activation compatibility

Activation and reactivation require compatible target, ConfigOperator and Enabler interfaces, same Kernel, target Policy activity and this queue selected as configOperator. They do not read the target's enabled status. This allows queue repair while the target remains paused; each queued operation still enforces its own execution requirements. Other transition/caller/history/grace/payload guards retain their existing order.

Caller is authorized and every prerequisite not varied below is valid. An incompatible target leaves lifecycle history, pending actions, reservations, configuration and custody unchanged.

| ID | Target active | Target enabled | Input fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-REENABLE-D06 | true | false | None; Core may be inactive/paused or select another Payout | Success | Exact local transition; preserve target and queue | Covered: [test][test_givenReadyBinding_whenActivated_thenExactTransition] |
| BLCUCT-REENABLE-D07 | true | Fuzz false/true | Reject each consumed interface advertisement; seed every interface | BurnerLoansPayoutTimelock_InvalidPayout(Payout) | Unchanged | Covered: [test][test_givenMissingConsumedInterface_whenActivated_reverts] |

[test_givenAlreadyEnabled_whenActivated_reverts]: ./reEnable.t.sol#L72
[test_givenControllerChanged_whenActivated_reverts]: ./reEnable.t.sol#L126
[test_givenExpiredGrace_whenReEnabled_reverts]: ./reEnable.t.sol#L230
[test_givenGraceOverflow_whenReEnabled_reverts]: ./reEnable.t.sol#L255
[test_givenInactivePolicy_whenActivated_reverts]: ./reEnable.t.sol#L85
[test_givenKernelGetterReverts_whenActivated_reverts]: ./reEnable.t.sol#L144
[test_givenNeverEnabled_whenReEnabled_reverts]: ./reEnable.t.sol#L186
[test_givenReadyBinding_whenActivated_thenExactTransition]: ./reEnable.t.sol#L28
[test_givenUnauthorizedCaller_whenActivated_reverts]: ./reEnable.t.sol#L59
[test_givenWithinGrace_whenReEnabled_thenExactTransition]: ./reEnable.t.sol#L200
[test_givenWrongKernel_whenActivated_reverts]: ./reEnable.t.sol#L103
[test_whenGraceBoundarySeedsUsed]: ./reEnable.t.sol#L280

[test_givenControllerGetterReverts_whenActivated_reverts]: ./reEnable.t.sol#L163

[test_givenInactivePayout_whenActivated_reverts]: reEnable.t.sol#L331

[test_givenMissingConsumedInterface_whenActivated_reverts]: reEnable.t.sol#L347
