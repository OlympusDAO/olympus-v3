# Olympus ERC-20 Safety Examples

These examples show current Olympus V3 patterns. Use the rule that fits the new accounting path.
Do not copy an example without reading its full call path.

## Safe Transfers

`src/libraries/TransferHelper.sol` accepts a successful call with no return data or a decoded `true`
value. It reverts when the token call fails or returns `false`.

The repository also uses versioned safe-transfer libraries from dependencies. Follow the pattern in
the contract area that you change.

## Exact Incoming Custody

`src/bases/BaseAssetManager.sol::_depositAsset()` reads the custody balance before and after
`safeTransferFrom`. It rejects a deposit when the custody contract receives less than the requested
amount.

This is the correct place for the check because `BaseAssetManager` creates shares and liabilities
from the received tokens.

`src/test/policies/DepositManager/deposit.t.sol::test_givenAssetIsFeeOnTransfer_reverts()` proves
that a fee-on-transfer token cannot create deposit accounting.

## Multi-Contract Deposits

`src/policies/libraries/BurnerLoansCustody.sol::deposit()` first pulls collateral into Burner Loans.
DepositManager then pulls the requested amount into final custody.

DepositManager performs the exact incoming balance check. Burner Loans also rejects a new residual
balance because it must not retain collateral between calls.

`src/test/policies/BurnerLoans/depositCollateral.t.sol` contains examples for:

- A safe-transfer error with no collateral credit.
- A fee-on-transfer token rejected at the custody boundary.
- A token callback rejected by the reentrancy guard.
- A DepositManager error that restores balances and position accounting.

## Exact Repayment

`src/policies/libraries/BurnerLoansCustody.sol::repay()` transfers OHM directly from the payer to
Burner Loans Inventory. It reads the Inventory balance before and after the transfer.

The function settles debt only after Inventory receives the exact repayment amount. This prevents
nominal repayment from reducing more debt than Inventory received.

## Outgoing Transfers

Burner Loans does not read recipient balances after collateral withdrawals, fee transfers, or yield
distribution. These paths use safe transfers and rely on governance to admit tokens with acceptable
transfer behavior.

`documentation/burner_loans.md` records this token rule and identifies the incoming custody checks.

## Callback Tests

`src/test/policies/BurnerLoans/fixtures/ReentrantFeeToken.sol` can call a target during `transfer` or
`transferFrom`.

The Burner Loans tests authorize the callback token before the nested call. This makes the nested
call reach the shared reentrancy guard instead of failing an unrelated authorization check.

Useful examples include:

- `src/test/policies/BurnerLoans/depositCollateral.t.sol::test_givenCallbackToken_cannotReenterDeposit()`
- `src/test/policies/BurnerLoans/withdrawCollateral.t.sol::test_givenCallbackToken_cannotReenterWithdrawal()`
- `src/test/policies/BurnerLoans/borrow.t.sol::test_givenReentrantFeeToken_borrowCannotMintOrIndexTwice()`
- `src/test/periphery/BurnerLoansComposites/depositAndBorrow.t.sol::test_givenReentrantCollateralToken_cannotEnterTwice()`

The tests assert that the callback fails and the outer action applies once.
