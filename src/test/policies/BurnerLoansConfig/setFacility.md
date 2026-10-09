# setFacility scenario plan

Scope: initial Burner Loans facility binding and compatibility validation in BLC.setFacility.

BLC = BurnerLoansConfig; BL = BurnerLoans. Use an unlinked, Kernel-active, locally disabled BLC with
initialized dependencies. Inactive BLC rejects setFacility despite a retained Admin role. Guard order is local BLC
disablement, Admin, BLC Kernel activity, unlinked pointer, active same-Kernel facility, then
interfaces and OHM. Admin calls setFacility; a compatible BL must be Kernel-active, report the same
Kernel and OHM token, and support IBurnerLoansLifecycle, IBurnerLoansView and IBurnerLoansRescue.
IBurnerLoans is declarations-only and is inherited by IBurnerLoansView, so it has no separate
compatibility check. IEnabler is not required by setFacility, and the candidate facility's local
enablement does not affect binding. Reverting or malformed candidate Kernel, ERC165 and OHM reads
are normalized to BurnerLoansConfig_InvalidFacility(candidate).

Success stores the exact facility pointer and emits FacilitySet once; no custody, debt or markets
change. Failure matches the exact custom error, leaves the pointer zero and commits no event.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator
binding and active dependencies; snapshot after deactivation, before the attempted action. Getters
remain readable. Preserve existing guard precedence unless a row specifies a change.
`Either` means candidate local enablement does not affect the binding or is not reached before the
stated failure.

## Behavior

| ID | Caller | BLC Kernel | BLC local | Candidate local | Candidate compatibility | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LINK-P01 | Admin | Active | Disabled | Enabled | Active, same Kernel and OHM; all three required interfaces | Success | Store facility; exact FacilitySet event | Covered: [test][test_givenCompatibleEnabledFacility_whenAdminSetsFacility] |
| LINK-P02 | Admin | Active | Disabled | Disabled | Active, same Kernel and OHM; all three required interfaces | Success | Store facility; exact FacilitySet event; candidate remains locally disabled | Covered: [test][test_givenCompatibleDisabledFacility_whenAdminSetsFacility] |
| LINK-L01 | Admin with role retained | Inactive | Disabled | Either | Active, same Kernel and OHM; all three required interfaces | BurnerLoansConfig_PolicyInactive() | Facility pointer stays zero; no FacilitySet or balance/market change | Covered: [test][test_givenConfigPolicyInactive_whenAdminSetsFacility_reverts] |
| LINK-L02 | Admin | Active | Enabled | Either | Active, same Kernel and OHM; all three required interfaces | NotDisabled() | Facility pointer stays zero; no FacilitySet or balance/market change | Covered: [test][test_givenConfigEnabled_whenAdminSetsFacility_reverts] |

## Authorization

The current facility is zero and the parameter is the same valid, locally enabled BL in every row.

| ID | Caller | BLC Kernel | BLC local | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| LINK-A01 | Caller other than Admin, fuzz | Active | Disabled | ROLES_RequireRole(ADMIN_ROLE) | Facility pointer stays zero; no committed event | Covered: [test][test_givenConfigActiveAndDisabled_whenCallerIsNotAdmin_reverts] |
| LINK-A02 | Caller other than Admin, fuzz | Inactive | Disabled | ROLES_RequireRole(ADMIN_ROLE) before BLC activity check | Facility pointer stays zero; no event or balance/market change | Covered: [test][test_givenConfigInactiveAndDisabled_whenCallerIsNotAdmin_reverts] |
| LINK-A03 | Caller other than Admin, fuzz | Active | Enabled | NotDisabled() before authorization and activity checks | Facility pointer stays zero; no event or balance/market change | Covered: [test][test_givenConfigEnabled_whenCallerIsNotAdmin_reverts] |
| LINK-A04 | Caller other than Admin, fuzz | Inactive | Enabled | NotDisabled() before authorization and activity checks | Facility pointer stays zero; no event or balance/market change | Covered: [test][test_givenConfigEnabled_whenCallerIsNotAdmin_reverts] |

## Invalid inputs

BLC is Kernel-active and locally disabled in every row.

| ID | Caller | Current facility | Facility param | Candidate state/failure | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LINK-I01 | Admin | Zero | Nonzero contract | Active, same Kernel and OHM; lacks IBurnerLoansLifecycle | BurnerLoansConfig_InvalidFacility(candidate) | Pointer stays zero; no committed event | Covered: [test][test_givenCandidateMissingLifecycleInterface_reverts] |
| LINK-I02 | Admin | Zero | Nonzero contract | Active, same Kernel and OHM; lacks IBurnerLoansView | BurnerLoansConfig_InvalidFacility(candidate) | Pointer stays zero; no committed event | Covered: [test][test_givenCandidateMissingViewInterface_reverts] |
| LINK-I03 | Admin | Zero | Nonzero contract | Active, same Kernel and OHM; lacks IBurnerLoansRescue | BurnerLoansConfig_InvalidFacility(candidate) | Pointer stays zero; no committed event | Covered: [test][test_givenCandidateMissingRescueInterface_reverts] |
| LINK-I04 | Admin | Zero | Nonzero contract | Kernel-inactive; otherwise compatible | BurnerLoansConfig_InvalidFacility(candidate) | Pointer stays zero; no committed event | Covered: [test][test_givenCompatibleCandidateKernelInactive_reverts] |
| LINK-I05 | Admin | Zero | Nonzero contract | Active under another Kernel; otherwise compatible | BurnerLoansConfig_InvalidFacility(candidate) | Pointer stays zero; no committed event | Covered: [test][test_givenActiveCandidateReportsDifferentKernel_reverts] |
| LINK-I06 | Admin | Zero | Nonzero contract | Kernel getter reverts; otherwise compatible | BurnerLoansConfig_InvalidFacility(candidate) | Pointer stays zero; no committed event | Covered: [test][test_givenActiveCandidateKernelReadReverts_reverts] |
| LINK-I07 | Admin | Zero | Nonzero contract | Active, same Kernel and all interfaces; another OHM | BurnerLoansConfig_InvalidFacility(candidate) | Pointer stays zero; no committed event | Covered: [test][test_givenCandidateReportsDifferentOhm_reverts] |
| LINK-I08 | Admin | Zero | Zero | No code | BurnerLoansConfig_InvalidFacility(candidate) | Pointer stays zero; no committed event | Covered: [test][test_whenFacilityIsZero_reverts] |
| LINK-I10 | Admin | Zero | Nonzero EOA, fuzz | No code | BurnerLoansConfig_InvalidFacility(candidate) | Pointer stays zero; no committed event | Covered: [test][test_whenFacilityIsNonzeroEoa_reverts] |
| LINK-I09 | Admin | Same nonzero facility | Same current facility | Any | BurnerLoansConfig_FacilityAlreadySet() | Existing facility and markets unchanged; no event | Covered: [test][test_givenFacilitySet_whenAdminSetsSameFacility_reverts] |
| LINK-I11 | Admin | Existing nonzero facility | Different valid facility | Active, same Kernel and OHM; all interfaces | BurnerLoansConfig_FacilityAlreadySet() | Existing facility and markets unchanged; no event | Covered: [test][test_givenFacilitySet_whenAdminSetsDifferentFacility_reverts] |
| LINK-I12 | Admin | Zero | Nonzero contract | Active and same Kernel; supportsInterface reverts | BurnerLoansConfig_InvalidFacility(candidate) | Pointer stays zero; no committed event | Covered: [test][test_givenCandidateSupportsInterfaceReverts_reverts] |
| LINK-I15 | Admin | Zero | Nonzero contract | Active and same Kernel; supportsInterface returns malformed data | BurnerLoansConfig_InvalidFacility(candidate) | Pointer stays zero; no committed event | Covered: [test][test_givenCandidateSupportsInterfaceMalformed_reverts] |
| LINK-I13 | Admin | Zero | Nonzero contract | Active, same Kernel and all interfaces; OHM getter reverts | BurnerLoansConfig_InvalidFacility(candidate) | Pointer stays zero; no committed event | Covered: [test][test_givenCandidateOhmReadReverts_reverts] |
| LINK-I14 | Admin | Zero | Nonzero contract | Active, same Kernel and all interfaces; OHM getter returns malformed data | BurnerLoansConfig_InvalidFacility(candidate) | Pointer stays zero; no committed event | Covered: [test][test_givenCandidateOhmReadMalformed_reverts] |

[test_givenActiveCandidateKernelReadReverts_reverts]: ./setFacility.t.sol#L196
[test_givenActiveCandidateReportsDifferentKernel_reverts]: ./setFacility.t.sol#L185
[test_givenCandidateMissingLifecycleInterface_reverts]: ./setFacility.t.sol#L158
[test_givenCandidateMissingRescueInterface_reverts]: ./setFacility.t.sol#L172
[test_givenCandidateMissingViewInterface_reverts]: ./setFacility.t.sol#L165
[test_givenCandidateOhmReadMalformed_reverts]: ./setFacility.t.sol#L290
[test_givenCandidateOhmReadReverts_reverts]: ./setFacility.t.sol#L279
[test_givenCandidateReportsDifferentOhm_reverts]: ./setFacility.t.sol#L207
[test_givenCandidateSupportsInterfaceMalformed_reverts]: ./setFacility.t.sol#L268
[test_givenCandidateSupportsInterfaceReverts_reverts]: ./setFacility.t.sol#L257
[test_givenCompatibleCandidateKernelInactive_reverts]: ./setFacility.t.sol#L179
[test_givenCompatibleDisabledFacility_whenAdminSetsFacility]: ./setFacility.t.sol#L64
[test_givenCompatibleEnabledFacility_whenAdminSetsFacility]: ./setFacility.t.sol#L48
[test_givenConfigActiveAndDisabled_whenCallerIsNotAdmin_reverts]: ./setFacility.t.sol#L107
[test_givenConfigEnabled_whenAdminSetsFacility_reverts]: ./setFacility.t.sol#L94
[test_givenConfigEnabled_whenCallerIsNotAdmin_reverts]: ./setFacility.t.sol#L140
[test_givenConfigInactiveAndDisabled_whenCallerIsNotAdmin_reverts]: ./setFacility.t.sol#L123
[test_givenConfigPolicyInactive_whenAdminSetsFacility_reverts]: ./setFacility.t.sol#L80
[test_givenFacilitySet_whenAdminSetsDifferentFacility_reverts]: ./setFacility.t.sol#L240
[test_givenFacilitySet_whenAdminSetsSameFacility_reverts]: ./setFacility.t.sol#L225
[test_whenFacilityIsNonzeroEoa_reverts]: ./setFacility.t.sol#L218
[test_whenFacilityIsZero_reverts]: ./setFacility.t.sol#L213
