# OperatorAuth `validateAuthorization` scenarios

Source: `src/policies/utils/OperatorAuth.sol`; ABI: `IOperatorAuth`.

Account A owns each grant; designated operator O differs from A; unauthorized signed-acceptance callers exclude only O, so A is also an unauthorized submitter. Actions are uint8 single bits; supported harness mask is 15. Epochs are uint256; deadlines uint48 and inclusive against full-width time. Default time is 100. Default context is zero; custom harness contexts are explicit. Permissions are consumer data, capped at 320 bytes by this harness. No Kernel or ERC-20 accounting belongs to this generic engine. Reverts preserve counters, authority and logs.

Direct approvals permit only A. Signed approvals permit only O, verify before installation, and authenticate every fixed field, permission byte and signature-data byte. Cancellation is scoped to its calling account and bypasses consumer admission. View callers are unrestricted; the requested account/operator identities are validated independently of the viewer.

| ID | Condition / exercised caller and input | Execution / proof | Effects | Test |
| --- | --- | --- | --- | --- |
| OAVALIDATE-P01 | given Original Stamp when Validated | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_givenOriginalStamp_whenValidated] |
| OAVALIDATE-I01 | given Grant when Wrong Stamp reverts | OperatorAuth_InvalidContext | Unchanged after revert | Covered: [test][test_givenGrant_whenWrongStamp_reverts] |
| OAVALIDATE-I02 | when Owner Supplies Nonzero Stamp reverts | OperatorAuth_InvalidContext | Unchanged after revert | Covered: [test][test_whenOwnerSuppliesNonzeroStamp_reverts] |
| OAVALIDATE-P02 | given Captured Stamp when Identical Payload Replaced reverts | OperatorAuth_InvalidContext | Unchanged after revert | Covered: [test][test_givenCapturedStamp_whenIdenticalPayloadReplaced_reverts] |
| OAVALIDATE-L01 | given Use Disabled when Owner Validates reverts | UseDisabled | Unchanged after revert | Covered: [test][test_givenUseDisabled_whenOwnerValidates_reverts] |

## Identity isolation

The second account or operator has its own valid grant with identical permissions and epochs.
Fuzz the second address excluding zero, A and O, which are separate identity/zero-input cases.
Public validation still must reject a stamp captured for the other identity pair.

| ID | Valid grants | Stamp used for validation | Expected result | Test |
| --- | --- | --- | --- | --- |
| OAVALIDATE-A01 | A→O and B→O | A→O stamp supplied for B→O | InvalidContext; both original stamps remain valid and unchanged | [test][test_givenSameOperatorForTwoAccounts_whenOtherAccountStampUsed_reverts] |
| OAVALIDATE-A02 | A→O and A→X | A→O stamp supplied for A→X | InvalidContext; both original stamps remain valid and unchanged | [test][test_givenTwoOperatorsForAccount_whenOtherOperatorStampUsed_reverts] |

[test_givenCapturedStamp_whenIdenticalPayloadReplaced_reverts]: ./validateAuthorization.t.sol#L89
[test_givenGrant_whenWrongStamp_reverts]: ./validateAuthorization.t.sol#L76
[test_givenOriginalStamp_whenValidated]: ./validateAuthorization.t.sol#L65
[test_givenUseDisabled_whenOwnerValidates_reverts]: ./validateAuthorization.t.sol#L98
[test_whenOwnerSuppliesNonzeroStamp_reverts]: ./validateAuthorization.t.sol#L83

[test_givenSameOperatorForTwoAccounts_whenOtherAccountStampUsed_reverts]: ./validateAuthorization.t.sol#L15
[test_givenTwoOperatorsForAccount_whenOtherOperatorStampUsed_reverts]: ./validateAuthorization.t.sol#L40
