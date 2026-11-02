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

`src/policies/burnerloans/BurnerLoansCore.sol::settleDeposit()` first pulls collateral into Core
with an exact receipt check. DepositManager then pulls the requested amount into final custody.

DepositManager performs its own exact incoming balance check before crediting custody accounting.

`src/test/policies/BurnerLoansCollateral/depositCollateral.t.sol` contains examples for:

- A safe-transfer error with no collateral credit.
- A fee-on-transfer token rejected at the custody boundary.
- A token callback rejected by the reentrancy guard.
- A DepositManager error that restores balances and position accounting.

## Exact Repayment

`src/policies/burnerloans/BurnerLoansCore.sol::settleRepay()` transfers OHM directly from the payer
to Inventory using the shared exact receipt helper.

The function settles debt only after Inventory receives the exact repayment amount. This prevents
nominal repayment from reducing more debt than Inventory received.

## Outgoing Transfers

Burner Loans does not read recipient balances after collateral withdrawals, fee transfers, or yield
distribution. These paths use safe transfers and rely on governance to admit tokens with acceptable
transfer behavior.

`documentation/burner_loans.md` records this token rule and identifies the incoming custody checks.

## Callback Tests

The modular callback fixtures can call a target during token transfers, vault deposits and receipt
approvals.

The Burner Loans tests authorize the callback token before the nested call. This makes the nested
call reach the shared reentrancy guard instead of failing an unrelated authorization check.

Useful examples include:

- `src/test/policies/BurnerLoansCollateral/depositCollateralCallbacks.t.sol::test_givenPayerPullCallback_whenActionReentryCaught()`
- `src/test/policies/BurnerLoansDebt/borrowCallbacks.t.sol::test_givenCaughtFeeTokenCallback_whenBorrowed_thenOnlyOuterOperationSucceeds()`
- `src/test/policies/BurnerLoansDebt/repayCallbacks.t.sol::test_givenCaughtOhmCallback_whenRepaid_thenOnlyOuterOperationSucceeds()`

The tests assert that the callback fails and the outer action applies once.
