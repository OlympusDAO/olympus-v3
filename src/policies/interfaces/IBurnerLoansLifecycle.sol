// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Lifecycle Interface
/// @notice State-changing borrower lifecycle operations.
interface IBurnerLoansLifecycle {
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
    /// @param configurator_ Burner Loans Config policy to bind.
    function setConfigurator(address configurator_) external;

    /// @notice Adds a collateral asset after Config creates its FLOAN market.
    /// @dev Reverts if:
    ///      - Burner Loans is disabled.
    ///      - The caller is not the bound Config policy.
    ///      - The FLOAN market does not exist, is ambiguous, or has incompatible configuration.
    ///      - The asset is already registered.
    /// @param asset_ Collateral asset to append to the facility registry.
    function addAsset(address asset_) external;

    /// @notice Sets the facility-wide recipient of configured collateral-yield shares.
    /// @dev Callable only while Burner Loans is enabled and by its currently bound Config policy. A
    ///      nonzero recipient must be an active, globally enabled same-Kernel policy implementing
    ///      `IYieldRecipient` and `IEnabler`. Setting zero requires all per-asset allocations to be
    ///      cleared first. Nonzero rotation preserves every allocation and validates every nonzero
    ///      asset route before changing state; each pair is validated again when yield is claimed.
    /// @param recipient_ New yield recipient, or zero after all allocations are cleared.
    function setYieldRecipient(address recipient_) external;

    /// @notice Sets the share of an asset's claimed yield routed to the facility recipient.
    /// @dev Reverts if:
    ///      - Burner Loans is disabled.
    ///      - The caller is not the bound Config policy.
    ///      - The asset is not registered or `bps_` exceeds 10_000.
    ///      - The yield recipient is zero.
    ///      - For nonzero `bps_`, the recipient lacks a required interface, is not an active Kernel
    ///        policy, is disabled, or its vault route does not match DepositManager.
    ///      A zero value remains available to clear an allocation after recipient drift.
    /// @param asset_ Collateral asset whose allocation is changed.
    /// @param bps_ Recipient share in basis points.
    function setYieldRecipientAssetBps(address asset_, uint16 bps_) external;

    /// @notice Deposits exact-transfer collateral into a borrower's position.
    /// @dev Callable by the borrower or an authorized operator. Reverts if Burner Loans, the
    ///      market, or custody route is disabled; the caller is unauthorized; the asset is
    ///      unconfigured; the amount is zero; the safe transfer fails or is inexact; no collateral
    ///      is credited; or a callback enters another protected lifecycle action.
    /// @param asset_ Collateral asset to deposit.
    /// @param amount_ Collateral amount transferred from the caller.
    /// @param onBehalfOf_ Borrower whose position receives the collateral credit.
    /// @return depositedAmount Collateral credited in collateral token decimals.
    /// @return resultingCollateral Borrower's resulting collateral in collateral token decimals.
    function depositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external returns (uint256 depositedAmount, uint256 resultingCollateral);

    /// @notice Withdraws credited collateral from a borrower's position.
    /// @dev Asset-origination and DepositManager-period disable do not block this exit. Reverts if:
    ///      - Burner Loans or DepositManager is disabled.
    ///      - The caller is unauthorized or the asset, custody period, or position is unavailable.
    ///      - The withdrawal is zero, exceeds collateral, returns zero assets, or leaves an
    ///        indebted position unhealthy.
    ///      - The outgoing transfer fails or a callback enters another protected lifecycle action.
    ///      The requested collateral credit is debited when ERC-4626 rounding returns fewer nonzero
    ///      assets. Callers can inspect the projected output with `previewWithdrawCollateral`.
    /// @param asset_ Collateral asset to withdraw.
    /// @param amount_ Asset-denominated collateral credit to debit from the position.
    /// @param onBehalfOf_ Borrower whose position is debited.
    /// @param recipient_ Account that receives the withdrawn collateral.
    /// @return tokenOut Collateral token returned.
    /// @return amountOut Actual nonzero collateral assets withdrawn. May be less than `amount_`.
    /// @return remainingDepositedCollateral Borrower's remaining collateral credit.
    /// @return healthFactor Borrower's health factor after the withdrawal, scaled by 1e18.
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
    /// @dev Reverts if:
    ///      - Burner Loans, asset originations, or Burner Loans Inventory is disabled.
    ///      - The caller is unauthorized or the market or position is unavailable.
    ///      - The amount or recipient is zero, or PRICE, backing, maturity, or health validation
    ///        fails.
    ///      - A debt cap is exceeded, the fee exceeds `maxFee_`, or its transfer fails.
    ///      - FLOAN cannot store the debt increase or Inventory cannot fund the exact amount.
    /// @param asset_ Collateral asset securing the position.
    /// @param ohmAmount_ Principal requested, in OHM decimals.
    /// @param onBehalfOf_ Borrower whose debt is increased.
    /// @param recipient_ Account that receives the borrowed OHM.
    /// @param maxFee_ Maximum origination fee accepted, in collateral token decimals.
    /// @return principal Principal borrowed, in OHM decimals.
    /// @return fee Origination fee, in collateral token decimals.
    /// @return resultingDebtOhm Principal returned by FLOAN after the mutation, in OHM decimals.
    /// @return maturity Maturity returned by FLOAN after the mutation.
    /// @return healthFactor Health calculated from FLOAN's resulting position, scaled by 1e18.
    function borrow(
        address asset_,
        uint128 ohmAmount_,
        address onBehalfOf_,
        address recipient_,
        uint256 maxFee_
    )
        external
        returns (
            uint256 principal,
            uint256 fee,
            uint256 resultingDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        );

    /// @notice Repays OHM principal for a borrower.
    /// @dev Permissionless on behalf of any borrower. Reverts if:
    ///      - Burner Loans or Burner Loans Inventory is disabled.
    ///      - The asset or debt position is unavailable.
    ///      - The amount is zero, exceeds principal, or is submitted in the latest borrow block.
    ///      - The OHM transfer fails or Inventory receives an inexact amount.
    ///      - FLOAN debt reduction or Inventory settlement fails.
    /// @param asset_ Collateral asset securing the position.
    /// @param repayOhm_ Principal to repay, in OHM decimals.
    /// @param onBehalfOf_ Borrower whose debt is reduced.
    /// @return remainingDebtOhm Principal returned by FLOAN after repayment, in OHM decimals.
    /// @return healthFactor Max uint after full repayment; zero when partial repayment deliberately
    ///         avoids a live PRICE read.
    function repay(
        address asset_,
        uint128 repayOhm_,
        address onBehalfOf_
    ) external returns (uint256 remainingDebtOhm, uint256 healthFactor);

    /// @notice Extends an active position's maturity and charges any applicable fee.
    /// @dev Reverts if Burner Loans or originations are disabled, the caller is unauthorized, the
    ///      asset or position is unavailable, the term count is invalid, the position is matured or
    ///      unhealthy, the resulting maturity exceeds its horizon, the fee exceeds `maxFee_`, or
    ///      the collateral-fee transfer to Treasury fails.
    /// @param asset_ Collateral asset securing the position.
    /// @param onBehalfOf_ Borrower whose maturity is extended.
    /// @param termCount_ Number of configured terms added to the maturity.
    /// @param maxFee_ Maximum extension fee accepted, in collateral token decimals.
    /// @return fee Extension fee charged, in collateral token decimals.
    /// @return maturity Resulting maturity timestamp.
    /// @return healthFactor Resulting health factor, scaled by 1e18.
    function extend(
        address asset_,
        address onBehalfOf_,
        uint16 termCount_,
        uint256 maxFee_
    ) external returns (uint256 fee, uint48 maturity, uint256 healthFactor);

    /// @notice Defaults eligible positions and routes seized collateral.
    /// @dev Permissionless and available while asset originations are disabled. Reverts if Burner
    ///      Loans or custody is disabled, the asset is unavailable, the batch is empty or too large,
    ///      a borrower is duplicated or not seizable, custody is insolvent, or a transfer fails.
    /// @param asset_ Collateral asset seized and distributed.
    /// @param borrowers_ Borrowers whose positions are seized atomically.
    /// @return keeperReward Keeper reward in collateral token decimals.
    /// @return collateralToTreasury Collateral routed to Treasury.
    function seize(
        address asset_,
        address[] calldata borrowers_
    ) external returns (uint256 keeperReward, uint256 collateralToTreasury);
}
