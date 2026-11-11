// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @notice User-facing collateral actions bound to a permanent Burner Loans Core.
interface IBurnerLoansCollateral {
    // ========== EVENTS ========== //

    /// @notice Emitted when collateral is withdrawn from a borrower's position.
    /// @param caller Account that initiated the withdrawal.
    /// @param asset Withdrawn collateral asset.
    /// @param onBehalfOf Borrower whose position was debited.
    /// @param recipient Account that received the collateral.
    /// @param requestedAssetAmount Asset-denominated collateral credit debited from the position.
    /// @param tokenOut Token received by the recipient.
    /// @param amountOut Amount received, in `tokenOut` decimals.
    event CollateralWithdrawn(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        address recipient,
        uint256 requestedAssetAmount,
        address tokenOut,
        uint256 amountOut
    );

    /// @notice Emitted when collateral is deposited for a borrower.
    /// @param caller Account that initiated the deposit.
    /// @param asset Deposited collateral asset.
    /// @param onBehalfOf Borrower whose position was credited.
    /// @param amount Collateral transferred into custody.
    /// @param depositedAmount Asset-denominated collateral credit created by this deposit.
    event CollateralDeposited(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 depositedAmount
    );

    // ========== ERRORS ========== //

    /// @notice A collateral operation exceeds the borrower's available collateral.
    /// @param requested Requested collateral credit, in collateral token decimals.
    /// @param available Available collateral credit, in collateral token decimals.
    error BurnerLoans_InsufficientCollateral(uint256 requested, uint256 available);

    // ========== STRUCTS ========== //

    /// @notice Projected result of a collateral withdrawal.
    /// @param returnToken Collateral token returned to the recipient.
    /// @param returnAmount Amount returned, in `returnToken` decimals.
    /// @param remainingDepositedCollateral Withdrawable collateral credit remaining after withdrawal.
    /// @param resultingHealthFactor Health factor after withdrawal, scaled by 1e18.
    ///        false when `returnAmount` is zero.
    struct WithdrawPreview {
        address returnToken;
        uint256 returnAmount;
        uint256 remainingDepositedCollateral;
        uint256 resultingHealthFactor;
    }

    // ========== FUNCTIONS ========== //

    /// @notice Deposits the caller's assets for an authorized borrower.
    /// @param asset Configured underlying collateral token.
    /// @param amount Requested deposit in underlying token units.
    /// @param borrower Account receiving collateral credit.
    /// @return credit Collateral actually credited by DepositManager, in underlying units.
    /// @return collateral Borrower's total collateral after the deposit, in underlying units.
    /// @return resultingHealthFactor Actual WAD-scaled health; uint256.max when no debt exists.
    function depositCollateral(
        address asset,
        uint128 amount,
        address borrower
    ) external returns (uint128 credit, uint128 collateral, uint256 resultingHealthFactor);

    /// @notice Withdraws collateral for an authorized borrower and validates actual resulting health atomically.
    /// @param asset Configured underlying collateral token.
    /// @param amount Collateral credit to withdraw, in underlying units.
    /// @param borrower Account whose collateral is withdrawn.
    /// @param recipient Account receiving the underlying tokens or vault shares.
    /// @return result Actual output token/amount, remaining collateral and WAD-scaled health.
    function withdrawCollateral(
        address asset,
        uint128 amount,
        address borrower,
        address recipient
    ) external returns (WithdrawPreview memory result);

    /// @notice Quotes collateral credit and the resulting position for any borrower.
    /// @param asset_ Configured underlying collateral asset.
    /// @param amount_ Requested deposit in underlying token units.
    /// @param onBehalfOf_ Borrower whose position would receive credit, independently of the quote requester or execution payer.
    /// @return credit Estimated collateral credit in underlying units.
    /// @return collateral Projected total collateral in underlying units.
    /// @return resultingHealthFactor Projected WAD health; uint256.max when debt-free.
    function previewDepositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external view returns (uint256 credit, uint256 collateral, uint256 resultingHealthFactor);

    /// @notice Quotes withdrawal output and the resulting position for any borrower.
    /// @param asset_ Configured underlying collateral asset.
    /// @param amount_ Collateral credit to withdraw, in underlying units.
    /// @param onBehalfOf_ Borrower whose collateral would be withdrawn, independently of the quote requester.
    /// @param recipient_ Account that would receive underlying tokens or vault shares.
    /// @return result Output token/amount, remaining collateral and WAD health.
    function previewWithdrawCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_,
        address recipient_
    ) external view returns (IBurnerLoansCollateral.WithdrawPreview memory result);
}
