# OperatorAuth `cancelGrant` scenarios

Source: `src/policies/utils/OperatorAuth.sol`; ABI: `IOperatorAuth`.

Account A owns each grant; designated operator O differs from A; unauthorized signed-acceptance callers exclude only O, so A is also an unauthorized submitter. Actions are uint8 single bits; supported harness mask is 15. Epochs are uint256; deadlines uint48 and inclusive against full-width time. Default time is 100. Default context is zero; custom harness contexts are explicit. Permissions are consumer data, capped at 320 bytes by this harness. No Kernel or ERC-20 accounting belongs to this generic engine. Reverts preserve counters, authority and logs.

Direct approvals permit only A. Signed approvals permit only O, verify before installation, and authenticate every fixed field, permission byte and signature-data byte. Cancellation is scoped to its calling account and bypasses consumer admission. View callers are unrestricted; the requested account/operator identities are validated independently of the viewer.

| ID | Condition / exercised caller and input | Execution / proof | Effects | Test |
| --- | --- | --- | --- | --- |
| OACANCEL-P01 | given Grant when Cancelled invalidates Original | OperatorAuth_InvalidContext | Asserted epochs, authority or returned data | Covered: [test][test_givenGrant_whenCancelled_invalidatesOriginal] |
| OACANCEL-A01 | given Grant when Unrelated Account Cancels authority Unchanged | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_givenGrant_whenUnrelatedAccountCancels_authorityUnchanged] |
| OACANCEL-L01 | given Admission Disabled when Cancelled | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_givenAdmissionDisabled_whenCancelled] |
| OACANCEL-N01 | given Pair Max when Cancelled reverts | OperatorAuth_EpochExhausted | Unchanged after revert | Covered: [test][test_givenPairMax_whenCancelled_reverts] |
| OACANCEL-P02 | when Other Operator Cancelled preserves Current Pair | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenOtherOperatorCancelled_preservesCurrentPair] |
| OACANCEL-I01 | Account A cancels zero operator | OperatorAuth_InvalidIdentity | Pair epoch unchanged | Covered: [test][test_whenZeroOperator_reverts] |
| OACANCEL-I02 | Fuzz account A cancels itself, excluding zero (covered separately) | OperatorAuth_SelfGrant | Pair epoch unchanged | Covered: [fuzz][test_whenSelfOperator_reverts] |

[test_givenAdmissionDisabled_whenCancelled]: ./cancelGrant.t.sol#L59
[test_givenGrant_whenCancelled_invalidatesOriginal]: ./cancelGrant.t.sol#L31
[test_givenGrant_whenUnrelatedAccountCancels_authorityUnchanged]: ./cancelGrant.t.sol#L43
[test_givenPairMax_whenCancelled_reverts]: ./cancelGrant.t.sol#L69
[test_whenOtherOperatorCancelled_preservesCurrentPair]: ./cancelGrant.t.sol#L77
[test_whenSelfOperator_reverts]: ./cancelGrant.t.sol#L22
[test_whenZeroOperator_reverts]: ./cancelGrant.t.sol#L14
