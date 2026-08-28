// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans View Interface
/// @notice Read-only position and quote surface implemented by the lifecycle policy.
interface IBurnerLoansView is IBurnerLoans {
    /// @notice Returns the OHM debt token used by this facility.
    /// @return address The OHM token address.
    function ohm() external view returns (address);

    /// @notice Returns the OHM funding Burner Loans Inventory bound to this facility.
    /// @return address The Burner Loans Inventory address.
    function inventory() external view returns (address);

    /// @notice Returns the Burner Loans Config policy authorized to configure this facility.
    /// @return address The Burner Loans Config address.
    function configurator() external view returns (address);

    /// @notice Validates that a collateral asset is supported by this facility's dependencies.
    /// @dev Reverts when PRICE does not support the asset or the facility's Deposit Manager cannot
    ///      provide enabled custody for the Burner Loans deposit period.
    /// @param asset_ Collateral asset to validate.
    function validateAssetDependencies(address asset_) external view;

    /// @notice Returns the fixed-term loan module used by this facility.
    /// @return address The FLOAN module address.
    function floan() external view returns (address);

    /// @notice Returns a borrower's position for a collateral asset.
    /// @dev Reverts when the asset is not configured or its market is incompatible.
    /// @param asset_ Collateral asset whose market contains the position.
    /// @param borrower_ Borrower whose position is queried.
    /// @return position The current Burner Loans position.
    function getPosition(
        address asset_,
        address borrower_
    ) external view returns (Position memory position);

    /// @notice Returns all active borrowers for a collateral asset.
    /// @dev Reverts when the asset is not configured or its market is incompatible.
    /// @param asset_ Collateral asset whose active borrowers are queried.
    /// @return borrowers Active borrowers in FLOAN order.
    function getActiveBorrowers(address asset_) external view returns (address[] memory borrowers);

    /// @notice Returns whether a borrower is currently eligible for seizure.
    /// @dev Reverts when the asset configuration or required prices are unavailable.
    /// @param asset_ Collateral asset securing the position.
    /// @param borrower_ Borrower whose position is checked.
    /// @return seizable True when the position can be seized.
    function isSeizable(address asset_, address borrower_) external view returns (bool seizable);

    /// @notice Quotes seizure of a borrower batch for one collateral asset.
    /// @dev Reverts for an invalid batch, duplicate borrower, missing debt, unavailable custody or
    ///      pricing, or any position that is not seizable.
    /// @param asset_ Collateral asset securing every position in the batch.
    /// @param borrowers_ Borrowers whose positions would be seized.
    /// @return preview Projected seizure accounting.
    function previewSeize(
        address asset_,
        address[] calldata borrowers_
    ) external view returns (SeizePreview memory preview);

    /// @notice Scans active borrowers and returns a bounded set of seizable addresses.
    /// @dev Reverts when the asset configuration or pricing is unavailable or the return limit is
    ///      above the supported batch size.
    /// @param asset_ Collateral asset whose active borrowers are scanned.
    /// @param startIndex_ Active-borrower index at which to begin.
    /// @param maxBorrowersToCheck_ Maximum borrowers to inspect.
    /// @param maxBorrowersToReturn_ Maximum seizable borrowers to return.
    /// @return borrowers Seizable borrowers found in the requested scan range.
    /// @return nextIndex Next borrower index to scan.
    /// @return expectedKeeperReward Projected keeper reward in collateral-token decimals.
    function getSeizableBorrowers(
        address asset_,
        uint256 startIndex_,
        uint256 maxBorrowersToCheck_,
        uint256 maxBorrowersToReturn_
    )
        external
        view
        returns (address[] memory borrowers, uint256 nextIndex, uint256 expectedKeeperReward);

    /// @notice Quotes a collateral deposit for a borrower.
    /// @dev Reverts when the facility or asset is disabled, the amount is zero, or custody cannot
    ///      accept and credit the deposit.
    /// @param asset_ Collateral asset to deposit.
    /// @param amount_ Deposit amount in collateral-token decimals.
    /// @param onBehalfOf_ Borrower receiving the collateral credit.
    /// @return depositedCollateral Projected collateral credited in collateral-token decimals.
    /// @return totalCollateral Projected total credited collateral in collateral-token decimals.
    function previewDepositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external view returns (uint256 depositedCollateral, uint256 totalCollateral);

    /// @notice Quotes a collateral withdrawal for a borrower.
    /// @dev Reverts for unavailable custody or pricing, or an invalid amount. An unhealthy result
    ///      is returned with `preview.executable` set to false.
    /// @param asset_ Collateral asset to withdraw.
    /// @param amount_ Credited collateral to remove, in collateral-token decimals.
    /// @param onBehalfOf_ Borrower whose position is quoted.
    /// @return preview Projected withdrawal accounting.
    function previewWithdrawCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external view returns (WithdrawPreview memory preview);

    /// @notice Quotes an OHM borrow against a collateral position.
    /// @dev Reverts for disabled originations, missing collateral, cap breach, unavailable prices,
    ///      matured debt, or an unhealthy current or resulting position.
    /// @param asset_ Collateral asset securing the loan.
    /// @param ohmAmount_ Principal requested in OHM token decimals.
    /// @param onBehalfOf_ Borrower whose position is quoted.
    /// @return preview Projected borrow accounting.
    function previewBorrow(
        address asset_,
        uint128 ohmAmount_,
        address onBehalfOf_
    ) external view returns (BorrowPreview memory preview);

    /// @notice Quotes repayment of a borrower's OHM principal.
    /// @dev Reverts when the asset is unconfigured, the amount is zero, there is no debt, the
    ///      amount exceeds debt, or repayment occurs in the borrow block.
    /// @param asset_ Collateral asset identifying the market.
    /// @param repayOhm_ Principal to repay in OHM token decimals.
    /// @param onBehalfOf_ Borrower whose debt is quoted.
    /// @return preview Projected repayment accounting.
    function previewRepay(
        address asset_,
        uint128 repayOhm_,
        address onBehalfOf_
    ) external view returns (RepayPreview memory preview);

    /// @notice Quotes an active position maturity extension.
    /// @dev Reverts for disabled originations, missing debt, unavailable custody or pricing,
    ///      unhealthy debt, a zero term count, or a maturity outside the configured horizon.
    /// @param asset_ Collateral asset identifying the market.
    /// @param onBehalfOf_ Borrower whose position is quoted.
    /// @param termCount_ Number of configured terms to add.
    /// @return preview Projected extension accounting.
    function previewExtend(
        address asset_,
        address onBehalfOf_,
        uint16 termCount_
    ) external view returns (ExtendPreview memory preview);

    /// @notice Calculates a position health factor from supplied collateral and debt.
    /// @dev Returns max uint for zero debt and otherwise reverts when configuration or prices are
    ///      unavailable.
    /// @param asset_ Collateral asset used for valuation.
    /// @param collateral_ Collateral amount in collateral-token decimals.
    /// @param debtOhm_ Debt principal in OHM token decimals.
    /// @return healthFactor Position health factor, scaled by 1e18.
    function positionHealthFactor(
        address asset_,
        uint256 collateral_,
        uint256 debtOhm_
    ) external view returns (uint256 healthFactor);

    /// @notice Quotes currently claimable collateral yield for the treasury.
    /// @dev Reverts when the facility is disabled or the asset or custody configuration is invalid.
    /// @param asset_ Collateral asset whose yield is queried.
    /// @return preview Projected yield harvest.
    function previewHarvestYield(
        address asset_
    ) external view returns (HarvestPreview memory preview);

    /// @notice Returns DepositManager accounting for this facility and asset.
    /// @dev Reverts when the asset is not configured or the custody query fails.
    /// @param asset_ Collateral asset whose custody status is queried.
    /// @return status Current collateral accounting status.
    function getAssetCollateralStatus(
        address asset_
    ) external view returns (AssetCollateralStatus memory status);
}
