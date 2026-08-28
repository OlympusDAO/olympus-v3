// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Declarations
/// @notice Shared errors, events, and data types for the Burner Loans contracts.
/// @dev This declarations-only interface keeps tuple types consistent without forcing lifecycle,
///      view, and configuration contracts to implement each other's selectors.
interface IBurnerLoans {
    error BurnerLoans_ZeroAddress();
    /// @notice The supplied collateral asset cannot be used by Burner Loans.
    /// @param asset Invalid collateral asset.
    error BurnerLoans_InvalidCollateralAsset(address asset);
    error BurnerLoans_InvalidDecimals(uint8 decimals);
    error BurnerLoans_InvalidPrice();
    error BurnerLoans_InvalidParam();
    error BurnerLoans_InvalidBps(uint256 bps);
    error BurnerLoans_InvalidCap();
    error BurnerLoans_InvalidDepositManager(address depositManager);
    /// @notice The supplied Burner Loans Inventory does not implement the expected interface.
    error BurnerLoans_InvalidInventory(address inventory);
    /// @notice The supplied Burner Loans Inventory funds a different OHM token.
    error BurnerLoans_InventoryOhmMismatch(address expectedOhm, address actualOhm);
    /// @notice The supplied Burner Loans Inventory is permanently bound to another facility.
    error BurnerLoans_InventoryFacilityMismatch(address expectedFacility, address actualFacility);
    /// @notice The supplied Burner Loans Inventory is not an active policy in Burner Loans' Kernel.
    error BurnerLoans_InventoryNotActive(address inventory);
    /// @notice The supplied Burner Loans Inventory is globally disabled.
    error BurnerLoans_InventoryNotEnabled(address inventory);
    /// @notice A repayment transfer delivered a different amount to Burner Loans Inventory.
    error BurnerLoans_InexactRepaymentTransfer(uint256 expected, uint256 actual);
    /// @notice The configured backing oracle does not implement IOlympusBackingOracle.
    /// @param backingOracle Invalid backing oracle address.
    error BurnerLoans_InvalidBackingOracle(address backingOracle);
    /// @notice The configured DepositManager belongs to a different Kernel.
    /// @param expectedKernel Kernel supplied to Burner Loans.
    /// @param actualKernel Kernel reported by DepositManager.
    error BurnerLoans_DepositManagerKernelMismatch(address expectedKernel, address actualKernel);
    error BurnerLoans_ZeroAmount();
    error BurnerLoans_ZeroCollateralCredit();
    error BurnerLoans_ZeroCollateralWithdrawal();
    error BurnerLoans_InsufficientCollateral(uint256 requested, uint256 available);
    error BurnerLoans_UnhealthyWithdrawal(uint256 healthFactor);
    error BurnerLoans_NoCollateral();
    error BurnerLoans_NoDebt();
    error BurnerLoans_RepayExceedsDebt(uint256 requested, uint256 debt);
    error BurnerLoans_SameBlockRepay(uint48 borrowBlock);
    error BurnerLoans_MaturityHorizonExceeded(uint256 requested, uint256 maximum);
    /// @notice An extension does not move the position maturity beyond the current timestamp.
    /// @param requested Resulting maturity calculated from the position's previous maturity.
    /// @param currentTimestamp Current block timestamp.
    error BurnerLoans_ExtensionMaturityNotFuture(uint256 requested, uint256 currentTimestamp);
    error BurnerLoans_UnhealthyPosition(uint256 healthFactor);
    error BurnerLoans_UnhealthyBorrow(uint256 healthFactor);
    error BurnerLoans_PositionMatured(uint48 maturity);
    error BurnerLoans_GlobalDebtCapExceeded(uint256 requestedDebtOhm, uint256 availableDebtOhm);
    error BurnerLoans_AssetDebtCapExceeded(
        address asset,
        uint256 requestedDebtOhm,
        uint256 availableDebtOhm
    );
    error BurnerLoans_FeeExceedsMax(uint256 fee, uint256 maxFee);
    error BurnerLoans_ResidualCollateralBalance(address asset, uint256 balance);
    error BurnerLoans_ReceiptApprovalFailed(address receiptTokenManager);
    error BurnerLoans_AssetAlreadyConfigured(address asset);
    error BurnerLoans_AssetNotConfigured(address asset);
    error BurnerLoans_AmbiguousMarket(address asset, uint256 marketCount);
    /// @notice The resolved FLOAN market does not use the Burner Loans configuration schema.
    /// @param marketId Incompatible FLOAN market identifier.
    /// @param configId Actual configuration schema identifier stored by the market.
    error BurnerLoans_IncompatibleMarketConfig(uint32 marketId, bytes16 configId);
    /// @notice A Burner Loans market's encoded product data has an invalid length.
    /// @param marketId FLOAN market containing the invalid data.
    /// @param length Actual encoded data length.
    error BurnerLoans_InvalidMarketConfigData(uint32 marketId, uint256 length);
    error BurnerLoans_AssetOriginationsDisabled(address asset);
    error BurnerLoans_InvalidFeeConfig();
    error BurnerLoans_InvalidModuleVersion();
    error BurnerLoans_InvalidBatch();
    error BurnerLoans_DuplicateBorrower(address borrower);
    error BurnerLoans_PositionNotSeizable(address borrower);
    error BurnerLoans_CustodyShortfall(
        address asset,
        uint256 liabilities,
        uint256 assets,
        uint256 borrowed
    );

    /// @notice Borrower position represented by the lifecycle policy.
    /// @param depositedCollateral Credited collateral in collateral-token decimals.
    /// @param debtOhm Outstanding principal in OHM token decimals.
    /// @param maturity Maturity timestamp in seconds.
    /// @param lastBorrowBlock Block number of the latest borrow.
    struct Position {
        uint256 depositedCollateral;
        uint256 debtOhm;
        uint48 maturity;
        uint48 lastBorrowBlock;
    }

    /// @notice Complete configuration for one collateral market.
    /// @param originationsEnabled Whether deposits, borrows, and extensions are enabled.
    /// @param collateralDecimals Decimal precision of the collateral token.
    /// @param collateralFactorBps Recognized collateral value in basis points.
    /// @param minCollateralRatioBps Minimum collateral ratio in basis points.
    /// @param backingMultiplierBps Backing requirement multiplier in basis points.
    /// @param keeperRewardBps Keeper reward rate in basis points.
    /// @param termLength Standard loan term in seconds.
    /// @param maxMaturityHorizon Maximum maturity distance from the current timestamp.
    /// @param debtCap Maximum live principal in OHM token decimals.
    /// @param maxKeeperReward Maximum keeper reward in collateral-token decimals.
    struct AssetConfig {
        bool originationsEnabled;
        uint8 collateralDecimals;
        uint16 collateralFactorBps;
        uint16 minCollateralRatioBps;
        uint16 backingMultiplierBps;
        uint16 keeperRewardBps;
        uint48 termLength;
        uint48 maxMaturityHorizon;
        uint256 debtCap;
        uint256 maxKeeperReward;
    }

    /// @notice Caller-supplied risk configuration for one collateral market.
    /// @param collateralFactorBps Recognized collateral value in basis points.
    /// @param minCollateralRatioBps Minimum collateral ratio in basis points.
    /// @param backingMultiplierBps Backing requirement multiplier in basis points.
    /// @param keeperRewardBps Keeper reward rate in basis points.
    /// @param termLength Standard loan term in seconds.
    /// @param maxMaturityHorizon Maximum maturity distance from the current timestamp.
    /// @param maxKeeperReward Maximum keeper reward in collateral-token decimals.
    struct AssetRiskConfigInput {
        uint16 collateralFactorBps;
        uint16 minCollateralRatioBps;
        uint16 backingMultiplierBps;
        uint16 keeperRewardBps;
        uint48 termLength;
        uint48 maxMaturityHorizon;
        uint256 maxKeeperReward;
    }

    /// @notice Utilization-based collateral fee configuration.
    /// @param baseFeeBps Base fee rate in basis points.
    /// @param kinkBps Utilization kink in basis points.
    /// @param preKinkSlopeBps Fee slope below the kink in basis points.
    /// @param postKinkSlopeBps Fee slope above the kink in basis points.
    struct AssetFeeConfig {
        uint16 baseFeeBps;
        uint16 kinkBps;
        uint16 preKinkSlopeBps;
        uint16 postKinkSlopeBps;
    }

    /// @notice Projected result of an OHM borrow.
    /// @param fee Collateral fee in collateral-token decimals.
    /// @param resultingDebtOhm Resulting principal in OHM token decimals.
    /// @param resultingHealthFactor Resulting health factor, scaled by 1e18.
    /// @param maturity Resulting maturity timestamp.
    /// @param executable Whether the quoted operation is executable.
    struct BorrowPreview {
        uint256 fee;
        uint256 resultingDebtOhm;
        uint256 resultingHealthFactor;
        uint48 maturity;
        bool executable;
    }

    /// @notice Projected result of an OHM repayment.
    /// @param repayAmount Principal repaid in OHM token decimals.
    /// @param remainingDebtOhm Remaining principal in OHM token decimals.
    /// @param resultingHealthFactor Resulting health factor, scaled by 1e18.
    /// @param executable Whether the quoted operation is executable.
    struct RepayPreview {
        uint256 repayAmount;
        uint256 remainingDebtOhm;
        uint256 resultingHealthFactor;
        bool executable;
    }

    /// @notice Projected result of a collateral withdrawal.
    /// @param returnToken Token returned to the recipient.
    /// @param returnAmount Assets returned in `returnToken` decimals.
    /// @param remainingDepositedCollateral Remaining credited collateral in collateral-token decimals.
    /// @param resultingHealthFactor Resulting health factor, scaled by 1e18.
    /// @param executable Whether the quoted operation is executable.
    struct WithdrawPreview {
        address returnToken;
        uint256 returnAmount;
        uint256 remainingDepositedCollateral;
        uint256 resultingHealthFactor;
        bool executable;
    }

    /// @notice Projected result of a maturity extension.
    /// @param fee Collateral fee in collateral-token decimals.
    /// @param maturity Resulting maturity timestamp.
    /// @param healthFactor Current health factor, scaled by 1e18.
    /// @param executable Whether the quoted operation is executable.
    struct ExtendPreview {
        uint256 fee;
        uint48 maturity;
        uint256 healthFactor;
        bool executable;
    }

    /// @notice Projected result of a seizure batch.
    /// @param seizedDebtOhm Defaulted principal in OHM token decimals.
    /// @param seizedCollateral Collateral removed in collateral-token decimals.
    /// @param collateralToTreasury Collateral routed to treasury in collateral-token decimals.
    /// @param keeperReward Keeper reward in collateral-token decimals.
    /// @param executable Whether the quoted operation is executable.
    struct SeizePreview {
        uint256 seizedDebtOhm;
        uint256 seizedCollateral;
        uint256 collateralToTreasury;
        uint256 keeperReward;
        bool executable;
    }

    /// @notice Projected collateral-yield harvest.
    /// @param amount Claimable yield in collateral-token decimals.
    /// @param executable Whether custody is solvent and the harvest is executable.
    struct HarvestPreview {
        uint256 amount;
        bool executable;
    }

    /// @notice Custody accounting for one collateral asset.
    /// @param shares DepositManager shares credited to the facility.
    /// @param assets Redeemable collateral assets in collateral-token decimals.
    /// @param borrowed Collateral borrowed from custody in collateral-token decimals.
    /// @param liabilities Receipt-token liabilities in collateral-token decimals.
    /// @param claimableYield Excess collateral assets in collateral-token decimals.
    /// @param solvent Whether assets plus borrowed collateral cover liabilities.
    struct AssetCollateralStatus {
        uint256 shares;
        uint256 assets;
        uint256 borrowed;
        uint256 liabilities;
        uint256 claimableYield;
        bool solvent;
    }

    event CollateralDeposited(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 depositedAmount
    );
    event CollateralWithdrawn(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        address recipient,
        uint256 amount
    );
    event Borrowed(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        address recipient,
        uint256 ohmAmount,
        uint256 fee
    );
    /// @notice Emitted when the Burner Loans Inventory contract is bound or replaced.
    /// @param inventory New Burner Loans Inventory policy.
    event InventorySet(address indexed inventory);

    /// @notice Emitted when the Burner Loans Config policy is bound or replaced.
    /// @param configurator New Burner Loans Config policy.
    event ConfiguratorSet(address indexed configurator);

    event Repaid(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        uint256 repaidOhm,
        uint256 remainingDebtOhm
    );
    event Extended(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        uint48 maturity,
        uint256 fee
    );
    event Seized(
        address indexed caller,
        address indexed asset,
        address indexed borrower,
        uint256 debtOhm,
        uint256 collateral
    );
    event SeizureBatchSettled(
        address indexed caller,
        address indexed asset,
        uint256 borrowerCount,
        uint256 seizedDebtOhm,
        uint256 seizedCollateral,
        uint256 keeperReward,
        uint256 collateralToTreasury
    );
    event YieldHarvested(address indexed asset, uint256 amount);
    event BackingOracleSet(address indexed backingOracle);
    event AssetAdded(address indexed asset, AssetConfig config);
    event AssetDebtCapSet(address indexed asset, uint256 debtCapOhm);
    event AssetRiskConfigSet(address indexed asset, AssetRiskConfigInput config);
    event AssetFeeConfigSet(address indexed asset, AssetFeeConfig config);
    event AssetOriginationsSet(address indexed asset, bool enabled);
}
