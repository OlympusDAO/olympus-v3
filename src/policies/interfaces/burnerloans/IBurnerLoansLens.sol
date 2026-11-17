// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

/// @notice Read-only positions, custody status, health and seizure scanning for one Core.
/// @dev Lens has no policy lifecycle. Economic queries use Core's currently selected Risk.
interface IBurnerLoansLens {
    /// @notice Seizure selection or the corresponding discovery cursor scope.
    enum Selection {
        All,
        Expired,
        Unhealthy
    }

    /// @notice The starting offset is outside the current active borrower list.
    /// @param start Requested zero-based offset.
    /// @param borrowerCount Current total active borrower count.
    error BurnerLoansLens_InvalidStart(uint256 start, uint256 borrowerCount);

    /// @notice Returns the borrower's position for an asset market.
    /// @param asset_ Registered underlying collateral token.
    /// @param borrower_ Borrower whose position is queried.
    /// @return position Collateral, principal, expiry and last-borrow block; zero fields if absent.
    function getPosition(
        address asset_,
        address borrower_
    ) external view returns (IBurnerLoansCore.Position memory position);

    /// @notice Returns borrowers with outstanding debt in the selected market.
    /// @param asset_ Registered underlying collateral token.
    /// @return borrowers Unique active borrower addresses; order can change after debt closure.
    function getActiveBorrowers(address asset_) external view returns (address[] memory borrowers);

    /// @notice Returns the market's current number of active debt borrowers.
    /// @param asset_ Registered collateral asset identifying the market.
    /// @return count Number of active borrowers, without allocating the borrower list.
    function getActiveBorrowerCount(address asset_) external view returns (uint256 count);

    /// @notice Returns aggregate outstanding principal for the selected market.
    /// @param asset_ Registered underlying collateral token.
    /// @return principal Outstanding principal in OHM token units.
    function assetActiveDebtOhm(address asset_) external view returns (uint256 principal);

    /// @notice Quotes position health under current Risk prices and configuration.
    /// @param asset_ Underlying collateral token identifying the risk configuration.
    /// @param collateral_ Collateral amount in underlying token units.
    /// @param debt_ Outstanding principal in OHM token units.
    /// @return healthFactor Health rounded down and scaled by 1e18, or uint256.max for zero debt.
    function positionHealthFactor(
        address asset_,
        uint256 collateral_,
        uint256 debt_
    ) external view returns (uint256 healthFactor);

    /// @notice Returns whether a debt-bearing position is expired or unhealthy.
    /// @param asset_ Registered underlying collateral token.
    /// @param borrower_ Borrower whose position is queried.
    /// @return seizable True at or after expiry, or when unexpired health is below 1e18.
    function isSeizable(address asset_, address borrower_) external view returns (bool seizable);

    /// @notice Returns DepositManager coverage for the Core operator namespace.
    /// @param asset_ Registered underlying collateral token.
    /// @return collateralStatus Shares, held assets, borrowed coverage, liabilities, solvency and yield.
    function getAssetCollateralStatus(
        address asset_
    ) external view returns (IBurnerLoansCore.AssetCollateralStatus memory collateralStatus);

    /// @notice Scans active borrowers and quotes rewards for msg.sender.
    /// @param asset_ Registered underlying collateral token.
    /// @param start_ Zero-based offset in the active borrower list; must be below the nonempty borrower count, or zero for an empty market.
    /// @param count_ Maximum borrowers examined, clipped to the remaining suffix.
    /// @return borrowers All eligible borrowers in the examined forward-only page.
    /// @return nextCursor Next unexamined index, or zero at the end; this call never wraps.
    /// @return keeperReward Estimated reward for msg.sender, in withdrawal-output token units.
    function getSeizableBorrowers(
        address asset_,
        uint256 start_,
        uint256 count_
    ) external view returns (address[] memory borrowers, uint256 nextCursor, uint256 keeperReward);

    /// @notice Scans active borrowers and quotes rewards for an explicit actor.
    /// @param actor_ Reward identity, independent of the caller; conveys no borrower authorization.
    /// @param asset_ Registered underlying collateral token.
    /// @param start_ Zero-based offset in the active borrower list; must be below the nonempty borrower count, or zero for an empty market.
    /// @param count_ Maximum borrowers examined, clipped to the remaining suffix.
    /// @return borrowers All eligible borrowers in the examined forward-only page.
    /// @return nextCursor Next unexamined index, or zero at the end; this call never wraps.
    /// @return keeperReward Estimated reward for actor_, in withdrawal-output token units.
    function getSeizableBorrowersFor(
        address actor_,
        address asset_,
        uint256 start_,
        uint256 count_
    ) external view returns (address[] memory borrowers, uint256 nextCursor, uint256 keeperReward);

    /// @notice Scans a bounded page and stops as soon as the result limit is reached.
    /// @param actor_ Reward identity, independent of the caller.
    /// @param asset_ Registered underlying collateral token.
    /// @param start_ Zero-based offset, with the same validity rules as getSeizableBorrowersFor.
    /// @param count_ Maximum active borrowers examined, clipped to the remaining suffix.
    /// @param maxResults_ Maximum eligible borrowers returned; zero performs no scan work.
    /// @return borrowers Eligible borrowers in scan order, up to maxResults_.
    /// @return nextCursor First unexamined borrower index in the active borrower list, or zero at the end; no candidate is discarded.
    /// @return keeperReward Estimated reward for actor_ over the returned borrowers.
    function getSeizableBorrowersBoundedFor(
        address actor_,
        address asset_,
        uint256 start_,
        uint256 count_,
        uint256 maxResults_
    ) external view returns (address[] memory borrowers, uint256 nextCursor, uint256 keeperReward);

    /// @notice Selects only expired debt and quotes the aggregate reward for an explicit actor.
    /// @dev Unexpired positions are skipped without classifying their health. Protocol actors receive
    ///      zero without price reads. Risk owns reward pricing, including zero-configured-reward
    ///      shortcuts. Selection and reward estimation do not assert Seize execution admission.
    /// @param actor_ Reward identity, independent of the caller; conveys no execution authority.
    /// @param asset_ Registered underlying collateral token.
    /// @param start_ Zero-based offset, with the same validity rules as getSeizableBorrowersFor.
    /// @param count_ Maximum active borrowers examined, clipped to the remaining suffix.
    /// @param maxResults_ Maximum expired borrowers returned; zero performs no scan work.
    /// @return borrowers Borrowers with positive principal and maturity at or before now, in scan order.
    /// @return nextCursor First unexamined borrower index in the active borrower list, or zero at the end; no wrap within the call.
    /// @return keeperReward Estimated aggregate reward for actor_, in withdrawal-output token units.
    function getExpiredBorrowersBoundedFor(
        address actor_,
        address asset_,
        uint256 start_,
        uint256 count_,
        uint256 maxResults_
    ) external view returns (address[] memory borrowers, uint256 nextCursor, uint256 keeperReward);

    /// @notice Scans only unexpired borrowers with positive debt and health below 1e18.
    /// @param actor_ Reward identity, independent of the caller.
    /// @param asset_ Registered underlying collateral token.
    /// @param start_ Zero-based offset in the active borrower list.
    /// @param count_ Maximum list entries examined, clipped to the remaining suffix.
    /// @param maxResults_ Maximum unhealthy borrowers selected before stopping.
    /// @return borrowers Unexpired unhealthy borrowers in active-list order; maturity equality is excluded.
    /// @return nextCursor First unexamined index, or zero at the end; the scan does not wrap.
    /// @return keeperReward Aggregate custody/reward quote for the actor and selected borrowers.
    function getUnhealthyBorrowersBoundedFor(
        address actor_,
        address asset_,
        uint256 start_,
        uint256 count_,
        uint256 maxResults_
    ) external view returns (address[] memory borrowers, uint256 nextCursor, uint256 keeperReward);
}
