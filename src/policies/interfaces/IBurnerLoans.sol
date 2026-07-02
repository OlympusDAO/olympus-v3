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
    /// @param enabled Whether the asset accepts new deposits, borrows, and extensions.
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

    /// @notice Asset-level utilization fee curve.
    /// @param baseFeeBps Base fee charged on borrows and extensions, in bps.
    /// @param kinkBps Utilization point where the second slope starts, in bps.
    /// @param slope1Bps Fee slope from zero utilization through the kink, in bps.
    /// @param slope2Bps Fee slope above the kink, in bps.
    struct FeeConfig {
        uint16 baseFeeBps;
        uint16 kinkBps;
        uint16 slope1Bps;
        uint16 slope2Bps;
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
    /// @param executable Whether the withdrawal is expected to execute with current state and prices.
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

    /// @notice Signature authorization payload.
    /// @param account Account granting operator authorization.
    /// @param authorized Operator being authorized.
    /// @param authorizationDeadline Timestamp until which the operator is authorized, in seconds.
    /// @param nonce Account nonce consumed by the signature.
    /// @param signatureDeadline Timestamp until which the signature may be submitted, in seconds.
    struct Authorization {
        address account;
        address authorized;
        uint96 authorizationDeadline;
        uint256 nonce;
        uint256 signatureDeadline;
    }

    /// @notice ECDSA signature components.
    /// @param v Recovery identifier.
    /// @param r ECDSA r value.
    /// @param s ECDSA s value.
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
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
    event AuthorizationSet(
        address indexed caller,
        address indexed account,
        address indexed authorized,
        uint96 authorizationDeadline
    );

    // ========== VIEW FUNCTIONS ========== //

    function ohm() external view returns (address);

    function depositManager() external view returns (address);

    function globalDebtCapOhm() external view returns (uint256);

    function totalActiveDebtOhm() external view returns (uint256);

    function assetActiveDebtOhm(address asset_) external view returns (uint256);

    function getAssetConfig(address asset_) external view returns (AssetConfig memory);

    function getFeeConfig(address asset_) external view returns (FeeConfig memory);

    function getPosition(address asset_, address borrower_) external view returns (Position memory);

    function isSeizable(address asset_, address borrower_) external view returns (bool);

    function getSeizableBorrowers(
        address asset_,
        uint256 startIndex_,
        uint256 maxBorrowersToCheck_,
        uint256 maxBorrowersToReturn_
    )
        external
        view
        returns (address[] memory borrowers, uint256 nextIndex, uint256 expectedKeeperReward);

    function getActiveBorrowers(address asset_) external view returns (address[] memory borrowers);

    function healthFactor(address asset_, address borrower_) external view returns (uint256);

    function authorizations(address account_, address authorized_) external view returns (uint96);

    function authorizationNonces(address account_) external view returns (uint256);

    function isSenderAuthorized(address account_) external view returns (bool);

    // ========== PREVIEW FUNCTIONS ========== //

    function previewDepositCollateral(
        address asset_,
        uint256 amount_,
        address onBehalfOf_
    ) external view returns (uint256 depositedCollateral, uint256 totalDepositedCollateral);

    function previewWithdrawCollateral(
        address asset_,
        uint256 amount_,
        address onBehalfOf_
    ) external view returns (WithdrawPreview memory);

    function previewBorrow(
        address asset_,
        uint256 ohmAmount_,
        address onBehalfOf_
    ) external view returns (BorrowPreview memory);

    function previewRepay(
        address asset_,
        uint256 ohmAmount_,
        address onBehalfOf_
    ) external view returns (uint256 repayAmount, uint256 remainingDebtOhm);

    function previewExtend(
        address asset_,
        address onBehalfOf_,
        uint256 termCount_
    ) external view returns (ExtendPreview memory);

    function previewSeize(
        address asset_,
        address[] calldata borrowers_
    ) external view returns (SeizePreview memory);

    function previewHarvestYield(address asset_) external view returns (HarvestPreview memory);

    // ========== USER FUNCTIONS ========== //

    function depositCollateral(
        address asset_,
        uint256 amount_,
        address onBehalfOf_
    ) external returns (uint256 depositedCollateral, uint256 totalDepositedCollateral);

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

    function repay(
        address asset_,
        uint256 ohmAmount_,
        address onBehalfOf_
    ) external returns (uint256 repaidOhm, uint256 remainingDebtOhm);

    function extend(
        address asset_,
        address onBehalfOf_,
        uint256 termCount_,
        uint256 maxFee_
    ) external returns (uint48 newMaturity, uint256 feeCollateral, uint256 healthFactor);

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

    function harvestYield(address asset_) external returns (uint256 amount);

    // ========== AUTHORIZATION FUNCTIONS ========== //

    function setAuthorization(address authorized_, uint96 authorizationDeadline_) external;

    function setAuthorizationWithSig(
        Authorization calldata authorization_,
        Signature calldata signature_
    ) external;

    function cancelAuthorization(address authorized_) external;

    // ========== ADMIN FUNCTIONS ========== //

    function setGlobalDebtCapOhm(uint256 debtCapOhm_) external;

    function setFeeConfig(address asset_, FeeConfig calldata config_) external;

    function addAsset(address asset_, AssetConfig calldata config_) external;

    function setAssetConfig(address asset_, AssetConfig calldata config_) external;

    function disableAsset(address asset_) external;

    function enableAsset(address asset_) external;
}
