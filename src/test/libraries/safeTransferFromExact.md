# safeTransferFromExact scenario plan

Scope: new SafeERC20Exact library through SafeERC20Harness; production callers own their callback/reentrancy protection.

## Domains and assertions

Debt, custody and transfer quantities are uint256 token base units; `MAX` means `type(uint256).max`.

Harness is permissionless; caller irrelevant to token sender authorization. amount and balances are uint256 token base units; constrain minted existingBalance+amount<=MAX for valid standard-token cases. Zero still calls token transferFrom; same-address sender/recipient does not increase balance for positive amount.

Success returns independently recorded recipient balance before transfer, and recipient delta equals requested amount. Revert rolls back token balances, allowance changes and token logs. Helper emits no own event; dependency errors must match actual token/SafeERC20 errors.

## Behavior

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| EXACT-P01 | Any harness caller, fuzz | Fuzz existing balance and positive amount with total<=MAX; seed amount=0,1,MAX and nonzero existing balance where compatible | Return pre-transfer recipient balance | Exact sender/recipient deltas | Covered: [evidence][test_givenRecipientHasExistingBalance_whenTransferIsExact], [evidence][test_whenAmountIsZero_preservesBalances], [evidence][test_whenAmountIsOne_transfersExactAmount], [evidence][test_whenAmountIsMaximum_transfersExactAmount] |

## Invalid inputs

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| EXACT-I01 | Any harness caller, fuzz | Token credits less/more than requested; recipient balance decreases; amount positive and zero where feasible | SafeERC20Exact_InexactTransferFrom(token,recipient,requested,received); received=0 for decreasing balance | Atomic balances/allowance rollback | Covered: [evidence][test_givenFeeOnTransferToken_reverts], [evidence][test_givenTokenOvercreditsRecipient_revertsAndRollsBack], [evidence][test_givenRecipientBalanceDecreases_revertsAndRollsBack], [evidence][test_givenRecipientBalanceDecreases_whenAmountIsZero_revertsAndRollsBack] |
| EXACT-I02 | Any harness caller, fuzz | Positive amount; sender=recipient | SafeERC20Exact_InexactTransferFrom(token,recipient,amount,0) on standard token | Atomic rollback | Covered: [evidence][test_whenSenderEqualsRecipient_revertsAndRollsBack] |

## Transfers

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| EXACT-T05 | Any harness caller, fuzz | Contract transferFrom returns no data after exact balance movement | Success; return pre-transfer recipient balance | Exact sender/recipient/allowance effects | Covered: [evidence][test_whenTransferFromReturnsNoDataAfterExactTransfer_succeeds] |
| EXACT-T06 | Any harness caller, fuzz | Contract transferFrom returns malformed/noncanonical success data | SafeERC20FailedOperation(token) | Balance/allowance/token-event rollback | Covered: [evidence][test_whenTransferFromReturnsShortData_revertsAndRollsBack], [evidence][test_whenTransferFromReturnsNoncanonicalWord_revertsAndRollsBack] |
| EXACT-T01 | Any harness caller, fuzz | Contract transferFrom returns false | SafeERC20FailedOperation(token) | Balance/allowance/token-event rollback | Covered: [evidence][test_whenTransferFromReturnsFalse_revertsAndRollsBack] |
| EXACT-T04 | Any harness caller, fuzz | Contract transferFrom reverts with controlled token custom error | Bubble exact token error | Balance/allowance/token-event rollback | Covered: [evidence][test_whenTransferFromReverts_bubblesAndRollsBack] |

## Balance query failures

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| EXACT-T02 | Any harness caller, fuzz | Pre-transfer balanceOf reverts with a controlled custom error or returns malformed/empty data; include token with no code | Bubble controlled query error or dependency ABI decode failure (empty revert for a no-code token); transferFrom is never reached | No balance, allowance or token-log change; do not expect SafeERC20FailedOperation | Covered: [evidence][test_givenPreTransferBalanceQueryReverts_bubblesWithoutTransfer], [evidence][test_givenPreTransferBalanceQueryReturnsMalformedData_revertsWithoutTransfer], [evidence][test_whenTokenHasNoCode_revertsBeforeTransfer] |
| EXACT-T03 | Any harness caller, fuzz | Pre-query succeeds, transferFrom completes, post-transfer balanceOf reverts or returns malformed data | Bubble controlled query error or ABI decode failure, as appropriate | Roll back completed transfer, allowance consumption and token logs | Covered: [evidence][test_givenPostTransferBalanceQueryReverts_bubblesAndRollsBack], [evidence][test_givenPostTransferBalanceQueryReturnsMalformedData_revertsAndRollsBack] |

## Callbacks

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| EXACT-C01 | Any harness caller | Transfer callback changes recipient balance; callback caught or propagated | Validate final observed delta; propagated token error bubbles | No reentrancy guard in helper; caller must supply one | Covered: [evidence][test_givenCallbackOvercreditsRecipient_revertsAndRollsBack], [evidence][test_givenCallbackFailureIsCaught_whenTransferIsExact_succeeds], [evidence][test_givenCallbackFailureIsPropagated_bubblesAndRollsBack] |

[test_givenRecipientHasExistingBalance_whenTransferIsExact]: ./safeTransferFromExact.t.sol#L54
[test_whenAmountIsZero_preservesBalances]: ./safeTransferFromExact.t.sol#L85
[test_whenAmountIsOne_transfersExactAmount]: ./safeTransferFromExact.t.sol#L101
[test_whenAmountIsMaximum_transfersExactAmount]: ./safeTransferFromExact.t.sol#L117
[test_givenFeeOnTransferToken_reverts]: ./safeTransferFromExact.t.sol#L138
[test_givenTokenOvercreditsRecipient_revertsAndRollsBack]: ./safeTransferFromExact.t.sol#L174
[test_givenRecipientBalanceDecreases_revertsAndRollsBack]: ./safeTransferFromExact.t.sol#L201
[test_givenRecipientBalanceDecreases_whenAmountIsZero_revertsAndRollsBack]: ./safeTransferFromExact.t.sol#L221
[test_whenSenderEqualsRecipient_revertsAndRollsBack]: ./safeTransferFromExact.t.sol#L243
[test_whenTransferFromReturnsNoDataAfterExactTransfer_succeeds]: ./safeTransferFromExact.t.sol#L272
[test_whenTransferFromReturnsShortData_revertsAndRollsBack]: ./safeTransferFromExact.t.sol#L302
[test_whenTransferFromReturnsNoncanonicalWord_revertsAndRollsBack]: ./safeTransferFromExact.t.sol#L325
[test_whenTransferFromReturnsFalse_revertsAndRollsBack]: ./safeTransferFromExact.t.sol#L346
[test_whenTransferFromReverts_bubblesAndRollsBack]: ./safeTransferFromExact.t.sol#L361
[test_givenPreTransferBalanceQueryReverts_bubblesWithoutTransfer]: ./safeTransferFromExact.t.sol#L374
[test_givenPreTransferBalanceQueryReturnsMalformedData_revertsWithoutTransfer]: ./safeTransferFromExact.t.sol#L400
[test_whenTokenHasNoCode_revertsBeforeTransfer]: ./safeTransferFromExact.t.sol#L424
[test_givenPostTransferBalanceQueryReverts_bubblesAndRollsBack]: ./safeTransferFromExact.t.sol#L433
[test_givenPostTransferBalanceQueryReturnsMalformedData_revertsAndRollsBack]: ./safeTransferFromExact.t.sol#L456
[test_givenCallbackOvercreditsRecipient_revertsAndRollsBack]: ./safeTransferFromExact.t.sol#L479
[test_givenCallbackFailureIsCaught_whenTransferIsExact_succeeds]: ./safeTransferFromExact.t.sol#L510
[test_givenCallbackFailureIsPropagated_bubblesAndRollsBack]: ./safeTransferFromExact.t.sol#L544
