# queueSetSendFeesToDistributor scenario plan

Scope: queuing BurnerLoansConfig.setSendFeesToDistributor through BurnerLoansConfigTimelock
(BLCT). Generic execution and cancellation behavior remains in the owning BLCT plans.

Default: BLCT, BurnerLoansConfig (BLC), and Burner Loans (BL) are Kernel-active and locally enabled.
A compatible, Kernel-active, locally enabled RD is selected. BLCT is BLC's selected configOperator.
Admin and Burner Loans Admin are distinct permitted proposers.

## Domains and assertions

The fee action has its own config key. Its expected state hash is
keccak256(abi.encode(BLC.facility(), BL.sendFeesToDistributor(), BL.revenueDistributor())). Only a
false-to-true transition validates the RD: queueing that transition must reject a zero,
Kernel-inactive, locally disabled or unreadable selected RD before acquiring the key. A same-value
request and a true-to-false transition skip RD validation; execution still applies the BLC and BL
lifecycle checks. A valid queue stores one BLC call with the exact boolean payload and does not
change the flag. Ready execution must recheck the hashed state before forwarding to BLC.

Unchanged means the queue, key ownership, flags, pointer, balances and liabilities retain their
pre-call values; no event is committed. A failed execution retains the action and key.

## Authorization

BL and BLC are active/enabled, BLCT is BLC's selected configOperator, the fee flag is `false`, the
RD is valid and enabled, and the parameter is `true` in every row.

| ID | Queue caller | BLCT Kernel | BLCT local | Param | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| QFEES-A01 | Unauthorized caller, fuzz | Active | Enabled | `true` | NotAuthorised() | Unchanged | Covered: [test][test_givenLifecycleState_whenUnauthorizedCallerQueues_reverts] |
| QFEES-A02 | Unauthorized caller, fuzz | Inactive | Enabled | `true` | BurnerLoansConfigTimelock_PolicyInactive(BLCT) before role check | Unchanged | Covered: [test][test_givenLifecycleState_whenUnauthorizedCallerQueues_reverts] |
| QFEES-A03 | Unauthorized caller, fuzz | Active | Disabled | `true` | NotEnabled() before policy and role checks | Unchanged | Covered: [test][test_givenLifecycleState_whenUnauthorizedCallerQueues_reverts] |
| QFEES-A04 | Unauthorized caller, fuzz | Inactive | Disabled | `true` | NotEnabled() before policy and role checks | Unchanged | Covered: [test][test_givenLifecycleState_whenUnauthorizedCallerQueues_reverts] |

## Lifecycle and forwarding prerequisites

The queue caller is permitted. Fuzz the current fee flag and parameter over both booleans, with
reachable zero/nonzero pointer and RD-state combinations. Seed enable, disable and same-value
requests. Non-BLCT gates use an active/enabled BLCT.

| ID | Gate | Kernel | Local / binding | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| QFEES-L01 | BLCT | Inactive | Enabled | BurnerLoansConfigTimelock_PolicyInactive(BLCT) | Unchanged | Covered: [test][test_givenTimelockUnavailable_whenPermittedCallerQueues_reverts] |
| QFEES-L02 | BLCT | Active | Disabled | NotEnabled() | Unchanged | Covered: [test][test_givenTimelockUnavailable_whenPermittedCallerQueues_reverts] |
| QFEES-L03 | BLCT | Inactive | Disabled | NotEnabled() before policy and role checks | Unchanged | Covered: [test][test_givenTimelockUnavailable_whenPermittedCallerQueues_reverts] |
| QFEES-L04 | BLC | Inactive | Enabled; BLCT selected | BurnerLoansConfigTimelock_PolicyInactive(BLC) | Unchanged | Covered: [test][test_givenConfigUnavailable_whenPermittedCallerQueues_reverts] |
| QFEES-L05 | BLC | Active | Disabled; BLCT selected | NotEnabled() | Unchanged | Covered: [test][test_givenConfigUnavailable_whenPermittedCallerQueues_reverts] |
| QFEES-L06 | BLC | Inactive | Disabled; BLCT selected | BurnerLoansConfigTimelock_PolicyInactive(BLC) before BLC local-state validation | Unchanged | Covered: [test][test_givenConfigUnavailable_whenPermittedCallerQueues_reverts] |
| QFEES-L07 | BLC operator | Active | Enabled; BLCT not selected | BurnerLoansConfig_UnauthorizedConfigOperator(BLCT) | Unchanged | Covered: [test][test_givenConfigUnavailable_whenPermittedCallerQueues_reverts] |

## Queue and execution

All policies are active/enabled, and BLCT is BLC's selected configOperator.

### Queue acceptance

| ID | Proposer | Current flag | RD state | Asset | Param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QFEES-P01 | Admin or Burner Loans Admin, fuzz between identities | `false` | Valid and enabled | Fuzz a BL-supported future fee asset and whether RD lists it | `true` | Queue accepted | Exact BLC action, fee-routing key, state hash and queue events; flag remains `false` | Covered: [test][test_givenValidDistributor_whenPermittedCallerQueuesAndExecutorRuns_succeeds] |

### Ready execution

The executor is any caller, fuzzed. The proposer is permitted during setup.

| ID | Current flag | RD state | Queued param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| QFEES-P02 | `false`; unchanged since queue | Valid and enabled; unchanged | `true` | Execution succeeds | Fee flag `true`; one underlying event; action removed and fee key released | Covered: [test][test_givenValidDistributor_whenPermittedCallerQueuesAndExecutorRuns_succeeds] |
| QFEES-P03 | `true` | Fuzz Kernel-active/enabled, Kernel-inactive, locally disabled and unreadable states before queue | `false` | Queue and execution succeed without RD validation | Fee flag `false`; one underlying event; action removed and fee key released | Covered: [test][test_givenFeeRoutingEnabled_whenDisableQueuedAndExecuted_skipsDistributorValidation] |
| QFEES-P04 | `false` | Zero | `false` | Queue accepted; execution is an underlying no-op | No flag event; action removed and fee key released | Covered: [test][test_givenDisableOrSameValue_whenQueuedAndExecuted_skipsDistributorValidation] |
| QFEES-P05 | `true` | Fuzz Kernel-active/enabled, Kernel-inactive, locally disabled and unreadable states before queue | `true` | Queue accepted; execution is an underlying no-op | Fee role and any pending fee remain assigned to RD; no flag event; action removed and fee key released | Covered: [test][test_givenDisableOrSameValue_whenQueuedAndExecuted_skipsDistributorValidation] |

The asset varied in QFEES-P01 is not a queue input; it is the asset of a future fee collected by BL.

## Queue rejection

All policies are active/enabled, BLCT is selected as configOperator, the current fee flag is `false`,
and the fee flag parameter is `true`. The proposer is fuzzed between Admin and Burner Loans Admin.

| ID | RD pointer/state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- |
| QFEES-I01 | Zero | BurnerLoans_RevenueDistributorRequired() | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorUnset_whenEnableQueued_revertsBeforeKeyAcquisition] |
| QFEES-I02 | Nonzero and Kernel-inactive | BurnerLoans_InvalidRevenueDistributor(RD) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorInactive_whenEnableQueued_reverts] |
| QFEES-I03 | Nonzero, Kernel-active and locally disabled | BurnerLoans_InvalidRevenueDistributor(RD) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorDisabled_whenEnableQueued_reverts] |
| QFEES-I04 | Nonzero; Kernel getter reverts | BurnerLoans_InvalidRevenueDistributor(RD) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorKernelReadReverts_whenEnableQueued_reverts] |
| QFEES-I05 | Nonzero; Kernel getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(RD) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorKernelReadMalformed_whenEnableQueued_reverts] |
| QFEES-I06 | Nonzero, same active Kernel; isEnabled getter reverts | BurnerLoans_InvalidRevenueDistributor(RD) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorEnabledReadReverts_whenEnableQueued_reverts] |
| QFEES-I07 | Nonzero, same active Kernel; isEnabled getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(RD) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorEnabledReadMalformed_whenEnableQueued_reverts] |

### Raw queue payload validation

| ID | Payload | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- |
| QFEES-I08 | 31 or 33 bytes instead of one ABI word | ITimelockBatchQueue_ActionInvalid(BLC, selector) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_whenFeeDistributorFlagPayloadIsInvalid_reverts] |
| QFEES-I09 | One ABI word containing `2` | ITimelockBatchQueue_ActionInvalid(BLC, selector) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_whenFeeDistributorFlagPayloadIsInvalid_reverts] |

## Execution rejection

The executor is any caller, fuzzed. BLCT and BLC remain active/enabled and the action is ready.

### Hashed-state conflicts

BL remains active/enabled. Live RD validity is irrelevant because the state-hash check fails first.

| ID | Queued param | Current fee flag | Pointer at execution | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| QFEES-S01 | `true` | `false` | Cleared to zero after queue | IConfigTimelockBatchQueue_ConfigStateChanged with independently computed hash | Fee flag remains `false`; action and key retained | Covered: [test][test_givenFlagQueued_whenDistributorPointerChanges_executionRetainsAction] |
| QFEES-S02 | `true` | `false` | Changed to another valid nonzero RD after queue | IConfigTimelockBatchQueue_ConfigStateChanged with independently computed hash | Fee flag remains `false`; action and key retained | Covered: [test][test_givenFlagQueued_whenDistributorPointerChanges_executionRetainsAction] |
| QFEES-S03 | `true` | Changed after queue | Original RD | IConfigTimelockBatchQueue_ConfigStateChanged with independently computed hash | Direct flag change retained; action and key retained | Covered: [test][test_givenFlagQueued_whenFlagChanges_executionRetainsAction] |
| QFEES-S12 | `false` | `true` | Changed after queue | IConfigTimelockBatchQueue_ConfigStateChanged with independently computed hash | Direct pointer change retained; fee flag unchanged; action and key retained | Covered: [test][test_givenFlagQueued_whenDistributorPointerChanges_executionRetainsAction] |
| QFEES-S13 | `false` | Changed after queue | Original RD | IConfigTimelockBatchQueue_ConfigStateChanged with independently computed hash | Direct flag change retained; action and key retained | Covered: [test][test_givenFlagQueued_whenFlagChanges_executionRetainsAction] |

### Live validation failures

The current flag and pointer still match the queued hash.

| ID | Queued param | BL Kernel | BL local | RD state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| QFEES-S04 | `true` | Inactive | Enabled | Valid and enabled | BurnerLoans_PolicyInactive() | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenFacilityInactive_executionRetainsAction] |
| QFEES-S05 | `true` | Active | Enabled | Kernel-inactive | BurnerLoans_InvalidRevenueDistributor(RD) | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenDistributorInactive_executionRetainsAction] |
| QFEES-S06 | `true` | Active | Enabled | Kernel-active; locally disabled | BurnerLoans_InvalidRevenueDistributor(RD) | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenDistributorDisabled_executionRetainsAction] |
| QFEES-S07 | `true` | Active | Disabled | Valid and enabled | NotEnabled() from BL | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenFacilityDisabled_executionRetainsAction] |
| QFEES-S08 | `true` | Active | Enabled | Kernel getter reverts | BurnerLoans_InvalidRevenueDistributor(RD) | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenDistributorKernelReadReverts_executionRetainsAction] |
| QFEES-S09 | `true` | Active | Enabled | Kernel getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(RD) | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenDistributorKernelReadMalformed_executionRetainsAction] |
| QFEES-S10 | `true` | Active | Enabled | isEnabled getter reverts | BurnerLoans_InvalidRevenueDistributor(RD) | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenDistributorEnabledReadReverts_executionRetainsAction] |
| QFEES-S11 | `true` | Active | Enabled | isEnabled getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(RD) | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenDistributorEnabledReadMalformed_executionRetainsAction] |

## Pending payout execution

All policies are active/enabled. The proposer is fuzzed between Admin and Burner Loans Admin; the
executor is any caller, fuzzed.

| ID | Current fee flag | RD pointer/state | Pending setup | Param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| QFEES-R01 | `false` | Nonzero, Kernel-active and locally enabled | Pending fee resolves to Treasury | `true` | Queue and execution succeed | Pending fee moves to RD only on execution; pendingFees, totalPending, custody, seizure and keeper-reward assignments stay unchanged; action removed and key released | Covered: [test][test_givenPendingPayouts_whenFlagExecutes_reassignsFeeOnly] |
| QFEES-R02 | `true` | Nonzero; validity is not rechecked | Pending fee resolves to RD | `false` | Queue and execution succeed | Pending fee moves to Treasury only on execution; other pending assignments and aggregate custody stay unchanged; action removed and key released | Covered: [test][test_givenPendingPayouts_whenFlagExecutes_reassignsFeeOnly] |

## Queue conflicts

All policies are active/enabled, and the proposer is fuzzed between Admin and Burner Loans Admin.

| ID | Existing action | New param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QFEES-Q01 | Pending setSendFeesToDistributor(true) holds the fee-routing key | `true` | IConfigTimelockBatchQueue_ConfigKeyPending(feeKey, firstActionId) | First action and key ownership unchanged; no second action ID consumed | Covered: [test][test_givenFeeActionPending_whenSecondFeeActionQueued_revertsWithKeyOwner] |
| QFEES-Q02 | Pending setSendFeesToDistributor(true) holds the fee-routing key | `false` | IConfigTimelockBatchQueue_ConfigKeyPending(feeKey, firstActionId) | First action and key ownership unchanged; no second action ID consumed | Covered: [test][test_givenFeeActionPending_whenSecondFeeActionQueued_revertsWithKeyOwner] |

[test_givenConfigUnavailable_whenPermittedCallerQueues_reverts]: ./queueSetSendFeesToDistributor.t.sol#L74
[test_givenDisableOrSameValue_whenQueuedAndExecuted_skipsDistributorValidation]: ./queueSetSendFeesToDistributor.t.sol#L149
[test_givenDistributorDisabled_whenEnableQueued_reverts]: ./queueSetSendFeesToDistributor.t.sol#L216
[test_givenDistributorEnabledReadMalformed_whenEnableQueued_reverts]: ./queueSetSendFeesToDistributor.t.sol#L242
[test_givenDistributorEnabledReadReverts_whenEnableQueued_reverts]: ./queueSetSendFeesToDistributor.t.sol#L235
[test_givenDistributorInactive_whenEnableQueued_reverts]: ./queueSetSendFeesToDistributor.t.sol#L211
[test_givenDistributorKernelReadMalformed_whenEnableQueued_reverts]: ./queueSetSendFeesToDistributor.t.sol#L228
[test_givenDistributorKernelReadReverts_whenEnableQueued_reverts]: ./queueSetSendFeesToDistributor.t.sol#L221
[test_givenDistributorUnset_whenEnableQueued_revertsBeforeKeyAcquisition]: ./queueSetSendFeesToDistributor.t.sol#L200
[test_givenEnableReady_whenDistributorDisabled_executionRetainsAction]: ./queueSetSendFeesToDistributor.t.sol#L288
[test_givenEnableReady_whenDistributorEnabledReadMalformed_executionRetainsAction]: ./queueSetSendFeesToDistributor.t.sol#L319
[test_givenEnableReady_whenDistributorEnabledReadReverts_executionRetainsAction]: ./queueSetSendFeesToDistributor.t.sol#L312
[test_givenEnableReady_whenDistributorInactive_executionRetainsAction]: ./queueSetSendFeesToDistributor.t.sol#L283
[test_givenEnableReady_whenDistributorKernelReadMalformed_executionRetainsAction]: ./queueSetSendFeesToDistributor.t.sol#L305
[test_givenEnableReady_whenDistributorKernelReadReverts_executionRetainsAction]: ./queueSetSendFeesToDistributor.t.sol#L298
[test_givenEnableReady_whenFacilityDisabled_executionRetainsAction]: ./queueSetSendFeesToDistributor.t.sol#L293
[test_givenEnableReady_whenFacilityInactive_executionRetainsAction]: ./queueSetSendFeesToDistributor.t.sol#L278
[test_givenFeeActionPending_whenSecondFeeActionQueued_revertsWithKeyOwner]: ./queueSetSendFeesToDistributor.t.sol#L346
[test_givenFeeRoutingEnabled_whenDisableQueuedAndExecuted_skipsDistributorValidation]: ./queueSetSendFeesToDistributor.t.sol#L175
[test_givenFlagQueued_whenDistributorPointerChanges_executionRetainsAction]: ./queueSetSendFeesToDistributor.t.sol#L249
[test_givenFlagQueued_whenFlagChanges_executionRetainsAction]: ./queueSetSendFeesToDistributor.t.sol#L267
[test_givenLifecycleState_whenUnauthorizedCallerQueues_reverts]: ./queueSetSendFeesToDistributor.t.sol#L23
[test_givenPendingPayouts_whenFlagExecutes_reassignsFeeOnly]: ./queueSetSendFeesToDistributor.t.sol#L326
[test_givenTimelockUnavailable_whenPermittedCallerQueues_reverts]: ./queueSetSendFeesToDistributor.t.sol#L50
[test_givenValidDistributor_whenPermittedCallerQueuesAndExecutorRuns_succeeds]: ./queueSetSendFeesToDistributor.t.sol#L109
[test_whenFeeDistributorFlagPayloadIsInvalid_reverts]: ./queueAction.t.sol#L182
