# OperatorAuth `constructor` scenarios

Source: `src/policies/utils/OperatorAuth.sol`; ABI: `IOperatorAuth`.

Account A owns each grant; designated operator O differs from A; unauthorized signed-acceptance callers exclude only O, so A is also an unauthorized submitter. Actions are uint8 single bits; supported harness mask is 15. Epochs are uint256; deadlines uint48 and inclusive against full-width time. Default time is 100. Default context is zero; custom harness contexts are explicit. Permissions are consumer data, capped at 320 bytes by this harness. No Kernel or ERC-20 accounting belongs to this generic engine. Reverts preserve counters, authority and logs.

Direct approvals permit only A. Signed approvals permit only O, verify before installation, and authenticate every fixed field, permission byte and signature-data byte. Cancellation is scoped to its calling account and bypasses consumer admission. View callers are unrestricted; the requested account/operator identities are validated independently of the viewer.

| ID | Condition / exercised caller and input | Execution / proof | Effects | Test |
| --- | --- | --- | --- | --- |
| OACONSTRUCT-I01 | when No Supported Actions reverts | OperatorAuth_InvalidActions | Unchanged after revert | Covered: [test][test_whenNoSupportedActions_reverts] |
| OACONSTRUCT-N01 | when Supported Mask Maximum | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenSupportedMaskMaximum] |

[test_whenNoSupportedActions_reverts]: ./constructor.t.sol#L12
[test_whenSupportedMaskMaximum]: ./constructor.t.sol#L20
