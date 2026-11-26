# trySafeTransfer scenario plan

Scope: OpenZeppelin trySafeTransfer usage through SafeERC20Harness; production payout callers own accounting and guards.

## Domains and assertions

Debt, custody and transfer quantities are uint256 token base units; `MAX` means `type(uint256).max`.

The helper is fail-soft for ordinary ERC20 transfer failures. uint256 amount in token base units; no contract-specific zero-recipient rule. No fixed gas cap is applied. Returned success follows OpenZeppelin return-data convention, not independent proof of balance movement.

For standard tokens, assert sender/recipient deltas. On failure, assert false without an outer revert and unchanged standard-token balances. Document token-side effects for malicious success/false return fixtures rather than assuming the helper can undo a completed nonreverting token call.

## Transfer amounts

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| TRY-P01 | Any harness caller, fuzz | Standard true-return token; amount fuzz 0..funded balance; guaranteed seeds 0 and 1 | true | Exact transfer balance delta | Covered: [evidence][test_whenStandardTokenAmountIsFunded], [evidence][test_whenAmountIsZero_succeedsWithoutMovingTokens], [evidence][test_whenAmountIsOne_transfersOne] |

## Invalid inputs

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| TRY-I01 | Any harness caller, fuzz | Token is EOA or zero address | false because token has no code | No fabricated transfer or outer revert | Covered: [evidence][test_whenTokenIsZeroAddress_returnsFalse], [evidence][test_whenTokenIsNonzeroAddressWithoutCode_returnsFalse] |
| TRY-I02 | Any harness caller, fuzz | Standard token rejects zero destination | false; recipient-validation revert is caught | Balances retained; no outer revert | Covered: [evidence][test_whenRecipientIsZeroAddress_returnsFalseAndRetainsBalances] |

## Numeric extremes

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| TRY-N01 | Any harness caller, fuzz | Standard funded token; amount=type(uint256).max; recipient initially empty | true | Exact MAX transfer; sender balance becomes zero | Covered: [evidence][test_whenAmountIsMaximum_transfersMaximum] |

## Transfers

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| TRY-T01 | Any harness caller, fuzz | Contract performs the funded transfer and returns no data | true; code exists at token address | Exact sender/recipient deltas; no outer revert | Covered: [evidence][test_whenTokenReturnsNoDataAfterTransfer_acceptsTransfer] |
| TRY-T02 | Any harness caller, fuzz | Short return data or noncanonical first word other than 1 | false; no outer revert | Do not infer token-side rollback for a nonreverting malformed response | Covered: [evidence][test_whenTokenReturnsShortData_returnsFalseButKeepsTokenEffects], [evidence][test_whenTokenReturnsNoncanonicalWord_returnsFalseButKeepsTokenEffects] |
| TRY-T04 | Any harness caller, fuzz | Contract returns false without changing balances | false; no outer revert | Sender/recipient balances retained | Covered: [evidence][test_whenTokenReturnsFalse_returnsFalseAndRetainsBalances] |
| TRY-T06 | Any harness caller, fuzz | At least 32 return bytes; first word=1; extra words follow | true; extra return data is ignored | Assert fixture balance effects separately from return classification | Covered: [evidence][test_whenTokenReturnsTrueWithExtraData_acceptsTransfer] |
| TRY-T07 | Any harness caller, fuzz | Contract returns canonical true without moving tokens | true | Balances unchanged; return value alone does not prove delivery | Covered: [evidence][test_whenTokenReturnsTrueWithoutTransfer_returnsTrueWithUnchangedBalances] |
| TRY-T03 | Any harness caller, fuzz | Standard token transfer exceeds available balance | false; insufficient-balance revert is caught | Balances retained; no outer revert | Covered: [evidence][test_whenAmountExceedsAvailableBalance_returnsFalseAndRetainsBalances] |
| TRY-T05 | Any harness caller, fuzz | Contract transfer reverts with controlled token error | false; token revert is caught | Token transfer effects rolled back; no outer revert | Covered: [evidence][test_whenTokenRevertsAfterTransfer_returnsFalseAndRollsBack] |

[test_whenAmountIsMaximum_transfersMaximum]: ./trySafeTransfer.t.sol#L77

[test_whenAmountIsZero_succeedsWithoutMovingTokens]: ./trySafeTransfer.t.sol#L49

[test_whenAmountIsOne_transfersOne]: ./trySafeTransfer.t.sol#L63

[test_whenStandardTokenAmountIsFunded]: ./trySafeTransfer.t.sol#L33

[test_whenTokenIsZeroAddress_returnsFalse]: ./trySafeTransfer.t.sol#L90

[test_whenTokenIsNonzeroAddressWithoutCode_returnsFalse]: ./trySafeTransfer.t.sol#L98

[test_whenRecipientIsZeroAddress_returnsFalseAndRetainsBalances]: ./trySafeTransfer.t.sol#L108

[test_whenTokenReturnsNoDataAfterTransfer_acceptsTransfer]: ./trySafeTransfer.t.sol#L124

[test_whenTokenReturnsShortData_returnsFalseButKeepsTokenEffects]: ./trySafeTransfer.t.sol#L145

[test_whenTokenReturnsNoncanonicalWord_returnsFalseButKeepsTokenEffects]: ./trySafeTransfer.t.sol#L165

[test_whenTokenReturnsFalse_returnsFalseAndRetainsBalances]: ./trySafeTransfer.t.sol#L183

[test_whenTokenReturnsTrueWithExtraData_acceptsTransfer]: ./trySafeTransfer.t.sol#L203

[test_whenTokenReturnsTrueWithoutTransfer_returnsTrueWithUnchangedBalances]: ./trySafeTransfer.t.sol#L220

[test_whenAmountExceedsAvailableBalance_returnsFalseAndRetainsBalances]: ./trySafeTransfer.t.sol#L242

[test_whenTokenRevertsAfterTransfer_returnsFalseAndRollsBack]: ./trySafeTransfer.t.sol#L261
