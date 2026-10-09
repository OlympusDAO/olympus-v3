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
    ///      same-Kernel, compatible, and currently point back to this facility. A different nonzero
    ///      replacement atomically transfers every registered FLOAN market manager from the outgoing
    ///      Config before storing and emitting the new address. Initial and same-address assignments
    ///      do not write market managers. Registered assets must have matching markets managed by
    ///      the outgoing Config before their managers can be transferred.
    ///      Any failure rolls back all earlier manager updates in the transaction.
    /// @param configurator_ Burner Loans Config policy to bind.
    function setConfigurator(address configurator_) external;

    /// @notice Sets the optional PriceCache used by Burner Loans.
    /// @dev Callable only by OCG admin while Burner Loans is enabled or disabled. Zero selects
    ///      direct PRICE mode. A nonzero candidate must implement the PriceCache, enabler, and
    ///      version interfaces, use a compatible version, and belong to the same Kernel.
    /// @param priceCache_ New PriceCache policy, or zero to use PRICE directly.
    function setPriceCache(address priceCache_) external;

    /// @notice Sets the shared revenue distributor pointer, or clears it when both send flags are
    ///         false. The current address is an authorized no-op.
    /// @dev Admin-only. A nonzero candidate must be an active same-Kernel distributor policy.
    function setRevenueDistributor(address distributor_) external;

    /// @notice Sets whether collateral fees are sent to the distributor.
    /// @dev Callable only by the bound Config policy. Enabling validates the distributor identity.
    function setSendFeesToDistributor(bool enabled_) external;

    /// @notice Sets whether custody yield is sent to the distributor.
    /// @dev Callable only by the bound Config policy. Enabling validates the distributor identity.
    function setSendYieldToDistributor(bool enabled_) external;

    /// @notice Sets the maximum age of cached prices used by Burner Loans.
    /// @dev Callable only by the configured Burner Loans Config policy while Burner Loans is
    ///      enabled. Every `uint48` value is valid, including zero and `type(uint48).max`.
    /// @param priceCacheMaxAge_ New maximum cached-price age, in seconds.
    function setPriceCacheMaxAge(uint48 priceCacheMaxAge_) external;

    /// @notice Adds a collateral asset after Config creates its FLOAN market.
    /// @dev The bound Config policy adds an asset after its FLOAN market is ready.
    /// @param asset_ Collateral asset to append to the facility registry.
    function addAsset(address asset_) external;

    /// @notice Retries amounts currently owed to one recipient for a token.
    /// @dev Permissionless while Burner Loans is Kernel-active and enabled.
    ///      The recipient may be an original keeper, current fee destination, current Treasury,
    ///      or more than one of these. Zero pending balances are no-ops. Rejected transfers remain owed.
    /// @return transferred Sum of fee, seized collateral, and keeper reward actually delivered.
    function transferPendingPayout(
        address token_,
        address recipient_
    ) external returns (uint256 transferred);

    /// @notice Deposits exact-transfer collateral into a borrower's position.
    /// @dev Callable by the borrower or an authorized operator. Collateral custody requires an
    ///      exact incoming transfer.
    /// @param asset_ Collateral asset to deposit.
    /// @param amount_ Collateral amount transferred from the caller.
    /// @param onBehalfOf_ Borrower whose position receives the collateral credit.
    /// @return depositedAmount Collateral credited in collateral token decimals.
    /// @return resultingCollateral Borrower's resulting collateral in collateral token decimals.
    /// @return healthFactor Borrower's health factor after the deposit, scaled by 1e18.
    function depositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external returns (uint256 depositedAmount, uint256 resultingCollateral, uint256 healthFactor);

    /// @notice Withdraws credited collateral from a borrower's position.
    /// @dev Asset-origination and DepositManager-period disable do not block this exit. The
    ///      requested collateral credit is debited when ERC-4626 rounding returns fewer nonzero
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
    /// @dev The first borrow in a debt episode establishes its maturity from the current term. An
    ///      additional borrow joins the aggregate position without changing its existing maturity,
    ///      including after the configured term or horizon is reduced. A failed outgoing fee payout
    ///      remains owed without interrupting the borrow.
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
    /// @dev Permissionless on behalf of any borrower.
    /// @param asset_ Collateral asset securing the position.
    /// @param repayOhm_ Principal to repay, in OHM decimals.
    /// @param onBehalfOf_ Borrower whose debt is reduced.
    /// @return remainingDebtOhm Principal returned by FLOAN after repayment, in OHM decimals.
    /// @return healthFactor Borrower's health factor after repayment, scaled by 1e18. Returns max
    ///         uint after full repayment.
    function repay(
        address asset_,
        uint128 repayOhm_,
        address onBehalfOf_
    ) external returns (uint256 remainingDebtOhm, uint256 healthFactor);

    /// @notice Extends an active position's maturity and charges any applicable fee.
    /// @dev Applies the currently configured term length and maturity horizon to the position's
    ///      entire outstanding principal; configuration present when the debt episode began does
    ///      not guarantee a future extension. A failed outgoing fee payout remains owed without
    ///      interrupting the extension.
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
    /// @dev Permissionless and available while asset originations are disabled. Failed outgoing
    ///      payouts remain owed without interrupting seizure.
    ///      A share-mode seizure that rounds to zero still defaults the positions and returns the
    ///      share token with zero reward and Treasury output. Retained share dust becomes custody
    ///      yield after the collateral liability is removed.
    /// @param asset_ Collateral asset seized and distributed.
    /// @param borrowers_ Borrowers whose positions are seized atomically.
    /// @return tokenOut Token distributed by the seizure.
    /// @return keeperReward Keeper reward owed in `tokenOut` decimals, delivered or pending.
    /// @return collateralToTreasury Amount owed to Treasury in `tokenOut` decimals, delivered or pending.
    function seize(
        address asset_,
        address[] calldata borrowers_
    ) external returns (address tokenOut, uint256 keeperReward, uint256 collateralToTreasury);
}
