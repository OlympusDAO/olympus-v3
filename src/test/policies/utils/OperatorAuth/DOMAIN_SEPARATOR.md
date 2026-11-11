# OperatorAuth `DOMAIN_SEPARATOR` scenarios

Source: `src/policies/utils/OperatorAuth.sol`; ABI: `IOperatorAuth`.

Account A owns each grant; designated operator O differs from A; unauthorized signed-acceptance callers exclude only O, so A is also an unauthorized submitter. Actions are uint8 single bits; supported harness mask is 15. Epochs are uint256; deadlines uint48 and inclusive against full-width time. Default time is 100. Default context is zero; custom harness contexts are explicit. Permissions are consumer data, capped at 320 bytes by this harness. No Kernel or ERC-20 accounting belongs to this generic engine. Reverts preserve counters, authority and logs.

Direct approvals permit only A. Signed approvals permit only O, verify before installation, and authenticate every fixed field, permission byte and signature-data byte. Cancellation is scoped to its calling account and bypasses consumer admission. View callers are unrestricted; the requested account/operator identities are validated independently of the viewer.

| ID | Condition / exercised caller and input | Execution / proof | Effects | Test |
| --- | --- | --- | --- | --- |
| OADOMAIN-P01 | when Domain Read binds Current Chain And Auth | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenDomainRead_bindsCurrentChainAndAuth] |
| OADOMAIN-P02 | when Chain Changes updates Signature Domain | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenChainChanges_updatesSignatureDomain] |
| OADOMAIN-P03 | given Accepted Grant when Chain Changes keeps Authority | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_givenAcceptedGrant_whenChainChanges_keepsAuthority] |
| OADOMAIN-P04 | when Other Auth Deployed domain Differs | Exact assertions in linked test | Asserted epochs, authority or returned data | Covered: [test][test_whenOtherAuthDeployed_domainDiffers] |

[test_givenAcceptedGrant_whenChainChanges_keepsAuthority]: ./DOMAIN_SEPARATOR.t.sol#L31
[test_whenChainChanges_updatesSignatureDomain]: ./DOMAIN_SEPARATOR.t.sol#L24
[test_whenDomainRead_bindsCurrentChainAndAuth]: ./DOMAIN_SEPARATOR.t.sol#L9
[test_whenOtherAuthDeployed_domainDiffers]: ./DOMAIN_SEPARATOR.t.sol#L43
