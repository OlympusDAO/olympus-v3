# OperatorAuth `captureAuthorization` scenarios

Source: `src/policies/utils/OperatorAuth.sol`; ABI: `IOperatorAuth`.

Account A owns each grant; designated operator O differs from A; unauthorized signed-acceptance callers exclude only O, so A is also an unauthorized submitter. Actions are uint8 single bits; supported harness mask is 15. Epochs are uint256; deadlines uint48 and inclusive against full-width time. Default time is 100. Default context is zero; custom harness contexts are explicit. Permissions are consumer data, capped at 320 bytes by this harness. No Kernel or ERC-20 accounting belongs to this generic engine. Reverts preserve counters, authority and logs.

Direct approvals permit only A. Signed approvals permit only O, verify before installation, and authenticate every fixed field, permission byte and signature-data byte. Cancellation is scoped to its calling account and bypasses consumer admission. View callers are unrestricted; the requested account/operator identities are validated independently of the viewer.

| ID | Condition / exercised caller and input | Execution / proof | Effects | Test |
| --- | --- | --- | --- | --- |
| OACAPTURE-P01 | when Owner Captures has Intrinsic Authority | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenOwnerCaptures_hasIntrinsicAuthority] |
| OACAPTURE-I01 | when Owner Checks Unsupported Action reverts | OperatorAuth_InvalidAction | Unchanged after revert | Covered: [test][test_whenOwnerChecksUnsupportedAction_reverts] |
| OACAPTURE-I02 | when Owner Checks Composite Action reverts | OperatorAuth_InvalidAction | Unchanged after revert | Covered: [test][test_whenOwnerChecksCompositeAction_reverts] |
| OACAPTURE-I03 | when Owner Checks Zero Action reverts | OperatorAuth_InvalidAction | Unchanged after revert | Covered: [test][test_whenOwnerChecksZeroAction_reverts] |
| OACAPTURE-I04 | when Zero Identities reverts | OperatorAuth_InvalidIdentity | Unchanged after revert | Covered: [test][test_whenZeroIdentities_reverts] |
| OACAPTURE-I05 | given No Grant when Captured reverts | OperatorAuth_InvalidContext | Unchanged after revert | Covered: [test][test_givenNoGrant_whenCaptured_reverts] |
| OACAPTURE-A01 | given Grant To Operator when Other Operator Captured reverts | OperatorAuth_InvalidContext | Unchanged after revert | Covered: [test][test_givenGrantToOperator_whenOtherOperatorCaptured_reverts] |
| OACAPTURE-P02 | given Grant when Unrelated Viewer Checks same Authority | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_givenGrant_whenUnrelatedViewerChecks_sameAuthority] |

## Delegation does not propagate

| ID | Valid grants | Attempt | Expected result | Test |
| --- | --- | --- | --- | --- |
| OACAPTURE-A02 | A→O and O→X; fuzz X excluding zero/A/O | Capture A→X authority | InvalidContext; A→O and O→X remain valid and unchanged | [test][test_givenOperatorGrantsAnotherOperator_whenOriginalAccountCaptured_reverts] |

[test_givenGrantToOperator_whenOtherOperatorCaptured_reverts]: ./captureAuthorization.t.sol#L97
[test_givenGrant_whenUnrelatedViewerChecks_sameAuthority]: ./captureAuthorization.t.sol#L105
[test_givenNoGrant_whenCaptured_reverts]: ./captureAuthorization.t.sol#L91
[test_whenOwnerCaptures_hasIntrinsicAuthority]: ./captureAuthorization.t.sol#L41
[test_whenOwnerChecksCompositeAction_reverts]: ./captureAuthorization.t.sol#L69
[test_whenOwnerChecksUnsupportedAction_reverts]: ./captureAuthorization.t.sol#L58
[test_whenOwnerChecksZeroAction_reverts]: ./captureAuthorization.t.sol#L77
[test_whenZeroIdentities_reverts]: ./captureAuthorization.t.sol#L85

[test_givenOperatorGrantsAnotherOperator_whenOriginalAccountCaptured_reverts]: ./captureAuthorization.t.sol#L14
