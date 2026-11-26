# BurnerLoansPayout.validatePayoutRecipient coverage plan

Source: [validatePayoutRecipient](../../../policies/burnerloans/BurnerLoansPayout.sol#L457).

Payout owns destination admission for credits and retries. Debt and Seize ask the selected Payout
to validate positive referral/keeper destinations in their quote paths. The validator itself is
permissionless and independent of Kernel activity, local enablement, Core state and routing.
Callers skip it for unused zero-valued allocations; direct calls always validate the supplied address.

## Coverage matrix

No numeric amounts, transfers, storage writes or external dependency calls occur. Accounting,
authorization and callback coverage for actual credits/retries stays in those action plans.
Local active and Local enabled vary independently. Unchanged means custody balances, all pending
buckets and aggregate reserves, and token/recipient indexes are preserved.

| ID | Caller | Destination | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-VALIDATE-RECIPIENT-P01 | Fuzz every address | Fuzz every address except zero/Payout | Fuzz bool | Fuzz bool | Success | Unchanged | Covered: [test_whenRecipientValid][test_whenRecipientValid] |
| BLCU-VALIDATE-RECIPIENT-I01 | Fuzz every address | Zero | Fuzz bool | Fuzz bool | BurnerLoansPayout_InvalidRecipient(0) | Unchanged | Covered: [test_whenRecipientZero_reverts][test_whenRecipientZero_reverts] |
| BLCU-VALIDATE-RECIPIENT-I02 | Fuzz every address | Payout | Fuzz bool | Fuzz bool | BurnerLoansPayout_InvalidRecipient(Payout) | Unchanged | Covered: [test_whenRecipientPayout_reverts][test_whenRecipientPayout_reverts] |
| BLCU-VALIDATE-RECIPIENT-P02 | Zero and MAX160 address | Address1 and MAX160 address | true | true | Success | Unchanged | Covered: [test_whenAddressBoundaries][test_whenAddressBoundaries] |
| BLCU-VALIDATE-RECIPIENT-L01 | Permissionless viewer | Valid keeper, zero, Payout at each transition | true→false→true→false→true | true→true→false→false→true | Valid keeper succeeds; zero/Payout reject with InvalidRecipient(address) throughout reactivation/re-enablement | Pending claims unchanged | Covered: [test_givenLifecycleTransitions_whenRecipientValidated][test_givenLifecycleTransitions_whenRecipientValidated] |

[test_whenRecipientValid]: validatePayoutRecipient.t.sol#L13
[test_whenRecipientZero_reverts]: validatePayoutRecipient.t.sol#L28
[test_whenRecipientPayout_reverts]: validatePayoutRecipient.t.sol#L47
[test_whenAddressBoundaries]: validatePayoutRecipient.t.sol#L66
[test_givenLifecycleTransitions_whenRecipientValidated]: validatePayoutRecipient.t.sol#L74
