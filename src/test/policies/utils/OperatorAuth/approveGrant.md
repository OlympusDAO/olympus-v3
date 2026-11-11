# OperatorAuth `approveGrant` scenarios

Source: `src/policies/utils/OperatorAuth.sol`; ABI: `IOperatorAuth`.

Account A owns each grant; designated operator O differs from A; unauthorized signed-acceptance callers exclude only O, so A is also an unauthorized submitter. Actions are uint8 single bits; supported harness mask is 15. Epochs are uint256; deadlines uint48 and inclusive against full-width time. Default time is 100. Default context is zero; custom harness contexts are explicit. Permissions are consumer data, capped at 320 bytes by this harness. No Kernel or ERC-20 accounting belongs to this generic engine. Reverts preserve counters, authority and logs.

Direct approvals permit only A. Signed approvals permit only O, verify before installation, and authenticate every fixed field, permission byte and signature-data byte. Cancellation is scoped to its calling account and bypasses consumer admission. View callers are unrestricted; the requested account/operator identities are validated independently of the viewer.

| ID | Condition / exercised caller and input | Execution / proof | Effects | Test |
| --- | --- | --- | --- | --- |
| OAGRANT-A01 | when Unrelated Caller reverts | OperatorAuth_InvalidIdentity | Unchanged after revert | Covered: [test][test_whenUnrelatedCaller_reverts] |
| OAGRANT-I01 | when Operator Zero reverts | OperatorAuth_InvalidIdentity | Unchanged after revert | Covered: [test][test_whenOperatorZero_reverts] |
| OAGRANT-I02 | when Self Grant reverts | OperatorAuth_SelfGrant | Unchanged after revert | Covered: [test][test_whenSelfGrant_reverts] |
| OAGRANT-I03 | when Empty Mask reverts | OperatorAuth_InvalidActions | Unchanged after revert | Covered: [test][test_whenEmptyMask_reverts] |
| OAGRANT-I04 | when Unsupported Mask reverts | OperatorAuth_InvalidActions | Unchanged after revert | Covered: [test][test_whenUnsupportedMask_reverts] |
| OAGRANT-I05 | when Wrong Context reverts | OperatorAuth_InvalidContext | Unchanged after revert | Covered: [test][test_whenWrongContext_reverts] |
| OAGRANT-I06 | when Oversized Permissions reverts | PermissionsTooLong | Unchanged after revert | Covered: [test][test_whenOversizedPermissions_reverts] |
| OAGRANT-L01 | given Creation Disabled when Approved reverts | CreationDisabled | Unchanged after revert | Covered: [test][test_givenCreationDisabled_whenApproved_reverts] |
| OAGRANT-N01 | when Deadline Inclusive | OperatorAuth_ExpiredGrant | Asserted epochs, authority or returned data | Covered: [test][test_whenDeadlineInclusive] |
| OAGRANT-N02 | when Full Width Timestamp Exceeds Uint48 reverts | OperatorAuth_ExpiredGrant | Unchanged after revert | Covered: [test][test_whenFullWidthTimestampExceedsUint48_reverts] |
| OAGRANT-N03 | given Pair Max when Approved reverts | OperatorAuth_EpochExhausted | Unchanged after revert | Covered: [test][test_givenPairMax_whenApproved_reverts] |
| OAGRANT-P01 | when Reusable Approved | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenReusableApproved] |
| OAGRANT-P02 | given Context Returns when No Replacement old Record Uses Original Context | OperatorAuth_InvalidContext | Asserted epochs, authority or returned data | Covered: [test][test_givenContextReturns_whenNoReplacement_oldRecordUsesOriginalContext] |
| OAGRANT-P03 | given New Namespace Grant when Old Context Returns reverts | OperatorAuth_InvalidContext | Unchanged after revert | Covered: [test][test_givenNewNamespaceGrant_whenOldContextReturns_reverts] |
| OAGRANT-I07 | when Account Zero reverts | OperatorAuth_InvalidIdentity | Unchanged after revert | Covered: [test][test_whenAccountZero_reverts] |
| OAGRANT-N04 | when Zero Timestamp And Deadline | OperatorAuth_ExpiredGrant | Asserted epochs, authority or returned data | Covered: [test][test_whenZeroTimestampAndDeadline] |
| OAGRANT-N05 | when Pair Immediately Below Max consumes Last Epoch | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenPairImmediatelyBelowMax_consumesLastEpoch] |
| OAGRANT-N06 | when Account Epoch Max acceptance Does Not Increment It | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenAccountEpochMax_acceptanceDoesNotIncrementIt] |
| OAGRANT-N07 | when Maximum Context And Permission Lengths | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenMaximumContextAndPermissionLengths] |
| OAGRANT-N08 | when Empty And Single Byte Permissions | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenEmptyAndSingleBytePermissions] |
| OATEMP-P01 | when Accepting Transaction Contains Repeated Actions consumes One Epoch | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenAcceptingTransactionContainsRepeatedActions_consumesOneEpoch] |
| OATEMP-P02 | given Temporary Grant when Second Transaction Same Block reverts | OperatorAuth_InvalidContext | Unchanged after revert | Covered: [test][test_givenTemporaryGrant_whenSecondTransactionSameBlock_reverts] |
| OATEMP-P03 | given Reusable Grant when Temporary Replacement Ends old Grant Cannot Revive | OperatorAuth_InvalidContext | Asserted epochs, authority or returned data | Covered: [test][test_givenReusableGrant_whenTemporaryReplacementEnds_oldGrantCannotRevive] |
| OATEMP-P04 | given Temporary when Reusable Replaces In Same Transaction new Record Selected | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_givenTemporary_whenReusableReplacesInSameTransaction_newRecordSelected] |
| OATEMP-P05 | when Temporary Payload Shrinks no Stale Tail | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenTemporaryPayloadShrinks_noStaleTail] |
| OATEMP-C01 | when Accepting Frame Reverts epoch And Payload Rollback | OperatorAuth_InvalidContext | Asserted epochs, authority or returned data | Covered: [test][test_whenAcceptingFrameReverts_epochAndPayloadRollback] |
| OATEMP-C02 | when Later Action Failure Caught prior Acceptance Survives | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenLaterActionFailureCaught_priorAcceptanceSurvives] |
| OATEMP-C03 | given Original Authority when Replacement Completion Fails rolls Back Replacement | OperatorAuth_InvalidContext | Asserted epochs, authority or returned data | Covered: [test][test_givenOriginalAuthority_whenReplacementCompletionFails_rollsBackReplacement] |
| OADEFAULT-P01 | when Default Consumer Approves no Core Required | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenDefaultConsumerApproves_noCoreRequired] |
| OAINV-P01 | epochs Match Independent Accounts And Pairs | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][invariant_epochsMatchIndependentAccountsAndPairs] |
| OAINV-P02 | only Current Reusable Authority Survives Transactions; getter matches model | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][invariant_onlyCurrentReusableAuthoritySurvivesTransactions] |
| OAINV-P03 | when Temporary Handler Accepts | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenTemporaryHandlerAccepts] |
| OAINV-P04 | when Accepting Actor Returns temporary Authority Remains In Parent Frame | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenAcceptingActorReturns_temporaryAuthorityRemainsInParentFrame] |
| OAGRANT-P10 | Account A approves temporary/reusable grant | Exact GrantAccepted emitter, indexed identities, metadata and permission hash | Epoch advances normally | Covered: [test][test_whenApproved_emitsPermissionsHash] |
| OAGRANT-P11 | Account approves temporary grant; fuzz permission length 0..320 and bytes; explicit 0/1/31/32/33/319/320 seeds | Exact whole-grant ABI roundtrip and captured authorization permissions, including unaligned payloads | Pair epoch advances once | Covered: [fuzz][test_whenTemporaryPermissionLengthVaries], [boundary seeds][test_whenTemporaryPermissionLengthBoundarySeeds] |

The stateful campaign uses two account actors, two operators, three contexts, reusable and temporary approvals, targeted cancellation and account-wide cancellation. Its independent model checks local counters and surviving reusable authority after each transaction. Temporary checks run inside the accepting actor because this checkout enables Forge call isolation; the separately named actor-return unit and external Anvil verification cover cross-frame lifetime. The campaign does not establish multi-transaction temporary storage behavior by itself. Separate Prague Anvil transactions verified that authority survives the accepting actor RETURN, and that a second transaction in the same manually mined block cannot use it; evidence is recorded in `.context/auth-implementation/verified-transaction-lifetimes.json`.

[invariant_epochsMatchIndependentAccountsAndPairs]: ./authorization.invariants.t.sol#L28
[invariant_onlyCurrentReusableAuthoritySurvivesTransactions]: ./authorization.invariants.t.sol#L49
[test_givenContextReturns_whenNoReplacement_oldRecordUsesOriginalContext]: ./approveGrant.t.sol#L215
[test_givenCreationDisabled_whenApproved_reverts]: ./approveGrant.t.sol#L140
[test_givenNewNamespaceGrant_whenOldContextReturns_reverts]: ./approveGrant.t.sol#L230
[test_givenOriginalAuthority_whenReplacementCompletionFails_rollsBackReplacement]: ./approveGrant.t.sol#L440
[test_givenPairMax_whenApproved_reverts]: ./approveGrant.t.sol#L186
[test_givenReusableGrant_whenTemporaryReplacementEnds_oldGrantCannotRevive]: ./approveGrant.t.sol#L376
[test_givenTemporaryGrant_whenSecondTransactionSameBlock_reverts]: ./approveGrant.t.sol#L366
[test_givenTemporary_whenReusableReplacesInSameTransaction_newRecordSelected]: ./approveGrant.t.sol#L390
[test_whenAcceptingActorReturns_temporaryAuthorityRemainsInParentFrame]: ./approveGrant.t.sol#L467
[test_whenAcceptingFrameReverts_epochAndPayloadRollback]: ./approveGrant.t.sol#L413
[test_whenAcceptingTransactionContainsRepeatedActions_consumesOneEpoch]: ./approveGrant.t.sol#L355
[test_whenAccountEpochMax_acceptanceDoesNotIncrementIt]: ./approveGrant.t.sol#L284
[test_whenAccountZero_reverts]: ./approveGrant.t.sol#L241
[test_whenApproved_emitsPermissionsHash]: ./approveGrant.t.sol#L60
[test_whenDeadlineInclusive]: ./approveGrant.t.sol#L151
[test_whenDefaultConsumerApproves_noCoreRequired]: ./approveGrant.t.sol#L338
[test_whenEmptyAndSingleBytePermissions]: ./approveGrant.t.sol#L318
[test_whenEmptyMask_reverts]: ./approveGrant.t.sol#L95
[test_whenFullWidthTimestampExceedsUint48_reverts]: ./approveGrant.t.sol#L172
[test_whenLaterActionFailureCaught_priorAcceptanceSurvives]: ./approveGrant.t.sol#L426
[test_whenMaximumContextAndPermissionLengths]: ./approveGrant.t.sol#L300
[test_whenOperatorZero_reverts]: ./approveGrant.t.sol#L77
[test_whenOversizedPermissions_reverts]: ./approveGrant.t.sol#L131
[test_whenPairImmediatelyBelowMax_consumesLastEpoch]: ./approveGrant.t.sol#L268
[test_whenReusableApproved]: ./approveGrant.t.sol#L195
[test_whenSelfGrant_reverts]: ./approveGrant.t.sol#L86
[test_whenTemporaryHandlerAccepts]: ./approveGrant.t.sol#L460
[test_whenTemporaryPayloadShrinks_noStaleTail]: ./approveGrant.t.sol#L404
[test_whenUnrelatedCaller_reverts]: ./approveGrant.t.sol#L67
[test_whenUnsupportedMask_reverts]: ./approveGrant.t.sol#L108
[test_whenWrongContext_reverts]: ./approveGrant.t.sol#L122
[test_whenZeroTimestampAndDeadline]: ./approveGrant.t.sol#L250
[test_whenTemporaryPermissionLengthVaries]: ./approveGrant.t.sol#L27
[test_whenTemporaryPermissionLengthBoundarySeeds]: ./approveGrant.t.sol#L50
