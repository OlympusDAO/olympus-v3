# BurnerLoansConfig.setPriceCacheMaxAge coverage plan

Source: [setPriceCacheMaxAge](../../../policies/burnerloans/BurnerLoansConfig.sol#L258).

## Domains and notation

Scenario scope: `BLCFG-CACHE-AGE`. The input is an age in seconds, `uint48`, with MAX48=`type(uint48).max`. Every value from zero through MAX48 is valid. Config stores no cache age: it resolves the current Risk through its bound Core and forwards the exact value once. Risk owns the authoritative `priceCacheMaxAge()` getter and `PriceCacheMaxAgeSet(age)` event. No Config event is emitted.

Config's permitted external callers are every ADMIN_ROLE holder and its selected nonzero configOperator. Fuzz all three equivalent classes (ADMIN-only, operator-only and their overlap) independently of old/new ages; guarantee each class with boundary drivers. Unauthorized callers exclude every ADMIN and the selected nonzero Config operator, retaining zero, former operators, borrowers, unrelated contracts and Risk-only operators.

Forwarded calls reach Risk with Config as `msg.sender`. Config must separately be Risk's selected nonzero configOperator or hold ADMIN_ROLE. An external caller's ADMIN role does not propagate through Config.

Guard order is Config Kernel activity → Config enabled → Config caller authorization → Core.risk() → Risk activity → Risk enabled → Risk caller authorization → Risk same-value return or write/event. An unchanged age still reaches all preceding guards. There is no separate Config validator or preview.

All bindings and unvaried dependencies are usable unless stated otherwise. Successful forwarding changes only Risk's cache age. Unchanged covers Config settings/lifecycle, other Risk settings/lifecycle, market definitions/configuration, canonical principal/collateral, Inventory accounting and relevant token balances. A rejected call commits no writes or logs. This action moves no tokens; arithmetic, TTL interpretation and Risk's own authority invariant belong to the Risk suite.

## Authorization

Config and Risk are active/enabled. Risk delegates to Config unless stated otherwise.

| ID | Caller | Execution | Effects | Test |
| --- | --- | --- | --- | --- |
| BLCFG-CACHE-AGE-A01 | Fuzz unauthorized callers; seed borrower, zero, unrelated contract, former Config operator, BURNER_LOANS_ADMIN_ROLE-only and Risk-only operator | NotAuthorised() | Unchanged; no target call | Covered: [test][test_whenUnauthorizedCallerConfiguresCacheAge_reverts], [test][test_whenUnauthorizedCallerConfiguresAnyAge_reverts], [test][test_whenUnauthorizedCallerSeedsConfigureAge_reverts], [test][test_givenRiskOnlyOperator_whenConfigCalled_reverts], [test][test_givenOperatorReplaced_whenFormerOperatorCalls_reverts], [test][test_givenConfigOperatorUnset_whenZeroCallerCalls_reverts] |
| BLCFG-CACHE-AGE-A02 | Fuzz ADMIN-only, selected Config operator-only and overlap; guarantee all three | Success | Exact age forwarded once and stored on Risk; preserve unrelated state | Covered: [test][test_givenAdminOnly_whenAgeChanged], [test][test_givenAdminOnly_whenAgeBoundaries], [test][test_givenOperatorOnly_whenAgeChanged], [test][test_givenOperatorOnly_whenAgeBoundaries], [test][test_givenAdminAndOperator_whenAgeChanged], [test][test_givenAdminAndOperator_whenAgeBoundaries] |
| BLCFG-CACHE-AGE-A03 | Former Config operator after replacement | NotAuthorised() | Old authority revoked; no forwarding | Covered: [test][test_givenOperatorReplaced_whenFormerOperatorCalls_reverts] |
| BLCFG-CACHE-AGE-A04 | ADMIN while Config's operator is unset | Success | Direct governance authority retained | Covered: [test][test_givenConfigOperatorUnset_whenAdminCalls] |
| BLCFG-CACHE-AGE-A05 | Unauthorized caller; Config inactive but enabled; Core.risk() also rejects | BurnerLoans_PolicyNotActive(Config) | Own inactivity precedes Config authorization and target lookup | Covered: [test][test_givenInactiveConfig_whenUnauthorizedCallerCalls_reverts] |
| BLCFG-CACHE-AGE-A06 | New Config operator after replacing the former operator | Success | New authority works without changing Risk delegation | Covered: [test][test_givenOperatorReplaced_whenNewOperatorCalls] |

## Config lifecycle

Risk is active/enabled and accepts Config. Earlier guards determine competing-fault errors.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-CACHE-AGE-L01 | Permitted Config caller | true | true | Success | Forward once; Config lifecycle unchanged | Covered: [test][test_givenAdminOnly_whenAgeChanged], [test][test_givenOperatorOnly_whenAgeChanged], [test][test_givenAdminAndOperator_whenAgeChanged] |
| BLCFG-CACHE-AGE-L02 | Fuzz all callers, including permitted and unauthorized | true | false | IEnabler.NotEnabled() | No target lookup/call, including when target lookup rejects | Covered: [test][test_givenDisabledConfig_whenAnyCallerCalls_reverts], [test][test_givenDisabledConfig_whenCallerSeedsCall_reverts] |
| BLCFG-CACHE-AGE-L03 | Fuzz permitted caller classes; guarantee ADMIN-only, operator-only and overlap | false | true | BurnerLoans_PolicyNotActive(Config) | No target lookup/call, including when target lookup rejects | Covered: [test][test_givenInactiveConfig_whenAdminOnlyCalls_reverts], [test][test_givenInactiveConfig_whenOperatorOnlyCalls_reverts], [test][test_givenInactiveConfig_whenAdminAndOperatorCalls_reverts] |
| BLCFG-CACHE-AGE-L04 | Fuzz all callers | false | false | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Own inactivity precedes local disablement and authorization | Covered: [test][test_givenInactiveDisabledConfig_whenAnyCallerCalls_reverts], [test][test_givenInactiveDisabledConfig_whenCallerSeedsCall_reverts] |
| BLCFG-CACHE-AGE-L05 | Permitted Config caller | true | Re-enabled | Success | Forwarding restored after a normal pause/reEnable sequence | Covered: [test][test_givenReEnabledConfig_whenAgeChanged] |

## Risk authority and lifecycle

Config is active/enabled; the external caller is permitted on Config. Same-value inputs do not bypass downstream admission.

| ID | External caller | Risk active | Risk enabled | Config authority on Risk | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-CACHE-AGE-D01 | ADMIN-only, Config operator-only and overlap seeds | true | true | Neither Risk operator nor ADMIN; test unset and different Risk operators | IPolicyAdmin.NotAuthorised(), including unchanged age | External caller authority is not forwarded; unchanged | Covered: [test][test_givenConfigNotRiskOperator_whenPermittedCallersCall_reverts], [test][test_givenRiskOperatorUnset_whenPermittedCallersCall_reverts] |
| BLCFG-CACHE-AGE-D02 | Permitted Config caller | true | false | Delegated Config | IEnabler.NotEnabled(), including unchanged age | Unchanged | Covered: [test][test_givenDisabledRisk_whenAgeSet_reverts], [test][test_givenDisabledRisk_whenAgeUnchanged_reverts] |
| BLCFG-CACHE-AGE-D03 | Permitted Config caller | false | true | Delegated Config | BurnerLoans_PolicyNotActive(Risk), including unchanged age | Unchanged | Covered: [test][test_givenInactiveRisk_whenAgeSet_reverts], [test][test_givenInactiveRisk_whenAgeUnchanged_reverts] |
| BLCFG-CACHE-AGE-D04 | Permitted Config caller | false | false | Delegated Config | BurnerLoans_PolicyNotActive(Risk) | Risk activity precedes enablement; unchanged | Covered: [test][test_givenInactiveDisabledRisk_whenAgeSet_reverts] |
| BLCFG-CACHE-AGE-D05 | Config operator-only | true | true | Config holds ADMIN; Risk operator is a distinct address | Success | Config's own ADMIN grant supplies downstream authority | Covered: [test][test_givenConfigHoldsRiskAdmin_whenAnotherRiskOperatorSelected] |
| BLCFG-CACHE-AGE-D06 | Config operator-only | true | Re-enabled | Delegated Config | Success | Risk service works after pause/reEnable | Covered: [test][test_givenReEnabledRisk_whenAgeChanged] |

## Forwarding, numeric boundaries and effects

Config and Risk are active/enabled; the external caller and Config itself have their respective authorities.

| ID | Caller | Input or dependency condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-CACHE-AGE-N01 | Fuzz permitted Config caller classes | Independently fuzz old/new ages over 0..MAX48, excluding equality | Success | Exact new age and one Risk event; no Config or economic mutation | Covered: [test][test_givenAdminOnly_whenAgeChanged], [test][test_givenOperatorOnly_whenAgeChanged], [test][test_givenAdminAndOperator_whenAgeChanged] |
| BLCFG-CACHE-AGE-N02 | ADMIN-only, operator-only and overlap seeds | Changed values 1, then 0, then MAX48 | Success | Each endpoint forwarded/stored exactly | Covered: [test][test_givenAdminOnly_whenAgeBoundaries], [test][test_givenOperatorOnly_whenAgeBoundaries], [test][test_givenAdminAndOperator_whenAgeBoundaries] |
| BLCFG-CACHE-AGE-P01 | Fuzz permitted Config caller classes | Requested age equals stored age; fuzz 0..MAX48; seed 0,1,MAX48 | Success | Forward once; no writes or events | Covered: [test][test_givenAdminOnly_whenAgeUnchanged], [test][test_givenOperatorOnly_whenAgeUnchanged], [test][test_givenAdminAndOperator_whenAgeUnchanged], [test][test_whenUnchangedAgeEndpoints] |
| BLCFG-CACHE-AGE-P02 | Config operator-only | Core independently active/inactive and enabled/disabled; guarantee all four pairs | Success for changed and unchanged ages | Read-only Risk lookup remains usable; no Core readiness or settlement guard | Covered: [test][test_givenIndependentCoreState_whenAgeChanged], [test][test_givenIndependentCoreState_whenAgeUnchanged], [test][test_whenCoreLifecycleChangeSeeds], [test][test_whenCoreLifecycleNoOpSeeds] |
| BLCFG-CACHE-AGE-P03 | Config operator-only | Core selects a replacement compatible, active/enabled Risk | Success on the newly selected Risk | Fresh lookup; old Risk age preserved; one new-Risk event | Covered: [test][test_givenRiskReplacement_whenAgeChanged] |
| BLCFG-CACHE-AGE-P04 | Config operator-only | Core kernel(), isEnabled(), configurator() and requireNotReentrant() reject if queried | Success | Only Core.risk() is consumed; no unrelated Core calls | Covered: [test][test_givenUnrelatedCoreGettersRevert_whenAgeChanged] |
| BLCFG-CACHE-AGE-T01 | Config operator-only | Core.risk() reverts with configured custom error | Propagate the exact error | No Risk call; unchanged | Covered: [test][test_givenCoreRiskLookupReverts_whenAgeSet_reverts] |
| BLCFG-CACHE-AGE-T02 | Config operator-only | Current Risk setter rejects the exact forwarded age with configured custom error | Propagate the exact error and arguments | Unchanged | Covered: [test][test_givenRiskSetterReverts_whenAgeSet_reverts] |
| BLCFG-CACHE-AGE-T03 | Config operator-only | Replacement Risk is paused after selection; old Risk remains operational | IEnabler.NotEnabled() | No stale-target fallback; both Risk ages preserved | Covered: [test][test_givenReplacementRiskPaused_whenAgeSet_reverts] |

- [x] Implement the permitted-caller, lifecycle, delegation and forwarding cases.
- [x] Verify numeric boundaries, unchanged values, exact events and rollback.
- [x] Refresh reciprocal mappings and run the focused suite.

[test_whenUnauthorizedCallerConfiguresCacheAge_reverts]: ./setPriceCacheMaxAge.t.sol#L177
[test_whenUnauthorizedCallerConfiguresAnyAge_reverts]: ./setPriceCacheMaxAge.t.sol#L183
[test_whenUnauthorizedCallerSeedsConfigureAge_reverts]: ./setPriceCacheMaxAge.t.sol#L193
[test_givenRiskOnlyOperator_whenConfigCalled_reverts]: ./setPriceCacheMaxAge.t.sol#L206
[test_givenAdminOnly_whenAgeChanged]: ./setPriceCacheMaxAge.t.sol#L213
[test_givenAdminOnly_whenAgeUnchanged]: ./setPriceCacheMaxAge.t.sol#L222
[test_givenInactiveConfig_whenAdminOnlyCalls_reverts]: ./setPriceCacheMaxAge.t.sol#L231
[test_givenAdminOnly_whenAgeBoundaries]: ./setPriceCacheMaxAge.t.sol#L241
[test_givenOperatorOnly_whenAgeChanged]: ./setPriceCacheMaxAge.t.sol#L246
[test_givenOperatorOnly_whenAgeUnchanged]: ./setPriceCacheMaxAge.t.sol#L255
[test_givenInactiveConfig_whenOperatorOnlyCalls_reverts]: ./setPriceCacheMaxAge.t.sol#L264
[test_givenOperatorOnly_whenAgeBoundaries]: ./setPriceCacheMaxAge.t.sol#L274
[test_givenAdminAndOperator_whenAgeChanged]: ./setPriceCacheMaxAge.t.sol#L279
[test_givenAdminAndOperator_whenAgeUnchanged]: ./setPriceCacheMaxAge.t.sol#L288
[test_givenInactiveConfig_whenAdminAndOperatorCalls_reverts]: ./setPriceCacheMaxAge.t.sol#L297
[test_givenAdminAndOperator_whenAgeBoundaries]: ./setPriceCacheMaxAge.t.sol#L307
[test_givenOperatorReplaced_whenFormerOperatorCalls_reverts]: ./setPriceCacheMaxAge.t.sol#L313
[test_givenOperatorReplaced_whenNewOperatorCalls]: ./setPriceCacheMaxAge.t.sol#L321
[test_givenConfigOperatorUnset_whenAdminCalls]: ./setPriceCacheMaxAge.t.sol#L327
[test_givenConfigOperatorUnset_whenZeroCallerCalls_reverts]: ./setPriceCacheMaxAge.t.sol#L333
[test_givenInactiveConfig_whenUnauthorizedCallerCalls_reverts]: ./setPriceCacheMaxAge.t.sol#L340
[test_givenDisabledConfig_whenAnyCallerCalls_reverts]: ./setPriceCacheMaxAge.t.sol#L350
[test_givenInactiveDisabledConfig_whenAnyCallerCalls_reverts]: ./setPriceCacheMaxAge.t.sol#L360
[test_givenDisabledConfig_whenCallerSeedsCall_reverts]: ./setPriceCacheMaxAge.t.sol#L369
[test_givenInactiveDisabledConfig_whenCallerSeedsCall_reverts]: ./setPriceCacheMaxAge.t.sol#L375
[test_givenReEnabledConfig_whenAgeChanged]: ./setPriceCacheMaxAge.t.sol#L388
[test_givenConfigNotRiskOperator_whenPermittedCallersCall_reverts]: ./setPriceCacheMaxAge.t.sol#L395
[test_givenRiskOperatorUnset_whenPermittedCallersCall_reverts]: ./setPriceCacheMaxAge.t.sol#L401
[test_givenDisabledRisk_whenAgeSet_reverts]: ./setPriceCacheMaxAge.t.sol#L407
[test_givenDisabledRisk_whenAgeUnchanged_reverts]: ./setPriceCacheMaxAge.t.sol#L417
[test_givenInactiveRisk_whenAgeSet_reverts]: ./setPriceCacheMaxAge.t.sol#L423
[test_givenInactiveRisk_whenAgeUnchanged_reverts]: ./setPriceCacheMaxAge.t.sol#L429
[test_givenInactiveDisabledRisk_whenAgeSet_reverts]: ./setPriceCacheMaxAge.t.sol#L435
[test_givenConfigHoldsRiskAdmin_whenAnotherRiskOperatorSelected]: ./setPriceCacheMaxAge.t.sol#L441
[test_givenReEnabledRisk_whenAgeChanged]: ./setPriceCacheMaxAge.t.sol#L448
[test_whenUnchangedAgeEndpoints]: ./setPriceCacheMaxAge.t.sol#L455
[test_givenIndependentCoreState_whenAgeChanged]: ./setPriceCacheMaxAge.t.sol#L464
[test_givenIndependentCoreState_whenAgeUnchanged]: ./setPriceCacheMaxAge.t.sol#L470
[test_whenCoreLifecycleChangeSeeds]: ./setPriceCacheMaxAge.t.sol#L476
[test_whenCoreLifecycleNoOpSeeds]: ./setPriceCacheMaxAge.t.sol#L484
[test_givenRiskReplacement_whenAgeChanged]: ./setPriceCacheMaxAge.t.sol#L492
[test_givenUnrelatedCoreGettersRevert_whenAgeChanged]: ./setPriceCacheMaxAge.t.sol#L505
[test_givenCoreRiskLookupReverts_whenAgeSet_reverts]: ./setPriceCacheMaxAge.t.sol#L524
[test_givenRiskSetterReverts_whenAgeSet_reverts]: ./setPriceCacheMaxAge.t.sol#L535
[test_givenReplacementRiskPaused_whenAgeSet_reverts]: ./setPriceCacheMaxAge.t.sol#L546
