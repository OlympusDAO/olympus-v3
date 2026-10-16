# setSendFeesToDistributor scenario plan

Scope: BurnerLoansConfig (BLC) forwarding of the fee-routing flag. The underlying Burner Loans
behavior has its own [plan](../BurnerLoans/setSendFeesToDistributor.md).

Default: BLC and Burner Loans (BL) are Kernel-active and locally enabled. A compatible,
Kernel-active, locally enabled RD is selected. Admin and the current nonzero configOperator are
distinct permitted caller classes; success and downstream-rejection cases fuzz a selector across
exactly those two identities.

## Domains and assertions

BLC guard order is local enablement, caller authorization, BLC Kernel activity, then forwarding the
exact boolean to its bound BL. BL then applies its own lifecycle and distributor validation.

Unchanged means both policies' configuration, balances and liabilities retain their pre-call values;
no event is committed. Success changes only BL's fee flag and emits the underlying fee-flag event.

## Authorization

BL is active and enabled, the current fee flag is `false`, the RD is valid and enabled, and the
parameter is `true` in every row.

| ID | Caller | BLC Kernel | BLC local | Current fee flag | RD state | Param | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CFEES-A01 | Neither Admin nor current configOperator, fuzz | Active | Enabled | `false` | Valid and enabled | `true` | BurnerLoansConfig_UnauthorizedConfigOperator(caller) | Unchanged | Covered: [test][test_givenConfigEnabled_whenCallerIsUnauthorized_reverts] |
| CFEES-A02 | Neither Admin nor current configOperator, fuzz | Inactive | Enabled | `false` | Valid and enabled | `true` | BurnerLoansConfig_UnauthorizedConfigOperator(caller) before activity check | Unchanged | Covered: [test][test_givenConfigEnabled_whenCallerIsUnauthorized_reverts] |
| CFEES-A03 | Neither Admin nor current configOperator, fuzz | Active | Disabled | `false` | Valid and enabled | `true` | NotEnabled() before authorization and activity checks | Unchanged | Covered: [test][test_givenConfigDisabled_whenCallerIsUnauthorized_reverts] |
| CFEES-A04 | Neither Admin nor current configOperator, fuzz | Inactive | Disabled | `false` | Valid and enabled | `true` | NotEnabled() before authorization and activity checks | Unchanged | Covered: [test][test_givenConfigDisabled_whenCallerIsUnauthorized_reverts] |

## Lifecycle

For BLC lifecycle rows, fuzz the caller between Admin and configOperator and fuzz reachable current
flag, parameter, pointer and RD-state combinations. For BL lifecycle rows, BLC is active/enabled and
the permitted caller reaches BL with the same fuzzed input domain.

| ID | Gate | Kernel | Local | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| CFEES-L01 | BLC | Inactive | Enabled | BurnerLoansConfig_PolicyInactive() before forwarding | Unchanged | Covered: [test][test_givenConfigInactive_whenPermittedCallerSetsFeeFlag_reverts] |
| CFEES-L02 | BLC | Active | Disabled | NotEnabled() before forwarding | Unchanged | Covered: [test][test_givenConfigDisabled_whenPermittedCallerSetsFeeFlag_reverts] |
| CFEES-L03 | BLC | Inactive | Disabled | NotEnabled() before authorization, activity and forwarding | Unchanged | Covered: [test][test_givenConfigDisabled_whenPermittedCallerSetsFeeFlag_reverts] |
| CFEES-L04 | BL after forwarding | Inactive | Enabled | Bubble BurnerLoans_PolicyInactive() | Unchanged | Covered: [test][test_givenFacilityInactive_whenPermittedCallerSetsFeeFlag_reverts] |
| CFEES-L05 | BL after forwarding | Active | Disabled | Bubble NotEnabled() | Unchanged | Covered: [test][test_givenFacilityDisabled_whenPermittedCallerSetsFeeFlag_reverts] |
| CFEES-L06 | BL after forwarding | Inactive | Disabled | Bubble BurnerLoans_PolicyInactive() before BL local-state and RD checks | Unchanged | Covered: [test][test_givenFacilityInactive_whenPermittedCallerSetsFeeFlag_reverts] |

## Forwarding

BLC and BL are active/enabled. The caller is fuzzed between Admin and configOperator.

| ID | Current fee flag | RD pointer/state | Fee asset | Param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CFEES-P01 | `false` | Nonzero, same-Kernel, Kernel-active and locally enabled | Fuzz a BL-supported future fee asset and whether RD lists it | `true` | Success | BL fee flag `true`; one SendFeesToDistributorSet(true) from BL | Covered: [test][test_givenValidDistributor_whenPermittedCallerEnablesFeeRouting] |
| CFEES-P02 | `true` | Fuzz Kernel-active/enabled, Kernel-inactive, locally disabled and unreadable live states | Not read | `false` | Success without RD revalidation | BL fee flag `false`; one SendFeesToDistributorSet(false) from BL | Covered: [test][test_givenFeeRoutingEnabled_whenPermittedCallerDisables_withoutRevalidation] |
| CFEES-P03 | `false` | Fuzz reachable zero or nonzero pointer states | Not read | `false` | Silent underlying no-op | No event or other mutation | Covered: [test][test_givenFeeRoutingDisabled_whenPermittedCallerSetsFalse_isNoOp] |
| CFEES-P04 | `true` | Fuzz Kernel-active/enabled, Kernel-inactive, locally disabled and unreadable live states | Not read | `true` | Silent underlying no-op without RD revalidation | No event or other mutation; fee role and any pending fee remain assigned to RD | Covered: [test][test_givenFeeRoutingEnabled_whenPermittedCallerSetsTrue_isNoOp] |

The fee asset is not a setter input; it is the asset of a future fee collected by BL.

## Downstream rejection

BLC and BL are active/enabled. The caller is fuzzed between Admin and configOperator. The current fee
flag is `false`, and the fee flag parameter is `true`.

| ID | RD pointer/state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- |
| CFEES-I01 | Zero | Bubble BurnerLoans_RevenueDistributorRequired() | Unchanged | Covered: [test][test_givenDistributorUnset_whenPermittedCallerEnablesFeeRouting_reverts] |
| CFEES-I02 | Nonzero and Kernel-inactive | Bubble BurnerLoans_InvalidRevenueDistributor(RD) | Unchanged | Covered: [test][test_givenDistributorInactive_whenPermittedCallerEnablesFeeRouting_reverts] |
| CFEES-I03 | Nonzero, Kernel-active and locally disabled | Bubble BurnerLoans_InvalidRevenueDistributor(RD) | Unchanged | Covered: [test][test_givenDistributorDisabled_whenPermittedCallerEnablesFeeRouting_reverts] |
| CFEES-I04 | Nonzero; Kernel getter reverts | Bubble BurnerLoans_InvalidRevenueDistributor(RD) | Unchanged | Covered: [test][test_givenDistributorKernelReadReverts_whenPermittedCallerEnablesFeeRouting_reverts] |
| CFEES-I05 | Nonzero; Kernel getter returns malformed data | Bubble BurnerLoans_InvalidRevenueDistributor(RD) | Unchanged | Covered: [test][test_givenDistributorKernelReadMalformed_whenPermittedCallerEnablesFeeRouting_reverts] |
| CFEES-I06 | Nonzero, same active Kernel; isEnabled getter reverts | Bubble BurnerLoans_InvalidRevenueDistributor(RD) | Unchanged | Covered: [test][test_givenDistributorEnabledReadReverts_whenPermittedCallerEnablesFeeRouting_reverts] |
| CFEES-I07 | Nonzero, same active Kernel; isEnabled getter returns malformed data | Bubble BurnerLoans_InvalidRevenueDistributor(RD) | Unchanged | Covered: [test][test_givenDistributorEnabledReadMalformed_whenPermittedCallerEnablesFeeRouting_reverts] |

## Pending payout forwarding

BLC and BL are active/enabled. The caller is fuzzed between Admin and configOperator.

| ID | Current fee flag | RD pointer/state | Pending setup | Param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CFEES-R01 | `false` | Nonzero, Kernel-active and locally enabled | Pending fee resolves to Treasury | `true` | Success | Pending fee recipient and enumeration move to RD; pending storage, totalPending, custody, seizure and keeper-reward assignments unchanged | Covered: [test][test_givenPendingPayouts_whenPermittedCallerEnablesFeeRouting_reassignsFee] |
| CFEES-R02 | `true` | Nonzero; validity is not rechecked | Pending fee resolves to RD | `false` | Success | Pending fee recipient and enumeration move to Treasury; other pending assignments and aggregate custody unchanged | Covered: [test][test_givenPendingPayouts_whenPermittedCallerDisablesFeeRouting_reassignsFee] |

[test_givenConfigDisabled_whenCallerIsUnauthorized_reverts]: ./setSendFeesToDistributor.t.sol#L43
[test_givenConfigDisabled_whenPermittedCallerSetsFeeFlag_reverts]: ./setSendFeesToDistributor.t.sol#L78
[test_givenConfigEnabled_whenCallerIsUnauthorized_reverts]: ./setSendFeesToDistributor.t.sol#L18
[test_givenConfigInactive_whenPermittedCallerSetsFeeFlag_reverts]: ./setSendFeesToDistributor.t.sol#L63
[test_givenDistributorDisabled_whenPermittedCallerEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L224
[test_givenDistributorEnabledReadMalformed_whenPermittedCallerEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L256
[test_givenDistributorEnabledReadReverts_whenPermittedCallerEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L249
[test_givenDistributorInactive_whenPermittedCallerEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L214
[test_givenDistributorKernelReadMalformed_whenPermittedCallerEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L242
[test_givenDistributorKernelReadReverts_whenPermittedCallerEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L235
[test_givenDistributorUnset_whenPermittedCallerEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L203
[test_givenFacilityDisabled_whenPermittedCallerSetsFeeFlag_reverts]: ./setSendFeesToDistributor.t.sol#L116
[test_givenFacilityInactive_whenPermittedCallerSetsFeeFlag_reverts]: ./setSendFeesToDistributor.t.sol#L96
[test_givenFeeRoutingDisabled_whenPermittedCallerSetsFalse_isNoOp]: ./setSendFeesToDistributor.t.sol#L168
[test_givenFeeRoutingEnabled_whenPermittedCallerDisables_withoutRevalidation]: ./setSendFeesToDistributor.t.sol#L151
[test_givenFeeRoutingEnabled_whenPermittedCallerSetsTrue_isNoOp]: ./setSendFeesToDistributor.t.sol#L185
[test_givenPendingPayouts_whenPermittedCallerDisablesFeeRouting_reassignsFee]: ./setSendFeesToDistributor.t.sol#L287
[test_givenPendingPayouts_whenPermittedCallerEnablesFeeRouting_reassignsFee]: ./setSendFeesToDistributor.t.sol#L273
[test_givenValidDistributor_whenPermittedCallerEnablesFeeRouting]: ./setSendFeesToDistributor.t.sol#L132
