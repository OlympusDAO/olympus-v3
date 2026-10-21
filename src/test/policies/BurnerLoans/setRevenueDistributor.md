# setRevenueDistributor scenario plan

Scope: immediate Admin-owned BL distributor pointer. Fee and yield routing flags have separate
[fee](./setSendFeesToDistributor.md) and [yield](./setSendYieldToDistributor.md) plans.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator
binding and active dependencies; snapshot after deactivation, before the attempted action. Getters
remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin only. Guard order is Admin, BL Kernel activity, BL local enablement, the
zero-pointer/send-flag restriction, same-pointer handling, then changed-target validation. A changed
nonzero target must report IRevenueDistributor and
IEnabler, belong to the same Kernel, and be Kernel-active and locally enabled. Reverting or malformed
Kernel and enabled-state reads are normalized to BurnerLoans_InvalidRevenueDistributor(target). The
setter does not read the candidate RD's route configuration for any BL-supported asset. Setting
revenueDistributor to address(0) removes
the selected distributor; this is prohibited while either routing flag is true. Unchanged pointer
returns before target revalidation, after the zero/flag restriction.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state
retain their pre-call values; a reverted transaction commits no events. Check exact error data.
Views are permissionless, including while disabled or Kernel-inactive. Changed pointer: one
RevenueDistributorSet; getter equals input; flags, debt quantities, position state and custody
unchanged.

Pending fees belong to the current fee role rather than the address selected when transfer failed.
With fee routing enabled, a nonzero pointer rotation moves pendingPayout and recipient enumeration
from the former RD to the new RD without changing pendingFees, totalPending or custody. Disabling fee
routing first moves that role to Treasury; clearing the pointer afterward changes no payout
assignment. Pending seized collateral always follows Treasury, while pending seizure rewards remain
assigned to their original keepers. Yield claims are atomic and create no pending-yield bucket:
pointer changes only affect context().yieldRecipient and future claims. Same pointer: no event or
mutation.

## Authorization

| ID | Caller | BL Kernel | BL local | Current pointer | Fee flag | Yield flag | Distributor param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DISTPTR-A01 | Non-admin, fuzz | Active | Enabled | Zero | `false` | `false` | Valid changed nonzero RD | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test][test_givenLifecycleState_whenCallerIsNotAdmin_reverts] |
| DISTPTR-A02 | Non-admin, fuzz | Inactive | Enabled | Zero | `false` | `false` | Valid changed nonzero RD | ROLES_RequireRole(ADMIN_ROLE) before lifecycle checks | Unchanged | Covered: [test][test_givenLifecycleState_whenCallerIsNotAdmin_reverts] |
| DISTPTR-A03 | Non-admin, fuzz | Active | Disabled | Zero | `false` | `false` | Valid changed nonzero RD | ROLES_RequireRole(ADMIN_ROLE) before lifecycle checks | Unchanged | Covered: [test][test_givenLifecycleState_whenCallerIsNotAdmin_reverts] |
| DISTPTR-A04 | Non-admin, fuzz | Inactive | Disabled | Zero | `false` | `false` | Valid changed nonzero RD | ROLES_RequireRole(ADMIN_ROLE) before lifecycle checks | Unchanged | Covered: [test][test_givenLifecycleState_whenCallerIsNotAdmin_reverts] |

## Valid pointer updates

The caller is Admin and BL is Kernel-active and locally enabled. This setter has no asset parameter
and does not inspect RD routes. In P01 and P04, select an asset from BL's supported-asset registry and
fuzz whether that asset is listed in the candidate RD; seed both listed and unlisted. This proves
that route state for any particular BL asset does not affect pointer selection.

| ID | Current pointer | Fee flag | Yield flag | Distributor param | RD state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DISTPTR-P01 | Zero | `false` | `false` | Changed nonzero RD | Both interfaces; same active Kernel; locally enabled; fuzz selected BL asset listed/unlisted | Success | Pointer equals target; one RevenueDistributorSet(target); flags and balances unchanged | Covered: [test][test_givenPointerUnset_whenAdminSetsValidDistributor] |
| DISTPTR-P02 | Nonzero RD | Fuzz `false`/`true` | Fuzz `false`/`true` independently | Same current RD | Fuzz Kernel-active/enabled, Kernel-inactive, or locally disabled | Silent no-op without target revalidation | No event; pointer retained | Covered: [test][test_givenPointerSelected_whenAdminSetsSameDistributor_isNoOp] |
| DISTPTR-P03 | Nonzero RD | `false` | `false` | Zero | Current RD state is not read | Success | Pointer zero; one RevenueDistributorSet(address(0)); flags and balances unchanged | Covered: [test][test_givenPointerSelected_whenAdminClearsPointer] |
| DISTPTR-P04 | Different nonzero RD | Fuzz `false`/`true` | Fuzz `false`/`true` independently | Changed nonzero RD | Both interfaces; same active Kernel; locally enabled; fuzz selected BL asset listed/unlisted | Success | Pointer equals target; one RevenueDistributorSet(target); flags and balances unchanged | Covered: [test][test_givenPointerSelected_whenAdminChangesDistributor] |
| DISTPTR-P05 | Zero | `false` | `false` | Zero | — | Silent no-op | No event, pointer or flag change | Covered: [test][test_givenPointerUnset_whenAdminSetsZero_isNoOp] |

## Lifecycle

The caller is Admin. Each row fuzzes reachable current-pointer and fee/yield-flag states, then fuzzes
the distributor parameter across zero, the current pointer and a changed nonzero address. Seed each
input class, including inputs that would fail later pointer validation, to prove lifecycle precedence.

| ID | BL Kernel | BL local | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| DISTPTR-L01 | Inactive | Enabled | BurnerLoans_PolicyInactive() before local-state and pointer checks | Pointer, flags and balances unchanged; no event | Covered: [test][test_givenPolicyInactive_whenAdminSetsDistributor_reverts] |
| DISTPTR-L02 | Active | Disabled | NotEnabled() before pointer checks | Pointer, flags and balances unchanged; no event | Covered: [test][test_givenLocallyDisabled_whenAdminSetsDistributor_reverts] |
| DISTPTR-L03 | Inactive | Disabled | BurnerLoans_PolicyInactive() before local-state and pointer checks | Pointer, flags and balances unchanged; no event | Covered: [test][test_givenPolicyInactive_whenAdminSetsDistributor_reverts] |

## Invalid inputs

The caller is Admin and BL is Kernel-active and locally enabled.

| ID | Current pointer | Fee flag | Yield flag | Distributor param | Target condition | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DISTPTR-I01 | Existing nonzero RD | `true` | `false` | Zero | — | BurnerLoans_RevenueDistributorRequired() | Existing pointer, flags and balances unchanged; no event | Covered: [test][test_givenFeeFlagEnabled_whenAdminClearsPointer_reverts] |
| DISTPTR-I03 | Existing nonzero RD | `false` | `true` | Zero | — | BurnerLoans_RevenueDistributorRequired() | Existing pointer, flags and balances unchanged; no event | Covered: [test][test_givenYieldFlagEnabled_whenAdminClearsPointer_reverts] |
| DISTPTR-I04 | Existing nonzero RD | `true` | `true` | Zero | — | BurnerLoans_RevenueDistributorRequired() | Existing pointer, flags and balances unchanged; no event | Covered: [test][test_givenBothFlagsEnabled_whenAdminClearsPointer_reverts] |
| DISTPTR-I02 | Existing nonzero RD | `false` | `false` | Changed nonzero address | EOA | BurnerLoans_InvalidRevenueDistributor(target) | Existing pointer, flags and balances unchanged; no event | Covered: [test][test_givenPointerSelected_whenAdminSetsEoa_reverts] |
| DISTPTR-I05 | Existing nonzero RD | `false` | `false` | Changed nonzero contract | Lacks IRevenueDistributor | BurnerLoans_InvalidRevenueDistributor(target) | Existing pointer, flags and balances unchanged; no event | Covered: [test][test_givenPointerSelected_whenCandidateLacksRevenueDistributor_reverts] |
| DISTPTR-I09 | Existing nonzero RD | `false` | `false` | Changed nonzero contract | Has IRevenueDistributor; lacks IEnabler | BurnerLoans_InvalidRevenueDistributor(target) | Existing pointer, flags and balances unchanged; no event | Covered: [test][test_givenPointerSelected_whenCandidateLacksEnabler_reverts] |
| DISTPTR-I06 | Existing nonzero RD | `false` | `false` | Changed nonzero contract | Compatible interfaces; another Kernel | BurnerLoans_InvalidRevenueDistributor(target) | Existing pointer, flags and balances unchanged; no event | Covered: [test][test_givenPointerSelected_whenCandidateUsesAnotherKernel_reverts] |
| DISTPTR-I07 | Existing nonzero RD | `false` | `false` | Changed nonzero contract | Compatible; same Kernel; Kernel-inactive | BurnerLoans_InvalidRevenueDistributor(target) | Existing pointer, flags and balances unchanged; no event | Covered: [test][test_givenPointerSelected_whenCandidateIsKernelInactive_reverts] |
| DISTPTR-I08 | Existing nonzero RD | `false` | `false` | Changed nonzero contract | Compatible; same active Kernel; locally disabled | BurnerLoans_InvalidRevenueDistributor(target) | Existing pointer, flags and balances unchanged; no event | Covered: [test][test_givenPointerSelected_whenCandidateIsLocallyDisabled_reverts] |
| DISTPTR-I10 | Existing nonzero RD | `false` | `false` | Changed nonzero contract | Both interfaces; Kernel getter reverts | BurnerLoans_InvalidRevenueDistributor(target) | Existing pointer, flags and balances unchanged; no event | Covered: [test][test_givenPointerSelected_whenCandidateKernelReadReverts_reverts] |
| DISTPTR-I11 | Existing nonzero RD | `false` | `false` | Changed nonzero contract | Both interfaces; Kernel getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(target) | Existing pointer, flags and balances unchanged; no event | Covered: [test][test_givenPointerSelected_whenCandidateKernelReadIsMalformed_reverts] |
| DISTPTR-I12 | Existing nonzero RD | `false` | `false` | Changed nonzero contract | Same active Kernel; isEnabled getter reverts | BurnerLoans_InvalidRevenueDistributor(target) | Existing pointer, flags and balances unchanged; no event | Covered: [test][test_givenPointerSelected_whenCandidateEnabledReadReverts_reverts] |
| DISTPTR-I13 | Existing nonzero RD | `false` | `false` | Changed nonzero contract | Same active Kernel; isEnabled getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(target) | Existing pointer, flags and balances unchanged; no event | Covered: [test][test_givenPointerSelected_whenCandidateEnabledReadIsMalformed_reverts] |

## Live routing and pending payouts

Use distinct former RD, new RD, Treasury and keeper identities. Seed nonzero pending fee,
seized-collateral and keeper-reward buckets where the row refers to pending payouts. The caller is
Admin and BL is Kernel-active and locally enabled.

| ID | Current pointer | Fee flag | Yield flag | Action | Pending setup | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DISTPTR-R01 | Former valid nonzero RD | `true` | `false` | Set a different valid enabled nonzero RD | Pending fee resolves to former RD | Success | Pointer and pending-fee recipient move to new RD; former RD has no fee entitlement; pendingFees, totalPending, custody, flags and unrelated pending buckets unchanged; one RevenueDistributorSet | Covered: [test][test_givenPendingFee_whenDistributorChanges_reassignsFee] |
| DISTPTR-R02 | Former valid nonzero RD | `false` | `true` | Set a different valid enabled nonzero RD | Pending fee resolves to Treasury | Success | context().yieldRecipient changes to the new RD; no pending-yield balance is created or moved; pending fee remains assigned to Treasury; seizure and reward buckets unchanged; one RevenueDistributorSet | Covered: [test][test_givenYieldRouting_whenDistributorChanges_updatesOnlyYieldRecipient] |
| DISTPTR-R03 | Former valid nonzero RD | `true` | `true` | Set a different valid enabled nonzero RD | Fee, seizure and keeper-reward obligations are nonzero | Success | Pending fee and yieldRecipient follow the new RD; seized collateral remains with Treasury and keeper reward with the original keeper; totalPending and custody unchanged; one RevenueDistributorSet | Covered: [test][test_givenBothRoutesAndPendingPayouts_whenDistributorChanges_preservesBuckets] |
| DISTPTR-R04 | Valid nonzero RD | Initially `true` | Initially `true` | Set fee flag `false`; set yield flag `false`; set distributor zero | Pending fee initially resolves to RD | All three calls succeed | Pending fee moves to Treasury when fee routing is disabled and a later retry pays Treasury; yieldRecipient moves to Treasury with no pending-yield entry; clearing the pointer changes neither assignment; seized collateral, keeper rewards, totalPending and custody remain consistent | Covered: [test][test_givenBothRoutesAndPendingPayouts_whenRoutesDisabledThenPointerCleared] |

[test_givenBothFlagsEnabled_whenAdminClearsPointer_reverts]: ./setRevenueDistributor.t.sol#L205
[test_givenBothRoutesAndPendingPayouts_whenDistributorChanges_preservesBuckets]: ./setRevenueDistributor.t.sol#L334
[test_givenBothRoutesAndPendingPayouts_whenRoutesDisabledThenPointerCleared]: ./setRevenueDistributor.t.sol#L359
[test_givenFeeFlagEnabled_whenAdminClearsPointer_reverts]: ./setRevenueDistributor.t.sol#L195
[test_givenLifecycleState_whenCallerIsNotAdmin_reverts]: ./setRevenueDistributor.t.sol#L26
[test_givenLocallyDisabled_whenAdminSetsDistributor_reverts]: ./setRevenueDistributor.t.sol#L180
[test_givenPendingFee_whenDistributorChanges_reassignsFee]: ./setRevenueDistributor.t.sol#L289
[test_givenPointerSelected_whenAdminChangesDistributor]: ./setRevenueDistributor.t.sol#L116
[test_givenPointerSelected_whenAdminClearsPointer]: ./setRevenueDistributor.t.sol#L99
[test_givenPointerSelected_whenAdminSetsEoa_reverts]: ./setRevenueDistributor.t.sol#L210
[test_givenPointerSelected_whenAdminSetsSameDistributor_isNoOp]: ./setRevenueDistributor.t.sol#L73
[test_givenPointerSelected_whenCandidateEnabledReadIsMalformed_reverts]: ./setRevenueDistributor.t.sol#L281
[test_givenPointerSelected_whenCandidateEnabledReadReverts_reverts]: ./setRevenueDistributor.t.sol#L273
[test_givenPointerSelected_whenCandidateIsKernelInactive_reverts]: ./setRevenueDistributor.t.sol#L243
[test_givenPointerSelected_whenCandidateIsLocallyDisabled_reverts]: ./setRevenueDistributor.t.sol#L250
[test_givenPointerSelected_whenCandidateKernelReadIsMalformed_reverts]: ./setRevenueDistributor.t.sol#L265
[test_givenPointerSelected_whenCandidateKernelReadReverts_reverts]: ./setRevenueDistributor.t.sol#L257
[test_givenPointerSelected_whenCandidateLacksEnabler_reverts]: ./setRevenueDistributor.t.sol#L227
[test_givenPointerSelected_whenCandidateLacksRevenueDistributor_reverts]: ./setRevenueDistributor.t.sol#L218
[test_givenPointerSelected_whenCandidateUsesAnotherKernel_reverts]: ./setRevenueDistributor.t.sol#L235
[test_givenPointerUnset_whenAdminSetsValidDistributor]: ./setRevenueDistributor.t.sol#L47
[test_givenPointerUnset_whenAdminSetsZero_isNoOp]: ./setRevenueDistributor.t.sol#L150
[test_givenPolicyInactive_whenAdminSetsDistributor_reverts]: ./setRevenueDistributor.t.sol#L162
[test_givenYieldFlagEnabled_whenAdminClearsPointer_reverts]: ./setRevenueDistributor.t.sol#L200
[test_givenYieldRouting_whenDistributorChanges_updatesOnlyYieldRecipient]: ./setRevenueDistributor.t.sol#L317
