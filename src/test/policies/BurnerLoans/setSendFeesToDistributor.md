# setSendFeesToDistributor scenario plan

Scope: the Burner Loans fee-routing flag. Yield routing has a separate
[plan](./setSendYieldToDistributor.md).

Default: BL is Kernel-active and locally enabled. The bound BurnerLoansConfig (BLC) is the only
permitted caller. The selected Revenue Distributor (RD) is a compatible same-Kernel policy.

## Domains and assertions

Required guard order is bound BLC caller, BL Kernel activity, BL local enablement, same-value
handling, then false-to-true RD validation. Changing the fee flag from false to true requires a
nonzero selected RD that is Kernel-active and locally enabled. Interface and Kernel compatibility
are established when the pointer is selected by setRevenueDistributor. The live Kernel and enabled
state are re-read. Reverting or malformed live Kernel and enabled-state reads are normalized to
BurnerLoans_InvalidRevenueDistributor(target). The setter does not read RD route configuration for
any BL-supported fee asset.
Changing the flag from true to false does not require a valid destination. A same-value input
returns after caller and BL lifecycle checks but before RD validation.

Unchanged means the fee flag, yield flag, distributor pointer, balances and liabilities retain their
pre-call values; no event is committed. Success changes only stored fee-routing configuration and
emits exactly one SendFeesToDistributorSet event. No tokens move. Pending fee storage and aggregate
custody do not change, but pendingPayout and recipient enumeration follow the new current fee role.
Pending seized collateral remains assigned to Treasury and keeper rewards to their original keepers.

## Authorization

| ID | Caller | BL Kernel | BL local | Current fee flag | RD pointer/state | Fee flag param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FEES-A01 | Caller other than bound BLC, fuzz | Active | Enabled | `false` | Valid and enabled | `true` | BurnerLoans_OnlyConfigurator(caller) | Unchanged | Covered: [test][test_givenLifecycleState_whenCallerIsNotConfigurator_reverts] |
| FEES-A02 | Caller other than bound BLC, fuzz | Inactive | Enabled | `false` | Valid and enabled | `true` | BurnerLoans_OnlyConfigurator(caller) before lifecycle checks | Unchanged | Covered: [test][test_givenLifecycleState_whenCallerIsNotConfigurator_reverts] |
| FEES-A03 | Caller other than bound BLC, fuzz | Active | Disabled | `false` | Valid and enabled | `true` | BurnerLoans_OnlyConfigurator(caller) before lifecycle checks | Unchanged | Covered: [test][test_givenLifecycleState_whenCallerIsNotConfigurator_reverts] |
| FEES-A04 | Caller other than bound BLC, fuzz | Inactive | Disabled | `false` | Valid and enabled | `true` | BurnerLoans_OnlyConfigurator(caller) before lifecycle checks | Unchanged | Covered: [test][test_givenLifecycleState_whenCallerIsNotConfigurator_reverts] |

## Lifecycle

The caller is BLC. Each row fuzzes the current fee flag and parameter over both booleans, with
reachable zero/nonzero pointer and live RD-state combinations. Seed enable, disable and same-value
requests to prove lifecycle precedence.

| ID | BL Kernel | BL local | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| FEES-L01 | Inactive | Enabled | BurnerLoans_PolicyInactive() before same-value and RD checks | Unchanged | Covered: [test][test_givenPolicyInactive_whenConfiguratorSetsFeeFlag_reverts] |
| FEES-L02 | Active | Disabled | NotEnabled() before same-value and RD checks | Unchanged | Covered: [test][test_givenLocallyDisabled_whenConfiguratorSetsFeeFlag_reverts] |
| FEES-L03 | Inactive | Disabled | BurnerLoans_PolicyInactive() before local-state, same-value and RD checks | Unchanged | Covered: [test][test_givenPolicyInactive_whenConfiguratorSetsFeeFlag_reverts] |

## Valid flag updates

BL is Kernel-active and locally enabled, and the caller is BLC in every row.

| ID | Current fee flag | RD pointer/state | Fee flag param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| FEES-P01 | `false` | Nonzero, same-Kernel, Kernel-active and locally enabled; fuzz a BL-supported future fee asset and whether RD lists it | `true` | Success | Fee flag `true`; one SendFeesToDistributorSet(true); yield flag and pointer unchanged | Covered: [test][test_givenValidDistributor_whenConfiguratorEnablesFeeRouting] |
| FEES-P02 | `true` | Fuzz Kernel-active/enabled, Kernel-inactive, locally disabled and unreadable live states | `false` | Success without RD revalidation | Fee flag `false`; one SendFeesToDistributorSet(false) | Covered: [test][test_givenFeeRoutingEnabled_whenConfiguratorDisables_withoutRevalidation] |
| FEES-P03 | `false` | Fuzz reachable zero or nonzero pointer states | `false` | Silent no-op | No event or token call | Covered: [test][test_givenFeeRoutingDisabled_whenConfiguratorSetsFalse_isNoOp] |
| FEES-P04 | `true` | Fuzz Kernel-active/enabled, Kernel-inactive, locally disabled and unreadable live states | `true` | Silent no-op without RD revalidation | No event or token call; fee role and any pending fee remain assigned to RD | Covered: [test][test_givenFeeRoutingEnabled_whenConfiguratorSetsTrue_isNoOp] |

The asset varied in FEES-P01 is the asset of a future fee collected by BL. The setter itself has no
asset parameter and does not inspect RD asset routes.

## Enable rejection

BL is Kernel-active and locally enabled, the current fee flag is `false`, the parameter is `true`,
and the caller is BLC in every row.

| ID | RD pointer/state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- |
| FEES-I01 | Zero | BurnerLoans_RevenueDistributorRequired() | Unchanged | Covered: [test][test_givenDistributorUnset_whenConfiguratorEnablesFeeRouting_reverts] |
| FEES-I05 | Nonzero and Kernel-inactive | BurnerLoans_InvalidRevenueDistributor(target) | Unchanged | Covered: [test][test_givenDistributorKernelInactive_whenConfiguratorEnablesFeeRouting_reverts] |
| FEES-I06 | Nonzero, Kernel-active and locally disabled | BurnerLoans_InvalidRevenueDistributor(target) | Unchanged | Covered: [test][test_givenDistributorLocallyDisabled_whenConfiguratorEnablesFeeRouting_reverts] |
| FEES-I07 | Nonzero; Kernel getter reverts | BurnerLoans_InvalidRevenueDistributor(target) | Unchanged | Covered: [test][test_givenDistributorKernelReadReverts_whenConfiguratorEnablesFeeRouting_reverts] |
| FEES-I08 | Nonzero; Kernel getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(target) | Unchanged | Covered: [test][test_givenDistributorKernelReadMalformed_whenConfiguratorEnablesFeeRouting_reverts] |
| FEES-I09 | Nonzero, same active Kernel; isEnabled getter reverts | BurnerLoans_InvalidRevenueDistributor(target) | Unchanged | Covered: [test][test_givenDistributorEnabledReadReverts_whenConfiguratorEnablesFeeRouting_reverts] |
| FEES-I10 | Nonzero, same active Kernel; isEnabled getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(target) | Unchanged | Covered: [test][test_givenDistributorEnabledReadMalformed_whenConfiguratorEnablesFeeRouting_reverts] |

## Pending payout reassignment

Use distinct RD, Treasury and keeper identities. Yield has no pending bucket; these rows concern the
fee, seized-collateral and keeper-reward buckets held by Burner Loans. BL is Kernel-active and
locally enabled, and the caller is BLC in every row.

| ID | Current fee flag | RD pointer/state | Pending setup | Fee flag param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FEES-R01 | `false` | Nonzero, Kernel-active and locally enabled | Pending fee resolves to Treasury | `true` | Success | Pending fee recipient and enumeration move from Treasury to RD; pendingFees, totalPending, custody, seizure and keeper-reward buckets unchanged; one event | Covered: [test][test_givenPendingPayouts_whenConfiguratorEnablesFeeRouting_reassignsFee] |
| FEES-R02 | `true` | Nonzero; validity is not rechecked | Failed transfer left a pending fee resolving to RD | `false` | Success | Pending fee recipient and enumeration move from RD to Treasury; pendingFees, totalPending, custody, seizure and keeper-reward buckets unchanged; one event | Covered: [test][test_givenPendingPayouts_whenConfiguratorDisablesFeeRouting_reassignsFee] |

[test_givenDistributorEnabledReadMalformed_whenConfiguratorEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L215
[test_givenDistributorEnabledReadReverts_whenConfiguratorEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L205
[test_givenDistributorKernelInactive_whenConfiguratorEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L164
[test_givenDistributorKernelReadMalformed_whenConfiguratorEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L195
[test_givenDistributorKernelReadReverts_whenConfiguratorEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L185
[test_givenDistributorLocallyDisabled_whenConfiguratorEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L174
[test_givenDistributorUnset_whenConfiguratorEnablesFeeRouting_reverts]: ./setSendFeesToDistributor.t.sol#L153
[test_givenFeeRoutingDisabled_whenConfiguratorSetsFalse_isNoOp]: ./setSendFeesToDistributor.t.sol#L118
[test_givenFeeRoutingEnabled_whenConfiguratorDisables_withoutRevalidation]: ./setSendFeesToDistributor.t.sol#L94
[test_givenFeeRoutingEnabled_whenConfiguratorSetsTrue_isNoOp]: ./setSendFeesToDistributor.t.sol#L135
[test_givenLifecycleState_whenCallerIsNotConfigurator_reverts]: ./setSendFeesToDistributor.t.sol#L14
[test_givenLocallyDisabled_whenConfiguratorSetsFeeFlag_reverts]: ./setSendFeesToDistributor.t.sol#L56
[test_givenPendingPayouts_whenConfiguratorDisablesFeeRouting_reassignsFee]: ./setSendFeesToDistributor.t.sol#L243
[test_givenPendingPayouts_whenConfiguratorEnablesFeeRouting_reassignsFee]: ./setSendFeesToDistributor.t.sol#L225
[test_givenPolicyInactive_whenConfiguratorSetsFeeFlag_reverts]: ./setSendFeesToDistributor.t.sol#L38
[test_givenValidDistributor_whenConfiguratorEnablesFeeRouting]: ./setSendFeesToDistributor.t.sol#L70
