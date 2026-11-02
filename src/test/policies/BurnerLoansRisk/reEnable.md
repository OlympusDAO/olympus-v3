# BurnerLoansRisk.reEnable coverage plan

Source: [reEnable](../../../bases/ReEnabler.sol#L46).

## Domains and notation

Scenario scope: `BLRISK-REENABLE`. ROLES is initialized through Kernel activation. Risk owns no loans or custody. A successful transition changes only isEnabled, lastTransitionAt and the inherited lifecycle events. Other configuration and all external state remain unchanged. enable/disable require empty bytes. reEnable has no payload and shares enable's activation checks after its own history/grace checks.

## Dependency validation contract

Risk has an immutable Core identity only; do not call Core or gate Risk activation on Core/controller state. Backing oracle is an ordinary calculator with interface/version checks. Optional cache needs IPriceCache/IEnabler/IVersioned and a matching Kernel; no numeric cache version is queried but may be inactive or disabled because PRICE is the fallback. Kernel modules use module-version checks, not Policy lifecycle checks.

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

The Core binding is identity-only; Core readiness, selected configOperator readiness and market population are not activation prerequisites. Modules are supplied by Kernel activation. Cache may be inactive or disabled because direct PRICE remains available.

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

[test_givenAdminActive_whenAlreadyEnabled_reverts]: reEnable.t.sol#L67

[test_givenAdminCache00_whenTransition]: reEnable.t.sol#L221

[test_givenAdminCache01_whenTransition]: reEnable.t.sol#L206

[test_givenAdminCache10_whenTransition]: reEnable.t.sol#L191

[test_givenAdminCache11_whenTransition]: reEnable.t.sol#L176

[test_givenAdminCacheInterface_whenTransition_reverts]: reEnable.t.sol#L122

[test_givenAdminCacheKernel_whenTransition_reverts]: reEnable.t.sol#L150

[test_givenAdminInactive_whenAlreadyEnabled_reverts]: reEnable.t.sol#L76

[test_givenAdminInactive_whenTransition_reverts]: reEnable.t.sol#L87

[test_givenAdminNeverEnabled_whenReEnabled_reverts]: reEnable.t.sol#L255

[test_givenAdminOracleInterface_whenTransition_reverts]: reEnable.t.sol#L98

[test_givenAdmin_whenAfterDeadline_reverts]: reEnable.t.sol#L325

[test_givenAdmin_whenAtDeadline]: reEnable.t.sol#L300

[test_givenAdmin_whenAtDisable]: reEnable.t.sol#L291

[test_givenAdmin_whenDeadlineOverflows_reverts]: reEnable.t.sol#L351

[test_givenAdmin_whenDependencyRestored]: reEnable.t.sol#L236

[test_givenAdmin_whenGraceExpired_reverts]: reEnable.t.sol#L309

[test_givenAdmin_whenMaxTimestamp_reverts]: reEnable.t.sol#L338

[test_givenAdmin_whenOverflowEnd_reverts]: reEnable.t.sol#L393

[test_givenAdmin_whenOverflowStart_reverts]: reEnable.t.sol#L375

[test_givenAdmin_whenTransition]: reEnable.t.sol#L60

[test_givenAdmin_whenWithinGrace]: reEnable.t.sol#L273

[test_givenLoanAdminActive_whenAlreadyEnabled_reverts]: reEnable.t.sol#L418

[test_givenLoanAdminCache00_whenTransition]: reEnable.t.sol#L572

[test_givenLoanAdminCache01_whenTransition]: reEnable.t.sol#L557

[test_givenLoanAdminCache10_whenTransition]: reEnable.t.sol#L542

[test_givenLoanAdminCache11_whenTransition]: reEnable.t.sol#L527

[test_givenLoanAdminCacheInterface_whenTransition_reverts]: reEnable.t.sol#L473

[test_givenLoanAdminCacheKernel_whenTransition_reverts]: reEnable.t.sol#L501

[test_givenLoanAdminInactive_whenAlreadyEnabled_reverts]: reEnable.t.sol#L427

[test_givenLoanAdminInactive_whenTransition_reverts]: reEnable.t.sol#L438

[test_givenLoanAdminNeverEnabled_whenReEnabled_reverts]: reEnable.t.sol#L606

[test_givenLoanAdminOracleInterface_whenTransition_reverts]: reEnable.t.sol#L449

[test_givenLoanAdmin_whenAfterDeadline_reverts]: reEnable.t.sol#L676

[test_givenLoanAdmin_whenAtDeadline]: reEnable.t.sol#L651

[test_givenLoanAdmin_whenAtDisable]: reEnable.t.sol#L642

[test_givenLoanAdmin_whenDeadlineOverflows_reverts]: reEnable.t.sol#L702

[test_givenLoanAdmin_whenDependencyRestored]: reEnable.t.sol#L587

[test_givenLoanAdmin_whenGraceExpired_reverts]: reEnable.t.sol#L660

[test_givenLoanAdmin_whenMaxTimestamp_reverts]: reEnable.t.sol#L689

[test_givenLoanAdmin_whenOverflowEnd_reverts]: reEnable.t.sol#L744

[test_givenLoanAdmin_whenOverflowStart_reverts]: reEnable.t.sol#L726

[test_givenLoanAdmin_whenTransition]: reEnable.t.sol#L411

[test_givenLoanAdmin_whenWithinGrace]: reEnable.t.sol#L624

[test_whenUnauthorizedCaller_reverts]: reEnable.t.sol#L49
