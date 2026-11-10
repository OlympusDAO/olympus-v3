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

## Core compatibility and readiness

Payout retains both settlement guards and its own Kernel membership requirement. Enable and reEnable share the same Core compatibility checks.

| ID | Caller | Core metadata | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-ENABLE-D01 | ADMIN | Core enabled getter returns arbitrary bytes | Success without Core activity or enablement probes | Obligations and custody preserved | Covered: [test][test_givenUnreadableCoreReadiness_whenEnabled] |

## Callable Core compatibility

Construction and activation share the same IBurnerLoansCore interface validator. Core must report the same Kernel; its activity and local enablement remain independent. Existing payload, settlement, own-policy and caller guards retain their order.

| ID | Core condition | Result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLCU-ENABLE-D06 | Missing IBurnerLoansCore support | BurnerLoansPayout_InvalidCore(Core) | Paused state and timestamp preserved; restoring support permits retry | Covered: [test][test_givenMissingCoreInterface_whenActivated_reverts] |
| BLCU-ENABLE-D07 | Interface probe reverts | BurnerLoansPayout_InvalidCore(Core) | Paused state and timestamp preserved; restoring support permits retry | Covered: [test][test_givenRevertingCoreInterface_whenActivated_reverts] |
| BLCU-ENABLE-D08 | Interface probe returns short data | BurnerLoansPayout_InvalidCore(Core) | Paused state and timestamp preserved; restoring support permits retry | Covered: [test][test_givenMalformedCoreInterface_whenActivated_reverts] |

## Core compatibility acceptance criteria

Constructor and activation share the same interface and Kernel validator. Interface rejection precedes Kernel probing. Failed activation preserves lifecycle fields, configuration, accounting and events; restoring compatibility permits retry. Core need not be active or enabled. Existing authorization, settlement and grace guards retain their order. No numeric action inputs, new accounting or token transfers are introduced. Existing lifecycle, authorization and grace matrices remain applicable.

| ID | Core condition | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLCU-ENABLE-K03 | Kernel getter returns short, oversized or noncanonical ABI data; fuzz non-32-byte responses and seed lengths 0,1,31,33,64 plus MAX256 word | PolicyDependency_InvalidDependency(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenMalformedCoreKernel_whenActivated_revertsThenRestored]; [test][test_givenMalformedCoreKernelBoundaries_whenActivated_revertsThenRestored] |
| BLCU-ENABLE-K01 | Core reports another Kernel | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenDifferentCoreKernel_whenActivated_revertsThenRestored] |
| BLCU-ENABLE-K02 | Core Kernel getter reverts | PolicyDependency_InvalidDependency(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenRevertingCoreKernel_whenActivated_revertsThenRestored] |
| BLCU-ENABLE-K04 | Core migrates while old Kernel retains active membership; pause remains available | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenCoreMigrated_whenActivated_revertsThenRestored] |

[test_givenAlreadyEnabled_whenEnabled_reverts]: ./enable.t.sol#L100
[test_givenCoreBusy_whenEnabled_reverts]: ./enable.t.sol#L131
[test_givenInactiveDisabled_whenEnabled_reverts]: ./enable.t.sol#L87
[test_givenIncomingCallback_whenAuthorizedTokenTransitions_thenCoreGuardRejects]: ./enableCallback.t.sol#L40
[test_givenOutgoingCallback_whenAuthorizedTokenTransitions_thenGuardRejects]: ./enableCallback.t.sol#L19
[test_givenPaused_whenEnabled_thenExactTransition]: ./enable.t.sol#L29
[test_givenUnauthorized_whenEnabled_reverts]: ./enable.t.sol#L74
[test_whenNonemptyDataAtBoundaries_reverts]: ./enable.t.sol#L121
[test_whenNonemptyData_reverts]: ./enable.t.sol#L110

[test_givenUnreadableCoreReadiness_whenEnabled]: ./enable.t.sol#L52

[test_givenMissingCoreInterface_whenActivated_reverts]: ./enable.t.sol#L162

[test_givenRevertingCoreInterface_whenActivated_reverts]: ./enable.t.sol#L188

[test_givenMalformedCoreInterface_whenActivated_reverts]: ./enable.t.sol#L217

[test_givenMalformedCoreKernel_whenActivated_revertsThenRestored]: enable.t.sol#L242

[test_givenMalformedCoreKernelBoundaries_whenActivated_revertsThenRestored]: enable.t.sol#L262

[test_givenDifferentCoreKernel_whenActivated_revertsThenRestored]: enable.t.sol#L291

[test_givenRevertingCoreKernel_whenActivated_revertsThenRestored]: enable.t.sol#L311

[test_givenCoreMigrated_whenActivated_revertsThenRestored]: enable.t.sol#L330
