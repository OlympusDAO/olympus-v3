// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans Lifecycle Interface
/// @notice State-changing borrower lifecycle operations.
interface IBurnerLoansLifecycle is IBurnerLoans {
    /// @notice Binds the Burner Loans Inventory used for OHM funding and principal accounting.
    /// @dev Callable only by OCG admin while Burner Loans is globally disabled. The new
    ///      BurnerLoansInventory must be a same-Kernel compatible contract, use the same OHM, and be
    ///      permanently bound to this facility. It must be active and enabled before Burner Loans is
    ///      enabled. Version migration remains an operational responsibility and is not inferred
    ///      from the outgoing contract's accounting.
    /// @param inventory_ Burner Loans Inventory policy to bind.
    function setInventory(address inventory_) external;

    /// @notice Sets the Burner Loans Config policy authorized to configure this facility.
    /// @dev Callable only by OCG admin while Burner Loans is globally disabled. The policy must be
    ///      same-Kernel, compatible, and currently point back to this facility.
    /// @param configurator_ Burner Loans Config policy to authorize.
    function setConfigurator(address configurator_) external;

    /// @notice Deposits exact-transfer collateral into a borrower's position.
    /// @dev Reverts when the safe token transfer fails or DepositManager observes an inexact receipt.
    ///      Callback attempts to another lifecycle action revert through the shared reentrancy guard.
    /// @param asset_ Collateral asset to deposit.
    /// @param amount_ Amount to deposit, in collateral-token decimals.
    /// @param onBehalfOf_ Borrower receiving the collateral credit.
    /// @return depositedCollateral Collateral credited in collateral-token decimals.
    /// @return totalCollateral Borrower's resulting collateral in collateral-token decimals.
    function depositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external returns (uint256 depositedCollateral, uint256 totalCollateral);

    /// @notice Withdraws credited collateral from a borrower's position.
    /// @dev Assumes governance admitted an exact-transfer asset. Reverts when the safe outgoing
    ///      transfer fails. Callback attempts to another lifecycle action revert through the shared
    ///      reentrancy guard.
    /// @param asset_ Collateral asset to withdraw.
    /// @param amount_ Amount to remove from credited collateral, in collateral-token decimals.
    /// @param onBehalfOf_ Borrower whose position is updated.
    /// @param recipient_ Account receiving the withdrawn collateral.
    /// @return tokenOut Collateral token returned.
    /// @return amountOut Collateral assets withdrawn, in collateral-token decimals.
    /// @return remainingDepositedCollateral Borrower's remaining credited collateral, in collateral-token decimals.
    /// @return healthFactor Borrower's post-withdrawal health factor, scaled by 1e18.
    function withdrawCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_,
        address recipient_
    )
        external
        returns (
            address tokenOut,
            uint256 amountOut,
            uint256 remainingDepositedCollateral,
            uint256 healthFactor
        );

    /// @notice Borrows OHM against a collateral position.
    /// @param asset_ Collateral asset securing the loan.
    /// @param ohmAmount_ Principal requested in OHM token decimals.
    /// @param onBehalfOf_ Borrower whose position receives the debt.
    /// @param recipient_ Account receiving borrowed OHM.
    /// @param maxFee_ Maximum collateral fee accepted, in collateral-token decimals.
    /// @return borrowedOhm Principal borrowed in OHM token decimals.
    /// @return feeCollateral Origination fee in collateral-token decimals.
    /// @return totalDebtOhm Resulting principal in OHM token decimals.
    /// @return maturity Resulting maturity timestamp.
    /// @return healthFactor Resulting health factor, scaled by 1e18.
    function borrow(
        address asset_,
        uint128 ohmAmount_,
        address onBehalfOf_,
        address recipient_,
        uint256 maxFee_
    )
        external
        returns (
            uint256 borrowedOhm,
            uint256 feeCollateral,
            uint256 totalDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        );

    /// @notice Repays OHM principal for a borrower.
    /// @param asset_ Collateral asset identifying the market.
    /// @param repayOhm_ Principal to repay in OHM token decimals.
    /// @param onBehalfOf_ Borrower whose debt is reduced.
    /// @return healthFactor Conservative post-repayment health factor, scaled by 1e18.
    function repay(
        address asset_,
        uint128 repayOhm_,
        address onBehalfOf_
    ) external returns (uint256 healthFactor);

    /// @notice Extends an active position's maturity and charges any applicable fee.
    /// @param asset_ Collateral asset identifying the market.
    /// @param onBehalfOf_ Borrower whose maturity is extended.
    /// @param termCount_ Number of configured terms to add.
    /// @param maxFee_ Maximum collateral fee accepted, in collateral-token decimals.
    /// @return fee Fee charged in collateral-token decimals.
    /// @return maturity Resulting maturity timestamp.
    /// @return healthFactor Resulting health factor, scaled by 1e18.
    function extend(
        address asset_,
        address onBehalfOf_,
        uint16 termCount_,
        uint256 maxFee_
    ) external returns (uint256 fee, uint48 maturity, uint256 healthFactor);

    /// @notice Defaults eligible positions and routes seized collateral.
    /// @param asset_ Collateral asset shared by the positions.
    /// @param borrowers_ Borrowers whose positions are seized.
    /// @return keeperReward Keeper reward in collateral-token decimals.
    /// @return collateralToTreasury Collateral routed to treasury in collateral-token decimals.
    function seize(
        address asset_,
        address[] calldata borrowers_
    ) external returns (uint256 keeperReward, uint256 collateralToTreasury);

    /// @notice Claims excess collateral yield for the treasury.
    /// @param asset_ Collateral asset whose custody yield is claimed.
    /// @return yieldClaimed Yield transferred to treasury in collateral-token decimals.
    function harvestYield(address asset_) external returns (uint256 yieldClaimed);
}
