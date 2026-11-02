# BurnerLoansPayoutConfigTimelock.queueBatch coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Coverage records implemented domains and assertions independently of pass/fail status.

Source: [queueBatch](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L189).

## Domains and notation

Scenario scope: `BLCUCT-BATCH`. Valid default: real same-Kernel Payout, stored controller=this timelock, cached ROLES initialized, Local active=true and Local enabled=true. Payout has IEnabler, but recovery ignores its paused state; Core lifecycle and selection do not block recovery from an active Payout; its local pause is allowed. Recovery previews reject an inactive Payout. Core must be idle for target mutations. Permitted proposers hold ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE; fuzz each exclusive class and overlap; distributor replacement is direct ADMIN-only and is not admitted by this queue or batches.

Unchanged means authoritative state, balances, allowances and committed logs applicable to this function remain unchanged. Faults are isolated with all other prerequisites satisfied. Use [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md); preserve independent lifecycle columns and guaranteed numeric boundary seeds.

For every successful queue, independently fuzz the getter caller and assert getQueuedAction's proposer/timestamps/pending flags and exact ordered actions; getQueuedActionLength equals the input length; getQueuedSubAction returns each exact target/selector/payload. Each getQueuedConfigDestination is the bound Payout, getQueuedConfigStateCount is one, and getQueuedConfigState returns the independently expected destination-scoped key and pre-state hash. pendingActionId records this ID and nextActionId increments once. Capture expected hashes from the documented controller/flag/distributor/Treasury tuple, not from the getter being tested. No target setter, token movement or entitlement debit occurs.

Stored reads remain usable when timelock, Core and Payout activity/enabled flags change independently after queueing and target getters reject unexpected calls. At successful length boundaries, query valid first/last sub-actions; fuzz invalid subIndex in length..MAX256 with seeds length,MAX256: getQueuedSubAction rejects SubActionIndexOutOfBounds(id,subIndex,length), while config destination/count return zero and config-state lookup rejects ConfigStateIndexOutOfBounds(id,subIndex,stateIndex,0). For each existing sub-action, fuzz stateIndex in 1..MAX256 with seeds 1,MAX256: getQueuedConfigState rejects ConfigStateIndexOutOfBounds(id,subIndex,stateIndex,1). These assertions belong to the successful queue cases below, including the final usable ID; unknown and terminal actions are asserted with execute/cancel scenarios.

## Batch length

A maximum-uint256 array cannot be materialized within the EVM memory/gas budget; test practical out-of-range lengths instead of inventing an unreachable fixture.

| ID | Caller | Length / setup | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-BATCH-N01 | Fuzz ADMIN proposer identity | 0 | ITimelockBatchQueue_BatchEmpty() after local activity, enablement and proposer admission | No ID/key/log consumption | Covered: [test_whenBatchEmpty_reverts](queueBatch.t.sol#L57) |
| BLCUCT-BATCH-N02 | Fuzz ADMIN proposer identity | Fuzz16..64; seed16,64 | BatchTooLarge(length,15) after local activity, enablement and proposer admission | Unchanged | Covered: [test_whenBatchOversized_reverts](queueBatch.t.sol#L67), [test_whenBatchBoundarySeedsUsed](queueBatch.t.sol#L620) |
| BLCUCT-BATCH-N03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Fuzz1..15 distinct valid keys; seed1,15 | Success | Exact count/payload/key owners and co-located getter assertions, including valid/invalid index bounds; one nextActionId increment | Covered: [test_whenValidBatchQueued_thenExactState](queueBatch.t.sol#L85), [test_whenBatchBoundarySeedsUsed](queueBatch.t.sol#L620) |

## Local lifecycle

Valid batch size; initialized ROLES.

| ID | Caller | Local active | Local enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-BATCH-L01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | true | true | Admitted with valid inputs | Queue-only effects | Covered: [test_whenValidBatchQueued_thenExactState](queueBatch.t.sol#L85) |
| BLCUCT-BATCH-L02 | Fuzz all callers | true | false | NotEnabled() | Unchanged | Covered: [test_givenActiveDisabled_whenBatchQueued_reverts](queueBatch.t.sol#L199) |
| BLCUCT-BATCH-L03 | Fuzz all callers | false | true | BurnerLoans_PolicyNotActive(BurnerLoansPayoutConfigTimelock) | Unchanged | Covered: [test_givenInactive_whenBatchQueued_reverts](queueBatch.t.sol#L222) |
| BLCUCT-BATCH-L04 | Fuzz all callers | false | false | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test_givenInactiveDisabled_whenBatchQueued_reverts](queueBatch.t.sol#L209) |

## Caller and target authority

Local active/enabled; target same Kernel. Both exclusive proposer roles and overlap are seeded.

| ID | Caller | Batch / fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-BATCH-A01 | Fuzz outside ADMIN/BL admin holders | Valid targets and malformed payloads separately | NotAuthorised() before sub-action checks | Unchanged | Covered: [test_givenUnauthorized_whenBatchQueued_reverts](queueBatch.t.sol#L235) |
| BLCUCT-BATCH-A02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Payout no longer selects this controller | NotAuthorised() | Unchanged | Covered: [test_givenOtherController_whenBatchQueued_reverts](queueBatch.t.sol#L250) |
| BLCUCT-BATCH-A03 | Fuzz ADMIN-only, BL admin-only and overlap | Batch includes Payout.setRevenueDistributor | ITimelockBatchQueue_ActionInvalid(Payout,selector) | No queue ID/key/event, even after an earlier valid entry | Covered: [test_whenSelectorNotAllowed_reverts](queueBatch.t.sol#L320), [test_whenFlagDisableThenDistributorClearBatched_reverts](queueBatch.t.sol#L542) |
| BLCUCT-BATCH-A04 | Fuzz ADMIN-only, BL admin-only and overlap | Mixed valid fee/yield flag and recovery requests | Success subject to independent keys and live validation | No ADMIN grant on forwarding timelock | Covered: [test_whenValidBatchQueued_thenExactState](queueBatch.t.sol#L85), [test_whenMixedRecoveryAndFlagsQueued_thenIndependentKeys](queueBatch.t.sol#L478) |

## Dependency binding

Own admission and controller selection pass.

| ID | Caller | Fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-BATCH-D01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Bound Payout reports another Kernel | PolicyDependency_KernelMismatch(Payout,expectedKernel,reportedKernel) | No queue changes | Covered: [test_givenOtherKernel_whenBatchQueued_reverts](queueBatch.t.sol#L265) |
| BLCUCT-BATCH-D02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Bound Payout active but deselected; Core inactive/disabled and Payout local enabled state vary independently | Success with valid requests | Concrete old target preserved; no reverse Core lifecycle checks | Covered: [test_givenDeselectedActiveTarget_whenBatchQueued_thenOriginalTarget](queueBatch.t.sol#L285) |

## Selectors and payload encodings

Canonical lengths: fee/yield flags32 bytes; surplus rescue64 bytes; pending rescue128 bytes. Distributor replacement is not an admitted selector. Pending amount is full uint256, so MAX256 is canonical subject to real entitlement.

| ID | Caller | Invalid sub-action | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-BATCH-I01 | Fuzz ADMIN proposer | Target zero | ActionInvalid(target,selector) | Whole queue rollback | Covered: [test_whenWrongTarget_reverts](queueBatch.t.sol#L306), [test_whenBatchBoundarySeedsUsed](queueBatch.t.sol#L620) |
| BLCUCT-BATCH-I02 | Fuzz ADMIN proposer | Target nonzero EOA | ActionInvalid(target,selector) | Whole queue rollback | Covered: [test_whenWrongTarget_reverts](queueBatch.t.sol#L306), [test_whenBatchBoundarySeedsUsed](queueBatch.t.sol#L620) |
| BLCUCT-BATCH-I03 | Fuzz ADMIN proposer | Target another deployed Payout | ActionInvalid(target,selector) | Whole queue rollback | Covered: [test_whenWrongTarget_reverts](queueBatch.t.sol#L306), [test_whenBatchBoundarySeedsUsed](queueBatch.t.sol#L620) |
| BLCUCT-BATCH-I04 | Fuzz ADMIN proposer | Unsupported selector; exclude the four allowed selectors | ActionInvalid(target,selector) | Whole queue rollback | Covered: [test_whenSelectorNotAllowed_reverts](queueBatch.t.sol#L320), [test_whenBatchBoundarySeedsUsed](queueBatch.t.sol#L620) |
| BLCUCT-BATCH-I05 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Each allowed selector with empty, expected-length-1 and expected-length+1 payloads | ActionInvalid(target,selector) | Validation never dispatches target setter | Covered: [test_whenEachPayloadLengthInvalid_reverts](queueBatch.t.sol#L337) |
| BLCUCT-BATCH-I06 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Boolean word in2..MAX256; fixed32 bytes | ActionInvalid(target,selector) | No noncanonical bool admitted | Covered: [test_whenBooleanNoncanonical_reverts](queueBatch.t.sol#L358), [test_whenBatchBoundarySeedsUsed](queueBatch.t.sol#L620) |
| BLCUCT-BATCH-I08 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Surplus-rescue token word exceeds160 bits; destination valid | ActionInvalid(target,selector) | No preview call | Covered: [test_whenAddressWordNoncanonical_reverts](queueBatch.t.sol#L377), [test_whenBatchBoundarySeedsUsed](queueBatch.t.sol#L620) |
| BLCUCT-BATCH-I09 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Surplus-rescue destination word exceeds160 bits; token valid | ActionInvalid(target,selector) | No preview call | Covered: [test_whenAddressWordNoncanonical_reverts](queueBatch.t.sol#L377), [test_whenBatchBoundarySeedsUsed](queueBatch.t.sol#L620) |
| BLCUCT-BATCH-I10 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Pending-rescue token word exceeds160 bits; other words valid | ActionInvalid(target,selector) | No preview call | Covered: [test_whenAddressWordNoncanonical_reverts](queueBatch.t.sol#L377), [test_whenBatchBoundarySeedsUsed](queueBatch.t.sol#L620) |
| BLCUCT-BATCH-I11 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Pending-rescue recipient word exceeds160 bits; other words valid | ActionInvalid(target,selector) | No preview call | Covered: [test_whenAddressWordNoncanonical_reverts](queueBatch.t.sol#L377), [test_whenBatchBoundarySeedsUsed](queueBatch.t.sol#L620) |
| BLCUCT-BATCH-I12 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Pending-rescue destination word exceeds160 bits; other words valid | ActionInvalid(target,selector) | No preview call | Covered: [test_whenAddressWordNoncanonical_reverts](queueBatch.t.sol#L377), [test_whenBatchBoundarySeedsUsed](queueBatch.t.sol#L620) |

## Key ownership and coupled routes

| ID | Caller | Batch / existing queue | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-BATCH-P01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Same selector/key repeated in a batch, same and different payloads | ConfigKeyPending(key,owningId) | First provisional key/ID/log rolls back | Covered: [test_whenDuplicateKeysInBatch_reverts](queueBatch.t.sol#L432) |
| BLCUCT-BATCH-P02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Key already owned by another pending or expired action | ConfigKeyPending(key,owningId) | Original queue untouched; expiry does not release key | Covered: [test_givenExistingKey_whenBatchQueued_reverts](queueBatch.t.sol#L455) |
| BLCUCT-BATCH-P03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Disable fee and yield flags together, both orders | Success | Independent keys/hashes and exact false payloads; flags remain unchanged at queue time | Covered: [test_whenFeeAndYieldFlagsAreDisabledInOneBatch_thenKeysAreIndependent](queueBatch.t.sol#L26), [test_whenDisableFlagsQueuedInEitherOrder_thenIndependentKeys](queueBatch.t.sol#L514) |
| BLCUCT-BATCH-P04 | Fuzz ADMIN-only, BL admin-only and overlap | Batch disables flags then attempts distributor clear | ITimelockBatchQueue_ActionInvalid(Payout,setRevenueDistributor) | Whole queue rolls back; ADMIN clears directly after delayed flags execute | Covered: [test_whenFlagDisableThenDistributorClearBatched_reverts](queueBatch.t.sol#L542) |
| BLCUCT-BATCH-P05 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Same token: surplus rescue and pending rescue; different selectors/valid recipients | Success with independent keys | Queue performs no transfer or entitlement debit | Covered: [test_whenMixedRecoveryAndFlagsQueued_thenIndependentKeys](queueBatch.t.sol#L478) |

## Counter and timestamp bounds

Use focused boundary storage/time fixtures; avoid a new counter framework.

| ID | Caller | Boundary | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-BATCH-N04 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | nextActionId=MAX64-1 focused counter fixture | One final usable ID; nextActionId=MAX64 | No wraparound | Covered: [test_givenFinalUsableId_whenQueued_thenNoWrap](queueBatch.t.sol#L578) |
| BLCUCT-BATCH-N05 | Fuzz all callers | nextActionId=MAX64; valid batch length | Current Panic(0x11) before queue authorization | No keys/action/logs; typed counter error remains a separate shared-base design decision | Covered: [test_givenExhaustedId_whenQueued_reverts](queueBatch.t.sol#L593) |
| BLCUCT-BATCH-N06 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | queuedAt+delay or executableAt+3 days exceedsMAX48, separately | Current Panic(0x11) | Rollback earlier provisional keys/counter/logs | Covered: [test_givenTimestampOverflow_whenQueued_reverts](queueBatch.t.sol#L604) |

- [x] Derive concrete acceptance criteria from the implemented call path.
- [x] Implement focused tests and map exact domains/effects; execution results are tracked separately.

## Admission precedence regressions

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-BATCH-L05 | Fuzz all callers | false | Fuzz false/true | ROLES code rejects; empty batch where exposed | BurnerLoans_PolicyNotActive(TL) | No ID, guard, payload or committed log | Covered: [test][test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts] |
| BLCUCT-BATCH-L06 | Fuzz all callers | true | false | ROLES code rejects; empty batch where exposed | NotEnabled() | No ID, guard, payload or committed log | Covered: [test][test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts] |
| BLCUCT-BATCH-A05 | Fuzz outside both accepted proposer roles | true | true | Target inactive or required metadata rejects; empty batch where exposed | NotAuthorised() | No ID, guard, payload or committed log | Covered: [test][test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts] |
| BLCUCT-BATCH-D03 | ADMIN proposer; fuzz identity | true | true | Payout inactive; fuzz Payout local enabled state | BurnerLoans_PolicyNotActive(Payout) | No queue or custody changes | Covered: [test][test_givenInactivePayout_whenRescueBatchQueued_reverts] |

[test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts]: ./queueBatch.t.sol#L672
[test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts]: ./queueBatch.t.sol#L698
[test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts]: ./queueBatch.t.sol#L718
[test_givenInactivePayout_whenRescueBatchQueued_reverts]: ./queueBatch.t.sol#L745
