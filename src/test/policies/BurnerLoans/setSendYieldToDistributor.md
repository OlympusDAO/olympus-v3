# setSendYieldToDistributor scenario plan

Scope: the Burner Loans yield-routing flag. Fee routing has a separate
[plan](./setSendFeesToDistributor.md).

Default: BL is Kernel-active and locally enabled. The bound BurnerLoansConfig (BLC) is the only
permitted caller. The selected Revenue Distributor (RD) is a compatible same-Kernel policy.

## Domains and assertions

Required guard order is bound BLC caller, BL Kernel activity, BL local enablement, same-value
handling, then false-to-true RD validation. Changing the yield flag from false to true requires a
nonzero selected RD that is Kernel-active and locally enabled. Interface and Kernel compatibility
are established when the pointer is selected by setRevenueDistributor. The live Kernel and enabled
state are re-read. Reverting or malformed live Kernel and enabled-state reads are normalized to
BurnerLoans_InvalidRevenueDistributor(target). The setter does not read RD route configuration for
any BL-supported yield asset.
Changing the flag from true to false does not require a valid destination. A same-value input
returns after caller and BL lifecycle checks but before RD validation.

Unchanged means the yield flag, fee flag, distributor pointer, balances and liabilities retain their
pre-call values; no event is committed. Success changes only stored yield-routing configuration and
emits exactly one SendYieldToDistributorSet event. No tokens move. context().yieldRecipient changes
between Treasury and RD. Yield claims are atomic: a failed claim or outgoing transfer reverts and
creates no pending-yield bucket. Existing pending fee, seized-collateral and keeper-reward buckets
are unaffected by a yield-routing change.

## Authorization

| ID | Caller | BL Kernel | BL local | Current yield flag | RD pointer/state | Yield flag param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| YIELD-A01 | Caller other than bound BLC, fuzz | Active | Enabled | `false` | Valid and enabled | `true` | BurnerLoans_OnlyConfigurator(caller) | Unchanged | Covered: [test][test_givenLifecycleState_whenCallerIsNotConfigurator_reverts] |
| YIELD-A02 | Caller other than bound BLC, fuzz | Inactive | Enabled | `false` | Valid and enabled | `true` | BurnerLoans_OnlyConfigurator(caller) before lifecycle checks | Unchanged | Covered: [test][test_givenLifecycleState_whenCallerIsNotConfigurator_reverts] |
| YIELD-A03 | Caller other than bound BLC, fuzz | Active | Disabled | `false` | Valid and enabled | `true` | BurnerLoans_OnlyConfigurator(caller) before lifecycle checks | Unchanged | Covered: [test][test_givenLifecycleState_whenCallerIsNotConfigurator_reverts] |
| YIELD-A04 | Caller other than bound BLC, fuzz | Inactive | Disabled | `false` | Valid and enabled | `true` | BurnerLoans_OnlyConfigurator(caller) before lifecycle checks | Unchanged | Covered: [test][test_givenLifecycleState_whenCallerIsNotConfigurator_reverts] |

## Lifecycle

The caller is BLC. Each row fuzzes the current yield flag and parameter over both booleans, with
reachable zero/nonzero pointer and live RD-state combinations. Seed enable, disable and same-value
requests to prove lifecycle precedence.

| ID | BL Kernel | BL local | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| YIELD-L01 | Inactive | Enabled | BurnerLoans_PolicyInactive() before same-value and RD checks | Unchanged | Covered: [test][test_givenPolicyInactive_whenConfiguratorSetsYieldFlag_reverts] |
| YIELD-L02 | Active | Disabled | NotEnabled() before same-value and RD checks | Unchanged | Covered: [test][test_givenLocallyDisabled_whenConfiguratorSetsYieldFlag_reverts] |
| YIELD-L03 | Inactive | Disabled | BurnerLoans_PolicyInactive() before local-state, same-value and RD checks | Unchanged | Covered: [test][test_givenPolicyInactive_whenConfiguratorSetsYieldFlag_reverts] |

## Valid flag updates

BL is Kernel-active and locally enabled, and the caller is BLC in every row.

| ID | Current yield flag | RD pointer/state | Yield flag param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| YIELD-P01 | `false` | Nonzero, same-Kernel, Kernel-active and locally enabled; fuzz a BL-supported future yield asset and whether RD lists it | `true` | Success | Yield flag `true`; context().yieldRecipient is RD; one SendYieldToDistributorSet(true); fee flag and pointer unchanged | Covered: [test][test_givenValidDistributor_whenConfiguratorEnablesYieldRouting] |
| YIELD-P02 | `true` | Fuzz Kernel-active/enabled, Kernel-inactive, locally disabled and unreadable live states | `false` | Success without RD revalidation | Yield flag `false`; context().yieldRecipient is Treasury; one SendYieldToDistributorSet(false) | Covered: [test][test_givenYieldRoutingEnabled_whenConfiguratorDisables_withoutRevalidation] |
| YIELD-P03 | `false` | Fuzz reachable zero or nonzero pointer states | `false` | Silent no-op | No event or token call | Covered: [test][test_givenYieldRoutingDisabled_whenConfiguratorSetsFalse_isNoOp] |
| YIELD-P04 | `true` | Fuzz Kernel-active/enabled, Kernel-inactive, locally disabled and unreadable live states | `true` | Silent no-op without RD revalidation | No event or token call; context().yieldRecipient remains RD | Covered: [test][test_givenYieldRoutingEnabled_whenConfiguratorSetsTrue_isNoOp] |

The asset varied in YIELD-P01 is a BL-supported asset used by a future claimYield(asset) call. The
setter itself has no asset parameter and does not inspect RD asset routes.

## Enable rejection

BL is Kernel-active and locally enabled, the current yield flag is `false`, the parameter is
`true`, and the caller is BLC in every row.

| ID | RD pointer/state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- |
| YIELD-I01 | Zero | BurnerLoans_RevenueDistributorRequired() | Unchanged | Covered: [test][test_givenDistributorUnset_whenConfiguratorEnablesYieldRouting_reverts] |
| YIELD-I05 | Nonzero and Kernel-inactive | BurnerLoans_InvalidRevenueDistributor(target) | Unchanged | Covered: [test][test_givenDistributorKernelInactive_whenConfiguratorEnablesYieldRouting_reverts] |
| YIELD-I06 | Nonzero, Kernel-active and locally disabled | BurnerLoans_InvalidRevenueDistributor(target) | Unchanged | Covered: [test][test_givenDistributorLocallyDisabled_whenConfiguratorEnablesYieldRouting_reverts] |
| YIELD-I07 | Nonzero; Kernel getter reverts | BurnerLoans_InvalidRevenueDistributor(target) | Unchanged | Covered: [test][test_givenDistributorKernelReadReverts_whenConfiguratorEnablesYieldRouting_reverts] |
| YIELD-I08 | Nonzero; Kernel getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(target) | Unchanged | Covered: [test][test_givenDistributorKernelReadMalformed_whenConfiguratorEnablesYieldRouting_reverts] |
| YIELD-I09 | Nonzero, same active Kernel; isEnabled getter reverts | BurnerLoans_InvalidRevenueDistributor(target) | Unchanged | Covered: [test][test_givenDistributorEnabledReadReverts_whenConfiguratorEnablesYieldRouting_reverts] |
| YIELD-I10 | Nonzero, same active Kernel; isEnabled getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(target) | Unchanged | Covered: [test][test_givenDistributorEnabledReadMalformed_whenConfiguratorEnablesYieldRouting_reverts] |

## Pending transfers and future yield

BL is Kernel-active and locally enabled, and the caller is BLC in every row.

| ID | Current yield flag | RD pointer/state | Pending setup | Yield flag param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| YIELD-R01 | `false` | Nonzero, Kernel-active and locally enabled | Fee, seized-collateral and keeper-reward buckets are nonzero | `true` | Success | context().yieldRecipient moves from Treasury to RD; all pending buckets, recipients, totalPending and custody remain unchanged; no pending yield exists | Covered: [test][test_givenPendingPayouts_whenConfiguratorEnablesYieldRouting_preservesPayouts] |
| YIELD-R02 | `true` | Nonzero; validity is not rechecked | Existing pending payout buckets | `false` | Setter succeeds | context().yieldRecipient is Treasury; no pending-yield bucket or payout recipient is created; existing pending buckets remain unchanged | Covered: [test][test_givenPendingPayouts_whenConfiguratorDisablesYieldRouting_preservesPayouts] |

[test_givenDistributorEnabledReadMalformed_whenConfiguratorEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L219
[test_givenDistributorEnabledReadReverts_whenConfiguratorEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L209
[test_givenDistributorKernelInactive_whenConfiguratorEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L168
[test_givenDistributorKernelReadMalformed_whenConfiguratorEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L199
[test_givenDistributorKernelReadReverts_whenConfiguratorEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L189
[test_givenDistributorLocallyDisabled_whenConfiguratorEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L178
[test_givenDistributorUnset_whenConfiguratorEnablesYieldRouting_reverts]: ./setSendYieldToDistributor.t.sol#L157
[test_givenLifecycleState_whenCallerIsNotConfigurator_reverts]: ./setSendYieldToDistributor.t.sol#L14
[test_givenLocallyDisabled_whenConfiguratorSetsYieldFlag_reverts]: ./setSendYieldToDistributor.t.sol#L56
[test_givenPendingPayouts_whenConfiguratorDisablesYieldRouting_preservesPayouts]: ./setSendYieldToDistributor.t.sol#L245
[test_givenPendingPayouts_whenConfiguratorEnablesYieldRouting_preservesPayouts]: ./setSendYieldToDistributor.t.sol#L229
[test_givenPolicyInactive_whenConfiguratorSetsYieldFlag_reverts]: ./setSendYieldToDistributor.t.sol#L38
[test_givenValidDistributor_whenConfiguratorEnablesYieldRouting]: ./setSendYieldToDistributor.t.sol#L70
[test_givenYieldRoutingDisabled_whenConfiguratorSetsFalse_isNoOp]: ./setSendYieldToDistributor.t.sol#L120
[test_givenYieldRoutingEnabled_whenConfiguratorDisables_withoutRevalidation]: ./setSendYieldToDistributor.t.sol#L95
[test_givenYieldRoutingEnabled_whenConfiguratorSetsTrue_isNoOp]: ./setSendYieldToDistributor.t.sol#L138
