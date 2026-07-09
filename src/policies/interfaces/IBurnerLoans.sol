// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans
/// @notice Interface for a fixed-term OHM shorting facility backed by whitelisted collateral.
interface IBurnerLoans {
    // ========== ERRORS ========== //

    error BurnerLoans_ZeroAddress();
    error BurnerLoans_NotImplemented();
    error BurnerLoans_InvalidDecimals(uint8 decimals);
    error BurnerLoans_InvalidPrice();
    error BurnerLoans_InvalidParam();
    error BurnerLoans_InvalidBps(uint256 bps);
    error BurnerLoans_InvalidCap();
    error BurnerLoans_InvalidDepositManager(address depositManager);
    error BurnerLoans_ZeroAmount();
    error BurnerLoans_ZeroCollateralCredit();
    error BurnerLoans_ZeroCollateralWithdrawal();
    error BurnerLoans_InsufficientCollateral(uint256 requested, uint256 available);
    error BurnerLoans_UnhealthyWithdrawal(uint256 healthFactor);
    error BurnerLoans_ResidualCollateralBalance(address asset, uint256 balance);
    error BurnerLoans_ReceiptApprovalFailed(address receiptTokenManager);
    error BurnerLoans_AssetAlreadyConfigured(address asset);
    error BurnerLoans_AssetNotConfigured(address asset);
    error BurnerLoans_AssetNotEnabled(address asset);
    error BurnerLoans_AssetAlreadyEnabled(address asset);
    error BurnerLoans_InvalidFeeConfig();
    error BurnerLoans_UnauthorizedConfigurator(address caller);
    error BurnerLoans_InvalidModuleVersion();

    // ========== ENUMS ========== //

    enum PositionStatus {
        NoDebt,
        Active,
        Seized
    }

    // ========== STRUCTS ========== //

    /// @notice Per-owner, per-collateral asset position.
    /// @param depositedCollateral Collateral credited to the position, in collateral token decimals.
    /// @param debtOhm Outstanding borrowed OHM, in OHM decimals.
    /// @param maturity Timestamp after which a debt-bearing position is seizable, in seconds.
    /// @param lastBorrowBlock Block number of the latest borrow against the position.
    /// @param status Current position status.
    struct Position {
        uint256 depositedCollateral;
        uint256 debtOhm;
        uint48 maturity;
        uint48 lastBorrowBlock;
        PositionStatus status;
    }

    /// @notice Asset-level risk and term configuration.
    /// @param enabled Whether the asset accepts new exposure.
    /// @param collateralDecimals Decimal scale returned by the collateral ERC20.
    /// @param collateralFactorBps Risk haircut applied to collateral value, in bps.
    /// @param minCollateralRatioBps Minimum collateral ratio applied to OHM debt value, in bps.
    /// @param backingMultiplierBps Multiplier applied to the backing preservation floor, in bps.
    /// @param keeperRewardBps Share of seized collateral paid to a non-protocol keeper, in bps.
    /// @param termLength Fixed extension term length for the asset, in seconds.
    /// @param maxMaturityHorizon Maximum permitted maturity from the current block timestamp, in seconds.
    /// @param debtCap Maximum active debt for the asset, in OHM decimals.
    /// @param maxKeeperReward Maximum non-protocol keeper reward, in collateral token decimals.
    struct AssetConfig {
        bool enabled;
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

    /// @notice Asset-level risk and term configuration supplied by callers.
    /// @dev Excludes storage-only fields (`enabled`, `collateralDecimals`) and separately managed debt cap.
    /// @param collateralFactorBps Collateral factor, in bps.
    /// @param minCollateralRatioBps Minimum collateral ratio, in bps.
    /// @param backingMultiplierBps Backing multiplier, in bps.
    /// @param keeperRewardBps Keeper reward share, in bps.
    /// @param termLength Fixed term length, in seconds.
    /// @param maxMaturityHorizon Maximum maturity horizon, in seconds.
    /// @param maxKeeperReward Maximum keeper reward, in collateral token decimals.
    struct AssetRiskConfigInput {
        uint16 collateralFactorBps;
        uint16 minCollateralRatioBps;
        uint16 backingMultiplierBps;
        uint16 keeperRewardBps;
        uint48 termLength;
        uint48 maxMaturityHorizon;
        uint256 maxKeeperReward;
    }

    /// @notice Asset-level utilization fee curve.
    /// @param baseFeeBps Base fee charged on borrows and extensions, in bps.
    /// @param kinkBps Utilization point where the second slope starts, in bps. Zero means no kink.
    /// @param preKinkSlopeBps Aave-style full fee-rate increase from zero utilization through the kink, in bps.
    /// @param postKinkSlopeBps Aave-style additional fee-rate increase from the kink to full utilization, in bps. Must be zero when `kinkBps` is zero.
    struct AssetFeeConfig {
        uint16 baseFeeBps;
        uint16 kinkBps;
        uint16 preKinkSlopeBps;
        uint16 postKinkSlopeBps;
    }

    /// @notice Result returned by borrow previews.
    /// @param fee Collateral fee due for the borrow, in collateral token decimals.
    /// @param resultingDebtOhm Total position debt after the borrow, in OHM decimals.
    /// @param resultingHealthFactor Health factor after the borrow, scaled to WAD.
    /// @param maturity Position maturity after the borrow, as a Unix timestamp.
    /// @param executable Whether the borrow is expected to execute with current state and prices.
    struct BorrowPreview {
        uint256 fee;
        uint256 resultingDebtOhm;
        uint256 resultingHealthFactor;
        uint48 maturity;
        bool executable;
    }

    /// @notice Result returned by collateral withdrawal previews.
    /// @param returnToken Token expected to be returned, either collateral asset or a vault/share token.
    /// @param returnAmount Amount of `returnToken`, in that token's native decimals.
    /// @param remainingDepositedCollateral Position collateral remaining after withdrawal, in collateral token decimals.
    /// @param resultingHealthFactor Health factor after the withdrawal, scaled to WAD.
    /// @param executable Whether local amount and health checks permit the withdrawal.
    struct WithdrawPreview {
        address returnToken;
        uint256 returnAmount;
        uint256 remainingDepositedCollateral;
        uint256 resultingHealthFactor;
        bool executable;
    }

    /// @notice Result returned by extension previews.
    /// @param fee Collateral fee due for the extension, in collateral token decimals.
    /// @param maturity Position maturity after the extension, as a Unix timestamp.
    /// @param healthFactor Current health factor, scaled to WAD.
    /// @param executable Whether the extension is expected to execute with current state and prices.
    struct ExtendPreview {
        uint256 fee;
        uint48 maturity;
        uint256 healthFactor;
        bool executable;
    }

    /// @notice Result returned by seizure previews.
    /// @param seizedDebtOhm Debt that would be closed by seizure, in OHM decimals.
    /// @param seizedCollateral Collateral that would be seized, in collateral token decimals.
    /// @param collateralToTreasury Collateral expected to be retained by the treasury, in collateral token decimals.
    /// @param keeperReward Collateral expected to be paid to a non-protocol keeper, in collateral token decimals.
    /// @param executable Whether at least one provided borrower is currently seizable.
    struct SeizePreview {
        uint256 seizedDebtOhm;
        uint256 seizedCollateral;
        uint256 collateralToTreasury;
        uint256 keeperReward;
        bool executable;
    }

    /// @notice Result returned by yield harvest previews.
    /// @param amount Harvestable surplus, in collateral token decimals unless the custody layer returns shares.
    /// @param executable Whether a harvest is expected to execute with current custody state.
    struct HarvestPreview {
        uint256 amount;
        bool executable;
    }

    // ========== EVENTS ========== //

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
        uint256 collateral,
        uint256 keeperReward
    );
    event YieldHarvested(address indexed asset, uint256 amount);
    event GlobalDebtCapSet(uint256 debtCapOhm);
    event AssetAdded(address indexed asset, AssetConfig config);
    event AssetDebtCapSet(address indexed asset, uint256 debtCapOhm);
    event ConfiguratorSet(address indexed configurator);
    event AssetRiskConfigSet(address indexed asset, AssetRiskConfigInput config);
    event AssetFeeConfigSet(address indexed asset, AssetFeeConfig config);
    event AssetEnabled(address indexed asset);
    event AssetDisabled(address indexed asset);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the OHM token address.
    /// @return address The OHM token used for borrowing and repayment.
    function ohm() external view returns (address);

    /// @notice Returns the DepositManager used for collateral custody.
    /// @return address The DepositManager address.
    function depositManager() external view returns (address);

    /// @notice Returns the global active debt cap.
    /// @return uint256 The maximum total active Burner Loans debt, in OHM decimals.
    function globalDebtCapOhm() external view returns (uint256);

    /// @notice Returns current active debt across all configured collateral assets.
    /// @return uint256 The total active Burner Loans debt, in OHM decimals.
    function totalActiveDebtOhm() external view returns (uint256);

    /// @notice Returns the configured Burner Loans timelock executor.
    /// @return address The configurator address.
    function configurator() external view returns (address);

    /// @notice Returns current active debt for a collateral asset.
    /// @param asset_ The collateral asset to query.
    /// @return uint256 The active debt backed by `asset_`, in OHM decimals.
    function assetActiveDebtOhm(address asset_) external view returns (uint256);

    /// @notice Returns whether a collateral asset has been configured.
    /// @param asset_ The collateral asset to query.
    /// @return bool True if `asset_` has been added to Burner Loans.
    function isAssetConfigured(address asset_) external view returns (bool);

    /// @notice Returns the risk and term configuration for a collateral asset.
    /// @param asset_ The collateral asset to query.
    /// @return AssetConfig The asset configuration.
    function getAssetConfig(address asset_) external view returns (AssetConfig memory);

    /// @notice Returns the utilization fee configuration for a collateral asset.
    /// @param asset_ The collateral asset to query.
    /// @return AssetFeeConfig The asset fee curve.
    function getAssetFeeConfig(address asset_) external view returns (AssetFeeConfig memory);

    /// @notice Validates a complete asset risk configuration.
    /// @dev Reverts if the supplied configuration violates Burner Loans risk, maturity, or reward bounds.
    /// @param config_ Complete asset configuration to validate.
    function validateAssetRiskConfig(AssetConfig calldata config_) external pure;

    /// @notice Validates a complete utilization fee configuration.
    /// @dev Reverts if the supplied fee curve violates bps bounds, kink rules, or the maximum fee rate.
    /// @param config_ Complete fee configuration to validate.
    function validateFeeConfig(AssetFeeConfig calldata config_) external pure;

    /// @notice Validates an asset active debt cap against live Burner Loans state.
    /// @dev Reverts if `asset_` is not configured, `debtCapOhm_` is below current active
    ///      debt for `asset_`, or `debtCapOhm_` is above the global debt cap.
    /// @param asset_ Collateral asset to validate.
    /// @param debtCapOhm_ Proposed asset active debt cap, in OHM decimals.
    function validateAssetDebtCap(address asset_, uint256 debtCapOhm_) external view;

    /// @notice Returns a borrower position for one collateral asset.
    /// @param asset_ The collateral asset backing the position.
    /// @param borrower_ The position owner.
    /// @return Position The borrower's position.
    function getPosition(address asset_, address borrower_) external view returns (Position memory);

    /// @notice Returns whether a borrower's position can currently be seized.
    /// @param asset_ The collateral asset backing the position.
    /// @param borrower_ The position owner.
    /// @return bool True if the position is seizable by health factor or maturity.
    function isSeizable(address asset_, address borrower_) external view returns (bool);

    /// @notice Scans active borrowers for a collateral asset and returns seizable borrowers.
    /// @dev Intended for on-chain automation with bounded work per call.
    /// @param asset_ The collateral asset to scan.
    /// @param startIndex_ The index in the active borrower set to start scanning.
    /// @param maxBorrowersToCheck_ Maximum active borrowers to inspect.
    /// @param maxBorrowersToReturn_ Maximum seizable borrowers to return.
    /// @return borrowers Seizable borrower addresses found in this scan window.
    /// @return nextIndex The next active-borrower index to scan.
    /// @return expectedKeeperReward Expected keeper reward for seizing the returned borrowers, in collateral token decimals.
    function getSeizableBorrowers(
        address asset_,
        uint256 startIndex_,
        uint256 maxBorrowersToCheck_,
        uint256 maxBorrowersToReturn_
    )
        external
        view
        returns (address[] memory borrowers, uint256 nextIndex, uint256 expectedKeeperReward);

    /// @notice Returns all active borrowers for a collateral asset.
    /// @dev Intended primarily for off-chain indexing and inspection because the result can grow.
    /// @param asset_ The collateral asset to query.
    /// @return borrowers Active borrower addresses for `asset_`.
    function getActiveBorrowers(address asset_) external view returns (address[] memory borrowers);

    /// @notice Returns a borrower's current health factor for one collateral asset.
    /// @dev The health factor is WAD-scaled. Values below 1e18 are seizable.
    /// @param asset_ The collateral asset backing the position.
    /// @param borrower_ The position owner.
    /// @return uint256 The WAD-scaled health factor.
    function healthFactor(address asset_, address borrower_) external view returns (uint256);

    // ========== PREVIEW FUNCTIONS ========== //

    /// @notice Previews the collateral deposited into a position.
    /// @dev Reverts unless Burner Loans and the collateral asset are enabled. The returned
    ///      amount is the custody layer's expected withdrawable credit, not blindly `amount_`.
    /// @param asset_ The collateral asset to deposit.
    /// @param amount_ The amount of collateral to deposit, in collateral token decimals.
    /// @param onBehalfOf_ The position owner receiving the collateral deposit.
    /// @return depositedCollateral Collateral expected to be deposited, in collateral token decimals.
    /// @return totalDepositedCollateral Total position collateral after the deposit, in collateral token decimals.
    function previewDepositCollateral(
        address asset_,
        uint256 amount_,
        address onBehalfOf_
    ) external view returns (uint256 depositedCollateral, uint256 totalDepositedCollateral);

    /// @notice Previews collateral withdrawal from a position.
    /// @dev Reverts unless Burner Loans is enabled. Asset-level disable does not block
    ///      withdrawal. Debt-free positions do not require PRICE freshness; debt-bearing
    ///      positions use fresh PRICE data to report resulting health.
    /// @param asset_ The collateral asset backing the position.
    /// @param amount_ The requested withdrawal amount, in collateral token decimals.
    /// @param onBehalfOf_ The position owner.
    /// @return WithdrawPreview Preview data including return token, amount out, remaining collateral, and health factor.
    function previewWithdrawCollateral(
        address asset_,
        uint256 amount_,
        address onBehalfOf_
    ) external view returns (WithdrawPreview memory);

    /// @notice Previews borrowing OHM against an existing collateral position.
    /// @param asset_ The collateral asset backing the position.
    /// @param ohmAmount_ The OHM amount to borrow, in OHM decimals.
    /// @param onBehalfOf_ The position owner.
    /// @return BorrowPreview Preview data including fee, resulting debt, resulting health factor, and maturity.
    function previewBorrow(
        address asset_,
        uint256 ohmAmount_,
        address onBehalfOf_
    ) external view returns (BorrowPreview memory);

    /// @notice Previews repayment of OHM debt.
    /// @param asset_ The collateral asset backing the position.
    /// @param ohmAmount_ The requested repayment amount, in OHM decimals.
    /// @param onBehalfOf_ The position owner whose debt is repaid.
    /// @return repayAmount OHM expected to be repaid, in OHM decimals.
    /// @return remainingDebtOhm Debt remaining after repayment, in OHM decimals.
    function previewRepay(
        address asset_,
        uint256 ohmAmount_,
        address onBehalfOf_
    ) external view returns (uint256 repayAmount, uint256 remainingDebtOhm);

    /// @notice Previews extension of a position's maturity.
    /// @param asset_ The collateral asset backing the position.
    /// @param onBehalfOf_ The position owner.
    /// @param termCount_ Number of fixed asset terms to extend by.
    /// @return ExtendPreview Preview data including fee, new maturity, current health factor, and executability.
    function previewExtend(
        address asset_,
        address onBehalfOf_,
        uint256 termCount_
    ) external view returns (ExtendPreview memory);

    /// @notice Previews seizing a batch of borrowers for one collateral asset.
    /// @param asset_ The collateral asset backing all borrower positions.
    /// @param borrowers_ Borrowers to inspect for seizure.
    /// @return SeizePreview Preview data including debt closed, collateral seized, treasury collateral, and keeper reward.
    function previewSeize(
        address asset_,
        address[] calldata borrowers_
    ) external view returns (SeizePreview memory);

    /// @notice Previews surplus yield harvest for a collateral asset.
    /// @param asset_ The collateral asset to harvest.
    /// @return HarvestPreview Preview data including harvestable amount and executability.
    function previewHarvestYield(address asset_) external view returns (HarvestPreview memory);

    // ========== USER FUNCTIONS ========== //

    /// @notice Deposits collateral into a position.
    /// @dev Caller must be the position owner or an authorized operator. Reverts unless Burner
    ///      Loans and the collateral asset are enabled. Credits the DepositManager actual
    ///      withdrawable amount and reverts if that amount is zero.
    /// @param asset_ The collateral asset to deposit.
    /// @param amount_ The collateral amount to deposit, in collateral token decimals.
    /// @param onBehalfOf_ The position owner receiving the collateral deposit.
    /// @return depositedCollateral Collateral deposited through the custody layer, in collateral token decimals.
    /// @return totalDepositedCollateral Total position collateral after the deposit, in collateral token decimals.
    function depositCollateral(
        address asset_,
        uint256 amount_,
        address onBehalfOf_
    ) external returns (uint256 depositedCollateral, uint256 totalDepositedCollateral);

    /// @notice Withdraws collateral from a position.
    /// @dev Caller must be the position owner or an authorized operator. Reverts unless Burner
    ///      Loans is enabled. Asset-level disable does not block withdrawal. Withdrawals with
    ///      active debt require fresh PRICE data and resulting health of at least 1e18.
    /// @param asset_ The collateral asset backing the position.
    /// @param amount_ The requested withdrawal amount, in collateral token decimals.
    /// @param onBehalfOf_ The position owner.
    /// @param recipient_ The account receiving the withdrawn asset or share token.
    /// @return tokenOut Token returned by the custody layer, either collateral asset or a vault/share token.
    /// @return amountOut Amount returned, in `tokenOut` decimals.
    /// @return remainingDepositedCollateral Position collateral remaining, in collateral token decimals.
    /// @return healthFactor Resulting WAD-scaled health factor.
    function withdrawCollateral(
        address asset_,
        uint256 amount_,
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
    /// @dev Caller must be the position owner or an authorized operator. Reverts if the asset or policy is disabled.
    /// @param asset_ The collateral asset backing the position.
    /// @param ohmAmount_ The OHM amount to borrow, in OHM decimals.
    /// @param onBehalfOf_ The position owner whose debt increases.
    /// @param recipient_ The account receiving borrowed OHM.
    /// @param maxFee_ Maximum acceptable borrow fee, in collateral token decimals.
    /// @return borrowedOhm OHM borrowed, in OHM decimals.
    /// @return feeCollateral Fee paid immediately, in collateral token decimals.
    /// @return totalDebtOhm Total position debt after borrowing, in OHM decimals.
    /// @return maturity Position maturity after borrowing, as a Unix timestamp.
    /// @return healthFactor Resulting WAD-scaled health factor.
    function borrow(
        address asset_,
        uint256 ohmAmount_,
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

    /// @notice Repays OHM debt for a position.
    /// @dev Repayment is permissionless; collateral remains owned by the position owner.
    /// @param asset_ The collateral asset backing the position.
    /// @param ohmAmount_ The requested repayment amount, in OHM decimals.
    /// @param onBehalfOf_ The position owner whose debt is repaid.
    /// @return repaidOhm OHM repaid and burned, in OHM decimals.
    /// @return remainingDebtOhm Debt remaining after repayment, in OHM decimals.
    function repay(
        address asset_,
        uint256 ohmAmount_,
        address onBehalfOf_
    ) external returns (uint256 repaidOhm, uint256 remainingDebtOhm);

    /// @notice Extends a debt-bearing position's maturity.
    /// @dev Caller must be the position owner or an authorized operator. Fees scale linearly with `termCount_`.
    /// @param asset_ The collateral asset backing the position.
    /// @param onBehalfOf_ The position owner.
    /// @param termCount_ Number of fixed asset terms to extend by.
    /// @param maxFee_ Maximum acceptable total extension fee, in collateral token decimals.
    /// @return newMaturity Position maturity after extension, as a Unix timestamp.
    /// @return feeCollateral Fee paid immediately, in collateral token decimals.
    /// @return healthFactor Current WAD-scaled health factor.
    function extend(
        address asset_,
        address onBehalfOf_,
        uint256 termCount_,
        uint256 maxFee_
    ) external returns (uint48 newMaturity, uint256 feeCollateral, uint256 healthFactor);

    /// @notice Seizes one or more seizable borrowers for one collateral asset.
    /// @dev All borrowers must be for `asset_`. Non-protocol callers may receive a capped keeper reward.
    /// @param asset_ The collateral asset backing all seized positions.
    /// @param borrowers_ Borrower positions to seize.
    /// @return seizedDebtOhm Debt closed by seizure, in OHM decimals.
    /// @return seizedCollateral Collateral seized from borrowers, in collateral token decimals.
    /// @return collateralToTreasury Collateral sent or credited to TRSRY, in collateral token decimals.
    /// @return keeperReward Collateral paid to a non-protocol keeper, in collateral token decimals.
    function seize(
        address asset_,
        address[] calldata borrowers_
    )
        external
        returns (
            uint256 seizedDebtOhm,
            uint256 seizedCollateral,
            uint256 collateralToTreasury,
            uint256 keeperReward
        );

    /// @notice Harvests surplus collateral yield to TRSRY.
    /// @param asset_ The collateral asset to harvest.
    /// @return amount Amount harvested, in collateral token decimals unless the custody layer returns shares.
    function harvestYield(address asset_) external returns (uint256 amount);

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Sets the global active debt cap.
    /// @dev Admin-only. In the expected deployment, `admin` is the OCG timelock, so this
    ///      function is effectively timelocked by governance. Reverts while Burner Loans is
    ///      disabled.
    /// @param debtCapOhm_ New global cap, in OHM decimals.
    function setGlobalDebtCap(uint256 debtCapOhm_) external;

    /// @notice Adds a whitelisted collateral asset.
    /// @dev Admin-only. In the expected deployment, `admin` is the OCG timelock, so this
    ///      function is effectively timelocked by governance. Validates PRICE approval,
    ///      DepositManager support, ERC20 decimal scale, and risk bounds. The asset is enabled
    ///      immediately and collateral decimals are read from the ERC20. Reverts while Burner
    ///      Loans is disabled.
    /// @param asset_ Collateral asset to add.
    /// @param debtCapOhm_ Initial active debt cap, in OHM decimals.
    /// @param riskConfig_ Initial risk and term configuration.
    /// @param feeConfig_ Initial utilization fee curve.
    function addAsset(
        address asset_,
        uint256 debtCapOhm_,
        AssetRiskConfigInput calldata riskConfig_,
        AssetFeeConfig calldata feeConfig_
    ) external;

    /// @notice Sets an asset's active debt cap.
    /// @dev Callable by admin or the configurator. Direct admin calls are effectively
    ///      timelocked by governance in the expected deployment. Reverts while Burner Loans is
    ///      disabled.
    /// @param asset_ Collateral asset to update.
    /// @param debtCapOhm_ New asset cap, in OHM decimals.
    function setAssetDebtCap(address asset_, uint256 debtCapOhm_) external;

    /// @notice Sets the external config timelock executor.
    /// @dev Admin-only. In the expected deployment, `admin` is the OCG timelock, so this
    ///      function is effectively timelocked by governance. The configurator can call
    ///      risk-parameter setters without holding admin. Reverts while Burner Loans is
    ///      disabled.
    /// @param configurator_ New configurator address.
    function setConfigurator(address configurator_) external;

    /// @notice Enables a configured asset for new exposure.
    /// @dev Admin-only. In the expected deployment, `admin` is the OCG timelock, so this
    ///      function is effectively timelocked by governance.
    /// @param asset_ Collateral asset to enable.
    function enableAsset(address asset_) external;

    /// @notice Immediately disables a configured asset for new exposure.
    /// @dev Admin or burner_loans_admin only. Does not block repayment, withdrawal, seizure, harvest,
    ///      or safe cleanup while Burner Loans is globally enabled.
    /// @param asset_ Collateral asset to disable.
    function disableAsset(address asset_) external;

    /// @notice Sets asset risk and term fields.
    /// @dev Callable by admin or the configurator. Replaces all risk and term fields
    ///      while preserving admin-only fields such as enabled status, collateral decimals, and debt cap.
    ///      Reverts while Burner Loans is disabled.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete risk and term configuration.
    function setAssetRiskConfig(address asset_, AssetRiskConfigInput calldata config_) external;

    /// @notice Sets the complete asset fee curve.
    /// @dev Callable by admin or the configurator. The Burner Loans Config Timelock
    ///      may expose partial-update helpers, but this setter receives the full resulting curve.
    ///      Reverts while Burner Loans is disabled.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete fee curve.
    function setAssetFeeConfig(address asset_, AssetFeeConfig calldata config_) external;
}
