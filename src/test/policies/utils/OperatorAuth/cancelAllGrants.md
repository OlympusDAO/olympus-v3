# OperatorAuth `cancelAllGrants` scenarios

Source: `src/policies/utils/OperatorAuth.sol`; ABI: `IOperatorAuth`.

Account A owns each grant; designated operator O differs from A; unauthorized signed-acceptance callers exclude only O, so A is also an unauthorized submitter. Actions are uint8 single bits; supported harness mask is 15. Epochs are uint256; deadlines uint48 and inclusive against full-width time. Default time is 100. Default context is zero; custom harness contexts are explicit. Permissions are consumer data, capped at 320 bytes by this harness. No Kernel or ERC-20 accounting belongs to this generic engine. Reverts preserve counters, authority and logs.

Direct approvals permit only A. Signed approvals permit only O, verify before installation, and authenticate every fixed field, permission byte and signature-data byte. Cancellation is scoped to its calling account and bypasses consumer admission. View callers are unrestricted; the requested account/operator identities are validated independently of the viewer.

| ID | Condition / exercised caller and input | Execution / proof | Effects | Test |
| --- | --- | --- | --- | --- |
| OAALL-P01 | given Grant when Cancelled preserves Pairs | OperatorAuth_InvalidContext | Asserted epochs, authority or returned data | Covered: [test][test_givenGrant_whenCancelled_preservesPairs] |
| OAALL-P02 | given Future Pair Signature when Account Cancelled reverts | OperatorAuth_InvalidEpoch | Unchanged after revert | Covered: [test][test_givenFuturePairSignature_whenAccountCancelled_reverts] |
| OAALL-L01 | given Admission Disabled when Cancelled | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_givenAdmissionDisabled_whenCancelled] |
| OAALL-N01 | given Account Max when Cancelled reverts | OperatorAuth_EpochExhausted | Unchanged after revert | Covered: [test][test_givenAccountMax_whenCancelled_reverts] |

[test_givenAccountMax_whenCancelled_reverts]: ./cancelAllGrants.t.sol#L48
[test_givenAdmissionDisabled_whenCancelled]: ./cancelAllGrants.t.sol#L39
[test_givenFuturePairSignature_whenAccountCancelled_reverts]: ./cancelAllGrants.t.sol#L25
[test_givenGrant_whenCancelled_preservesPairs]: ./cancelAllGrants.t.sol#L14
