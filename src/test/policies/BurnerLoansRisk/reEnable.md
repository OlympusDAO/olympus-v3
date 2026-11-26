# BurnerLoansRisk.reEnable coverage plan

Source: [reEnable](../../../bases/ReEnabler.sol#L46).

## Domains and notation

Scenario scope: `BLRISK-REENABLE`. ROLES is initialized through Kernel activation. Risk owns no loans or custody. A successful transition changes only isEnabled, lastTransitionAt and the inherited lifecycle events. Other configuration and all external state remain unchanged. enable/disable require empty bytes. reEnable has no payload and shares enable's activation checks after its own history/grace checks.

## Dependency validation contract

Risk validates its immutable Core interface and matching Kernel; Core activity and enablement and controller readiness do not gate Risk activation. Backing oracle must advertise IBackingOracle/IEnabler (no IVersioned requirement), report the same Kernel, be active in that Kernel and be enabled. Kernel/status failures use shared PolicyDependency errors. Optional cache needs IPriceCache/IEnabler/IVersioned and a matching Kernel; no numeric cache version is queried but may be inactive or disabled because PRICE is the fallback. Kernel modules use module-version checks, not Policy lifecycle checks.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: cache → `BurnerLoans_InvalidPriceCache(cache)`; oracle → `BurnerLoans_InvalidBackingOracle(oracle)`.

## Authorization

Subject has the state required for this transition; all other prerequisites are ready.

| ID | Caller | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLRISK-REENABLE-A01 | Fuzz caller excluding every permitted identity listed below | NotAuthorised() | No transition/logs | Covered: [test][test_whenUnauthorizedCaller_reverts] |
| BLRISK-REENABLE-A02 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | Success | Exact inherited events/timestamp and local flag | Covered: [test][test_givenAdmin_whenTransition], [test][test_givenLoanAdmin_whenTransition] |

## Local lifecycle

For inactive rows, activate then Kernel-deactivate Risk so cached ROLES remains available.

| ID | Caller | Local active | Local enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-REENABLE-L01 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | true | false | Success | Transition only on success | Covered: [test][test_givenAdmin_whenTransition], [test][test_givenLoanAdmin_whenTransition] |
| BLRISK-REENABLE-L02 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | true | true | NotDisabled() | Transition only on success | Covered: [test][test_givenAdminActive_whenAlreadyEnabled_reverts], [test][test_givenLoanAdminActive_whenAlreadyEnabled_reverts] |
| BLRISK-REENABLE-L03 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | false | false | BurnerLoans_PolicyNotActive(Risk) | Transition only on success | Covered: [test][test_givenAdminInactive_whenTransition_reverts], [test][test_givenLoanAdminInactive_whenTransition_reverts] |
| BLRISK-REENABLE-L04 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | false | true | NotDisabled() | Transition only on success | Covered: [test][test_givenAdminInactive_whenAlreadyEnabled_reverts], [test][test_givenLoanAdminInactive_whenAlreadyEnabled_reverts] |

## Direct dependency compatibility

The Core binding must expose IBurnerLoansCore and report the same Kernel. Core readiness, selected configOperator readiness and market population are not activation prerequisites. Modules are supplied by Kernel activation. Cache may be inactive or disabled because direct PRICE remains available.

| ID | Caller | Dependency / fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-REENABLE-D01 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | Backing oracle no longer supports its interface | BurnerLoans_InvalidBackingOracle(oracle) | No transition/logs | Covered: [test][test_givenAdminOracleInterface_whenTransition_reverts], [test][test_givenLoanAdminOracleInterface_whenTransition_reverts] |
| BLRISK-REENABLE-D02 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | Nonzero cache loses required interfaces | BurnerLoans_InvalidPriceCache(cache) | No transition/logs | Covered: [test][test_givenAdminCacheInterface_whenTransition_reverts], [test][test_givenLoanAdminCacheInterface_whenTransition_reverts] |
| BLRISK-REENABLE-D03 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | Nonzero cache reports another Kernel | PolicyDependency_KernelMismatch(cache,expectedKernel,reportedKernel) | No transition/logs | Covered: [test][test_givenAdminCacheKernel_whenTransition_reverts], [test][test_givenLoanAdminCacheKernel_whenTransition_reverts] |
| BLRISK-REENABLE-D04 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | Compatible optional cache; independently fuzz active/enabled and guarantee all four states | Success | PRICE fallback remains available | Covered: [test][test_givenAdminCache11_whenTransition], [test][test_givenAdminCache10_whenTransition], [test][test_givenAdminCache01_whenTransition], [test][test_givenAdminCache00_whenTransition], [test][test_givenLoanAdminCache11_whenTransition], [test][test_givenLoanAdminCache10_whenTransition], [test][test_givenLoanAdminCache01_whenTransition], [test][test_givenLoanAdminCache00_whenTransition] |
| BLRISK-REENABLE-D05 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | Restore failed dependency and retry same transition | Success | No stale failed state; exact lifecycle fields/events | Covered: [test][test_givenAdmin_whenDependencyRestored], [test][test_givenLoanAdmin_whenDependencyRestored] |

## History and grace period

L=lastTransitionAt, G=gracePeriod, D=L+G; local active=true, local enabled=false, authorized caller and compatible bindings.

| ID | Caller | History / time | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-REENABLE-N01 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | Never enabled; L=0 | NeverEnabled() | No transition/logs | Covered: [test][test_givenAdminNeverEnabled_whenReEnabled_reverts], [test][test_givenLoanAdminNeverEnabled_whenReEnabled_reverts] |
| BLRISK-REENABLE-N02 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | Fuzz representable L,G and independently now in L..D; seed L,D | Success | Enabled then Transition at now | Covered: [test][test_givenAdmin_whenWithinGrace], [test][test_givenAdmin_whenAtDisable], [test][test_givenAdmin_whenAtDeadline], [test][test_givenLoanAdmin_whenWithinGrace], [test][test_givenLoanAdmin_whenAtDisable], [test][test_givenLoanAdmin_whenAtDeadline] |
| BLRISK-REENABLE-N03 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | Fuzz now in D+1..MAX48; seed D+1,MAX48 | GracePeriod_Expired(D) | No transition/logs | Covered: [test][test_givenAdmin_whenGraceExpired_reverts], [test][test_givenAdmin_whenAfterDeadline_reverts], [test][test_givenAdmin_whenMaxTimestamp_reverts], [test][test_givenLoanAdmin_whenGraceExpired_reverts], [test][test_givenLoanAdmin_whenAfterDeadline_reverts], [test][test_givenLoanAdmin_whenMaxTimestamp_reverts] |
| BLRISK-REENABLE-N04 | Fuzz ADMIN or BURNER_LOANS_ADMIN_ROLE holder; guarantee each exclusive class | Fuzz L in MAX48-G+1..MAX48; seed endpoints | SafeCastOverflowedUintDowncast(48,uint256(L)+G) | No transition/logs | Covered: [test][test_givenAdmin_whenDeadlineOverflows_reverts], [test][test_givenAdmin_whenOverflowStart_reverts], [test][test_givenAdmin_whenOverflowEnd_reverts], [test][test_givenLoanAdmin_whenDeadlineOverflows_reverts], [test][test_givenLoanAdmin_whenOverflowStart_reverts], [test][test_givenLoanAdmin_whenOverflowEnd_reverts] |

- [x] Complete focused tests and exact mappings.

## Core compatibility acceptance criteria

Constructor and activation share the same interface and Kernel validator. Interface rejection precedes Kernel probing. Failed activation preserves lifecycle fields, configuration, accounting and events; restoring compatibility permits retry. Core need not be active or enabled. Existing authorization, settlement and grace guards retain their order. No numeric action inputs, new accounting or token transfers are introduced. Existing lifecycle, authorization and grace matrices remain applicable.

| ID | Core condition | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLRISK-REENABLE-K03 | Kernel getter returns short, oversized or noncanonical ABI data; fuzz non-32-byte responses and seed lengths 0,1,31,33,64 plus MAX256 word | PolicyDependency_InvalidDependency(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenMalformedCoreKernel_whenActivated_revertsThenRestored]; [test][test_givenMalformedCoreKernelBoundaries_whenActivated_revertsThenRestored] |
| BLRISK-REENABLE-K01 | Core reports another Kernel | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenDifferentCoreKernel_whenActivated_revertsThenRestored] |
| BLRISK-REENABLE-K02 | Core Kernel getter reverts | PolicyDependency_InvalidDependency(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenRevertingCoreKernel_whenActivated_revertsThenRestored] |
| BLRISK-REENABLE-I20 | Missing Core interface support/response | BurnerLoansRisk_InvalidCore(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenMissingCoreInterface_whenActivated_revertsThenRestored] |
| BLRISK-REENABLE-I21 | Reverting Core interface support/response | BurnerLoansRisk_InvalidCore(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenRevertingCoreInterface_whenActivated_revertsThenRestored] |
| BLRISK-REENABLE-I22 | Malformed Core interface support/response | BurnerLoansRisk_InvalidCore(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenMalformedCoreInterface_whenActivated_revertsThenRestored] |
| BLRISK-REENABLE-K05 | Same-Kernel compatible Core; all four active/enabled combinations | Success without Core readiness probes | Exact normal success; other state preserved | Covered: [test][test_givenCoreLifecycle_whenCompatible]; [test][test_whenCoreLifecycleSeeds] |

## Backing lifecycle acceptance

After existing state/history, authorization and grace checks, reEnable uses the
same oracle compatibility and readiness checks as enable: IBackingOracle/IEnabler,
same Kernel, active membership and local enablement. No IVersioned is required.

| ID | Caller | Scenario | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLRISK-REENABLE-D06 | ADMIN | Oracle active/enabled vary independently; exclude true/true | PolicyDependency_NotActive(oracle); no committed changes | Covered: [test][test_givenBackingUnavailable_whenConsumed_reverts] |
| BLRISK-REENABLE-D07 | ADMIN | Deterministic oracle states: active/disabled, inactive/enabled, inactive/disabled | PolicyDependency_NotActive(oracle) for each seed | Covered: [test][test_givenBackingLifecycleBoundaries_whenConsumed_reverts] |
| BLRISK-REENABLE-D08 | ADMIN | Oracle kernel() reports 0xBAD instead of Risk Kernel | PolicyDependency_KernelMismatch(oracle,Risk Kernel,0xBAD) | Covered: [test][test_givenBackingForeignKernel_whenAdmitted_reverts] |
| BLRISK-REENABLE-D09 | ADMIN | Oracle kernel() returns uint256.max, a noncanonical address | PolicyDependency_InvalidDependency(oracle) | Covered: [test][test_givenBackingMalformedKernel_whenAdmitted_reverts] |
| BLRISK-REENABLE-D10 | ADMIN | Oracle no longer advertises IEnabler | BurnerLoans_InvalidBackingOracle(oracle) | Covered: [test][test_givenBackingMissingEnabler_whenAdmitted_reverts] |

[test_givenAdminActive_whenAlreadyEnabled_reverts]: reEnable.t.sol#L68

[test_givenAdminCache00_whenTransition]: reEnable.t.sol#L222

[test_givenAdminCache01_whenTransition]: reEnable.t.sol#L207

[test_givenAdminCache10_whenTransition]: reEnable.t.sol#L192

[test_givenAdminCache11_whenTransition]: reEnable.t.sol#L177

[test_givenAdminCacheInterface_whenTransition_reverts]: reEnable.t.sol#L123

[test_givenAdminCacheKernel_whenTransition_reverts]: reEnable.t.sol#L151

[test_givenAdminInactive_whenAlreadyEnabled_reverts]: reEnable.t.sol#L77

[test_givenAdminInactive_whenTransition_reverts]: reEnable.t.sol#L88

[test_givenAdminNeverEnabled_whenReEnabled_reverts]: reEnable.t.sol#L256

[test_givenAdminOracleInterface_whenTransition_reverts]: reEnable.t.sol#L99

[test_givenAdmin_whenAfterDeadline_reverts]: reEnable.t.sol#L326

[test_givenAdmin_whenAtDeadline]: reEnable.t.sol#L301

[test_givenAdmin_whenAtDisable]: reEnable.t.sol#L292

[test_givenAdmin_whenDeadlineOverflows_reverts]: reEnable.t.sol#L352

[test_givenAdmin_whenDependencyRestored]: reEnable.t.sol#L237

[test_givenAdmin_whenGraceExpired_reverts]: reEnable.t.sol#L310

[test_givenAdmin_whenMaxTimestamp_reverts]: reEnable.t.sol#L339

[test_givenAdmin_whenOverflowEnd_reverts]: reEnable.t.sol#L394

[test_givenAdmin_whenOverflowStart_reverts]: reEnable.t.sol#L376

[test_givenAdmin_whenTransition]: reEnable.t.sol#L61

[test_givenAdmin_whenWithinGrace]: reEnable.t.sol#L274

[test_givenLoanAdminActive_whenAlreadyEnabled_reverts]: reEnable.t.sol#L419

[test_givenLoanAdminCache00_whenTransition]: reEnable.t.sol#L573

[test_givenLoanAdminCache01_whenTransition]: reEnable.t.sol#L558

[test_givenLoanAdminCache10_whenTransition]: reEnable.t.sol#L543

[test_givenLoanAdminCache11_whenTransition]: reEnable.t.sol#L528

[test_givenLoanAdminCacheInterface_whenTransition_reverts]: reEnable.t.sol#L474

[test_givenLoanAdminCacheKernel_whenTransition_reverts]: reEnable.t.sol#L502

[test_givenLoanAdminInactive_whenAlreadyEnabled_reverts]: reEnable.t.sol#L428

[test_givenLoanAdminInactive_whenTransition_reverts]: reEnable.t.sol#L439

[test_givenLoanAdminNeverEnabled_whenReEnabled_reverts]: reEnable.t.sol#L607

[test_givenLoanAdminOracleInterface_whenTransition_reverts]: reEnable.t.sol#L450

[test_givenLoanAdmin_whenAfterDeadline_reverts]: reEnable.t.sol#L677

[test_givenLoanAdmin_whenAtDeadline]: reEnable.t.sol#L652

[test_givenLoanAdmin_whenAtDisable]: reEnable.t.sol#L643

[test_givenLoanAdmin_whenDeadlineOverflows_reverts]: reEnable.t.sol#L703

[test_givenLoanAdmin_whenDependencyRestored]: reEnable.t.sol#L588

[test_givenLoanAdmin_whenGraceExpired_reverts]: reEnable.t.sol#L661

[test_givenLoanAdmin_whenMaxTimestamp_reverts]: reEnable.t.sol#L690

[test_givenLoanAdmin_whenOverflowEnd_reverts]: reEnable.t.sol#L745

[test_givenLoanAdmin_whenOverflowStart_reverts]: reEnable.t.sol#L727

[test_givenLoanAdmin_whenTransition]: reEnable.t.sol#L412

[test_givenLoanAdmin_whenWithinGrace]: reEnable.t.sol#L625

[test_whenUnauthorizedCaller_reverts]: reEnable.t.sol#L50

[test_givenMalformedCoreKernel_whenActivated_revertsThenRestored]: reEnable.t.sol#L763

[test_givenMalformedCoreKernelBoundaries_whenActivated_revertsThenRestored]: reEnable.t.sol#L780

[test_givenDifferentCoreKernel_whenActivated_revertsThenRestored]: reEnable.t.sol#L806

[test_givenRevertingCoreKernel_whenActivated_revertsThenRestored]: reEnable.t.sol#L823

[test_givenMissingCoreInterface_whenActivated_revertsThenRestored]: reEnable.t.sol#L839

[test_givenRevertingCoreInterface_whenActivated_revertsThenRestored]: reEnable.t.sol#L858

[test_givenMalformedCoreInterface_whenActivated_revertsThenRestored]: reEnable.t.sol#L880

[test_givenCoreLifecycle_whenCompatible]: reEnable.t.sol#L914

[test_whenCoreLifecycleSeeds]: reEnable.t.sol#L923

[test_givenBackingUnavailable_whenConsumed_reverts]: ./reEnable.t.sol#L933

[test_givenBackingLifecycleBoundaries_whenConsumed_reverts]: ./reEnable.t.sol#L948

[test_givenBackingForeignKernel_whenAdmitted_reverts]: ./reEnable.t.sol#L958

[test_givenBackingMalformedKernel_whenAdmitted_reverts]: ./reEnable.t.sol#L977

[test_givenBackingMissingEnabler_whenAdmitted_reverts]: ./reEnable.t.sol#L994
