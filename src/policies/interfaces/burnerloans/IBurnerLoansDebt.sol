// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @notice User-facing borrowing, repayment and maturity extensions bound to a permanent Burner Loans Core.
interface IBurnerLoansDebt {
    // ========== EVENTS ========== //

    /// @notice Emitted when OHM principal is repaid for a borrower.
    /// @param caller Account that initiated the repayment.
    /// @param asset Collateral asset securing the position.
    /// @param onBehalfOf Borrower whose debt decreased.
    /// @param repaidOhm Principal repaid, in OHM decimals.
    /// @param remainingDebtOhm Principal remaining, in OHM decimals.
    event Repaid(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        uint256 repaidOhm,
        uint256 remainingDebtOhm
    );

    /// @notice Emitted when OHM principal is borrowed against collateral.
    /// @param caller Account that initiated the borrow.
    /// @param asset Collateral asset securing the position.
    /// @param onBehalfOf Borrower whose debt increased.
    /// @param recipient Account that received the borrowed OHM.
    /// @param ohmAmount Principal borrowed, in OHM decimals.
    /// @param protocolFee Protocol allocation of the origination fee, in collateral token decimals.
    /// @param referrer Referrer supplied for this borrow, or zero for none.
    /// @param referralFee Referral allocation of the origination fee, in collateral token decimals.
    event Borrowed(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        address recipient,
        uint256 ohmAmount,
        uint256 protocolFee,
        address referrer,
        uint256 referralFee
    );

    /// @notice Emitted when an active position's maturity is extended.
    /// @param caller Account that initiated the extension.
    /// @param asset Collateral asset securing the position.
    /// @param onBehalfOf Borrower whose maturity changed.
    /// @param maturity New maturity timestamp.
    /// @param protocolFee Protocol allocation of the extension fee, in collateral token decimals.
    /// @param referrer Referrer supplied for this extension, independently of earlier operations.
    /// @param referralFee Referral allocation of the extension fee, in collateral token decimals.
    event Extended(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        uint48 maturity,
        uint256 protocolFee,
        address referrer,
        uint256 referralFee
    );

    // ========== ERRORS ========== //

    /// @notice The borrower has no collateral position for the asset.
    error BurnerLoans_NoCollateral();

    /// @notice A repayment exceeds the borrower's outstanding principal.
    /// @param requested Requested repayment, in OHM decimals.
    /// @param debt Outstanding principal, in OHM decimals.
    error BurnerLoans_RepayExceedsDebt(uint256 requested, uint256 debt);

    /// @notice A repayment was attempted in the same block as the position's latest borrow.
    /// @param borrowBlock Block number of the latest borrow.
    error BurnerLoans_SameBlockRepay(uint48 borrowBlock);

    /// @notice An operation requires an active position but its maturity has passed.
    /// @param maturity Position maturity timestamp.
    error BurnerLoans_PositionExpired(uint48 maturity);

    /// @notice A borrow would exceed the collateral market's active-principal cap.
    /// @param asset Collateral asset whose cap would be exceeded.
    /// @param requestedDebtOhm Principal requested by the borrow, in OHM decimals.
    /// @param availableDebtOhm Remaining market capacity, in OHM decimals.
    error BurnerLoans_AssetDebtCapExceeded(
        address asset,
        uint256 requestedDebtOhm,
        uint256 availableDebtOhm
    );

    /// @notice The calculated total fee exceeds the caller's maximum accepted total fee.
    /// @param fee Calculated total fee (protocolFee + referralFee), in collateral token decimals.
    /// @param maxFee Maximum total fee accepted by the caller, in collateral token decimals.
    error BurnerLoans_FeeExceedsMax(uint256 fee, uint256 maxFee);

    /// @notice A requested maturity exceeds the configured maturity horizon.
    /// @param requested Requested maturity timestamp.
    /// @param maximum Maximum permitted maturity timestamp.
    error BurnerLoans_MaturityHorizonExceeded(uint256 requested, uint256 maximum);

    /// @notice An extension does not move the position maturity beyond the current timestamp.
    /// @param requested Resulting maturity calculated from the position's previous maturity.
    /// @param currentTimestamp Current block timestamp.
    error BurnerLoans_ExtensionMaturityNotFuture(uint256 requested, uint256 currentTimestamp);

    // ========== STRUCTS ========== //

    /// @notice Projected result of a borrow.
    /// @param fee Total origination fee (protocolFee + referralFee), in collateral token decimals.
    /// @param resultingDebtOhm Principal after the borrow, in OHM decimals.
    /// @param resultingHealthFactor Health factor after the borrow, scaled by 1e18.
    /// @param maturity Maturity timestamp after the borrow.
    struct BorrowPreview {
        uint256 fee;
        uint256 resultingDebtOhm;
        uint256 resultingHealthFactor;
        uint48 maturity;
    }

    /// @notice Projected result of a maturity extension.
    /// @param fee Total extension fee (protocolFee + referralFee), in collateral token decimals.
    /// @param maturity Maturity timestamp after the extension.
    /// @param healthFactor Health factor after the extension, scaled by 1e18.
    struct ExtendPreview {
        uint256 fee;
        uint48 maturity;
        uint256 healthFactor;
    }

    // ========== FUNCTIONS ========== //

    /// @notice Borrows for an authorized borrower and collects the caller's total origination fee.
    /// @param asset Configured collateral token identifying the borrower's market.
    /// @param amount Principal to borrow, in OHM units.
    /// @param borrower Account whose position incurs the debt.
    /// @param recipient Account receiving the borrowed OHM.
    /// @param maxFee Maximum accepted total origination fee (protocolFee + referralFee), in underlying collateral units.
    /// @param referrer Referral recipient for this operation, or zero for none.
    /// @return result Total fee (protocolFee + referralFee), resulting principal, WAD-scaled health and maturity.
    function borrow(
        address asset,
        uint128 amount,
        address borrower,
        address recipient,
        uint256 maxFee,
        address referrer
    ) external returns (BorrowPreview memory result);

    /// @notice Repays from the caller's OHM and reports the borrower's resulting position health.
    /// @param asset Configured collateral token identifying the borrower's market.
    /// @param amount Principal to repay, in OHM units.
    /// @param borrower Account whose principal is repaid; no operator grant is required.
    /// @return principal Outstanding principal after repayment, in OHM units.
    /// @return resultingHealthFactor WAD-scaled health, or uint256.max when debt is fully repaid.
    function repay(
        address asset,
        uint128 amount,
        address borrower
    ) external returns (uint128 principal, uint256 resultingHealthFactor);

    /// @notice Quotes new borrowing, the total origination fee and the resulting position for any borrower.
    /// @param asset_ Configured collateral asset.
    /// @param amount_ Requested principal in OHM units.
    /// @param onBehalfOf_ Borrower whose position would incur debt, independently of the quote requester or execution fee payer.
    /// @param recipient_ Account that would receive the borrowed OHM.
    /// @param maxFee_ Maximum accepted total fee (protocolFee + referralFee), in underlying collateral units.
    /// @param referrer_ Referral recipient for this operation, or zero for none.
    /// @return result Projected total fee (protocolFee + referralFee), principal, maturity and WAD health.
    function previewBorrow(
        address asset_,
        uint128 amount_,
        address onBehalfOf_,
        address recipient_,
        uint256 maxFee_,
        address referrer_
    ) external view returns (IBurnerLoansDebt.BorrowPreview memory result);

    /// @notice Quotes remaining principal and resulting health for a repayment.
    /// @param asset_ Configured collateral token identifying the borrower's market.
    /// @param amount_ Principal to repay, in OHM units.
    /// @param borrower_ Account whose principal would be reduced.
    /// @return remainingPrincipal Outstanding principal after repayment, in OHM units.
    /// @return resultingHealthFactor WAD-scaled health, or uint256.max for full repayment.
    function previewRepay(
        address asset_,
        uint128 amount_,
        address borrower_
    ) external view returns (uint128 remainingPrincipal, uint256 resultingHealthFactor);

    /// @notice Extends an authorized borrower's maturity by whole configured terms and collects the total extension fee.
    /// @param asset Configured collateral token identifying the borrower's market.
    /// @param borrower Account whose debt maturity is extended.
    /// @param terms Number of configured term lengths added to the existing maturity.
    /// @param maxFee Maximum accepted total extension fee (protocolFee + referralFee), in underlying collateral units.
    /// @param referrer Referral recipient for this operation, independently of previous operations.
    /// @return result Total fee (protocolFee + referralFee), resulting WAD-scaled health and maturity.
    function extend(
        address asset,
        address borrower,
        uint16 terms,
        uint256 maxFee,
        address referrer
    ) external returns (ExtendPreview memory result);

    /// @notice Quotes a maturity extension and its total extension fee for any borrower.
    /// @param asset_ Configured collateral asset.
    /// @param onBehalfOf_ Borrower whose debt would be extended, independently of the quote requester or execution fee payer.
    /// @param terms_ Whole configured term lengths to add to stored maturity.
    /// @param maxFee_ Maximum accepted total fee (protocolFee + referralFee), in underlying collateral units.
    /// @param referrer_ Referral recipient for this operation, or zero for none.
    /// @return result Projected total fee (protocolFee + referralFee), maturity and WAD health.
    function previewExtend(
        address asset_,
        address onBehalfOf_,
        uint16 terms_,
        uint256 maxFee_,
        address referrer_
    ) external view returns (ExtendPreview memory result);
}
