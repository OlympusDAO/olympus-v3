// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Declarations
/// @notice Shared errors, events, and data types for the Burner Loans contracts.
/// @dev This declarations-only interface keeps tuple types consistent without forcing lifecycle,
///      view, and configuration contracts to implement each other's selectors.
interface IBurnerLoans {
    /// @notice A required address is zero.
    error BurnerLoans_ZeroAddress();

    /// @notice The supplied collateral asset cannot be used by Burner Loans.
    /// @param asset Invalid collateral asset.
    error BurnerLoans_InvalidCollateralAsset(address asset);

    /// @notice A token reports unsupported decimals.
    /// @param decimals Reported token decimals.
    error BurnerLoans_InvalidDecimals(uint8 decimals);

    /// @notice A required asset price is zero or otherwise invalid.
    error BurnerLoans_InvalidPrice();

    /// @notice A supplied configuration parameter violates its required bounds.
    error BurnerLoans_InvalidParam();

    /// @notice A basis-point value exceeds the permitted range.
    /// @param bps Invalid basis-point value.
    error BurnerLoans_InvalidBps(uint256 bps);

    /// @notice A debt cap is invalid for the requested operation.
    error BurnerLoans_InvalidCap();

    /// @notice The supplied DepositManager does not implement the required interface.
    /// @param depositManager Invalid DepositManager address.
    error BurnerLoans_InvalidDepositManager(address depositManager);

    /// @notice The supplied Burner Loans Inventory does not implement the expected interface.
    /// @param inventory Invalid Burner Loans Inventory address.
    error BurnerLoans_InvalidInventory(address inventory);

    /// @notice The supplied Burner Loans Inventory funds a different OHM token.
    /// @param expectedOhm OHM token used by Burner Loans.
    /// @param actualOhm OHM token reported by the Inventory contract.
    error BurnerLoans_InventoryOhmMismatch(address expectedOhm, address actualOhm);

    /// @notice The supplied Burner Loans Inventory is permanently bound to another facility.
    /// @param expectedFacility Burner Loans facility being configured.
    /// @param actualFacility Facility reported by the Inventory contract.
    error BurnerLoans_InventoryFacilityMismatch(address expectedFacility, address actualFacility);

    /// @notice The supplied Burner Loans Inventory is not an active policy in Burner Loans' Kernel.
    /// @param inventory Inactive Burner Loans Inventory address.
    error BurnerLoans_InventoryNotActive(address inventory);

    /// @notice The supplied Burner Loans Inventory is globally disabled.
    /// @param inventory Disabled Burner Loans Inventory address.
    error BurnerLoans_InventoryNotEnabled(address inventory);

    /// @notice The configured backing oracle does not implement IOlympusBackingOracle.
    /// @param backingOracle Invalid backing oracle address.
    error BurnerLoans_InvalidBackingOracle(address backingOracle);

    /// @notice The configured DepositManager belongs to a different Kernel.
    /// @param expectedKernel Kernel supplied to Burner Loans.
    /// @param actualKernel Kernel reported by DepositManager.
    error BurnerLoans_DepositManagerKernelMismatch(address expectedKernel, address actualKernel);

    /// @notice An operation was requested with a zero token amount.
    error BurnerLoans_ZeroAmount();

    /// @notice A collateral deposit produced no asset-denominated collateral credit.
    error BurnerLoans_ZeroCollateralCredit();

    /// @notice A collateral withdrawal produced no assets.
    error BurnerLoans_ZeroCollateralWithdrawal();

    /// @notice A collateral operation exceeds the borrower's available collateral.
    /// @param requested Requested collateral credit, in collateral token decimals.
    /// @param available Available collateral credit, in collateral token decimals.
    error BurnerLoans_InsufficientCollateral(uint256 requested, uint256 available);

    /// @notice A collateral withdrawal would leave the position below its required health factor.
    /// @param healthFactor Resulting health factor, scaled by 1e18.
    error BurnerLoans_UnhealthyWithdrawal(uint256 healthFactor);

    /// @notice The borrower has no collateral position for the asset.
    error BurnerLoans_NoCollateral();

    /// @notice The borrower has no outstanding debt for the asset.
    error BurnerLoans_NoDebt();

    /// @notice A repayment exceeds the borrower's outstanding principal.
    /// @param requested Requested repayment, in OHM decimals.
    /// @param debt Outstanding principal, in OHM decimals.
    error BurnerLoans_RepayExceedsDebt(uint256 requested, uint256 debt);

    /// @notice A repayment was attempted in the same block as the position's latest borrow.
    /// @param borrowBlock Block number of the latest borrow.
    error BurnerLoans_SameBlockRepay(uint48 borrowBlock);

    /// @notice A requested maturity exceeds the configured maturity horizon.
    /// @param requested Requested maturity timestamp.
    /// @param maximum Maximum permitted maturity timestamp.
    error BurnerLoans_MaturityHorizonExceeded(uint256 requested, uint256 maximum);

    /// @notice An extension does not move the position maturity beyond the current timestamp.
    /// @param requested Resulting maturity calculated from the position's previous maturity.
    /// @param currentTimestamp Current block timestamp.
    error BurnerLoans_ExtensionMaturityNotFuture(uint256 requested, uint256 currentTimestamp);

    /// @notice An operation requires a healthy position but the position is unhealthy.
    /// @param healthFactor Current health factor, scaled by 1e18.
    error BurnerLoans_UnhealthyPosition(uint256 healthFactor);

    /// @notice A borrow would leave the position below its required health factor.
    /// @param healthFactor Resulting health factor, scaled by 1e18.
    error BurnerLoans_UnhealthyBorrow(uint256 healthFactor);

    /// @notice An operation requires an active position but its maturity has passed.
    /// @param maturity Position maturity timestamp.
    error BurnerLoans_PositionMatured(uint48 maturity);

    /// @notice A borrow would exceed the facility-wide active-principal cap.
    /// @param requestedDebtOhm Principal requested by the borrow, in OHM decimals.
    /// @param availableDebtOhm Remaining facility capacity, in OHM decimals.
    error BurnerLoans_GlobalDebtCapExceeded(uint256 requestedDebtOhm, uint256 availableDebtOhm);

    /// @notice A borrow would exceed the collateral market's active-principal cap.
    /// @param asset Collateral asset whose cap would be exceeded.
    /// @param requestedDebtOhm Principal requested by the borrow, in OHM decimals.
    /// @param availableDebtOhm Remaining market capacity, in OHM decimals.
    error BurnerLoans_AssetDebtCapExceeded(
        address asset,
        uint256 requestedDebtOhm,
        uint256 availableDebtOhm
    );

    /// @notice A calculated fee exceeds the caller's maximum accepted fee.
    /// @param fee Calculated fee, in collateral token decimals.
    /// @param maxFee Maximum fee accepted by the caller, in collateral token decimals.
    error BurnerLoans_FeeExceedsMax(uint256 fee, uint256 maxFee);

    /// @notice Burner Loans retains an unexpected direct balance of a collateral asset.
    /// @param asset Collateral asset with a residual balance.
    /// @param balance Residual balance, in collateral token decimals.
    error BurnerLoans_ResidualCollateralBalance(address asset, uint256 balance);

    /// @notice Burner Loans could not approve the ReceiptTokenManager for collateral custody.
    /// @param receiptTokenManager ReceiptTokenManager whose approval failed.
    error BurnerLoans_ReceiptApprovalFailed(address receiptTokenManager);

    /// @notice The collateral asset is already registered by Burner Loans.
    /// @param asset Already-registered collateral asset.
    error BurnerLoans_AssetAlreadyConfigured(address asset);

    /// @notice The collateral asset is not registered by Burner Loans.
    /// @param asset Unregistered collateral asset.
    error BurnerLoans_AssetNotConfigured(address asset);

    /// @notice More than one FLOAN market matches a collateral asset and facility.
    /// @param asset Collateral asset with ambiguous markets.
    /// @param marketCount Number of matching markets.
    error BurnerLoans_AmbiguousMarket(address asset, uint256 marketCount);

    /// @notice The resolved FLOAN market does not use the Burner Loans configuration schema.
    /// @param marketId Incompatible FLOAN market identifier.
    /// @param configId Actual configuration schema identifier stored by the market.
    error BurnerLoans_IncompatibleMarketConfig(uint32 marketId, bytes16 configId);

    /// @notice A Burner Loans market's encoded product data has an invalid length.
    /// @param marketId FLOAN market containing the invalid data.
    /// @param length Actual encoded data length.
    error BurnerLoans_InvalidMarketConfigData(uint32 marketId, uint256 length);

    /// @notice New originations are disabled for the collateral asset.
    /// @param asset Collateral asset whose originations are disabled.
    error BurnerLoans_AssetOriginationsDisabled(address asset);

    /// @notice A utilization fee configuration violates the required bounds.
    error BurnerLoans_InvalidFeeConfig();

    /// @notice A required Kernel module uses an unsupported major version.
    error BurnerLoans_InvalidModuleVersion();

    /// @notice A batch is empty or exceeds the supported batch size.
    error BurnerLoans_InvalidBatch();

    /// @notice A borrower appears more than once in a seizure batch.
    /// @param borrower Duplicated borrower address.
    error BurnerLoans_DuplicateBorrower(address borrower);

    /// @notice A borrower does not currently satisfy the seizure conditions.
    /// @param borrower Borrower that cannot be seized.
    error BurnerLoans_PositionNotSeizable(address borrower);

    /// @notice Custodied collateral is insufficient to cover recorded liabilities.
    /// @param asset Insolvent collateral asset.
    /// @param liabilities Collateral liabilities, in collateral token decimals.
    /// @param assets Collateral assets held in custody, in collateral token decimals.
    /// @param borrowed Collateral currently borrowed from custody, in collateral token decimals.
    error BurnerLoans_CustodyShortfall(
        address asset,
        uint256 liabilities,
        uint256 assets,
        uint256 borrowed
    );

    /// @notice A yield-configuration mutation was not called by the bound Config policy.
    /// @param caller Unauthorized caller.
    error BurnerLoans_OnlyConfigurator(address caller);

    /// @notice The proposed yield recipient does not implement the required recipient interfaces.
    /// @param recipient Rejected recipient.
    error BurnerLoans_InvalidYieldRecipient(address recipient);

    /// @notice The proposed yield recipient is not active in the facility Kernel.
    /// @param recipient Inactive recipient.
    error BurnerLoans_YieldRecipientNotActivePolicy(address recipient);

    /// @notice The proposed yield recipient is globally disabled.
    /// @param recipient Disabled recipient.
    error BurnerLoans_YieldRecipientNotEnabled(address recipient);

    /// @notice The recipient entry reports a vault different from DepositManager's vault.
    /// @param expectedVault DepositManager vault used as the lookup key.
    /// @param actualVault Vault returned by the recipient.
    error BurnerLoans_YieldRecipientAssetVaultMismatch(address expectedVault, address actualVault);

    /// @notice The recipient entry reports an underlying asset different from the collateral asset.
    /// @param expectedAsset Collateral asset being configured.
    /// @param actualAsset Underlying asset returned by the recipient.
    error BurnerLoans_YieldRecipientAssetMismatch(address expectedAsset, address actualAsset);

    /// @notice The recipient entry for an exact DepositManager asset-vault pair is disabled.
    /// @param recipient Yield recipient queried.
    /// @param asset Collateral asset being configured.
    /// @param vault DepositManager vault used as the lookup key.
    error BurnerLoans_YieldRecipientAssetNotEnabled(
        address recipient,
        address asset,
        address vault
    );

    /// @notice The global recipient cannot be cleared while nonzero asset allocations remain.
    /// @param count Number of assets with nonzero allocations.
    error BurnerLoans_YieldAllocationsActive(uint256 count);

    /// @notice A borrower's collateral and debt position for one collateral asset.
    /// @param depositedCollateral Withdrawable collateral credit, in collateral token decimals.
    /// @param debtOhm Outstanding principal, in OHM decimals.
    /// @param maturity Position maturity timestamp.
    /// @param lastBorrowBlock Block number of the position's latest borrow.
    struct Position {
        uint256 depositedCollateral;
        uint256 debtOhm;
        uint48 maturity;
        uint48 lastBorrowBlock;
    }

    /// @notice Complete configuration decoded from a Burner Loans FLOAN market.
    /// @param originationsEnabled Whether new debt may be originated against the asset.
    /// @param collateralDecimals Decimal precision of the collateral token.
    /// @param maxLtvBps Maximum loan-to-value ratio applied to collateral value.
    /// @param backingMultiplierBps Multiplier applied to the protocol backing floor.
    /// @param keeperRewardBps Share of seized collateral awarded to the keeper.
    /// @param termLength Duration added to the current timestamp for a new maturity.
    /// @param maxMaturityHorizon Maximum permitted distance between maturity and current time.
    /// @param debtCap Maximum active principal for the asset, in OHM decimals.
    /// @param maxKeeperReward Maximum keeper reward, in collateral token decimals.
    struct AssetConfig {
        bool originationsEnabled;
        uint8 collateralDecimals;
        uint16 maxLtvBps;
        uint16 backingMultiplierBps;
        uint16 keeperRewardBps;
        uint48 termLength;
        uint48 maxMaturityHorizon;
        uint256 debtCap;
        uint256 maxKeeperReward;
    }

    /// @notice Mutable risk and term fields for a Burner Loans collateral market.
    /// @param maxLtvBps Maximum loan-to-value ratio applied to collateral value.
    /// @param backingMultiplierBps Multiplier applied to the protocol backing floor.
    /// @param keeperRewardBps Share of seized collateral awarded to the keeper.
    /// @param termLength Duration added to the current timestamp for a new maturity.
    /// @param maxMaturityHorizon Maximum permitted distance between maturity and current time.
    /// @param maxKeeperReward Maximum keeper reward, in collateral token decimals.
    struct AssetRiskConfigInput {
        uint16 maxLtvBps;
        uint16 backingMultiplierBps;
        uint16 keeperRewardBps;
        uint48 termLength;
        uint48 maxMaturityHorizon;
        uint256 maxKeeperReward;
    }

    /// @notice Piecewise-linear utilization fee configuration.
    /// @param baseFeeBps Fee charged at zero utilization.
    /// @param kinkBps Utilization at which the fee slope changes.
    /// @param preKinkSlopeBps Fee increase across the utilization range below the kink.
    /// @param postKinkSlopeBps Fee increase across the utilization range above the kink.
    struct AssetFeeConfig {
        uint16 baseFeeBps;
        uint16 kinkBps;
        uint16 preKinkSlopeBps;
        uint16 postKinkSlopeBps;
    }

    /// @notice Projected result of a borrow.
    /// @param fee Origination fee, in collateral token decimals.
    /// @param resultingDebtOhm Principal after the borrow, in OHM decimals.
    /// @param resultingHealthFactor Health factor after the borrow, scaled by 1e18.
    /// @param maturity Maturity timestamp after the borrow.
    /// @param executable Whether the borrow is executable under current state.
    struct BorrowPreview {
        uint256 fee;
        uint256 resultingDebtOhm;
        uint256 resultingHealthFactor;
        uint48 maturity;
        bool executable;
    }

    /// @notice Projected result of a repayment.
    /// @param repayAmount Principal repaid, in OHM decimals.
    /// @param remainingDebtOhm Principal remaining after repayment, in OHM decimals.
    /// @param resultingHealthFactor Max uint after full repayment; zero after a partial repayment.
    /// @param executable Whether the repayment is executable under current state.
    struct RepayPreview {
        uint256 repayAmount;
        uint256 remainingDebtOhm;
        uint256 resultingHealthFactor;
        bool executable;
    }

    /// @notice Projected result of a collateral withdrawal.
    /// @param returnToken Collateral token returned to the recipient.
    /// @param returnAmount Collateral assets returned, in collateral token decimals.
    /// @param remainingDepositedCollateral Withdrawable collateral credit remaining after withdrawal.
    /// @param resultingHealthFactor Health factor after withdrawal, scaled by 1e18.
    /// @param executable Whether the collateral debit is executable under current state. Always
    ///        false when `returnAmount` is zero.
    struct WithdrawPreview {
        address returnToken;
        uint256 returnAmount;
        uint256 remainingDepositedCollateral;
        uint256 resultingHealthFactor;
        bool executable;
    }

    /// @notice Projected result of a maturity extension.
    /// @param fee Extension fee, in collateral token decimals.
    /// @param maturity Maturity timestamp after the extension.
    /// @param healthFactor Health factor after the extension, scaled by 1e18.
    /// @param executable Whether the extension is executable under current state.
    struct ExtendPreview {
        uint256 fee;
        uint48 maturity;
        uint256 healthFactor;
        bool executable;
    }

    /// @notice Projected aggregate result of a seizure batch.
    /// @param seizedDebtOhm Principal defaulted, in OHM decimals.
    /// @param seizedCollateral Collateral seized, in collateral token decimals.
    /// @param collateralToTreasury Collateral routed to Treasury.
    /// @param keeperReward Collateral awarded to the keeper.
    /// @param executable Whether every requested seizure is executable under current state.
    struct SeizePreview {
        uint256 seizedDebtOhm;
        uint256 seizedCollateral;
        uint256 collateralToTreasury;
        uint256 keeperReward;
        bool executable;
    }

    /// @notice Projected claimable yield for one collateral asset.
    /// @param amount Claimable collateral yield, in collateral token decimals.
    /// @param executable Whether the claim is executable under current state.
    struct ClaimYieldPreview {
        uint256 amount;
        bool executable;
    }

    /// @notice Current custody accounting for one collateral asset.
    /// @param shares Custody shares attributed to Burner Loans; raw asset units when no vault is configured.
    /// @param assets Assets represented by the custody shares, in collateral token decimals.
    /// @param borrowed Assets temporarily borrowed from custody, in collateral token decimals.
    /// @param liabilities Collateral owed to borrowers, in collateral token decimals.
    /// @param claimableYield Maximum yield reported by DepositManager after borrowed assets,
    ///        liabilities, and its one-unit solvency buffer, in collateral token decimals.
    /// @param solvent Whether custody assets plus borrowed assets cover liabilities.
    struct AssetCollateralStatus {
        uint256 shares;
        uint256 assets;
        uint256 borrowed;
        uint256 liabilities;
        uint256 claimableYield;
        bool solvent;
    }

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

    /// @notice Emitted when collateral is withdrawn from a borrower's position.
    /// @param caller Account that initiated the withdrawal.
    /// @param asset Withdrawn collateral asset.
    /// @param onBehalfOf Borrower whose position was debited.
    /// @param recipient Account that received the collateral.
    /// @param amount Asset-denominated collateral credit debited from the position.
    event CollateralWithdrawn(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        address recipient,
        uint256 amount
    );

    /// @notice Emitted when OHM principal is borrowed against collateral.
    /// @param caller Account that initiated the borrow.
    /// @param asset Collateral asset securing the position.
    /// @param onBehalfOf Borrower whose debt increased.
    /// @param recipient Account that received the borrowed OHM.
    /// @param ohmAmount Principal borrowed, in OHM decimals.
    /// @param fee Origination fee charged, in collateral token decimals.
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

    /// @notice Emitted when the facility-wide yield recipient changes.
    /// @param recipient New recipient, or zero after every allocation is cleared.
    event YieldRecipientSet(address indexed recipient);

    /// @notice Emitted when an asset's share of claimed yield routed to the recipient changes.
    /// @param asset Collateral asset whose share changed.
    /// @param bps New share in basis points.
    event YieldRecipientAssetBpsSet(address indexed asset, uint16 bps);

    /// @notice Emitted when Config registers a newly created collateral market.
    /// @param asset Collateral asset added to the append-only registry.
    event AssetRegistered(address indexed asset);

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

    /// @notice Emitted when an active position's maturity is extended.
    /// @param caller Account that initiated the extension.
    /// @param asset Collateral asset securing the position.
    /// @param onBehalfOf Borrower whose maturity changed.
    /// @param maturity New maturity timestamp.
    /// @param fee Extension fee charged, in collateral token decimals.
    event Extended(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        uint48 maturity,
        uint256 fee
    );

    /// @notice Emitted for each borrower included in a successful seizure batch.
    /// @param caller Keeper that initiated the seizure.
    /// @param asset Collateral asset seized from the position.
    /// @param borrower Borrower whose position defaulted.
    /// @param debtOhm Principal defaulted, in OHM decimals.
    /// @param collateral Asset-denominated collateral credit removed from the position.
    event Seized(
        address indexed caller,
        address indexed asset,
        address indexed borrower,
        uint256 debtOhm,
        uint256 collateral
    );

    /// @notice Emitted after a seizure batch is settled and collateral is distributed.
    /// @param caller Keeper that initiated the seizure.
    /// @param asset Collateral asset settled by the batch.
    /// @param borrowerCount Number of borrowers seized.
    /// @param seizedDebtOhm Aggregate principal defaulted, in OHM decimals.
    /// @param seizedCollateral Aggregate collateral seized.
    /// @param keeperReward Collateral awarded to the keeper.
    /// @param collateralToTreasury Collateral routed to Treasury.
    event SeizureBatchSettled(
        address indexed caller,
        address indexed asset,
        uint256 borrowerCount,
        uint256 seizedDebtOhm,
        uint256 seizedCollateral,
        uint256 keeperReward,
        uint256 collateralToTreasury
    );

    /// @notice Emitted after custody yield is claimed and distributed atomically.
    /// @param asset Collateral asset whose yield was claimed.
    /// @param recipient Configured recipient, or zero when all yield goes to Treasury.
    /// @param claimed Total collateral yield claimed.
    /// @param recipientAmount Amount sent to the configured recipient.
    /// @param treasuryAmount Amount sent to Treasury.
    event YieldClaimed(
        address indexed asset,
        address indexed recipient,
        uint256 claimed,
        uint256 recipientAmount,
        uint256 treasuryAmount
    );

    /// @notice Emitted when the canonical backing oracle changes.
    /// @param backingOracle New backing oracle address.
    event BackingOracleSet(address indexed backingOracle);

    /// @notice Emitted when Config creates and registers a collateral market.
    /// @param asset Collateral asset added to Burner Loans.
    /// @param config Initial collateral market configuration.
    event AssetAdded(address indexed asset, AssetConfig config);

    /// @notice Emitted when an asset's active-principal cap changes.
    /// @param asset Collateral asset whose cap changed.
    /// @param debtCapOhm New debt cap, in OHM decimals.
    event AssetDebtCapSet(address indexed asset, uint256 debtCapOhm);

    /// @notice Emitted when an asset's risk and term configuration changes.
    /// @param asset Collateral asset whose configuration changed.
    /// @param config New risk and term configuration.
    event AssetRiskConfigSet(address indexed asset, AssetRiskConfigInput config);

    /// @notice Emitted when an asset's utilization fee curve changes.
    /// @param asset Collateral asset whose fee configuration changed.
    /// @param config New utilization fee configuration.
    event AssetFeeConfigSet(address indexed asset, AssetFeeConfig config);

    /// @notice Emitted when new originations are enabled or disabled for an asset.
    /// @param asset Collateral asset whose origination state changed.
    /// @param enabled Whether new originations are enabled.
    event AssetOriginationsSet(address indexed asset, bool enabled);
}
