// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansCalculator} from "src/policies/libraries/BurnerLoansCalculator.sol";
import {BurnerLoansCustody} from "src/policies/libraries/BurnerLoansCustody.sol";
import {BurnerLoansDependencies} from "src/policies/libraries/BurnerLoansDependencies.sol";
import {BurnerLoansQuote} from "src/policies/libraries/BurnerLoansQuote.sol";
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
    using TransferHelper for ERC20;

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
        emit GlobalDebtCapSet(debtCapOhm_);
    }

    /// @notice Sets the oracle supplying canonical OHM backing.
    function setBackingOracle(address backingOracle_) external givenEnabled onlyAdminRole {
        if (backingOracle_ == address(0)) revert BurnerLoans_ZeroAddress();
        backingOracle = backingOracle_;
        emit BackingOracleSet(backingOracle_);
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
        IDepositManager.AssetConfiguration memory assetConfiguration = BurnerLoansCustody
            .validateCustodySupport(
                _DEPOSIT_MANAGER,
                asset_,
                BurnerLoansConstants.DEPOSIT_PERIOD,
                true
            );
        BurnerLoansCustody.validateDepositAmount(
            _DEPOSIT_MANAGER,
            asset_,
            assetConfiguration,
            amount_
        );

        uint128 depositedCollateral = BurnerLoansCustody.deposit(
            _DEPOSIT_MANAGER,
            asset_,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            amount_
        );
        if (depositedCollateral == 0) revert BurnerLoans_ZeroCollateralCredit();
        uint64 positionId = _FLOAN.getOrCreatePosition(_marketId(asset_), onBehalfOf_);
        uint128 totalCollateral = _FLOAN.addCollateral(positionId, depositedCollateral);

        emit CollateralDeposited(msg.sender, asset_, onBehalfOf_, amount_, depositedCollateral);

        return (depositedCollateral, totalCollateral);
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
        if (amount_ == 0) revert BurnerLoans_ZeroAmount();
        _requireSenderAuthorized(msg.sender, onBehalfOf_);
        if (recipient_ == address(0)) revert BurnerLoans_ZeroAddress();
        IDepositManager.AssetConfiguration memory assetConfiguration = BurnerLoansCustody
            .validateCustodySupport(
                _DEPOSIT_MANAGER,
                asset_,
                BurnerLoansConstants.DEPOSIT_PERIOD,
                false
            );
        if (BurnerLoansCustody.previewWithdrawAmount(assetConfiguration.vault, amount_) == 0)
            revert BurnerLoans_ZeroCollateralWithdrawal();

        (remainingDepositedCollateral, healthFactor_) = _debitCollateral(
            asset_,
            amount_,
            onBehalfOf_
        );
        amountOut = BurnerLoansCustody.withdraw(
            _DEPOSIT_MANAGER,
            asset_,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            amount_,
            recipient_
        );
        if (amountOut == 0) revert BurnerLoans_ZeroCollateralWithdrawal();

        emit CollateralWithdrawn(msg.sender, asset_, onBehalfOf_, recipient_, amount_);

        tokenOut = asset_;
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
        BorrowPreview memory quote = _executeBorrow(
            asset_,
            ohmAmount_,
            onBehalfOf_,
            recipient_,
            maxFee_
        );
        return (
            ohmAmount_,
            quote.fee,
            quote.resultingDebtOhm,
            quote.maturity,
            quote.resultingHealthFactor
        );
    }

    // ========== VIEW FUNCTIONS ========== //

    function floan() external view override returns (address) {
        return address(_FLOAN);
    }

    function ohm() external view returns (address) {
        return address(_OHM);
    }

    function depositManager() external view returns (address) {
        return address(_DEPOSIT_MANAGER);
    }

    function totalActiveDebtOhm() public view returns (uint256) {
        return _FLOAN.facilityPrincipalDue(address(this), address(_OHM));
    }

    function assetActiveDebtOhm(address asset_) external view returns (uint256) {
        (bool exists, uint32 marketId_) = _FLOAN.getMarketId(address(this), asset_, address(_OHM));
        return exists ? _FLOAN.marketPrincipalDue(marketId_) : 0;
    }

    function getPosition(
        address asset_,
        address borrower_
    ) external view override returns (Position memory) {
        return BurnerLoansView.getPosition(_position(asset_, borrower_));
    }

    function getActiveBorrowers(address asset_) external view override returns (address[] memory) {
        return _FLOAN.getActiveBorrowers(_marketId(asset_));
    }

    function previewDepositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external view override returns (uint256 depositedCollateral, uint256 totalCollateral) {
        _requireEnabled();
        return
            BurnerLoansView.previewDepositCollateral(
                _viewDependencies(),
                asset_,
                amount_,
                _position(asset_, onBehalfOf_)
            );
    }

    function previewWithdrawCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) external view override returns (WithdrawPreview memory) {
        _requireEnabled();
        return
            BurnerLoansView.previewWithdrawCollateral(
                _viewDependencies(),
                asset_,
                amount_,
                _position(asset_, onBehalfOf_)
            );
    }

    function previewBorrow(
        address asset_,
        uint128 ohmAmount_,
        address onBehalfOf_
    ) external view override returns (BorrowPreview memory) {
        _requireEnabled();
        return
            BurnerLoansQuote.quoteBorrow(
                _quoteDependencies(),
                asset_,
                ohmAmount_,
                _position(asset_, onBehalfOf_)
            );
    }

    function positionHealthFactor(
        address asset_,
        uint256 collateral_,
        uint256 debtOhm_
    ) external view override returns (uint256) {
        return
            BurnerLoansQuote.positionHealthFactor(
                _quoteDependencies(),
                asset_,
                collateral_,
                debtOhm_
            );
    }

    // ========== INTERNAL BORROW HELPERS ========== //

    /// @notice Executes a validated borrow with effects before fee collection and OHM minting.
    function _executeBorrow(
        address asset_,
        uint128 ohmAmount_,
        address onBehalfOf_,
        address recipient_,
        uint256 maxFee_
    ) internal returns (BorrowPreview memory quote) {
        _requireEnabled();
        _requireSenderAuthorized(msg.sender, onBehalfOf_);
        if (recipient_ == address(0)) revert BurnerLoans_ZeroAddress();

        quote = BurnerLoansQuote.quoteBorrow(
            _quoteDependencies(),
            asset_,
            ohmAmount_,
            _position(asset_, onBehalfOf_)
        );
        if (quote.fee > maxFee_) revert BurnerLoans_FeeExceedsMax(quote.fee, maxFee_);

        _FLOAN.increaseDebt(_positionId(asset_, onBehalfOf_), ohmAmount_, 0, quote.maturity);

        if (quote.fee != 0) {
            ERC20(asset_).safeTransferFrom(msg.sender, address(_TRSRY), quote.fee);
        }
        _MINTR.mintOhm(recipient_, ohmAmount_);

        emit Borrowed(msg.sender, asset_, onBehalfOf_, recipient_, ohmAmount_, quote.fee);
    }

    /// @notice Debits position collateral after validating resulting health.
    function _debitCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) internal returns (uint256 remainingCollateral, uint256 resultingHealthFactor) {
        IFLOANv1.Position memory position = _position(asset_, onBehalfOf_);
        if (amount_ > position.collateral) {
            revert BurnerLoans_InsufficientCollateral(amount_, position.collateral);
        }

        remainingCollateral = position.collateral - amount_;
        resultingHealthFactor = BurnerLoansQuote.positionHealthFactor(
            _quoteDependencies(),
            asset_,
            remainingCollateral,
            position.principalDue
        );
        if (position.principalDue != 0 && resultingHealthFactor < _WAD) {
            revert BurnerLoans_UnhealthyWithdrawal(resultingHealthFactor);
        }

        _FLOAN.removeCollateral(_positionId(asset_, onBehalfOf_), amount_);
    }

    function _quoteDependencies()
        internal
        view
        returns (BurnerLoansQuote.Dependencies memory dependencies)
    {
        return
            BurnerLoansQuote.Dependencies({
                ohm: _OHM,
                ohmDecimals: _OHM_DECIMALS,
                facility: address(this),
                globalDebtCapOhm: globalDebtCapOhm,
                backingOracle: backingOracle,
                floan: _FLOAN,
                price: _PRICE
            });
    }

    function _viewDependencies()
        internal
        view
        returns (BurnerLoansView.Dependencies memory dependencies)
    {
        return
            BurnerLoansView.Dependencies({
                ohm: _OHM,
                ohmDecimals: _OHM_DECIMALS,
                depositManager: _DEPOSIT_MANAGER,
                facility: address(this),
                globalDebtCapOhm: globalDebtCapOhm,
                backingOracle: backingOracle,
                floan: _FLOAN,
                price: _PRICE
            });
    }

    /// @notice Calculates health for a prospective position state using fresh PRICE data.
    /// @dev Debt-free positions deliberately do not require PRICE freshness.
    function _positionHealthFactor(
        address asset_,
        AssetConfig memory config_,
        uint256 depositedCollateral_,
        uint256 debtOhm_
    ) internal view returns (uint256) {
        if (debtOhm_ == 0) return type(uint256).max;

        uint48 observationFrequency = _PRICE.observationFrequency();
        (uint256 ohmUsdPrice, ) = _getFreshPrice(address(_OHM), observationFrequency);
        uint256 backingPerOhmUsd = _getBackingPerOhmUsd();
        (uint256 collateralUsdPrice, ) = _getFreshPrice(asset_, observationFrequency);

        uint256 riskAdjustedCollateralUsd = _riskAdjustedCollateralUsd(
            _collateralValueUsd(
                depositedCollateral_,
                collateralUsdPrice,
                config_.collateralDecimals
            ),
            config_.collateralFactorBps
        );
        uint256 requiredCollateralUsd = _requiredCollateralUsd(
            RequiredCollateralUsdInputs({
                debtValueUsd: _debtValueUsd(debtOhm_, ohmUsdPrice, _OHM_DECIMALS),
                debtOhm: debtOhm_,
                backingPerOhmUsd: backingPerOhmUsd,
                minCollateralRatioBps: config_.minCollateralRatioBps,
                backingMultiplierBps: config_.backingMultiplierBps
            })
        );

        return _healthFactor(riskAdjustedCollateralUsd, requiredCollateralUsd);
    }

    /// @notice Reads a non-zero PRICE value whose timestamp is within one observation window.
    function _getFreshPrice(
        address asset_,
        uint48 observationFrequency_
    ) internal view returns (uint256 price, uint48 timestamp) {
        (price, timestamp) = _PRICE.getPrice(asset_, IPRICEv2.Variant.CURRENT);
        if (price == 0 || timestamp == 0) revert BurnerLoans_InvalidPrice();

        if (block.timestamp > uint256(timestamp) + uint256(observationFrequency_)) {
            revert BurnerLoans_InvalidPrice();
        }
    }

    /// @notice Reads canonical OHM backing and converts it from 18 decimals to PRICE decimals.
    /// @dev Conversion rounds up so reducing decimal precision cannot weaken the backing floor.
    function _getBackingPerOhmUsd() internal view returns (uint256 backingPerOhmUsd) {
        address backingOracle_ = backingOracle;
        if (backingOracle_ == address(0)) revert BurnerLoans_ZeroAddress();

        uint256 backing18 = IOlympusBackingOracle(backingOracle_).backing();
        if (backing18 == 0) revert BurnerLoans_InvalidPrice();

        backingPerOhmUsd = FullMath.mulDivUp(backing18, _scale(_PRICE.decimals()), _WAD);
    }

    // ========== INTERNAL MATH HELPERS ========== //

    /// @notice Returns 10 ** decimals_.
    /// @dev Input: decimal count. Output: integer scale.
    function _scale(uint8 decimals_) internal pure returns (uint256) {
        return BurnerLoansCalculator.scale(decimals_);
    }

    /// @notice Converts OHM debt to USD value, rounding up.
    /// @dev Inputs: `debtOhm_` in OHM decimals, `ohmUsdPrice_` in PRICE decimals.
    ///      Output: USD value in PRICE decimals.
    function _debtValueUsd(
        uint256 debtOhm_,
        uint256 ohmUsdPrice_,
        uint8 ohmDecimals_
    ) internal pure returns (uint256) {
        if (ohmUsdPrice_ == 0) revert BurnerLoans_InvalidPrice();
        return BurnerLoansCalculator.debtValueUsd(debtOhm_, ohmUsdPrice_, ohmDecimals_);
    }

    /// @notice Converts collateral to USD value, rounding down.
    /// @dev Inputs: `collateralAmount_` in collateral token decimals,
    ///      `collateralUsdPrice_` in PRICE decimals. Output: USD value in PRICE decimals.
    function _collateralValueUsd(
        uint256 collateralAmount_,
        uint256 collateralUsdPrice_,
        uint8 collateralDecimals_
    ) internal pure returns (uint256) {
        if (collateralUsdPrice_ == 0) revert BurnerLoans_InvalidPrice();
        return
            BurnerLoansCalculator.collateralValueUsd(
                collateralAmount_,
                collateralUsdPrice_,
                collateralDecimals_
            );
    }

    /// @notice Applies the collateral factor to collateral USD value, rounding down.
    /// @dev Inputs and output are PRICE decimals.
    function _riskAdjustedCollateralUsd(
        uint256 collateralValueUsd_,
        uint256 collateralFactorBps_
    ) internal pure returns (uint256) {
        return
            BurnerLoansCalculator.riskAdjustedCollateralUsd(
                collateralValueUsd_,
                collateralFactorBps_
            );
    }

    /// @notice Calculates the backing floor for active or seized OHM debt, rounding up.
    /// @dev Inputs: `debtOhm_` in OHM decimals, `backingPerOhmUsd_` in PRICE decimals.
    ///      Output: required backing in PRICE decimals.
    function _requiredBackingUsd(
        uint256 debtOhm_,
        uint256 backingPerOhmUsd_,
        uint8 ohmDecimals_,
        uint256 backingMultiplierBps_
    ) internal pure returns (uint256) {
        if (backingPerOhmUsd_ == 0) revert BurnerLoans_InvalidPrice();

        return
            BurnerLoansCalculator.requiredBackingUsd(
                debtOhm_,
                backingPerOhmUsd_,
                ohmDecimals_,
                backingMultiplierBps_
            );
    }

    /// @notice Calculates the collateral requirement in USD, rounding requirements up.
    /// @dev Inputs and output are PRICE decimals except `debtOhm_`, which is OHM decimals.
    function _requiredCollateralUsd(
        RequiredCollateralUsdInputs memory inputs_
    ) internal view returns (uint256) {
        return
            BurnerLoansCalculator.requiredCollateralUsd(
                inputs_.debtValueUsd,
                inputs_.debtOhm,
                inputs_.backingPerOhmUsd,
                _OHM_DECIMALS,
                inputs_.minCollateralRatioBps,
                inputs_.backingMultiplierBps
            );
    }

    /// @notice Converts required USD collateral to collateral token units, rounding up.
    /// @dev Input: USD in PRICE decimals. Output: collateral amount in token-native decimals.
    function _requiredCollateralAsset(
        uint256 requiredCollateralUsd_,
        uint256 collateralUsdPrice_,
        uint8 collateralDecimals_
    ) internal pure returns (uint256) {
        if (collateralUsdPrice_ == 0) revert BurnerLoans_InvalidPrice();
        return
            BurnerLoansCalculator.requiredCollateralAsset(
                requiredCollateralUsd_,
                collateralUsdPrice_,
                collateralDecimals_
            );
    }

    /// @notice Calculates borrower health, rounding down.
    /// @dev Inputs: `riskAdjustedCollateralUsd_` and `requiredCollateralUsd_` in PRICE decimals.
    ///      Output: WAD health factor; 1e18 is the seizure boundary.
    function _healthFactor(
        uint256 riskAdjustedCollateralUsd_,
        uint256 requiredCollateralUsd_
    ) internal pure returns (uint256) {
        return
            BurnerLoansCalculator.healthFactor(riskAdjustedCollateralUsd_, requiredCollateralUsd_);
    }

    /// @notice Calculates utilization, rounding up.
    /// @dev Inputs: debt and cap use the same units. Output: bps.
    function _utilizationBps(uint256 debt_, uint256 cap_) internal pure returns (uint256) {
        if (cap_ == 0) {
            if (debt_ == 0) return 0;
            revert BurnerLoans_InvalidCap();
        }

        return FullMath.mulDivUp(debt_, _BPS, cap_);
    }

    /// @notice Calculates asset utilization, rounding up.
    /// @dev Inputs: debt and cap use the same units. Output: WAD.
    function _assetUtilizationWad(uint256 debt_, uint256 cap_) internal pure returns (uint256) {
        uint256 utilization = BurnerLoansCalculator.assetUtilizationWad(debt_, cap_);
        if (utilization == type(uint256).max) revert BurnerLoans_InvalidCap();
        return utilization;
    }

    /// @notice Calculates fee utilization from asset open interest only.
    /// @dev Global utilization is a capacity constraint, not a fee input. Output: WAD.
    function _effectiveUtilizationWad(
        UtilizationInputs memory inputs_
    ) internal pure returns (uint256) {
        return _assetUtilizationWad(inputs_.assetDebtOhm, inputs_.assetDebtCapOhm);
    }

    /// @notice Calculates utilization fee rate from the piecewise linear kink curve.
    /// @dev Uses Aave-style slope semantics. `preKinkSlopeBps` is the full increase from 0 utilization to the
    /// kink. `postKinkSlopeBps` is the additional increase from the kink to 100% utilization. `utilizationWad_`
    /// is WAD. Fee config values are bps. Output is WAD.
    function _feeRateWad(
        uint256 utilizationWad_,
        AssetFeeConfig memory feeConfig_
    ) internal pure override returns (uint256) {
        if (utilizationWad_ > _WAD) revert BurnerLoans_InvalidParam();

        return
            BurnerLoansCalculator.feeRateWad(
                utilizationWad_,
                feeConfig_.baseFeeBps,
                feeConfig_.kinkBps,
                feeConfig_.preKinkSlopeBps,
                feeConfig_.postKinkSlopeBps
            );
    }

    /// @notice Calculates the borrow fee in collateral units, rounding value transfers up.
    /// @dev Output is in collateral token decimals.
    function _borrowFee(
        uint256 incrementalRequiredCollateral_,
        uint256 feeRateWad_
    ) internal pure returns (uint256) {
        return BurnerLoansCalculator.borrowFee(incrementalRequiredCollateral_, feeRateWad_);
    }

    /// @notice Calculates the extension fee in collateral units, rounding the single-term fee up.
    /// @dev Output is in collateral token decimals and scales linearly with `termCount_`.
    function _extensionFee(
        uint256 currentRequiredCollateral_,
        uint256 feeRateWad_,
        uint256 termCount_
    ) internal pure returns (uint256) {
        uint256 singleTermFee = FullMath.mulDivUp(currentRequiredCollateral_, feeRateWad_, _WAD);
        return singleTermFee * termCount_;
    }

    /// @notice Calculates the keeper reward for a seizure batch.
    /// @dev All collateral amounts are token-native decimals. Price and backing inputs use PRICE decimals.
    function _keeperRewardAsset(KeeperRewardInputs memory inputs_) internal view returns (uint256) {
        if (
            inputs_.isProtocolSeizureCaller ||
            inputs_.rewardBps == 0 ||
            inputs_.maxKeeperRewardAsset == 0
        ) {
            return 0;
        }

        uint256 configuredRewardAsset = FullMath.mulDiv(
            inputs_.seizedCollateralAmount,
            inputs_.rewardBps,
            _BPS
        );
        if (configuredRewardAsset > inputs_.maxKeeperRewardAsset) {
            configuredRewardAsset = inputs_.maxKeeperRewardAsset;
        }

        uint256 requiredBackingUsd = _requiredBackingUsd(
            inputs_.seizedUnrepaidDebtOhm,
            inputs_.backingPerOhmUsd,
            _OHM_DECIMALS,
            inputs_.backingMultiplierBps
        );
        uint256 requiredBackingAsset = _requiredCollateralAsset(
            requiredBackingUsd,
            inputs_.collateralUsdPrice,
            inputs_.collateralDecimals
        );

        uint256 surplusAfterBackingAsset = inputs_.seizedCollateralAmount > requiredBackingAsset
            ? inputs_.seizedCollateralAmount - requiredBackingAsset
            : 0;

        return
            configuredRewardAsset < surplusAfterBackingAsset
                ? configuredRewardAsset
                : surplusAfterBackingAsset;
    }
}
