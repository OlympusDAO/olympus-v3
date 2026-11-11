# BurnerLoansConfigTimelock.queueBatch coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Implemented allowlist/ABI changes: exclude Custody routing/pending recovery and accept complete fee/risk structs. Old partial payloads are not valid inputs to the new API.

Source: [queueBatch](../../../policies/burnerloans/BurnerLoansConfigTimelock.sol#L334). Coverage is recorded in the Test column.

## Domains and notation

Scenario scope: `BLQB` identifies this contract/function.

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active BurnerLoansConfigTimelock; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Inputs ordered BatchAction[]; 0,1,15,16 and sufficiently sized larger arrays. Allowed target/selector pairs: immutable Config with setAssetDebtCap, setAssetWithdrawAsShares, setAssetFeeConfig, setAssetRiskConfig, setAssetOriginationsEnabled or rescue. Fixed payload sizes 64/160/224; no arbitrary forwarded calls.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Queue defaults: BLCT enabled+active; Config active/enabled and selects BLCT as configOperator; proposer ADMIN or BURNER_LOANS_ADMIN_ROLE. The existing Config authorization/lifecycle tables below use a Config-targeted batch. `queueBatch` checks own activity, local enablement and caller roles before its length bound 1..15. All wrappers enter the same queue code. Non-proposer fails `NotAuthorised()` after lifecycle checks. Keys are Config-scoped selector+asset/token keys; no arbitrary target forwarding is allowed. No public wrapper exists for originations; queueBatch supports its Config selector.

## Authorization

Fixed for this table: Local enabled: true; Local active: true; Config active: true.

| ID | Caller | Config enabled | Selected configOperator | Queue result | Test |
| --- | --- | --- | --- | --- | --- |
| BLQB-A01 | Fuzz outside ADMIN and BL admin holders | true | any | NotAuthorised | Covered: [test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts][test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts] |
| BLQB-A02 | Fuzz outside ADMIN and BL admin holders | false | any | NotAuthorised | Covered: [test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts][test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts] |
| BLQB-A03 | Fuzz permitted role caller | true | another/zero | UnauthorizedConfigOperator(BLCT) | Covered: [test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts][test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts] |
| BLQB-A04 | Fuzz permitted role caller | false | another/zero | UnauthorizedConfigOperator(BLCT) | Covered: [test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts][test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts] |
| BLQB-A05 | Fuzz permitted role caller | true | BLCT | Validate payload before acquiring key | Covered: [test_givenPermittedProposer_whenQueued_thenValidatedAndStored][test_givenPermittedProposer_whenQueued_thenValidatedAndStored] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Config active | Config enabled | Selected configOperator | Queue result | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLQB-L01 | Any, valid-sized batch | true | false | true | true | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQB-L02 | Any, valid-sized batch | true | false | true | false | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQB-L03 | Any, valid-sized batch | true | false | false | true | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQB-L04 | Any, valid-sized batch | true | false | false | false | any | NotEnabled | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQB-L05 | Any, valid-sized batch | false | false | true | true | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQB-L06 | Any, valid-sized batch | false | false | true | false | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQB-L07 | Any, valid-sized batch | false | false | false | true | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQB-L08 | Any, valid-sized batch | false | false | false | false | any | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQB-L09 | Any, valid-sized batch | false | true | true | true | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQB-L10 | Any, valid-sized batch | false | true | true | false | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQB-L11 | Any, valid-sized batch | false | true | false | true | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQB-L12 | Any, valid-sized batch | false | true | false | false | any | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQB-L13 | Any, valid-sized batch | true | true | false | true | any | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts] |
| BLQB-L14 | Any, valid-sized batch | true | true | false | false | any | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts] |
| BLQB-L15 | Fuzz permitted role caller | true | true | true | false | BLCT | PolicyDependency_NotActive(Config) | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts] |

Queue success increments uint64 nextActionId once, stores proposer/payload/order/queuedAt; executableAt=queuedAt+1day and expiresAt=executableAt+3days. No public delay setter exists. Record TimelockSubActionQueued, TimelockActionQueued and ConfigStateQueued exact emitter/fields/hashes. Every selector hash includes current `Config.configOperator()` alongside its existing facility and setting fields; rescue additionally retains `Core.configOperator()`. Full fee or six-field risk pre-state hashes reject any field drift; disjoint fee-vs-risk updates use different keys/hashes. Changes in live debt, token balance or vault support may leave hash unchanged but cause downstream failure instead.

Execution permissionless, pending-state/time checks FIRST, then BLCT admission and Config lifecycle/selected-operator checks. Risk's independent operator is not consulted. Cancellable-state checks FIRST, then BLCT active and EMERGENCY role only; local disablement permits cancellation. Failed execution retains action/key and all earlier subaction writes roll back. Successful execute/cancel releases keys and deletes payload/config guards; action metadata remains. Expiry alone does not release keys. Cancellation has no Config-enabled/activity/selected-operator requirement.

## Dependency lifecycle

Fixed for this table: Accounting / events: No action ID/key acquired.

| ID | Caller | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLQB-D01 | Fuzz all callers | Batch length=0; BLCT active and disabled; caller role irrelevant | NotEnabled() | Covered: [test_givenDisabledAndUnauthorized_whenEmptyBatchQueued_reverts][test_givenDisabledAndUnauthorized_whenEmptyBatchQueued_reverts] |

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLQB-I07 | Fuzz permitted role caller | Wrong target; supported selector/payload | ITimelockBatchQueue_ActionInvalid(target,selector) | Unchanged; no committed logs | Covered: [test_givenWrongTarget_whenQueued_reverts][test_givenWrongTarget_whenQueued_reverts] |
| BLQB-I08 | Fuzz permitted role caller | Allowed target/selector; payload length=expected-1; each admitted shape independently | ITimelockBatchQueue_ActionInvalid(target,selector) | Unchanged; no committed logs | Covered: [test_givenEachSupportedShape_whenPayloadShortByOne_reverts][test_givenEachSupportedShape_whenPayloadShortByOne_reverts] |
| BLQB-I09 | Fuzz permitted role caller | Allowed target/selector; payload length=expected+1; each admitted shape independently | ITimelockBatchQueue_ActionInvalid(target,selector) | Unchanged; no committed logs | Covered: [test_givenEachSupportedShape_whenPayloadLongByOne_reverts][test_givenEachSupportedShape_whenPayloadLongByOne_reverts] |
| BLQB-I10 | Fuzz permitted role caller | Allowed target/selector; payload has an extra32-byte word; each shape independently | ITimelockBatchQueue_ActionInvalid(target,selector) | Unchanged; no committed logs | Covered: [test_givenEachSupportedShape_whenPayloadExtraWord_reverts][test_givenEachSupportedShape_whenPayloadExtraWord_reverts] |
| BLQB-I11 | Fuzz permitted role caller | Unsupported asset in later valid-shaped subaction | BurnerLoansCore_AssetNotConfigured(asset) | Rollback earlier acquired keys and ID | Covered: [test_givenLaterUnregisteredAsset_whenQueued_thenEarlierKeyRollsBack][test_givenLaterUnregisteredAsset_whenQueued_thenEarlierKeyRollsBack] |

## Numeric boundaries and arithmetic

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLQB-N01 | Fuzz ADMIN proposer identity | Batch length fuzz 16..128; existing boundary seeds retained | ITimelockBatchQueue_BatchTooLarge(length,15) | No action ID/key acquired | Covered: [test_givenAnyCaller_whenOversizedBatchQueued_reverts][test_givenAnyCaller_whenOversizedBatchQueued_reverts] |
| BLQB-N02 | Fuzz permitted role caller | Target=Config; unsupported selector; fuzz bytes4 excluding admitted selectors | ITimelockBatchQueue_ActionInvalid(Config,selector) | Unchanged; no committed logs | Covered: [test_givenUnsupportedSelector_whenQueued_reverts][test_givenUnsupportedSelector_whenQueued_reverts] |
| BLQB-N04 | Fuzz permitted role caller | Originations/withdraw-as-shares raw bool word fuzz 2..MAX256 | ITimelockBatchQueue_ActionInvalid(Config,selector) | Unchanged; no committed logs | Covered: [test_givenNoncanonicalBool_whenOriginationsQueued_reverts][test_givenNoncanonicalBool_whenOriginationsQueued_reverts]; [test_givenRawAbiN04Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenRawAbiN04Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLQB-N05 | Fuzz permitted role caller | nextActionId=MAX64; otherwise valid batch; proposed next counter is uint256(MAX64)+1=2**64 | SafeCastOverflowedUintDowncast(64,2**64) | Injected storage boundary; preserve counter, existing payloads/owners and all keys; no partial batch or committed event | Covered: [test_givenCounterOverflow_whenQueued_thenReadableError][test_givenCounterOverflow_whenQueued_thenReadableError] |
| BLQB-N06 | Fuzz permitted role caller | queuedAt=MAX48-delay+1; otherwise valid batch; widened executableAt=uint256(queuedAt)+delay=2**48 | SafeCastOverflowedUintDowncast(48,2**48) while narrowing executableAt | Injected timestamp boundary; counter, pending keys, existing payloads and commitments unchanged; no partial batch or committed event | Covered: [test_givenExecutableTimestampOverflow_whenQueued_thenReadableError][test_givenExecutableTimestampOverflow_whenQueued_thenReadableError] |
| BLQB-N07 | Fuzz permitted role caller | queuedAt=MAX48-delay-window+1; executableAt fits uint48; widened expiresAt=uint256(executableAt)+window=2**48 | SafeCastOverflowedUintDowncast(48,2**48) while narrowing expiresAt | Injected timestamp boundary; counter, pending keys, existing payloads and commitments unchanged; no partial batch or committed event | Covered: [test_givenExpiryTimestampOverflow_whenQueued_thenReadableError][test_givenExpiryTimestampOverflow_whenQueued_thenReadableError] |

## Configuration transitions

| ID | Caller | Prior configuration / update | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLQB-P01 | Fuzz permitted role caller | Originations selector; registered asset; requested=true | Return ID | No public queue-originations wrapper required | Covered: [test_givenRegisteredAsset_whenOriginationsTrueQueued_thenStored][test_givenRegisteredAsset_whenOriginationsTrueQueued_thenStored] |
| BLQB-P02 | Fuzz permitted role caller | Originations selector; registered asset; requested=false | Return ID | No target mutation before delay | Covered: [test_givenRegisteredAsset_whenOriginationsFalseQueued_thenStored][test_givenRegisteredAsset_whenOriginationsFalseQueued_thenStored] |

## Removed selectors and partial payload rejection

All ordinary queue prerequisites pass. These cases apply to the approved new allowlist, not the current source.

| ID | Caller | Target / selector / payload | Result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLQB-I01 | Fuzz permitted role caller | Config target; former fee-routing selector | ActionInvalid(target,selector) | No key acquired or ID consumed | Covered: [test_givenFormerFeeRoutingSelector_whenQueued_reverts][test_givenFormerFeeRoutingSelector_whenQueued_reverts] |
| BLQB-I02 | Fuzz permitted role caller | Config target; former yield-routing selector | ActionInvalid(target,selector) | Unchanged | Covered: [test_givenFormerYieldRoutingSelector_whenQueued_reverts][test_givenFormerYieldRoutingSelector_whenQueued_reverts] |
| BLQB-I03 | Fuzz permitted role caller | Config target; former pending-payout rescue selector | ActionInvalid(target,selector) | Unchanged | Covered: [test_givenFormerPendingPayoutRescueSelector_whenQueued_reverts][test_givenFormerPendingPayoutRescueSelector_whenQueued_reverts] |
| BLQB-I04 | Fuzz permitted role caller | Config fee selector; old 288-byte partial payload | ActionInvalid(target,selector) | Unchanged | Covered: [test_givenLegacyPartialFeePayload_whenQueued_reverts][test_givenLegacyPartialFeePayload_whenQueued_reverts] |
| BLQB-I05 | Fuzz permitted role caller | Config risk selector; old 416-byte partial payload | ActionInvalid(target,selector) | Unchanged | Covered: [test_givenLegacyPartialRiskPayload_whenQueued_reverts][test_givenLegacyPartialRiskPayload_whenQueued_reverts] |
| BLQB-I06 | Fuzz permitted role caller | Payout target; otherwise admitted Config selector | ActionInvalid(target,selector) | No cross-timelock forwarding | Covered: [test_givenPayoutTarget_whenMarketSetterQueued_reverts][test_givenPayoutTarget_whenMarketSetterQueued_reverts] |

The expected action-counter overflow is a readable SafeCast downcast error for 64 bits and value 2**64, not Panic(0x11). Inspection of [TimelockBatchQueue._queueAction](../../../policies/utils/TimelockBatchQueue.sol#L194) and [TimelockQueue._queueAction](../../../policies/utils/TimelockQueue.sol#L114) shows both currently increment a uint64 directly; the shared batch path therefore needs implementation alignment. This scenario-only update changes no queue implementation. The last successful boundary is nextActionId=MAX64-1, returning MAX64-1 and storing nextActionId=MAX64.

For N06/N07, calculate each timestamp addition in uint256 and check its uint48 narrowing separately: executableAt first, then expiresAt. The exact failing value at either adjacent boundary is MAX48+1=2**48. Preserve the complete pre-queue state on failure. The shared implementation currently performs checked uint48 additions; these scenarios require readable SafeCast overflow errors instead of arithmetic panics.

## Queue conflicts and execution

| ID | Caller | Queue / execution condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLQB-P03 | Fuzz permitted role caller | Two sub-actions for the same selector and same asset A in one batch; seed each of debt cap, originations, risk config, withdraw-as-shares and fee config; seed identical/different valid proposed values | IConfigTimelockBatchQueue_ConfigKeyPending(K(selector,A),thisId) | Complete rollback including first key acquisition; no ID, payload, guard or committed event retained | Covered: [test_givenEachSetterRepeatedInSameBatch_whenQueued_thenAtomicConflict][test_givenEachSetterRepeatedInSameBatch_whenQueued_thenAtomicConflict] |
| BLQB-P04 | Fuzz permitted role caller | Same selector and same asset A key owned by an earlier pending action; seed each of the five asset setters, with identical/different valid proposed values | IConfigTimelockBatchQueue_ConfigKeyPending(K(selector,A),owner) | Earlier action/payload/hash/owner unchanged; no new ID/key/payload/event | Covered: [test_givenEachSetterAlreadyPending_whenQueued_thenOriginalPreserved][test_givenEachSetterAlreadyPending_whenQueued_thenOriginalPreserved] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLQB-P05 | Fuzz permitted role caller | One valid action; scoped key free | Return next ID | Store exact target/selector/payload and current pre-state hash | Covered: [test_givenOneAction_whenQueued_thenExactCommitment][test_givenOneAction_whenQueued_thenExactCommitment] |
| BLQB-P06 | Fuzz permitted role caller | Fifteen valid actions with distinct keys | Return one ID | Store all15 in order; one key per action; exact setting and current Config operator pre-state for each selector | Covered: [test_givenFifteenDistinctKeys_whenQueued_thenExactOrderedMetadata][test_givenFifteenDistinctKeys_whenQueued_thenExactOrderedMetadata] |
| BLQB-P07 | Fuzz permitted role caller | Typed asset setter bool field raw word>1; exact payload length | ITimelockBatchQueue_ActionInvalid(target,selector) | Unchanged; no committed logs | Covered: [test_givenNoncanonicalBool_whenWithdrawalQueued_reverts][test_givenNoncanonicalBool_whenWithdrawalQueued_reverts]; [test_givenRawAbiP07Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenRawAbiP07Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLQB-P08 | Fuzz permitted role caller | Address word has nonzero upper96 bits; exact payload length | ITimelockBatchQueue_ActionInvalid(target,selector) | Unchanged; no committed logs | Covered: [test_givenDirtyAddressWord_whenQueued_reverts][test_givenDirtyAddressWord_whenQueued_reverts]; [test_givenRawAbiP08Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenRawAbiP08Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLQB-P09 | Fuzz permitted role caller | Typed uint16/48/128 field exceeds its type bound; exact payload length; each field separately | ITimelockBatchQueue_ActionInvalid(target,selector) | Unchanged; no committed logs | Covered: [test_givenEachNumericFieldAboveAbiWidth_whenQueued_reverts][test_givenEachNumericFieldAboveAbiWidth_whenQueued_reverts] |
| BLQB-P10 | Fuzz permitted role caller | Risk and fee selectors for the same asset A in one batch; both proposals valid; seed both array orders | Return one ID | Distinct K(setAssetRiskConfig,A) and K(setAssetFeeConfig,A), exact ordered payloads and independent pre-state hashes; no target write until execution | Covered: [test_givenRiskAndFeeForSameAsset_whenBatched_thenIndependentBothOrders][test_givenRiskAndFeeForSameAsset_whenBatched_thenIndependentBothOrders] |

## Asset-selector and asset-address independence

For these asset setters, independently derive `K(f,A)=keccak256(abi.encode(address(Config),keccak256(abi.encode(f.selector,A))))`. The key includes the concrete Config destination, selector and asset, never the proposed value. A second valid proposal for the same selector/asset must conflict even when its proposed value differs. Another selector on the same asset and the same selector on another asset must not conflict. All other admission/input checks pass; assets are registered and share-mode proposals have compatible custody support.

Keep the first action pending when admitting the second. On success, assert two distinct IDs/keys, exact owner IDs and payloads, independently encoded pre-state hashes, and queue events with no immediate target writes. For every successful pair, execute in both orders in separate runs after both delays, with both proposals still valid: each changes only its targeted field(s)/asset, the other commitment remains executable, and each action releases only its own key. On duplicate rejection, preserve the first complete action/commitment/key owner and nextActionId; create no second payload, key or committed event.

Originations has no typed public queue wrapper. Its five cases below live under queueBatch; the other four function plans contain their reciprocal ordered-pair cases. Together these enumerate all 20 ordered pairs of distinct asset setters, all five same-selector/same-asset conflicts, and all five same-selector/different-asset successes.

| ID | Caller | Already pending | New proposal | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLQB-P14 | Fuzz permitted role caller | queueBatch([Config.setAssetOriginationsEnabled(A,value0)]) | queueBatch([Config.setAssetOriginationsEnabled(A,value1)]); seed equal/opposite booleans | IConfigTimelockBatchQueue_ConfigKeyPending(K(setAssetOriginationsEnabled,A),owner) | Original action/key/hash/counter unchanged; no second payload/event | Covered: [test_givenOriginationsPending_whenSameAssetQueuedAgain_reverts][test_givenOriginationsPending_whenSameAssetQueuedAgain_reverts] |
| BLQB-P15 | Fuzz permitted role caller | queueBatch([Config.setAssetOriginationsEnabled(A,value0)]) | queueBatch([Config.setAssetOriginationsEnabled(B,value1)]), registered B!=A | Return new ID; no key conflict | Distinct asset-scoped keys and unchanged first action; both execute in either order | Covered: [test_givenOriginationsPending_whenOtherAssetQueued_thenIndependentBothOrders][test_givenOriginationsPending_whenOtherAssetQueued_thenIndependentBothOrders] |
| BLQB-P16 | Fuzz permitted role caller | queueSetAssetDebtCap(A,value) | queueBatch([Config.setAssetOriginationsEnabled(A,value)]) | Return new ID; no key conflict | Distinct K(setAssetDebtCap,A) and K(setAssetOriginationsEnabled,A); both actions retained and executable in either order | Covered: [test_givenCapPending_whenOriginationsQueued_thenIndependentBothOrders][test_givenCapPending_whenOriginationsQueued_thenIndependentBothOrders] |
| BLQB-P17 | Fuzz permitted role caller | queueSetAssetRiskConfig(A,value) | queueBatch([Config.setAssetOriginationsEnabled(A,value)]) | Return new ID; no key conflict | Distinct K(setAssetRiskConfig,A) and K(setAssetOriginationsEnabled,A); both actions retained and executable in either order | Covered: [test_givenRiskPending_whenOriginationsQueued_thenIndependentBothOrders][test_givenRiskPending_whenOriginationsQueued_thenIndependentBothOrders] |
| BLQB-P18 | Fuzz permitted role caller | queueSetAssetWithdrawAsShares(A,value) | queueBatch([Config.setAssetOriginationsEnabled(A,value)]) | Return new ID; no key conflict | Distinct K(setAssetWithdrawAsShares,A) and K(setAssetOriginationsEnabled,A); both actions retained and executable in either order | Covered: [test_givenSharesPending_whenOriginationsQueued_thenIndependentBothOrders][test_givenSharesPending_whenOriginationsQueued_thenIndependentBothOrders] |
| BLQB-P19 | Fuzz permitted role caller | queueSetAssetFeeConfig(A,value) | queueBatch([Config.setAssetOriginationsEnabled(A,value)]) | Return new ID; no key conflict | Distinct K(setAssetFeeConfig,A) and K(setAssetOriginationsEnabled,A); both actions retained and executable in either order | Covered: [test_givenFeePending_whenOriginationsQueued_thenIndependentBothOrders][test_givenFeePending_whenOriginationsQueued_thenIndependentBothOrders] |

## Independent asset setters within one batch

Use one registered asset A and otherwise valid proposals. Each pair below is two sub-actions in one batch; explicitly seed both array orders. Together with BLQB-P10 these enumerate all ten unordered pairs of the five asset setters, with both orders required for each pair. Independently assert one returned ID, the exact two payloads in input order, two distinct scoped keys owned by that ID, separate target-field pre-state hashes and no target mutation at queue time. At delayed execution, assert both matching setters apply, both keys are released, and unrelated fields/accounting remain unchanged.

| ID | Caller | First selector | Second selector | Queue result / effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLQB-P20 | Fuzz permitted role caller | setAssetDebtCap(A,valueA) | setAssetOriginationsEnabled(A,valueB) | Return one ID; independent K(setAssetDebtCap,A) and K(setAssetOriginationsEnabled,A); seed both array orders | Covered: [test_givenCapAndOriginationsForSameAsset_whenBatched_thenIndependentBothOrders][test_givenCapAndOriginationsForSameAsset_whenBatched_thenIndependentBothOrders] |
| BLQB-P21 | Fuzz permitted role caller | setAssetDebtCap(A,valueA) | setAssetRiskConfig(A,valueB) | Return one ID; independent K(setAssetDebtCap,A) and K(setAssetRiskConfig,A); seed both array orders | Covered: [test_givenCapAndRiskForSameAsset_whenBatched_thenIndependentBothOrders][test_givenCapAndRiskForSameAsset_whenBatched_thenIndependentBothOrders] |
| BLQB-P22 | Fuzz permitted role caller | setAssetDebtCap(A,valueA) | setAssetWithdrawAsShares(A,valueB) | Return one ID; independent K(setAssetDebtCap,A) and K(setAssetWithdrawAsShares,A); seed both array orders | Covered: [test_givenCapAndSharesForSameAsset_whenBatched_thenIndependentBothOrders][test_givenCapAndSharesForSameAsset_whenBatched_thenIndependentBothOrders] |
| BLQB-P23 | Fuzz permitted role caller | setAssetDebtCap(A,valueA) | setAssetFeeConfig(A,valueB) | Return one ID; independent K(setAssetDebtCap,A) and K(setAssetFeeConfig,A); seed both array orders | Covered: [test_givenCapAndFeeForSameAsset_whenBatched_thenIndependentBothOrders][test_givenCapAndFeeForSameAsset_whenBatched_thenIndependentBothOrders] |
| BLQB-P24 | Fuzz permitted role caller | setAssetOriginationsEnabled(A,valueA) | setAssetRiskConfig(A,valueB) | Return one ID; independent K(setAssetOriginationsEnabled,A) and K(setAssetRiskConfig,A); seed both array orders | Covered: [test_givenOriginationsAndRiskForSameAsset_whenBatched_thenIndependentBothOrders][test_givenOriginationsAndRiskForSameAsset_whenBatched_thenIndependentBothOrders] |
| BLQB-P25 | Fuzz permitted role caller | setAssetOriginationsEnabled(A,valueA) | setAssetWithdrawAsShares(A,valueB) | Return one ID; independent K(setAssetOriginationsEnabled,A) and K(setAssetWithdrawAsShares,A); seed both array orders | Covered: [test_givenOriginationsAndSharesForSameAsset_whenBatched_thenIndependentBothOrders][test_givenOriginationsAndSharesForSameAsset_whenBatched_thenIndependentBothOrders] |
| BLQB-P26 | Fuzz permitted role caller | setAssetOriginationsEnabled(A,valueA) | setAssetFeeConfig(A,valueB) | Return one ID; independent K(setAssetOriginationsEnabled,A) and K(setAssetFeeConfig,A); seed both array orders | Covered: [test_givenOriginationsAndFeeForSameAsset_whenBatched_thenIndependentBothOrders][test_givenOriginationsAndFeeForSameAsset_whenBatched_thenIndependentBothOrders] |
| BLQB-P27 | Fuzz permitted role caller | setAssetRiskConfig(A,valueA) | setAssetWithdrawAsShares(A,valueB) | Return one ID; independent K(setAssetRiskConfig,A) and K(setAssetWithdrawAsShares,A); seed both array orders | Covered: [test_givenRiskAndSharesForSameAsset_whenBatched_thenIndependentBothOrders][test_givenRiskAndSharesForSameAsset_whenBatched_thenIndependentBothOrders] |
| BLQB-P28 | Fuzz permitted role caller | setAssetWithdrawAsShares(A,valueA) | setAssetFeeConfig(A,valueB) | Return one ID; independent K(setAssetWithdrawAsShares,A) and K(setAssetFeeConfig,A); seed both array orders | Covered: [test_givenSharesAndFeeForSameAsset_whenBatched_thenIndependentBothOrders][test_givenSharesAndFeeForSameAsset_whenBatched_thenIndependentBothOrders] |
| BLQB-P29 | Fuzz permitted role caller | Same selector on registered A | Same selector on registered B!=A; seed each of the five asset setters and both array orders | Return one ID; two distinct asset-scoped keys/hashes; both setters apply only to their named asset | Covered: [test_givenEachSetterForDifferentAssets_whenBatched_thenIndependentBothOrders][test_givenEachSetterForDifferentAssets_whenBatched_thenIndependentBothOrders] |

## Shared assertions

Invalid stored target/payload is not fabricated after queue validation. Raw malformed-input tests are entrypoint inputs. Max keys per batch15, one key per admitted action. Never forward ADMIN-only global cap or code-replacement setters.

Co-located API assertions: `nextActionId`, `getQueuedAction`, `getQueuedActionLength`, `getQueuedSubAction`, `getQueuedConfigStateCount`, `getQueuedConfigDestination`, `getQueuedConfigState`, `pendingActionId`, `maxConfigKeysPerBatch`, `timelockDelay`, `MIN_TIMELOCK_DELAY`, `MAX_TIMELOCK_DELAY`, `EXECUTION_WINDOW`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

## Target-specific routing and authority

The Config queue defaults apply. All entries have canonical payload lengths; the target/selector allowlist rejects before dispatch. Risk's operator remains independent; BLCT holds no ADMIN grant on Config.

| ID | Caller | Batch / authority | Queue result | Effects / getter assertions | Test |
| --- | --- | --- | --- | --- | --- |
| BLQB-I12 | Fuzz permitted role caller | Config target with former Config.setPriceCacheMaxAge selector | ITimelockBatchQueue_ActionInvalid(Config,selector) | No Config forwarding fallback, ID or key | Covered: [test_givenConfigAgeForwarding_whenQueued_reverts][test_givenConfigAgeForwarding_whenQueued_reverts] |
| BLQB-I13 | Fuzz permitted role caller | Risk target with a Config market setter selector | ITimelockBatchQueue_ActionInvalid(Risk,selector) | No write authority conferred by target whitelist alone | Covered: [test_givenRiskMarketSetter_whenQueued_reverts][test_givenRiskMarketSetter_whenQueued_reverts] |
| BLQB-I14 | Fuzz permitted role caller | Nonselected Risk target with setPriceCacheMaxAge | ITimelockBatchQueue_ActionInvalid(target,selector) | No stale or arbitrary Risk controller | Covered: [test_givenNonselectedRisk_whenQueued_reverts][test_givenNonselectedRisk_whenQueued_reverts] |
| BLQB-I15 | Fuzz permitted role caller | Selected Risk with setPriceCache, setBackingOracle or setConfigOperator; each selector separately | ITimelockBatchQueue_ActionInvalid(Risk,selector) | ADMIN dependency/operator replacements remain unavailable to proposers | Covered: [test_givenAdminOnlyRiskSelectors_whenQueued_reverts][test_givenAdminOnlyRiskSelectors_whenQueued_reverts] |
| BLQB-P11 | Fuzz permitted role caller | Config cap and fee updates; seed both orders | Return one ID | Exact Config selector/payload order and independent setting keys/hashes; no target setters called | Covered: [test_givenConfigAndRiskActions_whenBatched_thenIndependentTargets][test_givenConfigAndRiskActions_whenBatched_thenIndependentTargets] |
| BLQB-P12 | Fuzz permitted role caller | Config-only batch; Risk has another/zero operator | Return ID | No Risk operator lookup; public validators remain usable; no Risk setter | Covered: [test_givenRiskOperatorDifferent_whenConfigOnlyBatchQueued_thenAccepted][test_givenRiskOperatorDifferent_whenConfigOnlyBatchQueued_thenAccepted] |
| BLQB-D03 | Fuzz permitted role caller | Two Config domains; Config selects another/zero | BurnerLoansConfig_UnauthorizedConfigOperator(BLCT) | Entire queue rolls back; no partial authorization | Covered: [test_givenConfigOperatorRevoked_whenMixedBatchQueued_reverts][test_givenConfigOperatorRevoked_whenMixedBatchQueued_reverts] |

## Co-located queued-state reads

Use the action just queued above; fuzz an independent getter caller including zero. Read-only access does not require local/dependency activity or enablement. Independently encode target, payload, scoped key and pre-state hash; do not use another getter as the sole oracle.

| ID | Caller | Read / index | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUED-ACTION-N02 | Fuzz getter caller | Pending sub-action index in 0..length-1; seed zero and last | Exact queued payload at each valid index | No mutation | Covered: [test_givenPendingBatch_whenEachValidSubactionRead_thenExactPayload][test_givenPendingBatch_whenEachValidSubactionRead_thenExactPayload] |
| BLCT-QUEUED-STATE-P01 | Fuzz getter caller | Valid queued action/sub-action/config-state index zero | Exact destination, scoped key and independently encoded complete pre-state hash | No mutation | Covered: [test_givenPendingBatch_whenStateRead_thenIndependentCommitment][test_givenPendingBatch_whenStateRead_thenIndependentCommitment] |
| BLCT-QUEUED-STATE-P02 | Fuzz getter caller | Missing ID; seed zero/MAX64; counts/destination/pending-key getters | Defined zero/default count/destination/key owner, not an invented ActionNotFound gate | No mutation | Covered: [test_givenMissingId_whenStateGettersRead_thenDefaults][test_givenMissingId_whenStateGettersRead_thenDefaults] |
| BLCT-QUEUED-STATE-P03 | Fuzz getter caller | Config-state index>=count, including MAX256; valid pending action | ConfigStateIndexOutOfBounds(action,index,requested,length) | No mutation | Covered: [test_givenPendingAction_whenStateIndexOutOfBounds_reverts][test_givenPendingAction_whenStateIndexOutOfBounds_reverts]; [test_givenSTATEP03IndexEndpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenSTATEP03IndexEndpoints_whenBoundarySeedsRun_thenScenarioHolds] |

| ID | Caller | Read / index | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUED-ACTION-I01 | Fuzz getter caller | Pending sub-action index fuzz length..MAX256; seed length,MAX256 | SubActionIndexOutOfBounds(id,index,length) | No mutation | Covered: [test_givenPendingAction_whenPayloadIndexOutOfBounds_reverts][test_givenPendingAction_whenPayloadIndexOutOfBounds_reverts]; [test_givenACTIONI01IndexEndpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenACTIONI01IndexEndpoints_whenBoundarySeedsRun_thenScenarioHolds] |

## Admission precedence regressions

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLQB-L16 | Fuzz all callers | false | Fuzz false/true | ROLES code rejects; empty batch where exposed | BurnerLoans_PolicyNotActive(TL) | No ID, guard, payload or committed log | Covered: [test][test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts] |
| BLQB-L17 | Fuzz all callers | true | false | ROLES code rejects; empty batch where exposed | NotEnabled() | No ID, guard, payload or committed log | Covered: [test][test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts] |
| BLQB-A06 | Fuzz outside both accepted proposer roles | true | true | Target inactive or required metadata rejects; empty batch where exposed | NotAuthorised() | No ID, guard, payload or committed log | Covered: [test][test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts] |

[test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts]: ./queueBatch.t.sol#L26
[test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts]: ./queueBatch.t.sol#L38
[test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts]: ./queueBatch.t.sol#L51
[test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts]: ./queueBatch.t.sol#L71
[test_givenPermittedProposer_whenQueued_thenValidatedAndStored]: ./queueBatch.t.sol#L92
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueBatch.t.sol#L105
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueBatch.t.sol#L120
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueBatch.t.sol#L135
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueBatch.t.sol#L150
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueBatch.t.sol#L165
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueBatch.t.sol#L185
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueBatch.t.sol#L205
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueBatch.t.sol#L225
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts]: ./queueBatch.t.sol#L245
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueBatch.t.sol#L265
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueBatch.t.sol#L285
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueBatch.t.sol#L305
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts]: ./queueBatch.t.sol#L325
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts]: ./queueBatch.t.sol#L345
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts]: ./queueBatch.t.sol#L365
[test_givenDisabledAndUnauthorized_whenEmptyBatchQueued_reverts]: ./queueBatch.t.sol#L385
[test_givenWrongTarget_whenQueued_reverts]: ./queueBatch.t.sol#L419
[test_givenEachSupportedShape_whenPayloadShortByOne_reverts]: ./queueBatch.t.sol#L435
[test_givenEachSupportedShape_whenPayloadLongByOne_reverts]: ./queueBatch.t.sol#L453
[test_givenEachSupportedShape_whenPayloadExtraWord_reverts]: ./queueBatch.t.sol#L471
[test_givenLaterUnregisteredAsset_whenQueued_thenEarlierKeyRollsBack]: ./queueBatch.t.sol#L489
[test_givenAnyCaller_whenOversizedBatchQueued_reverts]: ./queueBatch.t.sol#L397
[test_givenUnsupportedSelector_whenQueued_reverts]: ./queueBatch.t.sol#L513
[test_givenNoncanonicalBool_whenOriginationsQueued_reverts]: ./queueBatch.t.sol#L530
[test_givenRawAbiN04Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueBatch.t.sol#L1341
[test_givenCounterOverflow_whenQueued_thenReadableError]: ./queueBatch.t.sol#L562
[test_givenExecutableTimestampOverflow_whenQueued_thenReadableError]: ./queueBatch.t.sol#L594
[test_givenExpiryTimestampOverflow_whenQueued_thenReadableError]: ./queueBatch.t.sol#L622
[test_givenRegisteredAsset_whenOriginationsTrueQueued_thenStored]: ./queueBatch.t.sol#L650
[test_givenRegisteredAsset_whenOriginationsFalseQueued_thenStored]: ./queueBatch.t.sol#L663
[test_givenFormerFeeRoutingSelector_whenQueued_reverts]: ./queueBatch.t.sol#L676
[test_givenFormerYieldRoutingSelector_whenQueued_reverts]: ./queueBatch.t.sol#L690
[test_givenFormerPendingPayoutRescueSelector_whenQueued_reverts]: ./queueBatch.t.sol#L704
[test_givenLegacyPartialFeePayload_whenQueued_reverts]: ./queueBatch.t.sol#L718
[test_givenLegacyPartialRiskPayload_whenQueued_reverts]: ./queueBatch.t.sol#L732
[test_givenPayoutTarget_whenMarketSetterQueued_reverts]: ./queueBatch.t.sol#L746
[test_givenEachSetterRepeatedInSameBatch_whenQueued_thenAtomicConflict]: ./queueBatch.t.sol#L821
[test_givenEachSetterAlreadyPending_whenQueued_thenOriginalPreserved]: ./queueBatch.t.sol#L850
[test_givenOneAction_whenQueued_thenExactCommitment]: ./queueBatch.t.sol#L874
[test_givenFifteenDistinctKeys_whenQueued_thenExactOrderedMetadata]: ./queueBatch.t.sol#L887
[test_givenNoncanonicalBool_whenWithdrawalQueued_reverts]: ./queueBatch.t.sol#L546
[test_givenRawAbiP07Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueBatch.t.sol#L1358
[test_givenDirtyAddressWord_whenQueued_reverts]: ./queueBatch.t.sol#L908
[test_givenRawAbiP08Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueBatch.t.sol#L1375
[test_givenEachNumericFieldAboveAbiWidth_whenQueued_reverts]: ./queueBatch.t.sol#L1476
[test_givenRiskAndFeeForSameAsset_whenBatched_thenIndependentBothOrders]: ./queueBatch.t.sol#L924
[test_givenOriginationsPending_whenSameAssetQueuedAgain_reverts]: ./queueBatch.t.sol#L1054
[test_givenOriginationsPending_whenOtherAssetQueued_thenIndependentBothOrders]: ./queueBatch.t.sol#L1075
[test_givenCapPending_whenOriginationsQueued_thenIndependentBothOrders]: ./queueBatch.t.sol#L1089
[test_givenRiskPending_whenOriginationsQueued_thenIndependentBothOrders]: ./queueBatch.t.sol#L1102
[test_givenSharesPending_whenOriginationsQueued_thenIndependentBothOrders]: ./queueBatch.t.sol#L1115
[test_givenFeePending_whenOriginationsQueued_thenIndependentBothOrders]: ./queueBatch.t.sol#L1128
[test_givenCapAndOriginationsForSameAsset_whenBatched_thenIndependentBothOrders]: ./queueBatch.t.sol#L937
[test_givenCapAndRiskForSameAsset_whenBatched_thenIndependentBothOrders]: ./queueBatch.t.sol#L950
[test_givenCapAndSharesForSameAsset_whenBatched_thenIndependentBothOrders]: ./queueBatch.t.sol#L963
[test_givenCapAndFeeForSameAsset_whenBatched_thenIndependentBothOrders]: ./queueBatch.t.sol#L976
[test_givenOriginationsAndRiskForSameAsset_whenBatched_thenIndependentBothOrders]: ./queueBatch.t.sol#L989
[test_givenOriginationsAndSharesForSameAsset_whenBatched_thenIndependentBothOrders]: ./queueBatch.t.sol#L1002
[test_givenOriginationsAndFeeForSameAsset_whenBatched_thenIndependentBothOrders]: ./queueBatch.t.sol#L1015
[test_givenRiskAndSharesForSameAsset_whenBatched_thenIndependentBothOrders]: ./queueBatch.t.sol#L1028
[test_givenSharesAndFeeForSameAsset_whenBatched_thenIndependentBothOrders]: ./queueBatch.t.sol#L1041
[test_givenEachSetterForDifferentAssets_whenBatched_thenIndependentBothOrders]: ./queueBatch.t.sol#L1141
[test_givenConfigAgeForwarding_whenQueued_reverts]: ./queueBatch.t.sol#L760
[test_givenRiskMarketSetter_whenQueued_reverts]: ./queueBatch.t.sol#L772
[test_givenNonselectedRisk_whenQueued_reverts]: ./queueBatch.t.sol#L784
[test_givenAdminOnlyRiskSelectors_whenQueued_reverts]: ./queueBatch.t.sol#L796
[test_givenConfigAndRiskActions_whenBatched_thenIndependentTargets]: ./queueBatch.t.sol#L1165
[test_givenRiskOperatorDifferent_whenConfigOnlyBatchQueued_thenAccepted]: ./queueBatch.t.sol#L1178
[test_givenConfigOperatorRevoked_whenMixedBatchQueued_reverts]: ./queueBatch.t.sol#L1193
[test_givenPendingBatch_whenEachValidSubactionRead_thenExactPayload]: ./queueBatch.t.sol#L1217
[test_givenPendingBatch_whenStateRead_thenIndependentCommitment]: ./queueBatch.t.sol#L1242
[test_givenMissingId_whenStateGettersRead_thenDefaults]: ./queueBatch.t.sol#L1257
[test_givenPendingAction_whenStateIndexOutOfBounds_reverts]: ./queueBatch.t.sol#L1276
[test_givenSTATEP03IndexEndpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueBatch.t.sol#L1317
[test_givenPendingAction_whenPayloadIndexOutOfBounds_reverts]: ./queueBatch.t.sol#L1298
[test_givenACTIONI01IndexEndpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueBatch.t.sol#L1329
[test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts]: ./queueBatch.t.sol#L1410
[test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts]: ./queueBatch.t.sol#L1436
[test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts]: ./queueBatch.t.sol#L1456
