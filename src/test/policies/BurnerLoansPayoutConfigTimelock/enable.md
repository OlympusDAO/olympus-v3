# BurnerLoansPayoutConfigTimelock.enable coverage plan

Coverage records implemented domains and assertions independently of pass/fail status.

Source: [enable](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol).

## Domains and notation

Scenario scope: `BLCUCT-ENABLE`. Valid default: real same-Kernel Payout, stored controller=this timelock, cached ROLES initialized, Local active=true and Local enabled=false. Payout has IEnabler, but recovery ignores its paused state; Core lifecycle, Payout inactivity and Core selection do not block recovery. Core must be idle for target mutations. Proposers fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap; distributor replacement is direct ADMIN-only and is not admitted by this queue or batches.

Unchanged means authoritative state, balances, allowances and committed logs applicable to this function remain unchanged. Faults are isolated with all other prerequisites satisfied. Use [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md); preserve independent lifecycle columns and guaranteed numeric boundary seeds.

## Dependency validation contract

The immutable Payout target must remain interface/Kernel/controller-compatible; active/enabled target flags do not gate recovery on an old Payout. Validate own timelock readiness. Do not require Core operation or current Core selection, and do not reuse the stricter Core.setPayout operational requirement here.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: Payout → `BurnerLoansPayoutTimelock_InvalidPayout(Payout)`.

## Authorization

ROLES initialized; valid history/grace for reEnable. Shared local-state/sentinel checks precede authorization.

| ID | Caller | Local active | Local enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-ENABLE-A01 | Fuzz ADMIN_ROLE holder | true | false | Success with valid prerequisites | Exact local transition/timestamp/events; no target/accounting mutation | Covered: [test][test_givenReadyBinding_whenActivated_thenExactTransition] |
| BLCUCT-ENABLE-A02 | Fuzz outside every accepted role class | true | false | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test][test_givenUnauthorizedCaller_whenActivated_reverts] |

## Local lifecycle

Data=0x for enable/disable; reEnable is parameterless. For reEnable fix lastTransitionAt>0 and a representable unexpired deadline.

| ID | Caller | Local active | Local enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-ENABLE-L01 | Fuzz all callers | true | true | NotDisabled() | Exact transition on success; unchanged on failure | Covered: [test][test_givenAlreadyEnabled_whenActivated_reverts] |
| BLCUCT-ENABLE-L02 | Fuzz all callers | false | true | NotDisabled() | Exact transition on success; unchanged on failure | Covered: [test][test_givenAlreadyEnabled_whenActivated_reverts] |
| BLCUCT-ENABLE-L03 | Fuzz ADMIN_ROLE holder | true | false | Success with ready bindings | Exact transition on success; unchanged on failure | Covered: [test][test_givenReadyBinding_whenActivated_thenExactTransition] |
| BLCUCT-ENABLE-L04 | Fuzz ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansPayoutConfigTimelock) | Exact transition on success; unchanged on failure | Covered: [test][test_givenInactivePolicy_whenActivated_reverts] |

## Unused payload

Correct starting local state; caller authorized; all other prerequisites ready. State/auth checks precede payload validation.

| ID | Caller | Payload | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-ENABLE-I01 | Fuzz ADMIN_ROLE holder | data=0x | Success with normal prerequisites | One transition and exact events | Covered: [test][test_givenReadyBinding_whenActivated_thenExactTransition] |
| BLCUCT-ENABLE-I02 | Fuzz ADMIN_ROLE holder | Fuzz nonempty length1..256; seed1,256 and encoded zero | BurnerLoans_InvalidEnablerData() | No transition/timestamp/events | Covered: [test][test_whenNonemptyPayload_reverts], [test][test_whenPayloadBoundarySeeds_reverts] |

## Target identity and controller

Local active=true, Local enabled=false; Core paused/inactive is permitted. Enable and reEnable use identical binding checks.

| ID | Caller | Fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-ENABLE-D01 | Fuzz ADMIN_ROLE holder | Bound Payout reports another Kernel | PolicyDependency_KernelMismatch(Payout,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenWrongKernel_whenActivated_reverts] |
| BLCUCT-ENABLE-D02 | Fuzz ADMIN_ROLE holder | Stored controller=another address | BurnerLoansPayoutTimelock_NotController() | Unchanged | Covered: [test][test_givenControllerChanged_whenActivated_reverts] |
| BLCUCT-ENABLE-D03 | Fuzz ADMIN_ROLE holder | Bound Payout inactive/retired; its Kernel matches and controller selects this timelock | Success | No Core operation/lifecycle or Payout enabled getter required for recovery | Covered: [test][test_givenReadyBinding_whenActivated_thenExactTransition] |
| BLCUCT-ENABLE-D04 | Fuzz ADMIN_ROLE holder | Payout Kernel getter raises configured error | PolicyDependency_InvalidDependency(Payout) | Unchanged | Covered: [test][test_givenKernelGetterReverts_whenActivated_reverts] |
| BLCUCT-ENABLE-D05 | Fuzz ADMIN_ROLE holder | Payout controller getter raises configured error | BurnerLoansPayoutTimelock_InvalidPayout(Payout) | Unchanged | Covered: [test][test_givenControllerGetterReverts_whenActivated_reverts] |

- [x] Derive concrete acceptance criteria from the implemented call path.
- [x] Implement focused tests and map exact domains/effects; execution results are tracked separately.

[test_givenAlreadyEnabled_whenActivated_reverts]: ./enable.t.sol#L64
[test_givenControllerChanged_whenActivated_reverts]: ./enable.t.sol#L114
[test_givenInactivePolicy_whenActivated_reverts]: ./enable.t.sol#L77
[test_givenKernelGetterReverts_whenActivated_reverts]: ./enable.t.sol#L130
[test_givenReadyBinding_whenActivated_thenExactTransition]: ./enable.t.sol#L21
[test_givenUnauthorizedCaller_whenActivated_reverts]: ./enable.t.sol#L51
[test_givenWrongKernel_whenActivated_reverts]: ./enable.t.sol#L93
[test_whenNonemptyPayload_reverts]: ./enable.t.sol#L168
[test_whenPayloadBoundarySeeds_reverts]: ./enable.t.sol#L183

[test_givenControllerGetterReverts_whenActivated_reverts]: ./enable.t.sol#L147
