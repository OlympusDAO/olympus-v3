# BurnerLoansConfigTimelock.queueSetAssetDebtCap coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [queueSetAssetDebtCap](../../../policies/burnerloans/BurnerLoansConfigTimelock.sol#L217). Coverage is recorded in the Test column.

## Domains and notation

Scenario scope: `BLCT-QUEUE-CAP` identifies this contract/function.

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active BurnerLoansConfigTimelock; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Queue authorization/lifecycle matrix is normative. Inputs: asset,address and cap:uint128; payload64 bytes. Committed prestate: Old asset cap.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

This wrapper queues a Config-targeted action; it does not configure Risk directly. Risk's operator need not match Config or BLCT. Queue defaults: BLCT enabled+active; immutable Config enabled+active; Config.configOperator=BLCT; proposer ADMIN or BURNER_LOANS_ADMIN_ROLE. `queueBatch` checks own activity, local enablement and caller roles before its length bound 1..15. All wrappers enter the same queue code. Non-proposer fails `NotAuthorised()` after lifecycle checks. Keys are Config-destination-scoped selector keys: global selector; asset/token selector+address. No public wrapper exists for originations; queueBatch supports its Config selector.

## Authorization

Fixed for this table: Local enabled: true; Local active: true; Config active: true.

| ID | Caller | Config enabled | Selected configOperator | Queue result | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CAP-A01 | Fuzz outside ADMIN and BL admin holders | true | any | NotAuthorised | Covered: [test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts][test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts] |
| BLCT-QUEUE-CAP-A02 | Fuzz outside ADMIN and BL admin holders | false | any | NotAuthorised | Covered: [test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts][test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts] |
| BLCT-QUEUE-CAP-A03 | Fuzz permitted role caller | true | another/zero | UnauthorizedConfigOperator(BLCT) | Covered: [test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts][test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts] |
| BLCT-QUEUE-CAP-A04 | Fuzz permitted role caller | false | another/zero | UnauthorizedConfigOperator(BLCT) | Covered: [test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts][test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts] |
| BLCT-QUEUE-CAP-A05 | Fuzz permitted role caller | true | BLCT | Validate payload before acquire key | Covered: [test_givenPermittedProposer_whenQueued_thenValidatedAndStored][test_givenPermittedProposer_whenQueued_thenValidatedAndStored]; [test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds][test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Config active | Config enabled | Selected configOperator | Queue result | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CAP-L01 | Any, valid-sized batch | true | false | true | true | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L02 | Any, valid-sized batch | true | false | true | false | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L03 | Any, valid-sized batch | true | false | false | true | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L04 | Any, valid-sized batch | true | false | false | false | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L05 | Any, valid-sized batch | false | false | true | true | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L06 | Any, valid-sized batch | false | false | true | false | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L07 | Any, valid-sized batch | false | false | false | true | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L08 | Any, valid-sized batch | false | false | false | false | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L09 | Any, valid-sized batch | false | true | true | true | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L10 | Any, valid-sized batch | false | true | true | false | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L11 | Any, valid-sized batch | false | true | false | true | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L12 | Any, valid-sized batch | false | true | false | false | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L13 | Any, valid-sized batch | true | true | false | true | any | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L14 | Any, valid-sized batch | true | true | false | false | any | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLCT-QUEUE-CAP-L15 | Fuzz permitted role caller | true | true | true | false | BLCT | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |

Queue success increments uint64 nextActionId once, stores proposer/payload/order/queuedAt; executableAt=queuedAt+1day and expiresAt=executableAt+3days. No public delay setter exists. Record TimelockSubActionQueued, TimelockActionQueued and ConfigStateQueued exact emitter/fields/hashes. Full fee or six-field risk pre-state hashes reject any field drift; disjoint fee-vs-risk updates use different keys/hashes. Changes in live debt, token balance or vault support may leave hash unchanged but cause downstream failure instead.

Execution permissionless, pending-state/time checks FIRST, then BLCT enabled, Config enabled, both active, selected operator. Cancellable-state checks FIRST, then BLCT enabled+active and EMERGENCY role only. Failed execution retains action/key and all earlier subaction writes roll back. Successful execute/cancel releases keys and deletes payload/config guards; action metadata remains. Expiry alone does not release keys. Cancellation has no Config-enabled/activity/selected-operator requirement.

## Invalid inputs

Fixed for this table: Accounting / events: No key acquired.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-QUEUE-CAP-I01 | Fuzz permitted role caller | Asset unregistered | BurnerLoansCore_AssetNotConfigured(asset) | Covered: [test_givenUnregisteredAsset_whenQueued_reverts][test_givenUnregisteredAsset_whenQueued_reverts] |

## Numeric boundaries and arithmetic

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CAP-N01 | Fuzz permitted role caller | Live debt D>0; fuzz cap 0..D-1; seed 0,D-1 | BurnerLoans_InvalidCap() | No key acquired | Covered: [test_givenLiveDebt_whenCapBelowDebt_reverts][test_givenLiveDebt_whenCapBelowDebt_reverts]; [test_givenCapN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenCapN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLCT-QUEUE-CAP-N02 | Fuzz permitted role caller | cap=D; seed D=0,D=1,MAX128 | Return ID | Cap not yet changed | Covered: [test_givenDebtBoundary_whenCapEqualsDebt_thenAccepted][test_givenDebtBoundary_whenCapEqualsDebt_thenAccepted]; [test_givenCapN02Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenCapN02Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLCT-QUEUE-CAP-N03 | Fuzz permitted role caller | D<MAX128; fuzz cap D+1..MAX128 | Return ID | No relation to Inventory global cap imposed | Covered: [test_givenLiveDebt_whenCapAboveDebt_thenAccepted][test_givenLiveDebt_whenCapAboveDebt_thenAccepted]; [test_givenCapN03Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenCapN03Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |

## Queue conflicts and execution

| ID | Caller | Queue / execution condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CAP-P01 | Fuzz permitted role caller | Valid payload; scoped key free | Return next ID; store typed payload, order, times and current pre-state hash | No target mutation; one key held | Covered: [test_givenFreeKey_whenQueued_thenExactMetadata][test_givenFreeKey_whenQueued_thenExactMetadata] |
| BLCT-QUEUE-CAP-P02 | Fuzz permitted role caller | queueSetAssetDebtCap(A,value) already pending under owner; queue the same setAssetDebtCap for the same A again; seed identical and different valid proposed values | IConfigTimelockBatchQueue_ConfigKeyPending(K(setAssetDebtCap,A),owner) | Original action/payload/hash/key owner and nextActionId unchanged; no second payload/key/event | Covered: [test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts][test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts] |
| BLCT-QUEUE-CAP-P03 | Fuzz permitted role caller | queueSetAssetDebtCap(A,value) pending; queue the same setAssetDebtCap for registered B!=A; proposed values independently valid | Return new ID; no key conflict | Distinct K(setAssetDebtCap,A) and K(setAssetDebtCap,B); first action unchanged; both execute in either order | Covered: [test_givenSameSetterOtherAssetPending_whenQueued_thenBothOrdersExecute][test_givenSameSetterOtherAssetPending_whenQueued_thenBothOrdersExecute] |
| BLCT-QUEUE-CAP-P04 | Fuzz all executors | Committed parameter/pre-state changes before ready execution | IConfigTimelockBatchQueue_ConfigStateChanged(id,index,key,expected,current) | Action and key retained | Covered: [test_givenCommittedStateDrift_whenExecuted_reverts][test_givenCommittedStateDrift_whenExecuted_reverts] |
| BLCT-QUEUE-CAP-P05 | Fuzz all executors | Ready at executableAt; pre-state unchanged; live setter requirements pass | Execute matching setter | Canonical state/event assertions from matching setter; key released | Covered: [test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup][test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup] |

## Live execution rejection

Fixed for this table: Accounting / events: Earlier batch writes roll back; action and keys retained.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-QUEUE-CAP-P06 | Fuzz all executors | Time-valid queue; cap pre-state unchanged; borrowing raises debt above proposed cap within old cap | IBurnerLoansErrors.BurnerLoans_InvalidCap() | Covered: [test_givenDebtGrowsAfterQueue_whenExecuted_reverts][test_givenDebtGrowsAfterQueue_whenExecuted_reverts] |

## Different asset setters on the same asset

For these asset setters, independently derive `K(f,A)=keccak256(abi.encode(address(Config),keccak256(abi.encode(f.selector,A))))`. The key includes the concrete Config destination, selector and asset, never the proposed value. A second valid proposal for the same selector/asset must conflict even when its proposed value differs. Another selector on the same asset and the same selector on another asset must not conflict. All other admission/input checks pass; assets are registered and share-mode proposals have compatible custody support.

Keep the first action pending when admitting the second. On success, assert two distinct IDs/keys, exact owner IDs and payloads, independently encoded pre-state hashes, and queue events with no immediate target writes. For every successful pair, execute in both orders in separate runs after both delays, with both proposals still valid: each changes only its targeted field(s)/asset, the other commitment remains executable, and each action releases only its own key. On duplicate rejection, preserve the first complete action/commitment/key owner and nextActionId; create no second payload, key or committed event.

| ID | Caller | Already pending | New proposal | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CAP-P07 | Fuzz permitted role caller | queueBatch([Config.setAssetOriginationsEnabled(A,value)]) | queueSetAssetDebtCap(A,value) | Return new ID; no key conflict | Distinct K(setAssetOriginationsEnabled,A) and K(setAssetDebtCap,A); both payloads/hashes/owners retained and executable in either order | Covered: [test_givenOriginationsPendingForSameAsset_whenCapQueued_thenBothOrdersExecute][test_givenOriginationsPendingForSameAsset_whenCapQueued_thenBothOrdersExecute] |
| BLCT-QUEUE-CAP-P08 | Fuzz permitted role caller | queueSetAssetRiskConfig(A,value) | queueSetAssetDebtCap(A,value) | Return new ID; no key conflict | Distinct K(setAssetRiskConfig,A) and K(setAssetDebtCap,A); both payloads/hashes/owners retained and executable in either order | Covered: [test_givenRiskPendingForSameAsset_whenCapQueued_thenBothOrdersExecute][test_givenRiskPendingForSameAsset_whenCapQueued_thenBothOrdersExecute] |
| BLCT-QUEUE-CAP-P09 | Fuzz permitted role caller | queueSetAssetWithdrawAsShares(A,value) | queueSetAssetDebtCap(A,value) | Return new ID; no key conflict | Distinct K(setAssetWithdrawAsShares,A) and K(setAssetDebtCap,A); both payloads/hashes/owners retained and executable in either order | Covered: [test_givenSharesPendingForSameAsset_whenCapQueued_thenBothOrdersExecute][test_givenSharesPendingForSameAsset_whenCapQueued_thenBothOrdersExecute] |
| BLCT-QUEUE-CAP-P10 | Fuzz permitted role caller | queueSetAssetFeeConfig(A,value) | queueSetAssetDebtCap(A,value) | Return new ID; no key conflict | Distinct K(setAssetFeeConfig,A) and K(setAssetDebtCap,A); both payloads/hashes/owners retained and executable in either order | Covered: [test_givenFeePendingForSameAsset_whenCapQueued_thenBothOrdersExecute][test_givenFeePendingForSameAsset_whenCapQueued_thenBothOrdersExecute] |

## Shared assertions

Cap>=live debt at queue; live debt may grow after queue without changing hash and cause setter InvalidCap at execution. Cap0 valid with debt0; independent global cap does not limit this cap. Test queue-time failure independently from execution after drift. Corresponding queueBatch raw-payload cases enforce canonical ABI lengths/widths; ordinary typed wrapper cannot construct over-width input.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

[test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L20
[test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L32
[test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L45
[test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L65
[test_givenPermittedProposer_whenQueued_thenValidatedAndStored]: ./queueSetAssetDebtCap.t.sol#L86
[test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetAssetDebtCap.t.sol#L578
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L99
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L114
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L129
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L144
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L159
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L179
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L199
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L219
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L239
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L259
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L279
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L299
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L319
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L339
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L359
[test_givenUnregisteredAsset_whenQueued_reverts]: ./queueSetAssetDebtCap.t.sol#L379
[test_givenLiveDebt_whenCapBelowDebt_reverts]: ./queueSetAssetDebtCap.t.sol#L514
[test_givenCapN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetAssetDebtCap.t.sol#L589
[test_givenDebtBoundary_whenCapEqualsDebt_thenAccepted]: ./queueSetAssetDebtCap.t.sol#L532
[test_givenCapN02Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetAssetDebtCap.t.sol#L598
[test_givenLiveDebt_whenCapAboveDebt_thenAccepted]: ./queueSetAssetDebtCap.t.sol#L547
[test_givenCapN03Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetAssetDebtCap.t.sol#L621
[test_givenFreeKey_whenQueued_thenExactMetadata]: ./queueSetAssetDebtCap.t.sol#L399
[test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts]: ./queueSetAssetDebtCap.t.sol#L409
[test_givenSameSetterOtherAssetPending_whenQueued_thenBothOrdersExecute]: ./queueSetAssetDebtCap.t.sol#L430
[test_givenCommittedStateDrift_whenExecuted_reverts]: ./queueSetAssetDebtCap.t.sol#L442
[test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup]: ./queueSetAssetDebtCap.t.sol#L452
[test_givenDebtGrowsAfterQueue_whenExecuted_reverts]: ./queueSetAssetDebtCap.t.sol#L565
[test_givenOriginationsPendingForSameAsset_whenCapQueued_thenBothOrdersExecute]: ./queueSetAssetDebtCap.t.sol#L462
[test_givenRiskPendingForSameAsset_whenCapQueued_thenBothOrdersExecute]: ./queueSetAssetDebtCap.t.sol#L475
[test_givenSharesPendingForSameAsset_whenCapQueued_thenBothOrdersExecute]: ./queueSetAssetDebtCap.t.sol#L488
[test_givenFeePendingForSameAsset_whenCapQueued_thenBothOrdersExecute]: ./queueSetAssetDebtCap.t.sol#L501
