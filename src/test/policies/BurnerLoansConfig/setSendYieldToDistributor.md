# setSendYieldToDistributor scenario plan

Scope: BurnerLoansConfig (BLC) forwarding of the yield-routing flag. The underlying Burner Loans
behavior has its own [plan](../BurnerLoans/setSendYieldToDistributor.md).

Default: BLC and Burner Loans (BL) are Kernel-active and locally enabled. A compatible,
Kernel-active, locally enabled RD is selected. Admin and the current nonzero configOperator are
distinct permitted caller classes; success and downstream-rejection cases fuzz a selector across
exactly those two identities.

## Domains and assertions

BLC guard order is local enablement, caller authorization, BLC Kernel activity, then forwarding the
exact boolean to its bound BL. BL then applies its own lifecycle and distributor validation.

Unchanged means both policies' configuration, balances and liabilities retain their pre-call values;
no event is committed. Success changes only BL's yield flag and emits the underlying yield-flag event.

## Authorization

BL is active and enabled, the current yield flag is `false`, the RD is valid and enabled, and the
parameter is `true` in every row.

| ID | Caller | BLC Kernel | BLC local | Current yield flag | RD state | Param | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CYIELD-A01 | Neither Admin nor current configOperator, fuzz | Active | Enabled | `false` | Valid and enabled | `true` | BurnerLoansConfig_UnauthorizedConfigOperator(caller) | Unchanged | Covered: [test][test_givenConfigEnabled_whenCallerIsUnauthorized_reverts] |
| CYIELD-A02 | Neither Admin nor current configOperator, fuzz | Inactive | Enabled | `false` | Valid and enabled | `true` | BurnerLoansConfig_UnauthorizedConfigOperator(caller) before activity check | Unchanged | Covered: [test][test_givenConfigEnabled_whenCallerIsUnauthorized_reverts] |
| CYIELD-A03 | Neither Admin nor current configOperator, fuzz | Active | Disabled | `false` | Valid and enabled | `true` | NotEnabled() before authorization and activity checks | Unchanged | Covered: [test][test_givenConfigDisabled_whenCallerIsUnauthorized_reverts] |
| CYIELD-A04 | Neither Admin nor current configOperator, fuzz | Inactive | Disabled | `false` | Valid and enabled | `true` | NotEnabled() before authorization and activity checks | Unchanged | Covered: [test][test_givenConfigDisabled_whenCallerIsUnauthorized_reverts] |

## Lifecycle

For BLC lifecycle rows, fuzz the caller between Admin and configOperator and fuzz reachable current
flag, parameter, pointer and RD-state combinations. For BL lifecycle rows, BLC is active/enabled and
the permitted caller reaches BL with the same fuzzed input domain.

| ID | Gate | Kernel | Local | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| CYIELD-L01 | BLC | Inactive | Enabled | BurnerLoansConfig_PolicyInactive() before forwarding | Unchanged | Covered: [test][test_givenConfigInactive_whenPermittedCallerSetsYieldFlag_reverts] |
| CYIELD-L02 | BLC | Active | Disabled | NotEnabled() before forwarding | Unchanged | Covered: [test][test_givenConfigDisabled_whenPermittedCallerSetsYieldFlag_reverts] |
| CYIELD-L03 | BLC | Inactive | Disabled | NotEnabled() before authorization, activity and forwarding | Unchanged | Covered: [test][test_givenConfigDisabled_whenPermittedCallerSetsYieldFlag_reverts] |
| CYIELD-L04 | BL after forwarding | Inactive | Enabled | Bubble BurnerLoans_PolicyInactive() | Unchanged | Covered: [test][test_givenFacilityInactive_whenPermittedCallerSetsYieldFlag_reverts] |
| CYIELD-L05 | BL after forwarding | Active | Disabled | Bubble NotEnabled() | Unchanged | Covered: [test][test_givenFacilityDisabled_whenPermittedCallerSetsYieldFlag_reverts] |
| CYIELD-L06 | BL after forwarding | Inactive | Disabled | Bubble BurnerLoans_PolicyInactive() before BL local-state and RD checks | Unchanged | Covered: [test][test_givenFacilityInactive_whenPermittedCallerSetsYieldFlag_reverts] |

## Forwarding

BLC and BL are active/enabled. The caller is fuzzed between Admin and configOperator.

| ID | Current yield flag | RD pointer/state | Yield asset | Param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CYIELD-P01 | `false` | Nonzero, same-Kernel, Kernel-active and locally enabled | Fuzz a BL-supported future yield asset and whether RD lists it | `true` | Success | BL yield flag `true`; context().yieldRecipient is RD; one SendYieldToDistributorSet(true) from BL | Covered: [test][test_givenValidDistributor_whenPermittedCallerEnablesYieldRouting] |
| CYIELD-P02 | `true` | Fuzz Kernel-active/enabled, Kernel-inactive, locally disabled and unreadable live states | Not read | `false` | Success without RD revalidation | BL yield flag `false`; context().yieldRecipient is Treasury; one underlying event | Covered: [test][test_givenYieldRoutingEnabled_whenPermittedCallerDisables_withoutRevalidation] |
| CYIELD-P03 | `false` | Fuzz reachable zero or nonzero pointer states | Not read | `false` | Silent underlying no-op | No event or other mutation | Covered: [test][test_givenYieldRoutingDisabled_whenPermittedCallerSetsFalse_isNoOp] |
| CYIELD-P04 | `true` | Fuzz Kernel-active/enabled, Kernel-inactive, locally disabled and unreadable live states | Not read | `true` | Silent underlying no-op without RD revalidation | No event or other mutation; context().yieldRecipient remains RD | Covered: [test][test_givenYieldRoutingEnabled_whenPermittedCallerSetsTrue_isNoOp] |

The yield asset is not a setter input; it is a BL-supported asset used by a future
claimYield(asset) call.

## Downstream rejection

BLC and BL are active/enabled. The caller is fuzzed between Admin and configOperator. The current
yield flag is `false`, and the yield flag parameter is `true`.

| ID | RD pointer/state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- |
| CYIELD-I01 | Zero | Bubble BurnerLoans_RevenueDistributorRequired() | Unchanged | Covered: [test][test_givenDistributorUnset_whenPermittedCallerEnablesYieldRouting_reverts] |
| CYIELD-I02 | Nonzero and Kernel-inactive | Bubble BurnerLoans_InvalidRevenueDistributor(RD) | Unchanged | Covered: [test][test_givenDistributorInactive_whenPermittedCallerEnablesYieldRouting_reverts] |
| CYIELD-I03 | Nonzero, Kernel-active and locally disabled | Bubble BurnerLoans_InvalidRevenueDistributor(RD) | Unchanged | Covered: [test][test_givenDistributorDisabled_whenPermittedCallerEnablesYieldRouting_reverts] |
| CYIELD-I04 | Nonzero; Kernel getter reverts | Bubble BurnerLoans_InvalidRevenueDistributor(RD) | Unchanged | Covered: [test][test_givenDistributorKernelReadReverts_whenPermittedCallerEnablesYieldRouting_reverts] |
| CYIELD-I05 | Nonzero; Kernel getter returns malformed data | Bubble BurnerLoans_InvalidRevenueDistributor(RD) | Unchanged | Covered: [test][test_givenDistributorKernelReadMalformed_whenPermittedCallerEnablesYieldRouting_reverts] |
| CYIELD-I06 | Nonzero, same active Kernel; isEnabled getter reverts | Bubble BurnerLoans_InvalidRevenueDistributor(RD) | Unchanged | Covered: [test][test_givenDistributorEnabledReadReverts_whenPermittedCallerEnablesYieldRouting_reverts] |
| CYIELD-I07 | Nonzero, same active Kernel; isEnabled getter returns malformed data | Bubble BurnerLoans_InvalidRevenueDistributor(RD) | Unchanged | Covered: [test][test_givenDistributorEnabledReadMalformed_whenPermittedCallerEnablesYieldRouting_reverts] |

## Pending payouts and future yield

BLC and BL are active/enabled. The caller is fuzzed between Admin and configOperator.

| ID | Current yield flag | RD pointer/state | Pending setup | Param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CYIELD-R01 | `false` | Nonzero, Kernel-active and locally enabled | Fee, seized-collateral and keeper-reward buckets are nonzero | `true` | Success | context().yieldRecipient moves from Treasury to RD; every pending bucket, recipient, totalPending and custody remain unchanged; no pending-yield bucket exists | Covered: [test][test_givenPendingPayouts_whenPermittedCallerChangesYieldRouting_preservesThem] |
| CYIELD-R02 | `true` | Nonzero; validity is not rechecked | Fee, seized-collateral and keeper-reward buckets are nonzero | `false` | Success | context().yieldRecipient moves from RD to Treasury; every pending bucket, recipient, totalPending and custody remain unchanged; no pending-yield bucket exists | Covered: [test][test_givenPendingPayouts_whenPermittedCallerChangesYieldRouting_preservesThem] |

[test_givenConfigDisabled_whenCallerIsUnauthorized_reverts]: ./setSendYieldToDistributor.t.sol#L43
[test_givenConfigDisabled_whenPermittedCallerSetsYieldFlag_reverts]: ./setSendYieldToDistributor.t.sol#L78
[test_givenConfigEnabled_whenCallerIsUnauthorized_reverts]: ./setSendYieldToDistributor.t.sol#L18
[test_givenConfigInactive_whenPermittedCallerSetsYieldFlag_reverts]: ./setSendYieldToDistributor.t.sol#L63
[test_givenDistributorDisabled_whenPermittedCallerEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L224
[test_givenDistributorEnabledReadMalformed_whenPermittedCallerEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L256
[test_givenDistributorEnabledReadReverts_whenPermittedCallerEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L249
[test_givenDistributorInactive_whenPermittedCallerEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L214
[test_givenDistributorKernelReadMalformed_whenPermittedCallerEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L242
[test_givenDistributorKernelReadReverts_whenPermittedCallerEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L235
[test_givenDistributorUnset_whenPermittedCallerEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L203
[test_givenFacilityDisabled_whenPermittedCallerSetsYieldFlag_reverts]: ./setSendYieldToDistributor.t.sol#L116
[test_givenFacilityInactive_whenPermittedCallerSetsYieldFlag_reverts]: ./setSendYieldToDistributor.t.sol#L96
[test_givenPendingPayouts_whenPermittedCallerChangesYieldRouting_preservesThem]: ./setSendYieldToDistributor.t.sol#L273
[test_givenValidDistributor_whenPermittedCallerEnablesYieldRouting]: ./setSendYieldToDistributor.t.sol#L132
[test_givenYieldRoutingDisabled_whenPermittedCallerSetsFalse_isNoOp]: ./setSendYieldToDistributor.t.sol#L168
[test_givenYieldRoutingEnabled_whenPermittedCallerDisables_withoutRevalidation]: ./setSendYieldToDistributor.t.sol#L151
[test_givenYieldRoutingEnabled_whenPermittedCallerSetsTrue_isNoOp]: ./setSendYieldToDistributor.t.sol#L185
