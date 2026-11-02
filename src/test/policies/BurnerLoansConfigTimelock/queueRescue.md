# BurnerLoansConfigTimelock.queueRescue coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [queueRescue](../../../policies/burnerloans/BurnerLoansConfigTimelock.sol#L252). Coverage is recorded in the Test column.

Required behavior: Config.rescue targets Core only. Queue validation uses Core.previewRescue directly; no Lens or Custody rescue occurs. Custody recovery has moved to [its own timelock](../BurnerLoansPayoutConfigTimelock/queueRescue.md).

## Domains and notation

Scenario scope: `BLCT-QUEUE-RESCUE` identifies this contract/function.

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active BurnerLoansConfigTimelock; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Error ownership: local policy inactivity uses the component’s BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) error. `PolicyDependency_NotActive(component)` identifies an unavailable external dependency; no additional lifecycle gates are implied.

Queue authorization/lifecycle matrix is normative. Inputs: token,address and destination,address; payload64 bytes. Committed prestate: Core/controller identity, no token balance fields.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

This wrapper queues a Config-targeted action; it does not configure Risk directly. Risk's operator need not match Config or BLCT. Queue defaults: BLCT enabled+active; immutable Config enabled+active; Config.configOperator=BLCT; proposer ADMIN or BURNER_LOANS_ADMIN_ROLE. `queueBatch` checks own activity, local enablement and caller roles before its length bound 1..15. All wrappers enter the same queue code. Non-proposer fails `NotAuthorised()` after lifecycle checks. Keys are Config-destination-scoped selector keys: global selector; asset/token selector+address. No public wrapper exists for originations; queueBatch supports its Config selector.

## Authorization

Fixed for this table: Local enabled: true; Local active: true; Config active: true.

| ID | Caller | Config enabled | Selected configOperator | Queue result | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-RESCUE-A01 | Fuzz outside ADMIN and BL admin holders | true | any | NotAuthorised | Covered: [test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts][test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-A02 | Fuzz outside ADMIN and BL admin holders | false | any | NotAuthorised | Covered: [test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts][test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-A03 | Fuzz permitted role caller | true | another/zero | UnauthorizedConfigOperator(BLCT) | Covered: [test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts][test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-A04 | Fuzz permitted role caller | false | another/zero | UnauthorizedConfigOperator(BLCT) | Covered: [test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts][test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-A05 | Fuzz permitted role caller | true | BLCT | Validate payload before acquire key | Covered: [test_givenPermittedProposer_whenQueued_thenValidatedAndStored][test_givenPermittedProposer_whenQueued_thenValidatedAndStored]; [test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds][test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Config active | Config enabled | Selected configOperator | Queue result | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-RESCUE-L01 | Any, valid-sized batch | true | false | true | true | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L02 | Any, valid-sized batch | true | false | true | false | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L03 | Any, valid-sized batch | true | false | false | true | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L04 | Any, valid-sized batch | true | false | false | false | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L05 | Any, valid-sized batch | false | false | true | true | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L06 | Any, valid-sized batch | false | false | true | false | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L07 | Any, valid-sized batch | false | false | false | true | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L08 | Any, valid-sized batch | false | false | false | false | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L09 | Any, valid-sized batch | false | true | true | true | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L10 | Any, valid-sized batch | false | true | true | false | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L11 | Any, valid-sized batch | false | true | false | true | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L12 | Any, valid-sized batch | false | true | false | false | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L13 | Any, valid-sized batch | true | true | false | true | any | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L14 | Any, valid-sized batch | true | true | false | false | any | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-L15 | Fuzz permitted role caller | true | true | true | false | BLCT | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |

Queue success increments uint64 nextActionId once, stores proposer/payload/order/queuedAt; executableAt=queuedAt+1day and expiresAt=executableAt+3days. No public delay setter exists. Record TimelockSubActionQueued, TimelockActionQueued and ConfigStateQueued exact emitter/fields/hashes. Full fee or six-field risk pre-state hashes reject any field drift; disjoint fee-vs-risk updates use different keys/hashes. Changes in live debt, token balance or vault support may leave hash unchanged but cause downstream failure instead.

Execution permissionless, pending-state/time checks FIRST, then BLCT enabled, Config enabled, both active, selected operator. Cancellable-state checks FIRST, then BLCT enabled+active and EMERGENCY role only. Failed execution retains action/key and all earlier subaction writes roll back. Successful execute/cancel releases keys and deletes payload/config guards; action metadata remains. Expiry alone does not release keys. Cancellation has no Config-enabled/activity/selected-operator requirement.

## Dependency lifecycle

Fixed for this table: Accounting / events: No key acquired.

| ID | Caller | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-QUEUE-RESCUE-D01 | Fuzz permitted role caller | Core inactive; other prerequisites ready | BurnerLoans_PolicyNotActive(BurnerLoansCore) from Core.previewRescue | Covered: [test_givenCoreInactive_whenQueued_reverts][test_givenCoreInactive_whenQueued_reverts] |

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-RESCUE-I01 | Fuzz permitted role caller | Token=0; destination otherwise valid | BurnerLoans_InvalidAsset(token) | No key acquired | Covered: [test_givenZeroToken_whenQueued_reverts][test_givenZeroToken_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-I02 | Fuzz permitted role caller | Token=EOA; destination otherwise valid | BurnerLoans_InvalidAsset(token) | No key acquired | Covered: [test_givenEoaToken_whenQueued_reverts][test_givenEoaToken_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-I03 | Fuzz permitted role caller | destination=0; token deployed | BurnerLoans_InvalidRescueDestination(destination) | No key acquired | Covered: [test_givenForbiddenZeroDestination_whenQueued_reverts][test_givenForbiddenZeroDestination_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-I04 | Fuzz permitted role caller | destination=Core; token deployed | BurnerLoans_InvalidRescueDestination(destination) | No key acquired | Covered: [test_givenForbiddenCoreDestination_whenQueued_reverts][test_givenForbiddenCoreDestination_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-I05 | Fuzz permitted role caller | destination=Payout; token deployed | BurnerLoans_InvalidRescueDestination(destination) | No key acquired | Covered: [test_givenForbiddenPayoutDestination_whenQueued_reverts][test_givenForbiddenPayoutDestination_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-I06 | Fuzz permitted role caller | destination=Config; token deployed | BurnerLoans_InvalidRescueDestination(destination) | No key acquired | Covered: [test_givenForbiddenConfigDestination_whenQueued_reverts][test_givenForbiddenConfigDestination_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-I07 | Fuzz permitted role caller | destination=Kernel; token deployed | BurnerLoans_InvalidRescueDestination(destination) | No key acquired | Covered: [test_givenForbiddenKernelDestination_whenQueued_reverts][test_givenForbiddenKernelDestination_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-I08 | Fuzz permitted role caller | destination=token; token deployed | BurnerLoans_InvalidRescueDestination(destination) | No key acquired | Covered: [test_givenForbiddenTokenDestination_whenQueued_reverts][test_givenForbiddenTokenDestination_whenQueued_reverts] |
| BLCT-QUEUE-RESCUE-I09 | Fuzz permitted role caller | Core direct token balance=0 | Return ID | Zero rescue queued; execution uses live balances | Covered: [test_givenZeroDirectBalance_whenQueued_thenUsesNoBalanceCommitment][test_givenZeroDirectBalance_whenQueued_thenUsesNoBalanceCommitment] |

## Queue conflicts and execution

| ID | Caller | Queue / execution condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-RESCUE-P01 | Fuzz permitted role caller | Valid payload; scoped key free | Return next ID; store typed payload, order, times and current pre-state hash | No target mutation; one key held | Covered: [test_givenFreeKey_whenQueued_thenExactMetadata][test_givenFreeKey_whenQueued_thenExactMetadata] |
| BLCT-QUEUE-RESCUE-P02 | Fuzz permitted role caller | Same scoped key is already pending | IConfigTimelockBatchQueue_ConfigKeyPending(key,owner) | No new ID/key/payload | Covered: [test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts][test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts] |
| BLCT-QUEUE-RESCUE-P03 | Fuzz permitted role caller | Independent scoped key; old unrelated action pending | Return new ID | Original action/key unchanged; new key held | Covered: [test_givenOtherTokenRescuePending_whenQueued_thenIndependentKeys][test_givenOtherTokenRescuePending_whenQueued_thenIndependentKeys] |
| BLCT-QUEUE-RESCUE-P04 | Fuzz all executors | Committed parameter/pre-state changes before ready execution | IConfigTimelockBatchQueue_ConfigStateChanged(id,index,key,expected,current) | Action and key retained | Covered: [test_givenCommittedStateDrift_whenExecuted_reverts][test_givenCommittedStateDrift_whenExecuted_reverts] |
| BLCT-QUEUE-RESCUE-P05 | Fuzz all executors | Ready at executableAt; pre-state unchanged; live setter requirements pass | Execute matching setter | Canonical state/event assertions from matching setter; key released | Covered: [test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup][test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup] |

## Live execution rejection

Fixed for this table: Accounting / events: Earlier batch writes roll back; action and keys retained.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-QUEUE-RESCUE-P06 | Fuzz all executors | Time-valid queue; Core/controller hash unchanged; token becomes rejecting on transfer | MockRevertingTransferToken.TransferReverted(destination) | Covered: [test_givenTokenStartsRejectingTransfers_whenExecuted_reverts][test_givenTokenStartsRejectingTransfers_whenExecuted_reverts] |

## Shared assertions

Validate Core.previewRescue at queue; no Lens read or Custody preview. Core must be active, may be disabled. Key per token excludes destination; zero surplus queue allowed. Execution rescues the CURRENT direct Core balance, not queued quantity. Test queue-time failure independently from execution after drift. Corresponding queueBatch raw-payload cases enforce canonical ABI lengths/widths; ordinary typed wrapper cannot construct over-width input.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

[test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts]: ./queueRescue.t.sol#L21
[test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts]: ./queueRescue.t.sol#L33
[test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts]: ./queueRescue.t.sol#L46
[test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts]: ./queueRescue.t.sol#L66
[test_givenPermittedProposer_whenQueued_thenValidatedAndStored]: ./queueRescue.t.sol#L87
[test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds]: ./queueRescue.t.sol#L637
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueRescue.t.sol#L100
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueRescue.t.sol#L115
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueRescue.t.sol#L130
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueRescue.t.sol#L145
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueRescue.t.sol#L160
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueRescue.t.sol#L180
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueRescue.t.sol#L200
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueRescue.t.sol#L220
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueRescue.t.sol#L240
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueRescue.t.sol#L260
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueRescue.t.sol#L280
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueRescue.t.sol#L300
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueRescue.t.sol#L320
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueRescue.t.sol#L340
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueRescue.t.sol#L360
[test_givenCoreInactive_whenQueued_reverts]: ./queueRescue.t.sol#L604
[test_givenZeroToken_whenQueued_reverts]: ./queueRescue.t.sol#L562
[test_givenEoaToken_whenQueued_reverts]: ./queueRescue.t.sol#L574
[test_givenForbiddenZeroDestination_whenQueued_reverts]: ./queueRescue.t.sol#L454
[test_givenForbiddenCoreDestination_whenQueued_reverts]: ./queueRescue.t.sol#L472
[test_givenForbiddenPayoutDestination_whenQueued_reverts]: ./queueRescue.t.sol#L490
[test_givenForbiddenConfigDestination_whenQueued_reverts]: ./queueRescue.t.sol#L508
[test_givenForbiddenKernelDestination_whenQueued_reverts]: ./queueRescue.t.sol#L526
[test_givenForbiddenTokenDestination_whenQueued_reverts]: ./queueRescue.t.sol#L544
[test_givenZeroDirectBalance_whenQueued_thenUsesNoBalanceCommitment]: ./queueRescue.t.sol#L591
[test_givenFreeKey_whenQueued_thenExactMetadata]: ./queueRescue.t.sol#L380
[test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts]: ./queueRescue.t.sol#L390
[test_givenOtherTokenRescuePending_whenQueued_thenIndependentKeys]: ./queueRescue.t.sol#L411
[test_givenCommittedStateDrift_whenExecuted_reverts]: ./queueRescue.t.sol#L422
[test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup]: ./queueRescue.t.sol#L436
[test_givenTokenStartsRejectingTransfers_whenExecuted_reverts]: ./queueRescue.t.sol#L620
