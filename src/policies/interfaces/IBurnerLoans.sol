// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Declarations
/// @notice Shared errors, events, and data types for the Burner Loans contracts.
/// @dev This declarations-only interface keeps tuple types consistent without forcing lifecycle,
///      view, and configuration contracts to implement each other's selectors.
interface IBurnerLoans {
    error BurnerLoans_ZeroAddress();
    error BurnerLoans_NotImplemented();
    error BurnerLoans_InvalidDecimals(uint8 decimals);
    error BurnerLoans_InvalidPrice();
    error BurnerLoans_InvalidParam();
    error BurnerLoans_InvalidBps(uint256 bps);
    error BurnerLoans_InvalidCap();
    error BurnerLoans_InvalidDepositManager(address depositManager);
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
    error BurnerLoans_PositionSeized();
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
    error BurnerLoans_UnauthorizedConfigurator(address caller);
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

    /// @notice Emitted when remaining MINTR approval is reconciled to active debt capacity.
    event MintApprovalSynchronized(uint256 approval);

    enum PositionStatus {
        NoDebt,
        Active,
        Seized
    }

    struct Position {
        uint256 depositedCollateral;
        uint256 debtOhm;
        uint48 maturity;
        uint48 lastBorrowBlock;
        PositionStatus status;
    }

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

    struct AssetRiskConfigInput {
        uint16 collateralFactorBps;
        uint16 minCollateralRatioBps;
        uint16 backingMultiplierBps;
        uint16 keeperRewardBps;
        uint48 termLength;
        uint48 maxMaturityHorizon;
        uint256 maxKeeperReward;
    }

    struct AssetFeeConfig {
        uint16 baseFeeBps;
        uint16 kinkBps;
        uint16 preKinkSlopeBps;
        uint16 postKinkSlopeBps;
    }

    struct BorrowPreview {
        uint256 fee;
        uint256 resultingDebtOhm;
        uint256 resultingHealthFactor;
        uint48 maturity;
        bool executable;
    }

    struct RepayPreview {
        uint256 repayAmount;
        uint256 remainingDebtOhm;
        uint256 resultingHealthFactor;
        bool executable;
    }

    struct WithdrawPreview {
        address returnToken;
        uint256 returnAmount;
        uint256 remainingDepositedCollateral;
        uint256 resultingHealthFactor;
        bool executable;
    }

    struct ExtendPreview {
        uint256 fee;
        uint48 maturity;
        uint256 healthFactor;
        bool executable;
    }

    struct SeizePreview {
        uint256 seizedDebtOhm;
        uint256 seizedCollateral;
        uint256 collateralToTreasury;
        uint256 keeperReward;
        bool executable;
    }

    struct HarvestPreview {
        uint256 amount;
        bool executable;
    }

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

    event Repaid(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        uint256 repaidOhm,
        uint256 remainingDebtOhm
    );
    event Repaid(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        uint256 ohmAmount
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
    event GlobalDebtCapSet(uint256 debtCapOhm);
    event BackingOracleSet(address indexed backingOracle);
    event AssetAdded(address indexed asset, AssetConfig config);
    event AssetDebtCapSet(address indexed asset, uint256 debtCapOhm);
    event ConfiguratorSet(address indexed configurator);
    event AssetRiskConfigSet(address indexed asset, AssetRiskConfigInput config);
    event AssetFeeConfigSet(address indexed asset, AssetFeeConfig config);
    event AssetOriginationsSet(address indexed asset, bool enabled);
}
