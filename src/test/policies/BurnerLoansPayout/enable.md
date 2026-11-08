# BurnerLoansPayout.enable coverage plan

Source: [enable](../../../bases/EnablerV2.sol); product hooks in [Payout](../../../policies/burnerloans/BurnerLoansPayout.sol).

Scenario scope: `BLCU-ENABLE`. Cached ROLES is initialized by Kernel activation. Core is idle and its lifecycle is independent. New credits require Payout active/enabled; claims, route repair and recovery stay available after pause.

## Dependency validation contract

Core is an immutable authority/guard reference, not an enabled-only dependency. Core/controller readiness does not gate Payout activation or old-claim recovery. Distributor selection and true routing flags validate that external service; transfer failure can leave pending payouts, so do not introduce a new hard distributor activation gate. Settlement guards still apply.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

## Authorization

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-ENABLE-A01 | Fuzz caller excluding every ADMIN holder | true | false | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test_givenUnauthorized_whenEnabled_reverts][test_givenUnauthorized_whenEnabled_reverts] |

## Lifecycle

Data is empty. Other dependencies do not gate a pause; enable requires own Kernel activity without depending on upstream Core readiness.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-ENABLE-L01 | ADMIN_ROLE holder | true | false | Success | On success only isEnabled/lastTransitionAt and transition events change; otherwise unchanged | Covered: [test_givenPaused_whenEnabled_thenExactTransition][test_givenPaused_whenEnabled_thenExactTransition] |
| BLCU-ENABLE-L02 | ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(Payout) | On success only isEnabled/lastTransitionAt and transition events change; otherwise unchanged | Covered: [test_givenInactiveDisabled_whenEnabled_reverts][test_givenInactiveDisabled_whenEnabled_reverts] |
| BLCU-ENABLE-L03 | ADMIN_ROLE holder | true | true | NotDisabled() | On success only isEnabled/lastTransitionAt and transition events change; otherwise unchanged | Covered: [test_givenAlreadyEnabled_whenEnabled_reverts][test_givenAlreadyEnabled_whenEnabled_reverts] |
| BLCU-ENABLE-L04 | ADMIN_ROLE holder | false | true | NotDisabled() | On success only isEnabled/lastTransitionAt and transition events change; otherwise unchanged | Covered: [test_givenAlreadyEnabled_whenEnabled_reverts][test_givenAlreadyEnabled_whenEnabled_reverts] |

## Invalid inputs

| ID | Caller | Data | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-ENABLE-I01 | ADMIN_ROLE holder | Fuzz nonempty bytes length 1..256; seed 0x00 and ABI-encoded zero | BurnerLoans_InvalidEnablerData() | Unchanged | Covered: [test_whenNonemptyData_reverts][test_whenNonemptyData_reverts]; [test_whenNonemptyDataAtBoundaries_reverts][test_whenNonemptyDataAtBoundaries_reverts] |

## Settlement safety

| ID | Caller | Guard | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-ENABLE-C01 | ADMIN_ROLE holder | Payout outgoing token callback | ReentrancyGuardReentrantCall() | No lifecycle change during payout | Covered: [test_givenOutgoingCallback_whenAuthorizedTokenTransitions_thenGuardRejects][test_givenOutgoingCallback_whenAuthorizedTokenTransitions_thenGuardRejects] |
| BLCU-ENABLE-C02 | ADMIN_ROLE holder | Core incoming transfer or settlement | ReentrancyGuardReentrantCall() | No lifecycle change during settlement | Covered: [test_givenCoreBusy_whenEnabled_reverts][test_givenCoreBusy_whenEnabled_reverts]; [test_givenIncomingCallback_whenAuthorizedTokenTransitions_thenCoreGuardRejects][test_givenIncomingCallback_whenAuthorizedTokenTransitions_thenCoreGuardRejects] |

[test_givenAlreadyEnabled_whenEnabled_reverts]: ./enable.t.sol#L71
[test_givenCoreBusy_whenEnabled_reverts]: ./enable.t.sol#L102
[test_givenInactiveDisabled_whenEnabled_reverts]: ./enable.t.sol#L58
[test_givenIncomingCallback_whenAuthorizedTokenTransitions_thenCoreGuardRejects]: ./enableCallback.t.sol#L40
[test_givenOutgoingCallback_whenAuthorizedTokenTransitions_thenGuardRejects]: ./enableCallback.t.sol#L19
[test_givenPaused_whenEnabled_thenExactTransition]: ./enable.t.sol#L22
[test_givenUnauthorized_whenEnabled_reverts]: ./enable.t.sol#L45
[test_whenNonemptyDataAtBoundaries_reverts]: ./enable.t.sol#L92
[test_whenNonemptyData_reverts]: ./enable.t.sol#L81
