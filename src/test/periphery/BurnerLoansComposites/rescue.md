# BurnerLoansComposites rescue scenarios

`rescue(token)` sends the full ERC-20 balance to the current owner. Rescue works while execution is
enabled or disabled and shares the execution reentrancy lock. Amounts are in raw token units.

| ID | Caller | Input / condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCRSC-P01 | Owner | Positive balance, fuzzed through uint256 max | Send the full balance | Owner receives the balance and `TokenRescued` records the transfer | Covered: [test][test_givenBalance_whenOwnerRescues] |
| BLCRSC-P02 | Owner | Execution disabled | Recover one unit | Execution stays disabled | Covered: [test][test_givenDisabled_whenOwnerRescues] |
| BLCRSC-P03 | New owner | Ownership accepted | Recover the token | The current owner receives the balance | Covered: [test][test_givenNewOwner_whenRescuing] |
| BLCRSC-P04 | Owner | Zero token balance | Return without a transfer | Balance stays zero | Covered: [test][test_givenEmptyBalance_whenOwnerRescues] |
| BLCRSC-A01 | Fuzz non-owner | Positive token balance | Reject unauthorized caller | Balance stays intact | Covered: [test][test_whenCallerIsNotOwner_reverts] |
| BLCRSC-A02 | Former owner | Ownership accepted by someone else | Reject unauthorized caller | Balance remains available to the new owner | Covered: [test][test_givenNewOwner_whenRescuing] |
| BLCRSC-I01 | Owner | Token address has no code | Reject invalid token | No transfer | Covered: [test][test_whenTokenHasNoCode_reverts] |
| BLCRSC-T01 | Owner | ERC-20 transfer returns false | Revert | Token balance stays intact | Covered: [test][test_whenTransferFails_reverts] |
| BLCRSC-C01 | Owner in transfer callback | Nested rescue during rescue | Reject via the shared lock | Nested and outer transfers roll back | Covered: [test][test_whenTransferCallsOwnerDuringRescue_reverts] |
| BLCRSC-C02 | Owner in funding callback | Rescue attempted during execution | Reject via the shared lock | Deposit and refund succeed, and the starting balance stays intact | Covered: [test][test_givenReusableGrant_whenOwnerTriesRescueDuringExecution] |

[test_givenBalance_whenOwnerRescues]: ./rescue.t.sol#L19
[test_givenDisabled_whenOwnerRescues]: ./rescue.t.sol#L33
[test_givenNewOwner_whenRescuing]: ./rescue.t.sol#L45
[test_givenEmptyBalance_whenOwnerRescues]: ./rescue.t.sol#L63
[test_whenCallerIsNotOwner_reverts]: ./rescue.t.sol#L70
[test_whenTokenHasNoCode_reverts]: ./rescue.t.sol#L84
[test_whenTransferFails_reverts]: ./rescue.t.sol#L93
[test_whenTransferCallsOwnerDuringRescue_reverts]: ./rescue.t.sol#L108
[test_givenReusableGrant_whenOwnerTriesRescueDuringExecution]: ./rescue.t.sol#L127
