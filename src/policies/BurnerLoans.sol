// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {BurnerLoansContext} from "src/policies/interfaces/IBurnerLoansSeizureContext.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";
import {BurnerLoansCustody} from "src/policies/libraries/BurnerLoansCustody.sol";
import {BurnerLoansDependencies} from "src/policies/libraries/BurnerLoansDependencies.sol";
import {BurnerLoansQuote} from "src/policies/libraries/BurnerLoansQuote.sol";
import {BurnerLoansSeizure} from "src/policies/libraries/BurnerLoansSeizure.sol";
import {BurnerLoansView} from "src/policies/libraries/BurnerLoansView.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {BurnerLoansLifecycle} from "src/policies/abstracts/BurnerLoansLifecycle.sol";

/// @title Burner Loans
/// @notice Fixed-term, zero-interest OHM shorting facility skeleton.
/// @dev U0-U3A implement shared enablement, policy wiring, scale-aware math, and configuration.
contract BurnerLoans is BurnerLoansLifecycle, ReentrancyGuardTransient {
    uint128 public globalDebtCapOhm;
    address public backingOracle;

    // ========== INTERNAL STRUCTS ========== //

    struct RequiredCollateralUsdInputs {
        uint256 debtValueUsd;
        uint256 debtOhm;
        uint256 backingPerOhmUsd;
        uint256 minCollateralRatioBps;
        uint256 backingMultiplierBps;
    }

    struct UtilizationInputs {
        uint256 assetDebtOhm;
        uint256 assetDebtCapOhm;
    }

    struct KeeperRewardInputs {
        bool isProtocolSeizureCaller;
        uint256 seizedCollateralAmount;
        uint256 seizedUnrepaidDebtOhm;
        uint256 backingPerOhmUsd;
        uint256 backingMultiplierBps;
        uint256 collateralUsdPrice;
        uint8 collateralDecimals;
        uint256 rewardBps;
        uint256 maxKeeperRewardAsset;
    }

    // ========== CONSTRUCTOR ========== //

    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        IDepositManager depositManager_
    ) BurnerLoansLifecycle(kernel_, ohm_, depositManager_) {}

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = BurnerLoansDependencies.keycodes();

        _FLOAN = IFLOANv1(getModuleAddress(dependencies[0]));
        _MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        address priceAddress = getModuleAddress(dependencies[2]);
        ROLES = ROLESv1(getModuleAddress(dependencies[3]));
        _TRSRY = TRSRYv1(getModuleAddress(dependencies[4]));

        _PRICE = BurnerLoansDependencies.validate(_FLOAN, _MINTR, priceAddress, ROLES, _TRSRY);

        _OHM.approve(address(_MINTR), type(uint256).max);
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        return BurnerLoansDependencies.permissions();
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Sets the maximum active principal for this Burner Loans facility.
    function setGlobalDebtCap(uint128 debtCapOhm_) external givenEnabled onlyAdminRole {
        if (debtCapOhm_ < totalActiveDebtOhm()) revert BurnerLoans_InvalidCap();
        globalDebtCapOhm = debtCapOhm_;

        BurnerLoansCustody.reconcileMintApproval(_FLOAN, _MINTR, _OHM, debtCapOhm_);
        emit GlobalDebtCapSet(debtCapOhm_);
    }

    /// @notice Sets the oracle supplying canonical OHM backing.
    function setBackingOracle(address backingOracle_) external givenEnabled onlyAdminRole {
        if (backingOracle_ == address(0)) revert BurnerLoans_ZeroAddress();
        backingOracle = backingOracle_;
        emit BackingOracleSet(backingOracle_);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    function syncMintApproval() external override returns (uint256 approval) {
        _onlyBurnerLoansManager();
        approval = BurnerLoansCustody.reconcileMintApproval(_FLOAN, _MINTR, _OHM, globalDebtCapOhm);
        emit MintApprovalSynchronized(approval);
    }

    // ========== USER FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Reverts if:
    ///      - Burner Loans, the collateral asset, or DepositManager is disabled.
    ///      - The caller is not the owner or an authorized operator.
    ///      - Custody is unsupported.
    ///      - `amount_` is zero, below the DepositManager minimum, or exceeds its operator cap.
    ///      - Token transfer fails, custody leaves residual collateral, or vault rounding produces
    ///        zero credit.
    function depositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external returns (uint256, uint256) {
        _requireEnabled();
        _requireAssetEnabled(asset_);
        if (amount_ == 0) revert BurnerLoans_ZeroAmount();
        _requireSenderAuthorized(msg.sender, onBehalfOf_);
        return
            BurnerLoansCustody.depositCollateral(
                _FLOAN,
                _DEPOSIT_MANAGER,
                _marketId(asset_),
                asset_,
                amount_,
                onBehalfOf_
            );
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Asset disable does not block this exit. Reverts if:
    ///      - Burner Loans or DepositManager is disabled.
    ///      - The caller is not the owner or an authorized operator.
    ///      - Custody is unsupported.
    ///      - `amount_` is zero, exceeds credited collateral, or rounds to zero output.
    ///      - `recipient_` is zero, PRICE is unavailable or stale with debt, or health falls below
    ///        1e18 after the withdrawal.
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
            uint256 healthFactor_
        )
    {
        _requireEnabled();
        _requireAssetConfigured(asset_);
        _requireSenderAuthorized(msg.sender, onBehalfOf_);
        BurnerLoansCustody.WithdrawParams memory params;
        params.marketId = _marketId(asset_);
        params.asset = asset_;
        params.onBehalfOf = onBehalfOf_;
        params.recipient = recipient_;
        params.amount = amount_;
        return BurnerLoansCustody.withdrawCollateral(this.context(), _DEPOSIT_MANAGER, params);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Uses pre-borrow asset utilization for the fee curve and charges the fee on the
    ///      incremental required collateral. Reverts if:
    ///      - Burner Loans or the collateral asset is disabled or unconfigured.
    ///      - The caller is not the owner or an authorized operator.
    ///      - `ohmAmount_` or `recipient_` is zero, or the position has no credited collateral.
    ///      - OHM or collateral PRICE is unsupported, zero, or stale.
    ///      - The resulting global or asset active debt exceeds its cap.
    ///      - The position is seized, matured, currently unhealthy, or unhealthy after borrowing.
    ///      - The collateral fee exceeds `maxFee_` or cannot be transferred from the caller.
    ///      - MINTR cannot mint exactly `ohmAmount_` to `recipient_`.
    function borrow(
        address asset_,
        uint128 ohmAmount_,
        address onBehalfOf_,
        address recipient_,
        uint256 maxFee_
    ) external nonReentrant returns (uint256, uint256, uint256, uint48, uint256) {
        _requireEnabled();
        _requireSenderAuthorized(msg.sender, onBehalfOf_);
        if (recipient_ == address(0)) revert BurnerLoans_ZeroAddress();
        BurnerLoansCustody.BorrowParams memory params;
        params.marketId = _marketId(asset_);
        params.asset = asset_;
        params.onBehalfOf = onBehalfOf_;
        params.recipient = recipient_;
        params.ohmAmount = ohmAmount_;
        params.maxFee = maxFee_;
        BorrowPreview memory quote = BurnerLoansCustody.borrow(
            this.context(),
            _MINTR,
            _TRSRY,
            params
        );
        return (
            ohmAmount_,
            quote.fee,
            quote.resultingDebtOhm,
            quote.maturity,
            quote.resultingHealthFactor
        );
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Partial repayments return zero as a conservative unknown-health sentinel so repayment
    ///      never depends on PRICE freshness. Full repayment returns the debt-free max value.
    function repay(
        address asset_,
        uint128 repayOhm_,
        address onBehalfOf_
    ) external override nonReentrant returns (uint256 healthFactor) {
        _requireEnabled();
        if (repayOhm_ == 0) revert BurnerLoans_ZeroAmount();
        return
            BurnerLoansCustody.repay(
                _FLOAN,
                _MINTR,
                _OHM,
                _marketId(asset_),
                asset_,
                onBehalfOf_,
                repayOhm_
            );
    }

    /// @inheritdoc IBurnerLoansLifecycle
    function extend(
        address asset_,
        address onBehalfOf_,
        uint16 termCount_,
        uint256 maxFee_
    ) external override nonReentrant returns (uint256 fee, uint48 maturity, uint256 healthFactor) {
        _requireEnabled();
        _requireSenderAuthorized(msg.sender, onBehalfOf_);
        ExtendPreview memory preview = BurnerLoansCustody.extend(
            this.context(),
            _TRSRY,
            _marketId(asset_),
            asset_,
            onBehalfOf_,
            termCount_,
            maxFee_
        );
        return (preview.fee, preview.maturity, preview.healthFactor);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    function seize(
        address asset_,
        address[] calldata borrowers_
    ) external override nonReentrant returns (uint256, uint256) {
        _requireEnabled();
        SeizePreview memory preview = BurnerLoansSeizure.seize(asset_, borrowers_);
        return (preview.keeperReward, preview.collateralToTreasury);
    }

    /// @inheritdoc IBurnerLoansLifecycle
    /// @dev Asset disable does not block safe surplus collection. Reverts if Burner Loans or
    ///      DepositManager is disabled, custody is unsupported, or custody is insolvent.
    function harvestYield(
        address asset_
    ) external override nonReentrant returns (uint256 yieldClaimed) {
        _requireEnabled();
        _requireAssetConfigured(asset_);
        return
            BurnerLoansCustody.harvestYield(
                _DEPOSIT_MANAGER,
                asset_,
                address(this),
                address(_TRSRY)
            );
    }

    // ========== VIEW FUNCTIONS ========== //

    function floan() external view override returns (address) {
        return address(_FLOAN);
    }

    function totalActiveDebtOhm() public view returns (uint256) {
        return _FLOAN.getFacilityPrincipalDue(address(this), address(_OHM));
    }

    function assetActiveDebtOhm(address asset_) external view returns (uint256) {
        return BurnerLoansView.assetActiveDebtOhm(_FLOAN, address(this), address(_OHM), asset_);
    }

    function getPosition(
        address asset_,
        address borrower_
    ) external view override returns (Position memory) {
        return BurnerLoansView.getPositionForBorrower(_FLOAN, _marketId(asset_), borrower_);
    }

    function getActiveBorrowers(address asset_) external view override returns (address[] memory) {
        return _FLOAN.getActiveBorrowers(_marketId(asset_));
    }

    function isSeizable(address asset_, address borrower_) external view override returns (bool) {
        return
            BurnerLoansView.isBorrowerSeizable(
                this.context(),
                asset_,
                _marketId(asset_),
                borrower_
            );
    }

    function previewSeize(
        address asset_,
        address[] calldata borrowers_
    ) external view override returns (SeizePreview memory) {
        _requireEnabled();
        return BurnerLoansSeizure.previewSeize(asset_, borrowers_);
    }

    function getSeizableBorrowers(
        address asset_,
        uint256 startIndex_,
        uint256 maxBorrowersToCheck_,
        uint256 maxBorrowersToReturn_
    ) external view override returns (address[] memory, uint256, uint256) {
        _requireEnabled();
        return
            BurnerLoansSeizure.getSeizableBorrowers(
                BurnerLoansSeizure.ScanRequest({
                    asset: asset_,
                    startIndex: startIndex_,
                    maxBorrowersToCheck: maxBorrowersToCheck_,
                    maxBorrowersToReturn: maxBorrowersToReturn_
                })
            );
    }

    function previewDepositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external view override returns (uint256 depositedCollateral, uint256 totalCollateral) {
        _requireEnabled();
        return
            BurnerLoansView.previewDepositCollateralForBorrower(
                this.context(),
                asset_,
                amount_,
                _marketId(asset_),
                onBehalfOf_
            );
    }

    function previewWithdrawCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external view override returns (WithdrawPreview memory) {
        _requireEnabled();
        return
            BurnerLoansView.previewWithdrawCollateralForBorrower(
                this.context(),
                asset_,
                amount_,
                _marketId(asset_),
                onBehalfOf_
            );
    }

    function previewBorrow(
        address asset_,
        uint128 ohmAmount_,
        address onBehalfOf_
    ) external view override returns (BorrowPreview memory) {
        _requireEnabled();
        return
            BurnerLoansQuote.previewBorrow(
                this.context(),
                asset_,
                ohmAmount_,
                _marketId(asset_),
                onBehalfOf_
            );
    }

    function previewRepay(
        address asset_,
        uint128 repayOhm_,
        address onBehalfOf_
    ) external view override returns (RepayPreview memory) {
        _requireEnabled();
        if (repayOhm_ == 0) revert BurnerLoans_ZeroAmount();
        return
            BurnerLoansView.previewRepayForBorrower(
                _FLOAN,
                _marketId(asset_),
                onBehalfOf_,
                repayOhm_
            );
    }

    function previewExtend(
        address asset_,
        address onBehalfOf_,
        uint16 termCount_
    ) external view override returns (ExtendPreview memory) {
        _requireEnabled();
        return
            BurnerLoansQuote.previewExtend(
                this.context(),
                asset_,
                termCount_,
                _marketId(asset_),
                onBehalfOf_
            );
    }

    function positionHealthFactor(
        address asset_,
        uint256 collateral_,
        uint256 debtOhm_
    ) external view override returns (uint256) {
        return BurnerLoansQuote.positionHealthFactor(this.context(), asset_, collateral_, debtOhm_);
    }

    /// @notice Quotes currently claimable custody yield for an asset.
    function previewHarvestYield(
        address asset_
    ) external view override returns (HarvestPreview memory) {
        _requireEnabled();
        AssetCollateralStatus memory collateralStatus = this.getAssetCollateralStatus(asset_);
        return
            HarvestPreview({
                amount: collateralStatus.claimableYield,
                executable: collateralStatus.solvent
            });
    }

    /// @notice Returns DepositManager accounting for this facility and asset.
    function getAssetCollateralStatus(
        address asset_
    ) external view override returns (AssetCollateralStatus memory) {
        _requireAssetConfigured(asset_);
        return BurnerLoansCustody.getAssetCollateralStatus(_DEPOSIT_MANAGER, asset_, address(this));
    }

    function context() external view returns (BurnerLoansContext memory dependencies) {
        return
            BurnerLoansContext({
                ohm: _OHM,
                ohmDecimals: _OHM_DECIMALS,
                depositManager: _DEPOSIT_MANAGER,
                facility: address(this),
                globalDebtCapOhm: globalDebtCapOhm,
                backingOracle: backingOracle,
                floan: _FLOAN,
                price: _PRICE,
                treasury: address(_TRSRY),
                roles: ROLES
            });
    }
}
