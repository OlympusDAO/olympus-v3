# BurnerLoansConfigTimelock.executeQueuedAction coverage plan

Shared action existence, terminal-status and execution-window checks precede concrete admission. Execution then requires own Kernel activity before local enablement and target checks; its caller remains permissionless.

Source: [executeQueuedAction](../../../policies/utils/TimelockBatchQueue.sol#L138). Coverage is recorded in the Test column.

## Domains and notation

Scenario scope: `BLCT-EXECUTE` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansConfigTimelock; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Permissionless executor, not restricted to proposer/DAO MS. actionId:uint64. Time interval includes executableAt and expiresAt; existing queued metadata remains readable after completion but payload readers reject completed action.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

The action exists and is pending; execution additionally lies inside the inclusive execution window. Those metadata/time checks precede the concrete lifecycle hook. Config selects BLCT for successful dispatch. Risk's independent operator is not consulted for Config-owned market updates.

## Authorization

Fixed for this table: Local active: true; Local enabled: true; Config active: true; Config enabled: true.

| ID | Caller | Execution | Test |
| --- | --- | --- | --- |
| BLCT-EXECUTE-A01 | Fuzz all executors | Execute body | Covered: [test_givenReadyAction_whenExecute_thenComplete][test_givenReadyAction_whenExecute_thenComplete] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Config active | Config enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-EXECUTE-L01 | Fuzz all executors | true | true | true | false | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts] |
| BLCT-EXECUTE-L02 | Fuzz all executors | true | true | false | true | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts] |
| BLCT-EXECUTE-L03 | Fuzz all executors | true | true | false | false | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts] |
| BLCT-EXECUTE-L04 | Fuzz all executors | true | false | true | true | NotEnabled() | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenExecute_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenExecute_reverts] |
| BLCT-EXECUTE-L05 | Fuzz all executors | true | false | true | false | NotEnabled() | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts] |
| BLCT-EXECUTE-L06 | Fuzz all executors | true | false | false | true | NotEnabled() | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts] |
| BLCT-EXECUTE-L07 | Fuzz all executors | true | false | false | false | NotEnabled() | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts] |
| BLCT-EXECUTE-L08 | Fuzz all executors | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenExecute_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenExecute_reverts] |
| BLCT-EXECUTE-L09 | Fuzz all executors | false | true | true | false | BurnerLoans_PolicyNotActive(BLCT) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts] |
| BLCT-EXECUTE-L10 | Fuzz all executors | false | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts] |
| BLCT-EXECUTE-L11 | Fuzz all executors | false | true | false | false | BurnerLoans_PolicyNotActive(BLCT) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts] |
| BLCT-EXECUTE-L12 | Fuzz all executors | false | false | true | true | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenExecute_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenExecute_reverts] |
| BLCT-EXECUTE-L13 | Fuzz all executors | false | false | true | false | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts] |
| BLCT-EXECUTE-L14 | Fuzz all executors | false | false | false | true | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts] |
| BLCT-EXECUTE-L15 | Fuzz all executors | false | false | false | false | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts] |

Proposer/ADMIN/BL-admin roles are not required to execute. A different/zero Config.configOperator rejects `BurnerLoansConfig_UnauthorizedConfigOperator(BLCT)`. All failures preserve action, payload and held keys. Every configuration hash includes current Config.configOperator(), with existing setting/facility fields and Core.configOperator() for rescue. Authority remains checked live before hash comparison; restoring the original operator and configuration permits retry within the original window.

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-EXECUTE-I01 | Fuzz all executors | actionId=0; no action | ITimelockBatchQueue_ActionNotFound(id) | Unchanged; no committed logs | Covered: [test_givenMissingZeroId_whenExecute_reverts][test_givenMissingZeroId_whenExecute_reverts] |
| BLCT-EXECUTE-I02 | Fuzz all executors | Debt grows above queued asset cap without a hash change | BurnerLoans_InvalidCap() | All earlier setters and key release roll back | Covered: [test_givenDebtGrowsAboveQueuedCap_whenExecuted_thenEarlierWriteRollsBack][test_givenDebtGrowsAboveQueuedCap_whenExecuted_thenEarlierWriteRollsBack] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-EXECUTE-N01 | Fuzz all executors | Nonexistent actionId fuzz 1..MAX64 | ITimelockBatchQueue_ActionNotFound(id) | Covered: [test_givenMissingNonzeroId_whenExecute_reverts][test_givenMissingNonzeroId_whenExecute_reverts] |

For the following boundary regression, BLCT and Config are active/enabled, Config selects BLCT as its operator, the asset is registered and execution occurs after the one-day delay. The queue proposer executes.

| ID | Caller | Queued risk input | Execution / return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-EXECUTE-N02 | Queue proposer | Complete risk struct with maxLtvBps=8000, backingMultiplierBps=13000, keeperRewardBps=25, termLength=20 days, maxMaturityHorizon=80 days and maxKeeperReward=MAX128 | Success | Canonical maxKeeperReward remains exactly MAX128 without truncation | Covered: [test][test_whenCompleteRiskConfigIsQueued_thenMaximumKeeperRewardIsPreserved] |

## Queue conflicts and execution

| ID | Caller | Queue / execution condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-EXECUTE-P01 | Fuzz all executors | Action already cancelled | ITimelockBatchQueue_ActionCancelled(id) | Unchanged; no committed logs | Covered: [test_givenCancelled_whenExecuted_reverts][test_givenCancelled_whenExecuted_reverts] |
| BLCT-EXECUTE-P02 | Fuzz all executors | Committed risk field changes, including a field unchanged in the proposed complete struct | IConfigTimelockBatchQueue_ConfigStateChanged(id,index,key,expected,current) | Full rollback; keys retained | Covered: [test_givenUnchangedProposedRiskFieldDrifts_whenExecuted_reverts][test_givenUnchangedProposedRiskFieldDrifts_whenExecuted_reverts] |
| BLCT-EXECUTE-P03 | Fuzz all executors | Committed fee field changes, including a field unchanged in the proposed complete struct | IConfigTimelockBatchQueue_ConfigStateChanged(id,index,key,expected,current) | Full rollback; keys retained | Covered: [test_givenUnchangedProposedFeeFieldDrifts_whenExecuted_reverts][test_givenUnchangedProposedFeeFieldDrifts_whenExecuted_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-EXECUTE-P04 | Fuzz all executors | Action already executed | ITimelockBatchQueue_ActionAlreadyExecuted(id) | Unchanged; no committed logs | Covered: [test_givenExecuted_whenExecuted_reverts][test_givenExecuted_whenExecuted_reverts] |
| BLCT-EXECUTE-P05 | Fuzz all executors | Pending action; now=executableAt-1 | ITimelockBatchQueue_ActionNotReady(id,executableAt) | Unchanged; no committed logs | Covered: [test_givenOneSecondBeforeReady_whenExecuted_reverts][test_givenOneSecondBeforeReady_whenExecuted_reverts] |
| BLCT-EXECUTE-P06 | Fuzz all executors | Pending action; now=executableAt; live gates pass | Success | Execute all in order; executed=true; payload/config guards deleted; keys released; exact execution events | Covered: [test_givenExactReadyTime_whenExecuted_thenInclusiveSuccess][test_givenExactReadyTime_whenExecuted_thenInclusiveSuccess] |
| BLCT-EXECUTE-P07 | Fuzz all executors | Pending action; now=expiresAt; live gates pass | Success | Inclusive expiry; complete all actions and release keys | Covered: [test_givenExactExpiryTime_whenExecuted_thenInclusiveSuccess][test_givenExactExpiryTime_whenExecuted_thenInclusiveSuccess] |
| BLCT-EXECUTE-P08 | Fuzz all executors | Pending action; now=expiresAt+1 | ITimelockBatchQueue_ActionExpired(id,expiresAt) | Keep action and keys until emergency cancellation | Covered: [test_givenOneSecondAfterExpiry_whenExecuted_reverts][test_givenOneSecondAfterExpiry_whenExecuted_reverts] |
| BLCT-EXECUTE-P09 | Fuzz all executors | Target returns zero-length revert | BurnerLoansConfigTimelock_SubActionCallFailed(target,selector) | Entire execution rolls back | Covered: [test_givenEmptyTargetRevert_whenExecuted_thenBoundedWrapper][test_givenEmptyTargetRevert_whenExecuted_thenBoundedWrapper] |
| BLCT-EXECUTE-P10 | Fuzz all executors | Target reverts with1..255 bytes; seed1,255 | Bubble exactly the configured bytes | Entire execution rolls back | Covered: [test_givenBoundedTargetRevert_whenExecuted_thenExactBubble][test_givenBoundedTargetRevert_whenExecuted_thenExactBubble]; [test_givenRevertDataP10Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenRevertDataP10Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLCT-EXECUTE-P11 | Fuzz all executors | Target reverts with exactly256 bytes | BurnerLoansConfigTimelock_SubActionCallFailed(target,selector) | Entire execution rolls back | Covered: [test_givenExactlyLimitTargetRevert_whenExecuted_thenBoundedWrapper][test_givenExactlyLimitTargetRevert_whenExecuted_thenBoundedWrapper] |
| BLCT-EXECUTE-P12 | Fuzz all executors | Target reverts with>256 bytes; include return-data bomb | BurnerLoansConfigTimelock_SubActionCallFailed(target,selector) | Copy capped256; entire execution rolls back | Covered: [test_givenOversizedTargetRevert_whenExecuted_thenBoundedWrapper][test_givenOversizedTargetRevert_whenExecuted_thenBoundedWrapper]; [test_givenRevertDataP12Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenRevertDataP12Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |

For the following integration regression, BLCT and Config are active/enabled, Config selects BLCT as its operator and the asset is registered. Fee tuple order is baseFeeBps, kinkBps, preKinkSlopeBps, postKinkSlopeBps.

| ID | Caller | Queued fee input | Execution / return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-EXECUTE-P15 | Unprivileged recipient, distinct from proposer | Complete fee tuple (10,7000,20,30); current baseFeeBps=25; execute after one-day delay | Success | Queue leaves current base fee at25; execution applies the exact complete fee struct | Covered: [test][test_whenCompleteFeeConfigIsQueued_thenAllFieldsApplyAfterDelay] |

## Callbacks and reentrancy

| ID | Caller | Callback / nested call | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-EXECUTE-C01 | Fuzz all executors | Target catches callback attempting same action | Nested ITimelockBatchQueue_ActionAlreadyExecuted(id); outer succeeds | Exactly one execution and key release | Covered: [test_givenTargetCatchesSameActionCallback_whenExecuted_thenOneExecution][test_givenTargetCatchesSameActionCallback_whenExecuted_thenOneExecution] |
| BLCT-EXECUTE-C02 | Fuzz all executors | Target propagates callback attempting same action | Bubble exact nested error | Executed marker, keys and all earlier mutations roll back | Covered: [test_givenTargetPropagatesSameActionCallback_whenExecuted_thenRollback][test_givenTargetPropagatesSameActionCallback_whenExecuted_thenRollback] |

## Shared assertions

Port real-setter rollback test, not only a mock target. Test risk+fee disjoint order both ways, multipleassets and rescue/config batches. A later registry getter failure also rolls entire batch back. Failed/exhausted execution cannot release expired keys; Emergency cancellation recovers them.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

## Independent Config domains

Risk cache-age dispatch is covered in the directly bound [Risk queue execution plan](../BurnerLoansRiskConfigTimelock/executeQueuedAction.md). These retained Config cases assert atomicity and independent settings without a second target.

| ID | Caller | Configuration / fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-EXECUTE-P14 | Fuzz all executors | Independent Config fee and debt-cap updates; seed both action orders | Success | Exact Config calls in stored order; all getters match; release both keys | Covered: [test_givenIndependentConfigDomains_whenExecuted_thenBothOrdersApply][test_givenIndependentConfigDomains_whenExecuted_thenBothOrdersApply] |
| BLCT-EXECUTE-T01 | Fuzz all executors | Two independent Config domains; the later setter raises an injected error after the earlier write; seed both orders | Exact target error | Earlier target writes/events and executed marker roll back; all actions, payloads and keys retained | Covered: [test_givenLaterConfigSetterReverts_whenExecuted_thenAtomicRollback][test_givenLaterConfigSetterReverts_whenExecuted_thenAtomicRollback] |
| BLCT-EXECUTE-D08 | Fuzz all executors | Config-only fee/risk update; Risk operator independently zero or another address | Success | No Risk configuration authorization required for public validators | Covered: [test_givenRiskOperatorIndependent_whenConfigExecuted_thenApplied][test_givenRiskOperatorIndependent_whenConfigExecuted_thenApplied] |
| BLCT-EXECUTE-D09 | Fuzz all executors | Two independent Config domains; Config no longer selects BLCT | BurnerLoansConfig_UnauthorizedConfigOperator(BLCT) | No partial execution or released keys | Covered: [test_givenConfigOperatorRevoked_whenIndependentBatchExecuted_reverts][test_givenConfigOperatorRevoked_whenIndependentBatchExecuted_reverts] |
| BLCT-EXECUTE-D10 | Fuzz all executors | Config operator revoked, execution rejected, then restored; fuzz original inclusive execution window | Original two-domain batch executes after restoration | Original commitments/deadlines retained during failure; both setters apply and keys release | Covered: [test_givenConfigOperatorRestored_whenOriginalBatchExecuted_thenApplied][test_givenConfigOperatorRestored_whenOriginalBatchExecuted_thenApplied] |
| BLCT-EXECUTE-D11 | Fuzz all executors | Config operator getter reverts, returns a non-word length, or noncanonical address | BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config) | Target, payload, commitments and key owners unchanged | Covered: [revert][test_givenConfigOperatorReadReverts_whenExecuted_reverts], [length fuzz][test_givenMalformedConfigOperatorLength_whenExecuted_reverts], [noncanonical][test_givenNoncanonicalConfigOperator_whenExecuted_reverts] |
| BLCT-EXECUTE-D12 | Fuzz all executors | Config is locally paused and reports a foreign Kernel | PolicyDependency_KernelMismatch(Config,expectedKernel,reportedKernel), before enabled-state validation | Action, payloads, key owners and economic state unchanged | Covered: [test][test_givenForeignKernelAndPausedConfig_whenExecuted_reverts] |

## Co-located terminal-state reads

After the corresponding successful/cancelled action, metadata remains readable while payload/config guards are removed. Repeat read-only queries under independently fuzzed local/dependency lifecycle flags.

| ID | Caller | Action / read | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUED-ACTION-N01 | Fuzz getter caller | Missing ID, including zero/MAX64, queried through getQueuedAction | ActionNotFound(id) | No mutation | Covered: [test_givenMissingId_whenMetadataRead_reverts][test_givenMissingId_whenMetadataRead_reverts] |
| BLCT-QUEUED-ACTION-P01 | Fuzz getter caller | Pending, executed, cancelled and expired metadata; separate established states | Exact metadata including terminal flags; payload/config state deleted only after execute/cancel, not merely expiry | No mutation | Covered: [test_givenEachEstablishedActionState_whenMetadataRead_thenFlagsAndPayloadsAgree][test_givenEachEstablishedActionState_whenMetadataRead_thenFlagsAndPayloadsAgree] |
| BLCT-QUEUED-ACTION-P02 | Fuzz getter caller | Payload getter after execution | ActionAlreadyExecuted(id) | No mutation; metadata still readable | Covered: [test_givenExecutedAction_whenPayloadRead_reverts][test_givenExecutedAction_whenPayloadRead_reverts] |

| ID | Caller | Action / read | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUED-ACTION-I02 | Fuzz getter caller | Payload getter after successful cancellation | ActionCancelled(id) | No mutation; cancelled metadata remains readable | Covered: [test_givenCancelledAction_whenPayloadRead_reverts][test_givenCancelledAction_whenPayloadRead_reverts] |

[test_givenReadyAction_whenExecute_thenComplete]: ./executeQueuedAction.t.sol#L290
[test_whenCompleteFeeConfigIsQueued_thenAllFieldsApplyAfterDelay]: ./executeQueuedAction.t.sol#L825
[test_whenCompleteRiskConfigIsQueued_thenMaximumKeeperRewardIsPreserved]: ./executeQueuedAction.t.sol#L850
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts]: ./executeQueuedAction.t.sol#L23
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts]: ./executeQueuedAction.t.sol#L41
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts]: ./executeQueuedAction.t.sol#L59
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenExecute_reverts]: ./executeQueuedAction.t.sol#L77
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts]: ./executeQueuedAction.t.sol#L88
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts]: ./executeQueuedAction.t.sol#L99
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts]: ./executeQueuedAction.t.sol#L110
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenExecute_reverts]: ./executeQueuedAction.t.sol#L121
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts]: ./executeQueuedAction.t.sol#L139
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts]: ./executeQueuedAction.t.sol#L157
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts]: ./executeQueuedAction.t.sol#L175
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenExecute_reverts]: ./executeQueuedAction.t.sol#L193
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts]: ./executeQueuedAction.t.sol#L211
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts]: ./executeQueuedAction.t.sol#L229
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts]: ./executeQueuedAction.t.sol#L247
[test_givenMissingZeroId_whenExecute_reverts]: ./executeQueuedAction.t.sol#L265
[test_givenDebtGrowsAboveQueuedCap_whenExecuted_thenEarlierWriteRollsBack]: ./executeQueuedAction.t.sol#L412
[test_givenMissingNonzeroId_whenExecute_reverts]: ./executeQueuedAction.t.sol#L277
[test_givenCancelled_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L297
[test_givenUnchangedProposedRiskFieldDrifts_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L374
[test_givenUnchangedProposedFeeFieldDrifts_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L394
[test_givenExecuted_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L311
[test_givenOneSecondBeforeReady_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L326
[test_givenExactReadyTime_whenExecuted_thenInclusiveSuccess]: ./executeQueuedAction.t.sol#L356
[test_givenExactExpiryTime_whenExecuted_thenInclusiveSuccess]: ./executeQueuedAction.t.sol#L365
[test_givenOneSecondAfterExpiry_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L341
[test_givenEmptyTargetRevert_whenExecuted_thenBoundedWrapper]: ./executeQueuedAction.t.sol#L428
[test_givenBoundedTargetRevert_whenExecuted_thenExactBubble]: ./executeQueuedAction.t.sol#L446
[test_givenRevertDataP10Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./executeQueuedAction.t.sol#L767
[test_givenExactlyLimitTargetRevert_whenExecuted_thenBoundedWrapper]: ./executeQueuedAction.t.sol#L459
[test_givenOversizedTargetRevert_whenExecuted_thenBoundedWrapper]: ./executeQueuedAction.t.sol#L479
[test_givenRevertDataP12Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./executeQueuedAction.t.sol#L776
[test_givenTargetCatchesSameActionCallback_whenExecuted_thenOneExecution]: ./executeQueuedAction.t.sol#L500
[test_givenTargetPropagatesSameActionCallback_whenExecuted_thenRollback]: ./executeQueuedAction.t.sol#L511
[test_givenIndependentConfigDomains_whenExecuted_thenBothOrdersApply]: ./executeQueuedAction.t.sol#L529
[test_givenLaterConfigSetterReverts_whenExecuted_thenAtomicRollback]: ./executeQueuedAction.t.sol#L548
[test_givenRiskOperatorIndependent_whenConfigExecuted_thenApplied]: ./executeQueuedAction.t.sol#L572
[test_givenConfigOperatorRevoked_whenIndependentBatchExecuted_reverts]: ./executeQueuedAction.t.sol#L585
[test_givenMissingId_whenMetadataRead_reverts]: ./executeQueuedAction.t.sol#L696
[test_givenEachEstablishedActionState_whenMetadataRead_thenFlagsAndPayloadsAgree]: ./executeQueuedAction.t.sol#L711
[test_givenExecutedAction_whenPayloadRead_reverts]: ./executeQueuedAction.t.sol#L734
[test_givenCancelledAction_whenPayloadRead_reverts]: ./executeQueuedAction.t.sol#L751

[test_givenConfigOperatorRestored_whenOriginalBatchExecuted_thenApplied]: ./executeQueuedAction.t.sol#L604
[test_givenConfigOperatorReadReverts_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L633
[test_givenMalformedConfigOperatorLength_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L654
[test_givenNoncanonicalConfigOperator_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L675
[test_givenForeignKernelAndPausedConfig_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L864
