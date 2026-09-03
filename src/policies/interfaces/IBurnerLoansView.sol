// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans View Interface
/// @notice Read-only position and quote surface implemented by the lifecycle policy.
interface IBurnerLoansView is IBurnerLoans {
    /// @notice Returns the OHM debt token used by this facility.
    /// @return ohm_ OHM token address.
    function ohm() external view returns (address ohm_);

    /// @notice Returns the OHM funding Burner Loans Inventory bound to this facility.
    /// @return inventory_ Burner Loans Inventory address, or zero before it is bound.
    function inventory() external view returns (address inventory_);

    /// @notice Returns the Burner Loans Config policy authorized to configure this facility.
    /// @return configurator_ Burner Loans Config address, or zero before it is bound.
    function configurator() external view returns (address configurator_);

    /// @notice Returns the facility-wide yield recipient.
    /// @return recipient Current recipient, or zero when none is configured.
    function getYieldRecipient() external view returns (address recipient);

    /// @notice Returns the number of collateral assets registered by Config.
    /// @return count Number of registered assets.
    function getAssetCount() external view returns (uint256 count);

    /// @notice Returns a registered collateral asset by append-only index.
    /// @dev Reverts with OpenZeppelin's enumerable-set bounds error for an invalid index.
    /// @param index_ Registry index to query.
    /// @return asset Registered collateral asset.
    function getAssetAt(uint256 index_) external view returns (address asset);

    /// @notice Returns an asset's raw yield-recipient share without requiring live market state.
    /// @param asset_ Collateral asset queried.
    /// @return bps Recipient share in basis points.
    function getYieldRecipientAssetBps(address asset_) external view returns (uint16 bps);

    /// @notice Validates a proposed facility-wide recipient.
    /// @dev Reverts if:
    ///      - The recipient is zero or lacks `IYieldRecipient` or `IEnabler` support.
    ///      - The recipient is not an active policy in the facility Kernel.
    ///      - The recipient is disabled.
    /// @param recipient_ Proposed recipient.
    function validateYieldRecipient(address recipient_) external view;

    /// @notice Validates a recipient's exact DepositManager route for one collateral asset.
    /// @dev Reverts if global recipient validation fails or the recipient pair is mismatched or
    ///      disabled.
    /// @param recipient_ Proposed recipient.
    /// @param asset_ Collateral asset whose route is validated.
    function validateYieldRecipientAsset(address recipient_, address asset_) external view;

    /// @notice Validates that a collateral asset is supported by this facility's dependencies.
    /// @dev Checks PRICE approval without reading a live price. Reverts when PRICE does not support
    ///      the asset or the facility's Deposit Manager cannot provide enabled custody for the
    ///      Burner Loans deposit period.
    /// @param asset_ Collateral asset to validate.
    function validateAssetDependencies(address asset_) external view;

    /// @notice Returns the fixed-term loan module used by this facility.
    /// @return floan_ FLOAN module address.
    function floan() external view returns (address floan_);

    /// @notice Returns a borrower's position for a collateral asset.
    /// @dev Reverts if the collateral asset is not uniquely configured.
    /// @param asset_ Collateral asset securing the position.
    /// @param borrower_ Borrower whose position is queried.
    /// @return position Borrower's position.
    function getPosition(
        address asset_,
        address borrower_
    ) external view returns (Position memory position);

    /// @notice Returns every active borrower for a collateral market.
    /// @dev Reverts if the collateral asset is not uniquely configured.
    /// @param asset_ Collateral asset whose active borrowers are queried.
    /// @return borrowers Active borrower addresses in FLOAN's stored order.
    function getActiveBorrowers(address asset_) external view returns (address[] memory borrowers);

    /// @notice Returns whether a borrower currently satisfies the seizure conditions.
    /// @dev Reverts if the collateral asset is not uniquely configured or price lookup fails.
    /// @param asset_ Collateral asset securing the position.
    /// @param borrower_ Borrower whose position is evaluated.
    /// @return seizable True when the position can be seized.
    function isSeizable(address asset_, address borrower_) external view returns (bool seizable);

    /// @notice Projects the aggregate result of seizing a borrower batch.
    /// @dev Reverts if Burner Loans or custody is disabled, the asset is unavailable, the batch is
    ///      invalid, a borrower is duplicated or not seizable, custody is insolvent, or price
    ///      validation fails.
    /// @param asset_ Collateral asset seized from every borrower.
    /// @param borrowers_ Borrowers evaluated atomically.
    /// @return preview Projected aggregate seizure result.
    function previewSeize(
        address asset_,
        address[] calldata borrowers_
    ) external view returns (SeizePreview memory preview);

    /// @notice Scans a bounded active-borrower range for seizable positions.
    /// @dev Reverts if Burner Loans is disabled, the asset is not uniquely configured, the return
    ///      limit exceeds the seizure batch maximum, or price validation fails. A zero check or
    ///      return limit produces an empty result without advancing the cursor.
    /// @param asset_ Collateral asset whose borrowers are scanned.
    /// @param startIndex_ Active-borrower index at which scanning begins.
    /// @param maxBorrowersToCheck_ Maximum number of active borrowers inspected.
    /// @param maxBorrowersToReturn_ Maximum number of seizable borrowers returned.
    /// @return borrowers Seizable borrowers found in the requested scan range.
    /// @return nextIndex Next borrower index to scan.
    /// @return expectedKeeperReward Projected aggregate keeper reward, in collateral token decimals.
    function getSeizableBorrowers(
        address asset_,
        uint256 startIndex_,
        uint256 maxBorrowersToCheck_,
        uint256 maxBorrowersToReturn_
    )
        external
        view
        returns (address[] memory borrowers, uint256 nextIndex, uint256 expectedKeeperReward);

    /// @notice Projects a collateral deposit for a borrower.
    /// @dev Reverts if Burner Loans, originations, or custody is disabled; the asset is unavailable;
    ///      the amount is zero; or custody cannot preview the deposit.
    /// @param asset_ Collateral asset to deposit.
    /// @param amount_ Proposed collateral deposit amount, in collateral token decimals.
    /// @param onBehalfOf_ Borrower whose position receives the collateral credit.
    /// @return depositedCollateral Projected collateral credit created by the deposit.
    /// @return totalCollateral Projected borrower collateral credit after the deposit.
    function previewDepositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external view returns (uint256 depositedCollateral, uint256 totalCollateral);

    /// @notice Projects a collateral withdrawal from a borrower's position.
    /// @dev Reverts if Burner Loans or custody is disabled, the asset or position is unavailable,
    ///      or the amount is zero or exceeds available collateral credit. The projected return may
    ///      be lower than the requested collateral debit or zero because ERC-4626 conversion rounds
    ///      down. Returns `preview.executable == false` when the resulting position would be
    ///      unhealthy or custody would return zero assets.
    /// @param asset_ Collateral asset to withdraw.
    /// @param amount_ Asset-denominated collateral credit debited from the position.
    /// @param onBehalfOf_ Borrower whose position is evaluated.
    /// @return preview Projected collateral withdrawal result.
    function previewWithdrawCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external view returns (WithdrawPreview memory preview);

    /// @notice Projects an OHM borrow against a collateral position.
    /// @dev Reverts if Burner Loans, originations, or Inventory is disabled; the asset or position
    ///      is unavailable; the amount is zero; price or custody validation fails; or a debt-cap,
    ///      maturity, or health bound would be exceeded.
    /// @param asset_ Collateral asset securing the position.
    /// @param ohmAmount_ Principal requested, in OHM decimals.
    /// @param onBehalfOf_ Borrower whose position is evaluated.
    /// @return preview Projected borrow result.
    function previewBorrow(
        address asset_,
        uint128 ohmAmount_,
        address onBehalfOf_
    ) external view returns (BorrowPreview memory preview);

    /// @notice Projects an OHM principal repayment for a borrower.
    /// @dev Reverts if Burner Loans is disabled, the asset or debt position is unavailable, the
    ///      amount is zero or exceeds debt, or repayment is attempted in the latest borrow block.
    /// @param asset_ Collateral asset securing the position.
    /// @param repayOhm_ Principal to repay, in OHM decimals.
    /// @param onBehalfOf_ Borrower whose debt is evaluated.
    /// @return preview Projected repayment result.
    function previewRepay(
        address asset_,
        uint128 repayOhm_,
        address onBehalfOf_
    ) external view returns (RepayPreview memory preview);

    /// @notice Projects an active position's maturity extension.
    /// @dev Reverts if Burner Loans or originations are disabled, the asset or position is
    ///      unavailable, the term count is invalid, the position is matured or unhealthy, or the
    ///      resulting maturity exceeds its configured horizon.
    /// @param asset_ Collateral asset securing the position.
    /// @param onBehalfOf_ Borrower whose position is evaluated.
    /// @param termCount_ Number of configured terms added to the maturity.
    /// @return preview Projected extension result.
    function previewExtend(
        address asset_,
        address onBehalfOf_,
        uint16 termCount_
    ) external view returns (ExtendPreview memory preview);

    /// @notice Calculates a hypothetical position health factor.
    /// @dev Reverts if the asset is not uniquely configured or required prices are unavailable.
    /// @param asset_ Collateral asset securing the hypothetical position.
    /// @param collateral_ Collateral amount, in collateral token decimals.
    /// @param debtOhm_ Principal amount, in OHM decimals.
    /// @return healthFactor Position health factor, scaled by 1e18.
    function positionHealthFactor(
        address asset_,
        uint256 collateral_,
        uint256 debtOhm_
    ) external view returns (uint256 healthFactor);

    /// @notice Projects claimable custody yield for one registered collateral asset.
    /// @dev Reverts if Burner Loans is disabled, the asset is unregistered, custody is unsupported,
    ///      or a solvent nonzero recipient allocation has an invalid live route. Insolvent custody
    ///      returns `preview.executable == false` and zero claimable yield.
    /// @param asset_ Collateral asset whose yield claim is previewed.
    /// @return preview Projected collateral-yield claim result.
    function previewClaimYield(
        address asset_
    ) external view returns (ClaimYieldPreview memory preview);

    /// @notice Returns DepositManager custody accounting for a registered collateral asset.
    /// @dev Reverts if the asset is unregistered or its custody configuration is unsupported.
    /// @param asset_ Collateral asset whose custody status is queried.
    /// @return status Current collateral accounting status.
    function getAssetCollateralStatus(
        address asset_
    ) external view returns (AssetCollateralStatus memory status);
}
