# BurnerLoansConfigTimelock.queueSetAssetFeeConfig coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Implemented complete-struct API: selection masks/merge helpers are removed while preserving the full old-state commitment and queue behavior. The current source accepts complete structs; legacy tests still exercise the former partial-update ABI.

Source: [queueSetAssetFeeConfig](../../../policies/burnerloans/BurnerLoansConfigTimelock.sol#L188). Coverage is recorded in the Test column.

## Domains and notation

Scenario scope: `BLQFC` identifies this contract/function.

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active BurnerLoansConfigTimelock; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Queue authorization/lifecycle matrix is normative. Inputs: asset address and complete four-field FeeConfig (uint16 fields); canonical payload 160 bytes. Committed prestate: Full old fee struct.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

This wrapper queues a Config-targeted action; it does not configure Risk directly. Risk's operator need not match Config or BLCT. Queue defaults: BLCT enabled+active; immutable Config enabled+active; Config.configOperator=BLCT; proposer ADMIN or BURNER_LOANS_ADMIN_ROLE. `queueBatch` checks own activity, local enablement and caller roles before its length bound 1..15. All wrappers enter the same queue code. Non-proposer fails `NotAuthorised()` after lifecycle checks. Keys are Config-destination-scoped selector keys: global selector; asset/token selector+address. No public wrapper exists for originations; queueBatch supports its Config selector.

## Authorization

Fixed for this table: Local enabled: true; Local active: true; Config active: true.

| ID | Caller | Config enabled | Supplied configOperator | Queue result | Test |
| --- | --- | --- | --- | --- | --- |
| BLQFC-A01 | Fuzz outside ADMIN and BL admin holders | true | any | NotAuthorised | Covered: [test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts][test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts] |
| BLQFC-A02 | Fuzz outside ADMIN and BL admin holders | false | any | NotAuthorised | Covered: [test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts][test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts] |
| BLQFC-A03 | Fuzz permitted role caller | true | another/zero | UnauthorizedConfigOperator(BLCT) | Covered: [test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts][test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts] |
| BLQFC-A04 | Fuzz permitted role caller | false | another/zero | UnauthorizedConfigOperator(BLCT) | Covered: [test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts][test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts] |
| BLQFC-A05 | Fuzz permitted role caller | true | BLCT | Validate payload before acquire key | Covered: [test_givenPermittedProposer_whenQueued_thenValidatedAndStored][test_givenPermittedProposer_whenQueued_thenValidatedAndStored]; [test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds][test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Config active | Config enabled | Supplied configOperator | Queue result | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLQFC-L01 | Any, valid-sized batch | true | false | true | true | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQFC-L02 | Any, valid-sized batch | true | false | true | false | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQFC-L03 | Any, valid-sized batch | true | false | false | true | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQFC-L04 | Any, valid-sized batch | true | false | false | false | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQFC-L05 | Any, valid-sized batch | false | false | true | true | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQFC-L06 | Any, valid-sized batch | false | false | true | false | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQFC-L07 | Any, valid-sized batch | false | false | false | true | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQFC-L08 | Any, valid-sized batch | false | false | false | false | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQFC-L09 | Any, valid-sized batch | false | true | true | true | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQFC-L10 | Any, valid-sized batch | false | true | true | false | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQFC-L11 | Any, valid-sized batch | false | true | false | true | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQFC-L12 | Any, valid-sized batch | false | true | false | false | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQFC-L13 | Any, valid-sized batch | true | true | false | true | any | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQFC-L14 | Any, valid-sized batch | true | true | false | false | any | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQFC-L15 | Fuzz permitted role caller | true | true | true | false | BLCT | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |

Queue success increments uint64 nextActionId once, stores proposer/payload/order/queuedAt; executableAt=queuedAt+1day and expiresAt=executableAt+3days. No public delay setter exists. Record TimelockSubActionQueued, TimelockActionQueued and ConfigStateQueued exact emitter/fields/hashes. Full fee or six-field risk pre-state hashes reject any field drift; disjoint fee-vs-risk updates use different keys/hashes. Changes in live debt, token balance or vault support may leave hash unchanged but cause downstream failure instead.

Execution permissionless, pending-state/time checks FIRST, then BLCT enabled, Config enabled, both active, selected operator. Cancellable-state checks FIRST, then BLCT enabled+active and EMERGENCY role only. Failed execution retains action/key and all earlier subaction writes roll back. Successful execute/cancel releases keys and deletes payload/config guards; action metadata remains. Expiry alone does not release keys. Cancellation has no Config-enabled/activity/selected-operator requirement.

## Invalid inputs

Fixed for this table: Accounting / events: No key acquired.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLQFC-I01 | Fuzz permitted role caller | Asset unregistered; all update fields otherwise valid | BurnerLoansCore_AssetNotConfigured(asset) | Covered: [test_givenUnregisteredAsset_whenQueued_reverts][test_givenUnregisteredAsset_whenQueued_reverts] |
| BLQFC-I02 | Fuzz permitted role caller | Complete-config kink=0; complete pre slope>0; earlier validations pass | BurnerLoans_InvalidFeeConfig() | Covered: [test_givenValidOtherFields_whenZeroKinkWithPreSlope_reverts][test_givenValidOtherFields_whenZeroKinkWithPreSlope_reverts] |
| BLQFC-I03 | Fuzz permitted role caller | Complete-config kink=0; pre slope=0; post slope>0; earlier validations pass | BurnerLoans_InvalidFeeConfig() | Covered: [test_givenValidOtherFields_whenZeroKinkWithPostSlope_reverts][test_givenValidOtherFields_whenZeroKinkWithPostSlope_reverts] |
| BLQFC-I04 | Fuzz permitted role caller | Complete-config base+pre+post>10000; earlier validations pass | BurnerLoans_InvalidFeeConfig() | Covered: [test_givenValidOtherFields_whenFeeSumAboveBps_reverts][test_givenValidOtherFields_whenFeeSumAboveBps_reverts] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: No key acquired.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLQFC-N03 | Fuzz permitted role caller | Supplied base fee fuzz 10001..MAX16; earlier validations pass | BurnerLoans_InvalidBps(value) | Covered: [test_givenValidOtherFields_whenBaseFeeAboveBps_reverts][test_givenValidOtherFields_whenBaseFeeAboveBps_reverts]; [test_givenFeeConfigN03Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenFeeConfigN03Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLQFC-N04 | Fuzz permitted role caller | Supplied pre-kink slope fuzz 10001..MAX16; earlier validations pass | BurnerLoans_InvalidBps(value) | Covered: [test_givenValidOtherFields_whenPreSlopeAboveBps_reverts][test_givenValidOtherFields_whenPreSlopeAboveBps_reverts]; [test_givenFeeConfigN04Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenFeeConfigN04Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLQFC-N05 | Fuzz permitted role caller | Supplied post-kink slope fuzz 10001..MAX16; earlier validations pass | BurnerLoans_InvalidBps(value) | Covered: [test_givenValidOtherFields_whenPostSlopeAboveBps_reverts][test_givenValidOtherFields_whenPostSlopeAboveBps_reverts]; [test_givenFeeConfigN05Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenFeeConfigN05Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLQFC-N06 | Fuzz permitted role caller | Complete-config kink fuzz 10000..MAX16; earlier validations pass | BurnerLoans_InvalidFeeConfig() | Covered: [test_givenValidOtherFields_whenKinkAtOrAboveBps_reverts][test_givenValidOtherFields_whenKinkAtOrAboveBps_reverts]; [test_givenFeeConfigN06Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenFeeConfigN06Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |

## Configuration transitions

Fixed for this table: Accounting / events: Queue commits the full prior configuration; any field drift conflicts.

| ID | Caller | Prior configuration / update | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLQFC-P02 | Fuzz permitted role caller | Fuzz complete valid configuration; independently seed each semantic boundary; no selection mask | Return ID | Covered: [test_givenCompleteStruct_whenQueued_thenExactValues][test_givenCompleteStruct_whenQueued_thenExactValues]; [test_givenFeeConfigP02CompleteStructs_whenBoundarySeedsRun_thenScenarioHolds][test_givenFeeConfigP02CompleteStructs_whenBoundarySeedsRun_thenScenarioHolds] |

## Complete-struct successful boundaries

Local/Config active and enabled, selected BLCT authority, registered asset and free key. No target mutation occurs when queued. Fuzz permitted proposer classes; execution is permissionless after the delay.

| ID | Caller | Complete proposed value | Queue / delayed execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLQFC-N01 | Fuzz permitted proposer | Base/slopes=0, kink=0 | Queue accepted; complete zero-fee curve applied after delay | Other market/risk fields unchanged | Covered: [test_givenZeroFeeCurve_whenExecuted_thenAllFieldsZero][test_givenZeroFeeCurve_whenExecuted_thenAllFieldsZero] |
| BLQFC-N02 | Fuzz permitted proposer | Fuzz valid base/pre/post in 0..10000 with sum<=10000; kink in 1..9999; seed sum=0,1,9999,10000 and kink=1,9999 | Queue accepted; supplied complete struct applied | No partial merge; exact fee event | Covered: [test_givenCompleteStruct_whenExecuted_thenExactValues][test_givenCompleteStruct_whenExecuted_thenExactValues]; [test_givenFeeConfigN02CompleteStructs_whenBoundarySeedsRun_thenScenarioHolds][test_givenFeeConfigN02CompleteStructs_whenBoundarySeedsRun_thenScenarioHolds] |
| BLQFC-P01 | Fuzz all executors | Complete value equals old value; commitment still matches | Queue executes; target configuration no-op | No target setter event/write; queue key released | Covered: [test_givenUnchangedCompleteStruct_whenExecuted_thenNoTargetEvent][test_givenUnchangedCompleteStruct_whenExecuted_thenNoTargetEvent] |

## Queue conflicts and execution

| ID | Caller | Queue / execution condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLQFC-P03 | Fuzz permitted role caller | Valid payload; scoped key free | Return next ID; store typed payload, order, times and current pre-state hash | No target mutation; one key held | Covered: [test_givenFreeKey_whenQueued_thenExactMetadata][test_givenFreeKey_whenQueued_thenExactMetadata] |
| BLQFC-P04 | Fuzz permitted role caller | queueSetAssetFeeConfig(A,value) already pending under owner; queue the same setAssetFeeConfig for the same A again; seed identical and different valid proposed values | IConfigTimelockBatchQueue_ConfigKeyPending(K(setAssetFeeConfig,A),owner) | Original action/payload/hash/key owner and nextActionId unchanged; no second payload/key/event | Covered: [test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts][test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts] |
| BLQFC-P05 | Fuzz permitted role caller | queueSetAssetFeeConfig(A,value) pending; queue the same setAssetFeeConfig for registered B!=A; proposed values independently valid | Return new ID; no key conflict | Distinct K(setAssetFeeConfig,A) and K(setAssetFeeConfig,B); first action unchanged; both execute in either order | Covered: [test_givenSameSetterOtherAssetPending_whenQueued_thenBothOrdersExecute][test_givenSameSetterOtherAssetPending_whenQueued_thenBothOrdersExecute] |
| BLQFC-P06 | Fuzz all executors | Committed parameter/pre-state changes before ready execution | IConfigTimelockBatchQueue_ConfigStateChanged(id,index,key,expected,current) | Action and key retained | Covered: [test_givenCommittedStateDrift_whenExecuted_reverts][test_givenCommittedStateDrift_whenExecuted_reverts] |
| BLQFC-P07 | Fuzz all executors | Ready at executableAt; pre-state unchanged; live setter requirements pass | Execute matching setter | Canonical state/event assertions from matching setter; key released | Covered: [test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup][test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup] |

## Live execution rejection

Fixed for this table: Accounting / events: Earlier batch writes roll back; action and keys retained.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLQFC-P08 | Fuzz all executors | Time-valid queue; fee pre-state unchanged; compatible preconfigured replacement Risk rejects proposed curve | IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig() | Covered: [test_givenReplacementRiskRejectsProposal_whenExecuted_reverts][test_givenReplacementRiskRejectsProposal_whenExecuted_reverts] |

## Different asset setters on the same asset

For these asset setters, independently derive `K(f,A)=keccak256(abi.encode(address(Config),keccak256(abi.encode(f.selector,A))))`. The key includes the concrete Config destination, selector and asset, never the proposed value. A second valid proposal for the same selector/asset must conflict even when its proposed value differs. Another selector on the same asset and the same selector on another asset must not conflict. All other admission/input checks pass; assets are registered and share-mode proposals have compatible custody support.

Keep the first action pending when admitting the second. On success, assert two distinct IDs/keys, exact owner IDs and payloads, independently encoded pre-state hashes, and queue events with no immediate target writes. For every successful pair, execute in both orders in separate runs after both delays, with both proposals still valid: each changes only its targeted field(s)/asset, the other commitment remains executable, and each action releases only its own key. On duplicate rejection, preserve the first complete action/commitment/key owner and nextActionId; create no second payload, key or committed event.

| ID | Caller | Already pending | New proposal | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLQFC-P09 | Fuzz permitted role caller | queueSetAssetDebtCap(A,value) | queueSetAssetFeeConfig(A,value) | Return new ID; no key conflict | Distinct K(setAssetDebtCap,A) and K(setAssetFeeConfig,A); both payloads/hashes/owners retained and executable in either order | Covered: [test_givenCapPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute][test_givenCapPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute] |
| BLQFC-P10 | Fuzz permitted role caller | queueBatch([Config.setAssetOriginationsEnabled(A,value)]) | queueSetAssetFeeConfig(A,value) | Return new ID; no key conflict | Distinct K(setAssetOriginationsEnabled,A) and K(setAssetFeeConfig,A); both payloads/hashes/owners retained and executable in either order | Covered: [test_givenOriginationsPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute][test_givenOriginationsPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute] |
| BLQFC-P11 | Fuzz permitted role caller | queueSetAssetRiskConfig(A,value) | queueSetAssetFeeConfig(A,value) | Return new ID; no key conflict | Distinct K(setAssetRiskConfig,A) and K(setAssetFeeConfig,A); both payloads/hashes/owners retained and executable in either order | Covered: [test_givenRiskPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute][test_givenRiskPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute] |
| BLQFC-P12 | Fuzz permitted role caller | queueSetAssetWithdrawAsShares(A,value) | queueSetAssetFeeConfig(A,value) | Return new ID; no key conflict | Distinct K(setAssetWithdrawAsShares,A) and K(setAssetFeeConfig,A); both payloads/hashes/owners retained and executable in either order | Covered: [test_givenSharesPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute][test_givenSharesPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute] |

## Shared assertions

Submit every field in FeeConfig and validate the entire curve with Config.validateFeeConfig. Fuzz each uint16 field independently, seeding 0,1,9999,10000,10001,MAX16 as applicable. Valid success domains enforce the sum/kink constraints; invalid field maxima remain distinct rejection cases. No selection booleans, zero-for-unselected convention or execution-time merge exist. Test queue-time failure independently from execution after drift. Corresponding queueBatch raw-payload cases enforce canonical ABI lengths/widths; ordinary typed wrapper cannot construct over-width input.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

[test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L22
[test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L34
[test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L47
[test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L67
[test_givenPermittedProposer_whenQueued_thenValidatedAndStored]: ./queueSetAssetFeeConfig.t.sol#L88
[test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetAssetFeeConfig.t.sol#L757
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L101
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L116
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L131
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L146
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L161
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L181
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L201
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L221
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L241
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L261
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L281
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L301
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L321
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L341
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L361
[test_givenUnregisteredAsset_whenQueued_reverts]: ./queueSetAssetFeeConfig.t.sol#L381
[test_givenValidOtherFields_whenZeroKinkWithPreSlope_reverts]: ./queueSetAssetFeeConfig.t.sol#L521
[test_givenValidOtherFields_whenZeroKinkWithPostSlope_reverts]: ./queueSetAssetFeeConfig.t.sol#L540
[test_givenValidOtherFields_whenFeeSumAboveBps_reverts]: ./queueSetAssetFeeConfig.t.sol#L559
[test_givenValidOtherFields_whenBaseFeeAboveBps_reverts]: ./queueSetAssetFeeConfig.t.sol#L578
[test_givenFeeConfigN03Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetAssetFeeConfig.t.sol#L768
[test_givenValidOtherFields_whenPreSlopeAboveBps_reverts]: ./queueSetAssetFeeConfig.t.sol#L599
[test_givenFeeConfigN04Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetAssetFeeConfig.t.sol#L785
[test_givenValidOtherFields_whenPostSlopeAboveBps_reverts]: ./queueSetAssetFeeConfig.t.sol#L620
[test_givenFeeConfigN05Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetAssetFeeConfig.t.sol#L802
[test_givenValidOtherFields_whenKinkAtOrAboveBps_reverts]: ./queueSetAssetFeeConfig.t.sol#L641
[test_givenFeeConfigN06Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetAssetFeeConfig.t.sol#L819
[test_givenCompleteStruct_whenQueued_thenExactValues]: ./queueSetAssetFeeConfig.t.sol#L659
[test_givenFeeConfigP02CompleteStructs_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetAssetFeeConfig.t.sol#L836
[test_givenZeroFeeCurve_whenExecuted_thenAllFieldsZero]: ./queueSetAssetFeeConfig.t.sol#L701
[test_givenCompleteStruct_whenExecuted_thenExactValues]: ./queueSetAssetFeeConfig.t.sol#L679
[test_givenFeeConfigN02CompleteStructs_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetAssetFeeConfig.t.sol#L883
[test_givenUnchangedCompleteStruct_whenExecuted_thenNoTargetEvent]: ./queueSetAssetFeeConfig.t.sol#L718
[test_givenFreeKey_whenQueued_thenExactMetadata]: ./queueSetAssetFeeConfig.t.sol#L401
[test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts]: ./queueSetAssetFeeConfig.t.sol#L411
[test_givenSameSetterOtherAssetPending_whenQueued_thenBothOrdersExecute]: ./queueSetAssetFeeConfig.t.sol#L435
[test_givenCommittedStateDrift_whenExecuted_reverts]: ./queueSetAssetFeeConfig.t.sol#L447
[test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup]: ./queueSetAssetFeeConfig.t.sol#L459
[test_givenReplacementRiskRejectsProposal_whenExecuted_reverts]: ./queueSetAssetFeeConfig.t.sol#L737
[test_givenCapPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute]: ./queueSetAssetFeeConfig.t.sol#L469
[test_givenOriginationsPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute]: ./queueSetAssetFeeConfig.t.sol#L482
[test_givenRiskPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute]: ./queueSetAssetFeeConfig.t.sol#L495
[test_givenSharesPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute]: ./queueSetAssetFeeConfig.t.sol#L508
