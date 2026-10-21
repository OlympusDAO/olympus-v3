# queueSetSendYieldToDistributor scenario plan

Scope: queuing BurnerLoansConfig.setSendYieldToDistributor through BurnerLoansConfigTimelock
(BLCT). Generic execution and cancellation behavior remains in the owning BLCT plans.

Default: BLCT, BurnerLoansConfig (BLC), and Burner Loans (BL) are Kernel-active and locally enabled.
A compatible, Kernel-active, locally enabled RD is selected. BLCT is BLC's selected configOperator.
Admin and Burner Loans Admin are distinct permitted proposers.

## Domains and assertions

The yield action has its own config key. Its expected state hash is
keccak256(abi.encode(BLC.facility(), BL.sendYieldToDistributor(), BL.revenueDistributor())). Only a
false-to-true transition validates the RD: queueing that transition must reject a zero,
Kernel-inactive, locally disabled or unreadable selected RD before acquiring the key. A same-value
request and a true-to-false transition skip RD validation; execution still applies the BLC and BL
lifecycle checks. A valid queue stores one BLC call with the exact boolean payload and does not
change the flag. Ready execution must recheck the hashed state before forwarding to BLC.

Unchanged means the queue, key ownership, flags, pointer, balances and liabilities retain their
pre-call values; no event is committed. A failed execution retains the action and key.

## Authorization

BL and BLC are active/enabled, BLCT is BLC's selected configOperator, the yield flag is `false`,
the RD is valid and enabled, and the parameter is `true` in every row.

| ID | Queue caller | BLCT Kernel | BLCT local | Param | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| QYIELD-A01 | Unauthorized caller, fuzz | Active | Enabled | `true` | NotAuthorised() | Unchanged | Covered: [test][test_givenLifecycleState_whenUnauthorizedCallerQueues_reverts] |
| QYIELD-A02 | Unauthorized caller, fuzz | Inactive | Enabled | `true` | BurnerLoansConfigTimelock_PolicyInactive(BLCT) before role check | Unchanged | Covered: [test][test_givenLifecycleState_whenUnauthorizedCallerQueues_reverts] |
| QYIELD-A03 | Unauthorized caller, fuzz | Active | Disabled | `true` | NotEnabled() before policy and role checks | Unchanged | Covered: [test][test_givenLifecycleState_whenUnauthorizedCallerQueues_reverts] |
| QYIELD-A04 | Unauthorized caller, fuzz | Inactive | Disabled | `true` | NotEnabled() before policy and role checks | Unchanged | Covered: [test][test_givenLifecycleState_whenUnauthorizedCallerQueues_reverts] |

## Lifecycle and forwarding prerequisites

The queue caller is permitted. Fuzz the current yield flag and parameter over both booleans, with
reachable zero/nonzero pointer and RD-state combinations. Seed enable, disable and same-value
requests. Non-BLCT gates use an active/enabled BLCT.

| ID | Gate | Kernel | Local / binding | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| QYIELD-L01 | BLCT | Inactive | Enabled | BurnerLoansConfigTimelock_PolicyInactive(BLCT) | Unchanged | Covered: [test][test_givenTimelockUnavailable_whenPermittedCallerQueues_reverts] |
| QYIELD-L02 | BLCT | Active | Disabled | NotEnabled() | Unchanged | Covered: [test][test_givenTimelockUnavailable_whenPermittedCallerQueues_reverts] |
| QYIELD-L03 | BLCT | Inactive | Disabled | NotEnabled() before policy and role checks | Unchanged | Covered: [test][test_givenTimelockUnavailable_whenPermittedCallerQueues_reverts] |
| QYIELD-L04 | BLC | Inactive | Enabled; BLCT selected | BurnerLoansConfigTimelock_PolicyInactive(BLC) | Unchanged | Covered: [test][test_givenConfigUnavailable_whenPermittedCallerQueues_reverts] |
| QYIELD-L05 | BLC | Active | Disabled; BLCT selected | NotEnabled() | Unchanged | Covered: [test][test_givenConfigUnavailable_whenPermittedCallerQueues_reverts] |
| QYIELD-L06 | BLC | Inactive | Disabled; BLCT selected | BurnerLoansConfigTimelock_PolicyInactive(BLC) before BLC local-state validation | Unchanged | Covered: [test][test_givenConfigUnavailable_whenPermittedCallerQueues_reverts] |
| QYIELD-L07 | BLC operator | Active | Enabled; BLCT not selected | BurnerLoansConfig_UnauthorizedConfigOperator(BLCT) | Unchanged | Covered: [test][test_givenConfigUnavailable_whenPermittedCallerQueues_reverts] |

## Queue and execution

All policies are active/enabled, and BLCT is BLC's selected configOperator.

### Queue acceptance

| ID | Proposer | Current flag | RD state | Asset | Param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QYIELD-P01 | Admin or Burner Loans Admin, fuzz between identities | `false` | Valid and enabled | Fuzz a BL-supported future yield asset and whether RD lists it | `true` | Queue accepted | Exact BLC action, yield-routing key, state hash and queue events; flag remains `false` | Covered: [test][test_givenValidDistributor_whenPermittedCallerQueuesAndExecutorRuns_succeeds] |

### Ready execution

The executor is any caller, fuzzed. The proposer is permitted during setup.

| ID | Current flag | RD state | Queued param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| QYIELD-P02 | `false`; unchanged since queue | Valid and enabled; unchanged | `true` | Execution succeeds | Yield flag `true`; one underlying event; action removed and yield key released | Covered: [test][test_givenValidDistributor_whenPermittedCallerQueuesAndExecutorRuns_succeeds] |
| QYIELD-P03 | `true` | Fuzz Kernel-active/enabled, Kernel-inactive, locally disabled and unreadable states before queue | `false` | Queue and execution succeed without RD validation | Yield flag `false`; context().yieldRecipient is Treasury; one underlying event; action removed and yield key released | Covered: [test][test_givenYieldRoutingEnabled_whenDisableQueuedAndExecuted_skipsDistributorValidation] |
| QYIELD-P04 | `false` | Zero | `false` | Queue accepted; execution is an underlying no-op | No flag event; action removed and yield key released | Covered: [test][test_givenSameValue_whenQueuedAndExecuted_skipsDistributorValidation] |
| QYIELD-P05 | `true` | Fuzz Kernel-active/enabled, Kernel-inactive, locally disabled and unreadable states before queue | `true` | Queue accepted; execution is an underlying no-op | context().yieldRecipient remains RD; no flag event; action removed and yield key released | Covered: [test][test_givenSameValue_whenQueuedAndExecuted_skipsDistributorValidation] |

The asset varied in QYIELD-P01 is not a queue input; it is a BL-supported asset used by a future
claimYield(asset) call.

## Queue rejection

All policies are active/enabled, BLCT is selected as configOperator, the current yield flag is
`false`, and the yield flag parameter is `true`. The proposer is fuzzed between Admin and Burner
Loans Admin.

| ID | RD pointer/state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- |
| QYIELD-I01 | Zero | BurnerLoans_RevenueDistributorRequired() | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorUnset_whenEnableQueued_revertsBeforeKeyAcquisition] |
| QYIELD-I02 | Nonzero and Kernel-inactive | BurnerLoans_InvalidRevenueDistributor(RD) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorInactive_whenEnableQueued_reverts] |
| QYIELD-I03 | Nonzero, Kernel-active and locally disabled | BurnerLoans_InvalidRevenueDistributor(RD) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorDisabled_whenEnableQueued_reverts] |
| QYIELD-I04 | Nonzero; Kernel getter reverts | BurnerLoans_InvalidRevenueDistributor(RD) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorKernelReadReverts_whenEnableQueued_reverts] |
| QYIELD-I05 | Nonzero; Kernel getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(RD) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorKernelReadMalformed_whenEnableQueued_reverts] |
| QYIELD-I06 | Nonzero, same active Kernel; isEnabled getter reverts | BurnerLoans_InvalidRevenueDistributor(RD) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorEnabledReadReverts_whenEnableQueued_reverts] |
| QYIELD-I07 | Nonzero, same active Kernel; isEnabled getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(RD) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_givenDistributorEnabledReadMalformed_whenEnableQueued_reverts] |

### Raw queue payload validation

| ID | Payload | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- |
| QYIELD-I08 | 31 or 33 bytes instead of one ABI word | ITimelockBatchQueue_ActionInvalid(BLC, selector) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_whenYieldDistributorFlagPayloadIsInvalid_reverts] |
| QYIELD-I09 | One ABI word containing `2` | ITimelockBatchQueue_ActionInvalid(BLC, selector) | No action ID consumed or key acquired; flag remains `false` | Covered: [test][test_whenYieldDistributorFlagPayloadIsInvalid_reverts] |

## Execution rejection

The executor is any caller, fuzzed. BLCT and BLC remain active/enabled and the action is ready.

### Hashed-state conflicts

BL remains active/enabled. Live RD validity is irrelevant because the state-hash check fails first.

| ID | Queued param | Current yield flag | Pointer at execution | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| QYIELD-S01 | `true` | `false` | Cleared to zero after queue | IConfigTimelockBatchQueue_ConfigStateChanged with independently computed hash | Yield flag remains `false`; action and key retained | Covered: [test][test_givenFlagQueued_whenDistributorPointerChanges_executionRetainsAction] |
| QYIELD-S02 | `true` | `false` | Changed to another valid nonzero RD after queue | IConfigTimelockBatchQueue_ConfigStateChanged with independently computed hash | Yield flag remains `false`; action and key retained | Covered: [test][test_givenFlagQueued_whenDistributorPointerChanges_executionRetainsAction] |
| QYIELD-S03 | `true` | Changed after queue | Original RD | IConfigTimelockBatchQueue_ConfigStateChanged with independently computed hash | Direct flag change retained; action and key retained | Covered: [test][test_givenFlagQueued_whenFlagChanges_executionRetainsAction] |
| QYIELD-S12 | `false` | `true` | Changed after queue | IConfigTimelockBatchQueue_ConfigStateChanged with independently computed hash | Direct pointer change retained; yield flag unchanged; action and key retained | Covered: [test][test_givenFlagQueued_whenDistributorPointerChanges_executionRetainsAction] |
| QYIELD-S13 | `false` | Changed after queue | Original RD | IConfigTimelockBatchQueue_ConfigStateChanged with independently computed hash | Direct flag change retained; action and key retained | Covered: [test][test_givenFlagQueued_whenFlagChanges_executionRetainsAction] |

### Live validation failures

The current flag and pointer still match the queued hash.

| ID | Queued param | BL Kernel | BL local | RD state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| QYIELD-S04 | `true` | Inactive | Enabled | Valid and enabled | BurnerLoans_PolicyInactive() | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenFacilityInactive_executionRetainsAction] |
| QYIELD-S05 | `true` | Active | Enabled | Kernel-inactive | BurnerLoans_InvalidRevenueDistributor(RD) | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenDistributorInactive_executionRetainsAction] |
| QYIELD-S06 | `true` | Active | Enabled | Kernel-active; locally disabled | BurnerLoans_InvalidRevenueDistributor(RD) | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenDistributorDisabled_executionRetainsAction] |
| QYIELD-S07 | `true` | Active | Disabled | Valid and enabled | NotEnabled() from BL | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenFacilityDisabled_executionRetainsAction] |
| QYIELD-S08 | `true` | Active | Enabled | Kernel getter reverts | BurnerLoans_InvalidRevenueDistributor(RD) | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenDistributorKernelReadReverts_executionRetainsAction] |
| QYIELD-S09 | `true` | Active | Enabled | Kernel getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(RD) | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenDistributorKernelReadMalformed_executionRetainsAction] |
| QYIELD-S10 | `true` | Active | Enabled | isEnabled getter reverts | BurnerLoans_InvalidRevenueDistributor(RD) | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenDistributorEnabledReadReverts_executionRetainsAction] |
| QYIELD-S11 | `true` | Active | Enabled | isEnabled getter returns malformed data | BurnerLoans_InvalidRevenueDistributor(RD) | Flag unchanged; action and key retained | Covered: [test][test_givenEnableReady_whenDistributorEnabledReadMalformed_executionRetainsAction] |

## Pending payouts and future yield

All policies are active/enabled. The proposer is fuzzed between Admin and Burner Loans Admin; the
executor is any caller, fuzzed.

| ID | Current yield flag | RD pointer/state | Pending setup | Param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| QYIELD-R01 | `false` | Nonzero, Kernel-active and locally enabled | Fee, seized-collateral and keeper-reward buckets are nonzero | `true` | Queue and execution succeed | context().yieldRecipient moves to RD only on execution; all pending buckets, recipients, totalPending and custody stay unchanged; no pending-yield bucket exists; action removed and key released | Covered: [test][test_givenPendingPayouts_whenYieldFlagExecutes_preservesAllPendingState] |
| QYIELD-R02 | `true` | Nonzero; validity is not rechecked | Existing pending payout buckets | `false` | Queue and execution succeed | context().yieldRecipient moves to Treasury on execution; no pending-yield entry or recipient is created; existing pending buckets stay unchanged; action removed and key released | Covered: [test][test_givenPendingPayouts_whenYieldFlagExecutes_preservesAllPendingState] |

## Queue conflicts

All policies are active/enabled, and the proposer is fuzzed between Admin and Burner Loans Admin.

| ID | Existing action | New param | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QYIELD-Q01 | Pending setSendYieldToDistributor(true) holds the yield-routing key | `true` | IConfigTimelockBatchQueue_ConfigKeyPending(yieldKey, firstActionId) | First action and key ownership unchanged; no second action ID consumed | Covered: [test][test_givenYieldActionPending_whenSecondYieldActionQueued_revertsWithKeyOwner] |
| QYIELD-Q02 | Pending setSendYieldToDistributor(true) holds the yield-routing key | `false` | IConfigTimelockBatchQueue_ConfigKeyPending(yieldKey, firstActionId) | First action and key ownership unchanged; no second action ID consumed | Covered: [test][test_givenYieldActionPending_whenSecondYieldActionQueued_revertsWithKeyOwner] |

[test_givenConfigUnavailable_whenPermittedCallerQueues_reverts]: ./queueSetSendYieldToDistributor.t.sol#L73
[test_givenDistributorDisabled_whenEnableQueued_reverts]: ./queueSetSendYieldToDistributor.t.sol#L213
[test_givenDistributorEnabledReadMalformed_whenEnableQueued_reverts]: ./queueSetSendYieldToDistributor.t.sol#L239
[test_givenDistributorEnabledReadReverts_whenEnableQueued_reverts]: ./queueSetSendYieldToDistributor.t.sol#L232
[test_givenDistributorInactive_whenEnableQueued_reverts]: ./queueSetSendYieldToDistributor.t.sol#L208
[test_givenDistributorKernelReadMalformed_whenEnableQueued_reverts]: ./queueSetSendYieldToDistributor.t.sol#L225
[test_givenDistributorKernelReadReverts_whenEnableQueued_reverts]: ./queueSetSendYieldToDistributor.t.sol#L218
[test_givenDistributorUnset_whenEnableQueued_revertsBeforeKeyAcquisition]: ./queueSetSendYieldToDistributor.t.sol#L197
[test_givenEnableReady_whenDistributorDisabled_executionRetainsAction]: ./queueSetSendYieldToDistributor.t.sol#L285
[test_givenEnableReady_whenDistributorEnabledReadMalformed_executionRetainsAction]: ./queueSetSendYieldToDistributor.t.sol#L316
[test_givenEnableReady_whenDistributorEnabledReadReverts_executionRetainsAction]: ./queueSetSendYieldToDistributor.t.sol#L309
[test_givenEnableReady_whenDistributorInactive_executionRetainsAction]: ./queueSetSendYieldToDistributor.t.sol#L280
[test_givenEnableReady_whenDistributorKernelReadMalformed_executionRetainsAction]: ./queueSetSendYieldToDistributor.t.sol#L302
[test_givenEnableReady_whenDistributorKernelReadReverts_executionRetainsAction]: ./queueSetSendYieldToDistributor.t.sol#L295
[test_givenEnableReady_whenFacilityDisabled_executionRetainsAction]: ./queueSetSendYieldToDistributor.t.sol#L290
[test_givenEnableReady_whenFacilityInactive_executionRetainsAction]: ./queueSetSendYieldToDistributor.t.sol#L275
[test_givenFlagQueued_whenDistributorPointerChanges_executionRetainsAction]: ./queueSetSendYieldToDistributor.t.sol#L246
[test_givenFlagQueued_whenFlagChanges_executionRetainsAction]: ./queueSetSendYieldToDistributor.t.sol#L264
[test_givenLifecycleState_whenUnauthorizedCallerQueues_reverts]: ./queueSetSendYieldToDistributor.t.sol#L23
[test_givenPendingPayouts_whenYieldFlagExecutes_preservesAllPendingState]: ./queueSetSendYieldToDistributor.t.sol#L323
[test_givenSameValue_whenQueuedAndExecuted_skipsDistributorValidation]: ./queueSetSendYieldToDistributor.t.sol#L146
[test_givenTimelockUnavailable_whenPermittedCallerQueues_reverts]: ./queueSetSendYieldToDistributor.t.sol#L49
[test_givenValidDistributor_whenPermittedCallerQueuesAndExecutorRuns_succeeds]: ./queueSetSendYieldToDistributor.t.sol#L108
[test_whenYieldDistributorFlagPayloadIsInvalid_reverts]: ./queueAction.t.sol#L191
[test_givenYieldActionPending_whenSecondYieldActionQueued_revertsWithKeyOwner]: ./queueSetSendYieldToDistributor.t.sol#L342
[test_givenYieldRoutingEnabled_whenDisableQueuedAndExecuted_skipsDistributorValidation]: ./queueSetSendYieldToDistributor.t.sol#L172
