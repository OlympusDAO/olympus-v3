# BurnerLoansConfigTimelock.queueSetAssetWithdrawAsShares coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [queueSetAssetWithdrawAsShares](../../../policies/burnerloans/BurnerLoansConfigTimelock.sol#L268). Coverage is recorded in the Test column.

## Domains and notation

Scenario scope: `BLCT-QUEUE-SHARES` identifies this contract/function.

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active BurnerLoansConfigTimelock; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Queue authorization/lifecycle matrix is normative. Inputs: asset,address and bool; payload64 bytes. Committed prestate: Old withdrawal-mode bool.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

This wrapper queues a Config-targeted action; it does not configure Risk directly. Risk's operator need not match Config or BLCT. Queue defaults: BLCT enabled+active; immutable Config enabled+active; Config.configOperator=BLCT; proposer ADMIN or BURNER_LOANS_ADMIN_ROLE. `queueBatch` checks own activity, local enablement and caller roles before its length bound 1..15. All wrappers enter the same queue code. Non-proposer fails `NotAuthorised()` after lifecycle checks. Keys are Config-destination-scoped selector keys: global selector; asset/token selector+address. No public wrapper exists for originations; queueBatch supports its Config selector.

## Authorization

Fixed for this table: Local enabled: true; Local active: true; Config active: true.

| ID | Caller | Config enabled | Selected configOperator | Queue result | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-SHARES-A01 | Fuzz outside ADMIN and BL admin holders | true | any | NotAuthorised | Covered: [test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts][test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-A02 | Fuzz outside ADMIN and BL admin holders | false | any | NotAuthorised | Covered: [test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts][test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-A03 | Fuzz permitted role caller | true | another/zero | UnauthorizedConfigOperator(BLCT) | Covered: [test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts][test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-A04 | Fuzz permitted role caller | false | another/zero | UnauthorizedConfigOperator(BLCT) | Covered: [test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts][test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-A05 | Fuzz permitted role caller | true | BLCT | Validate payload before acquire key | Covered: [test_givenPermittedProposer_whenQueued_thenValidatedAndStored][test_givenPermittedProposer_whenQueued_thenValidatedAndStored]; [test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds][test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Config active | Config enabled | Selected configOperator | Queue result | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-SHARES-L01 | Any, valid-sized batch | true | false | true | true | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L02 | Any, valid-sized batch | true | false | true | false | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L03 | Any, valid-sized batch | true | false | false | true | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L04 | Any, valid-sized batch | true | false | false | false | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L05 | Any, valid-sized batch | false | false | true | true | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L06 | Any, valid-sized batch | false | false | true | false | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L07 | Any, valid-sized batch | false | false | false | true | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L08 | Any, valid-sized batch | false | false | false | false | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L09 | Any, valid-sized batch | false | true | true | true | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L10 | Any, valid-sized batch | false | true | true | false | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L11 | Any, valid-sized batch | false | true | false | true | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L12 | Any, valid-sized batch | false | true | false | false | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L13 | Any, valid-sized batch | true | true | false | true | any | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L14 | Any, valid-sized batch | true | true | false | false | any | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-SHARES-L15 | Fuzz permitted role caller | true | true | true | false | BLCT | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |

Queue success increments uint64 nextActionId once, stores proposer/payload/order/queuedAt; executableAt=queuedAt+1day and expiresAt=executableAt+3days. No public delay setter exists. Record TimelockSubActionQueued, TimelockActionQueued and ConfigStateQueued exact emitter/fields/hashes. Full fee or six-field risk pre-state hashes reject any field drift; disjoint fee-vs-risk updates use different keys/hashes. Changes in live debt, token balance or vault support may leave hash unchanged but cause downstream failure instead.

Execution permissionless, pending-state/time checks FIRST, then BLCT enabled, Config enabled, both active, selected operator. Cancellable-state checks FIRST, then BLCT enabled+active and EMERGENCY role only. Failed execution retains action/key and all earlier subaction writes roll back. Successful execute/cancel releases keys and deletes payload/config guards; action metadata remains. Expiry alone does not release keys. Cancellation has no Config-enabled/activity/selected-operator requirement.

## Invalid inputs

Fixed for this table: Accounting / events: No key acquired.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-QUEUE-SHARES-I01 | Fuzz permitted role caller | Asset unregistered | BurnerLoansCore_AssetNotConfigured(asset) | Covered: [test_givenUnregisteredAsset_whenQueued_reverts][test_givenUnregisteredAsset_whenQueued_reverts] |

## Queue conflicts and execution

| ID | Caller | Queue / execution condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-SHARES-P01 | Fuzz permitted role caller | Valid payload; scoped key free | Return next ID; store typed payload, order, times and current pre-state hash | No target mutation; one key held | Covered: [test_givenFreeKey_whenQueued_thenExactMetadata][test_givenFreeKey_whenQueued_thenExactMetadata] |
| BLCT-QUEUE-SHARES-P02 | Fuzz permitted role caller | queueSetAssetWithdrawAsShares(A,value) already pending under owner; queue the same setAssetWithdrawAsShares for the same A again; seed identical and different valid proposed values | IConfigTimelockBatchQueue_ConfigKeyPending(K(setAssetWithdrawAsShares,A),owner) | Original action/payload/hash/key owner and nextActionId unchanged; no second payload/key/event | Covered: [test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts][test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts] |
| BLCT-QUEUE-SHARES-P03 | Fuzz permitted role caller | queueSetAssetWithdrawAsShares(A,value) pending; queue the same setAssetWithdrawAsShares for registered B!=A; proposed values independently valid | Return new ID; no key conflict | Distinct K(setAssetWithdrawAsShares,A) and K(setAssetWithdrawAsShares,B); first action unchanged; both execute in either order | Covered: [test_givenSameSetterOtherAssetPending_whenQueued_thenBothOrdersExecute][test_givenSameSetterOtherAssetPending_whenQueued_thenBothOrdersExecute] |
| BLCT-QUEUE-SHARES-P04 | Fuzz all executors | Committed parameter/pre-state changes before ready execution | IConfigTimelockBatchQueue_ConfigStateChanged(id,index,key,expected,current) | Action and key retained | Covered: [test_givenCommittedStateDrift_whenExecuted_reverts][test_givenCommittedStateDrift_whenExecuted_reverts] |
| BLCT-QUEUE-SHARES-P05 | Fuzz all executors | Ready at executableAt; pre-state unchanged; live setter requirements pass | Execute matching setter | Canonical state/event assertions from matching setter; key released | Covered: [test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup][test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-SHARES-P06 | Fuzz permitted role caller | Direct custody; request shares=true | AssetManager_VaultRequired(asset) | No key acquired | Covered: [test_givenDirectCustody_whenSharesRequested_reverts][test_givenDirectCustody_whenSharesRequested_reverts] |
| BLCT-QUEUE-SHARES-P07 | Fuzz permitted role caller | Asynchronous redemption vault; request shares=false | AssetManager_RequiresWithdrawAsShares(asset,vault) | No key acquired | Covered: [test_givenAsynchronousVault_whenUnderlyingQueued_reverts][test_givenAsynchronousVault_whenUnderlyingQueued_reverts] |
| BLCT-QUEUE-SHARES-P08 | Fuzz permitted role caller | Synchronous vault; request shares=false | Return ID | Underlying mode remains pending | Covered: [test_givenSynchronousVault_whenUnderlyingQueued_thenStored][test_givenSynchronousVault_whenUnderlyingQueued_thenStored] |
| BLCT-QUEUE-SHARES-P09 | Fuzz permitted role caller | Vault supports shares delivery; request shares=true | Return ID | Shares mode remains pending | Covered: [test_givenSynchronousVault_whenSharesQueued_thenStored][test_givenSynchronousVault_whenSharesQueued_thenStored] |
| BLCT-QUEUE-SHARES-P10 | Fuzz permitted role caller | Same requested mode; DM mode validation fails after support drift | Exact DepositManager mode error | Queue still validates same value | Covered: [test_givenAsynchronousVault_whenUnderlyingQueued_reverts][test_givenAsynchronousVault_whenUnderlyingQueued_reverts] |
| BLCT-QUEUE-SHARES-P11 | Fuzz all executors | Time-valid queued false; mode pre-state unchanged; DM now requires shares for same vault | AssetManager_RequiresWithdrawAsShares(asset,vault) | Earlier batch writes roll back; action and keys retained | Covered: [test_givenSupportDriftAfterQueue_whenExecuted_thenEarlierWritesRollBack][test_givenSupportDriftAfterQueue_whenExecuted_thenEarlierWritesRollBack] |

## Different asset setters on the same asset

For these asset setters, independently derive `K(f,A)=keccak256(abi.encode(address(Config),keccak256(abi.encode(f.selector,A))))`. The key includes the concrete Config destination, selector and asset, never the proposed value. A second valid proposal for the same selector/asset must conflict even when its proposed value differs. Another selector on the same asset and the same selector on another asset must not conflict. All other admission/input checks pass; assets are registered and share-mode proposals have compatible custody support.

Keep the first action pending when admitting the second. On success, assert two distinct IDs/keys, exact owner IDs and payloads, independently encoded pre-state hashes, and queue events with no immediate target writes. For every successful pair, execute in both orders in separate runs after both delays, with both proposals still valid: each changes only its targeted field(s)/asset, the other commitment remains executable, and each action releases only its own key. On duplicate rejection, preserve the first complete action/commitment/key owner and nextActionId; create no second payload, key or committed event.

| ID | Caller | Already pending | New proposal | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-SHARES-P12 | Fuzz permitted role caller | queueSetAssetDebtCap(A,value) | queueSetAssetWithdrawAsShares(A,value) | Return new ID; no key conflict | Distinct K(setAssetDebtCap,A) and K(setAssetWithdrawAsShares,A); both payloads/hashes/owners retained and executable in either order | Covered: [test_givenCapPendingForSameAsset_whenSharesQueued_thenBothOrdersExecute][test_givenCapPendingForSameAsset_whenSharesQueued_thenBothOrdersExecute] |
| BLCT-QUEUE-SHARES-P13 | Fuzz permitted role caller | queueBatch([Config.setAssetOriginationsEnabled(A,value)]) | queueSetAssetWithdrawAsShares(A,value) | Return new ID; no key conflict | Distinct K(setAssetOriginationsEnabled,A) and K(setAssetWithdrawAsShares,A); both payloads/hashes/owners retained and executable in either order | Covered: [test_givenOriginationsPendingForSameAsset_whenSharesQueued_thenBothOrdersExecute][test_givenOriginationsPendingForSameAsset_whenSharesQueued_thenBothOrdersExecute] |
| BLCT-QUEUE-SHARES-P14 | Fuzz permitted role caller | queueSetAssetRiskConfig(A,value) | queueSetAssetWithdrawAsShares(A,value) | Return new ID; no key conflict | Distinct K(setAssetRiskConfig,A) and K(setAssetWithdrawAsShares,A); both payloads/hashes/owners retained and executable in either order | Covered: [test_givenRiskPendingForSameAsset_whenSharesQueued_thenBothOrdersExecute][test_givenRiskPendingForSameAsset_whenSharesQueued_thenBothOrdersExecute] |
| BLCT-QUEUE-SHARES-P15 | Fuzz permitted role caller | queueSetAssetFeeConfig(A,value) | queueSetAssetWithdrawAsShares(A,value) | Return new ID; no key conflict | Distinct K(setAssetFeeConfig,A) and K(setAssetWithdrawAsShares,A); both payloads/hashes/owners retained and executable in either order | Covered: [test_givenFeePendingForSameAsset_whenSharesQueued_thenBothOrdersExecute][test_givenFeePendingForSameAsset_whenSharesQueued_thenBothOrdersExecute] |

## Shared assertions

DM mode validation at queue even same value; no originations gate. Underlying→shares works for async redemption; shares→underlying requires live sync support. Postqueue async switch causes live setter failure if hash unchanged. Test queue-time failure independently from execution after drift. Corresponding queueBatch raw-payload cases enforce canonical ABI lengths/widths; ordinary typed wrapper cannot construct over-width input.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

[test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L25
[test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L37
[test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L50
[test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L70
[test_givenPermittedProposer_whenQueued_thenValidatedAndStored]: ./queueSetAssetWithdrawAsShares.t.sol#L91
[test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetAssetWithdrawAsShares.t.sol#L613
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L104
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L119
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L134
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L149
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L164
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L184
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L204
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L224
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L244
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L264
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L284
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L304
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L324
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L344
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L364
[test_givenUnregisteredAsset_whenQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L384
[test_givenFreeKey_whenQueued_thenExactMetadata]: ./queueSetAssetWithdrawAsShares.t.sol#L404
[test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L414
[test_givenSameSetterOtherAssetPending_whenQueued_thenBothOrdersExecute]: ./queueSetAssetWithdrawAsShares.t.sol#L436
[test_givenCommittedStateDrift_whenExecuted_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L448
[test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup]: ./queueSetAssetWithdrawAsShares.t.sol#L459
[test_givenDirectCustody_whenSharesRequested_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L522
[test_givenAsynchronousVault_whenUnderlyingQueued_reverts]: ./queueSetAssetWithdrawAsShares.t.sol#L568
[test_givenSynchronousVault_whenUnderlyingQueued_thenStored]: ./queueSetAssetWithdrawAsShares.t.sol#L540
[test_givenSynchronousVault_whenSharesQueued_thenStored]: ./queueSetAssetWithdrawAsShares.t.sol#L554
[test_givenSupportDriftAfterQueue_whenExecuted_thenEarlierWritesRollBack]: ./queueSetAssetWithdrawAsShares.t.sol#L589
[test_givenCapPendingForSameAsset_whenSharesQueued_thenBothOrdersExecute]: ./queueSetAssetWithdrawAsShares.t.sol#L470
[test_givenOriginationsPendingForSameAsset_whenSharesQueued_thenBothOrdersExecute]: ./queueSetAssetWithdrawAsShares.t.sol#L483
[test_givenRiskPendingForSameAsset_whenSharesQueued_thenBothOrdersExecute]: ./queueSetAssetWithdrawAsShares.t.sol#L496
[test_givenFeePendingForSameAsset_whenSharesQueued_thenBothOrdersExecute]: ./queueSetAssetWithdrawAsShares.t.sol#L509
