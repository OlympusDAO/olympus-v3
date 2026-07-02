// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @title Burner Loans
/// @notice Fixed-term, zero-interest OHM shorting facility skeleton.
/// @dev U0-U2 implement shared enablement, policy wiring, and scale-aware math only.
contract BurnerLoans is Policy, PolicyEnablerV2, IBurnerLoans, IVersioned {
    // ========== CONSTANTS ========== //

    uint256 internal constant _BPS = 10_000;
    uint256 internal constant _WAD = 1e18;
    uint8 internal constant _MAX_SCALE_DECIMALS = 77;
    uint8 internal constant _MAX_TOKEN_DECIMALS = 36;

    // ========== IMMUTABLES ========== //

    IERC20 internal immutable _OHM;
    IDepositManager internal immutable _DEPOSIT_MANAGER;

    // ========== MODULES ========== //

    MINTRv1 public MINTR;
    IPRICEv2 public PRICE;
    TRSRYv1 public TRSRY;

    // ========== STATE ========== //

    uint256 public override globalDebtCapOhm;
    uint256 public override totalActiveDebtOhm;

    mapping(address asset => uint256 debtOhm) public override assetActiveDebtOhm;
    mapping(address asset => AssetConfig config) internal _assetConfigs;
    mapping(address asset => FeeConfig config) internal _feeConfigs;
    mapping(address owner => mapping(address asset => Position position)) internal _positions;
    mapping(address account => mapping(address authorized => uint96 deadline))
        public
        override authorizations;
    mapping(address account => uint256 nonce) public override authorizationNonces;

    // ========== INTERNAL STRUCTS ========== //

    struct RequiredCollateralUsdInputs {
        uint256 debtValueUsd;
        uint256 debtOhm;
        uint256 backingPerOhmUsd;
        uint8 ohmDecimals;
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
        uint8 ohmDecimals;
        uint256 backingMultiplierBps;
        uint256 collateralUsdPrice;
        uint8 collateralDecimals;
        uint256 rewardBps;
        uint256 maxKeeperRewardAsset;
    }

    // ========== CONSTRUCTOR ========== //

    constructor(Kernel kernel_, IERC20 ohm_, IDepositManager depositManager_) Policy(kernel_) {
        if (address(ohm_) == address(0) || address(depositManager_) == address(0)) {
            revert BurnerLoans_ZeroAddress();
        }
        if (
            !ERC165Checker.supportsInterface(
                address(depositManager_),
                type(IDepositManager).interfaceId
            )
        ) {
            revert BurnerLoans_InvalidDepositManager(address(depositManager_));
        }

        _OHM = ohm_;
        _DEPOSIT_MANAGER = depositManager_;
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("PRICE");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("TRSRY");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        address priceAddress = getModuleAddress(dependencies[1]);
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[3]));

        if (!IERC165(priceAddress).supportsInterface(type(IPRICEv2).interfaceId)) {
            revert Policy_WrongModuleVersion(abi.encode("PRICE must support IPRICEv2"));
        }
        PRICE = IPRICEv2(priceAddress);

        (uint8 mintrMajor, ) = MINTR.VERSION();
        (uint8 priceMajor, uint8 priceMinor) = Module(priceAddress).VERSION();
        (uint8 rolesMajor, ) = ROLES.VERSION();
        (uint8 trsryMajor, ) = TRSRY.VERSION();

        bool priceVersionSupported = priceMajor == 2 || (priceMajor == 1 && priceMinor >= 2);
        if (mintrMajor != 1 || !priceVersionSupported || rolesMajor != 1 || trsryMajor != 1) {
            revert Policy_WrongModuleVersion(abi.encode("MINTR 1, PRICE >=1.2, ROLES 1, TRSRY 1"));
        }

        _OHM.approve(address(MINTR), type(uint256).max);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](2);
        requests[0] = Permissions({keycode: MINTR.KEYCODE(), funcSelector: MINTR.mintOhm.selector});
        requests[1] = Permissions({keycode: MINTR.KEYCODE(), funcSelector: MINTR.burnOhm.selector});
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoans
    function ohm() external view returns (address) {
        return address(_OHM);
    }

    /// @inheritdoc IBurnerLoans
    function depositManager() external view returns (address) {
        return address(_DEPOSIT_MANAGER);
    }

    /// @inheritdoc IBurnerLoans
    function getAssetConfig(address asset_) external view returns (AssetConfig memory) {
        return _assetConfigs[asset_];
    }

    /// @inheritdoc IBurnerLoans
    function getFeeConfig(address asset_) external view returns (FeeConfig memory) {
        return _feeConfigs[asset_];
    }

    /// @inheritdoc IBurnerLoans
    function getPosition(
        address asset_,
        address borrower_
    ) external view returns (Position memory) {
        return _positions[borrower_][asset_];
    }

    /// @inheritdoc IBurnerLoans
    function isSeizable(address, address) external pure returns (bool) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function getSeizableBorrowers(
        address,
        uint256,
        uint256,
        uint256
    ) external pure returns (address[] memory, uint256, uint256) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function getActiveBorrowers(address) external pure returns (address[] memory) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function healthFactor(address, address) external pure returns (uint256) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function isSenderAuthorized(address account_) external view returns (bool) {
        return msg.sender == account_ || authorizations[account_][msg.sender] >= block.timestamp;
    }

    // ========== PREVIEW FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoans
    function previewDepositCollateral(
        address,
        uint256,
        address
    ) external pure returns (uint256, uint256) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function previewWithdrawCollateral(
        address,
        uint256,
        address
    ) external pure returns (WithdrawPreview memory) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function previewBorrow(address, uint256, address) external pure returns (BorrowPreview memory) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function previewRepay(address, uint256, address) external pure returns (uint256, uint256) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function previewExtend(address, address, uint256) external pure returns (ExtendPreview memory) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function previewSeize(address, address[] calldata) external pure returns (SeizePreview memory) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function previewHarvestYield(address) external pure returns (HarvestPreview memory) {
        revert BurnerLoans_NotImplemented();
    }

    // ========== USER FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoans
    function depositCollateral(address, uint256, address) external pure returns (uint256, uint256) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function withdrawCollateral(
        address,
        uint256,
        address,
        address
    ) external pure returns (address, uint256, uint256, uint256) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function borrow(
        address,
        uint256,
        address,
        address,
        uint256
    ) external view returns (uint256, uint256, uint256, uint48, uint256) {
        _requireEnabled();
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function repay(address, uint256, address) external pure returns (uint256, uint256) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function extend(
        address,
        address,
        uint256,
        uint256
    ) external view returns (uint48, uint256, uint256) {
        _requireEnabled();
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function seize(
        address,
        address[] calldata
    ) external pure returns (uint256, uint256, uint256, uint256) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function harvestYield(address) external pure returns (uint256) {
        revert BurnerLoans_NotImplemented();
    }

    // ========== AUTHORIZATION FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoans
    function setAuthorization(address, uint96) external pure {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function setAuthorizationWithSig(Authorization calldata, Signature calldata) external pure {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function cancelAuthorization(address) external pure {
        revert BurnerLoans_NotImplemented();
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoans
    function setGlobalDebtCapOhm(uint256) external pure {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function setFeeConfig(address, FeeConfig calldata) external pure {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function addAsset(address, AssetConfig calldata) external pure {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function setAssetConfig(address, AssetConfig calldata) external pure {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function disableAsset(address) external pure {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function enableAsset(address) external pure {
        revert BurnerLoans_NotImplemented();
    }

    // ========== INTERNAL MATH HELPERS ========== //

    /// @notice Returns 10 ** decimals_ after validating the exponent is safe.
    /// @dev Input: decimal count. Output: integer scale.
    function _scale(uint8 decimals_) internal pure returns (uint256) {
        if (decimals_ > _MAX_SCALE_DECIMALS) revert BurnerLoans_InvalidDecimals(decimals_);
        return 10 ** decimals_;
    }

    /// @notice Validates token-native decimals used for ERC20 balances.
    /// @dev Input: token decimals. Output: none. Reverts above the configured safe token scale.
    function _validateTokenDecimals(uint8 decimals_) internal pure {
        if (decimals_ > _MAX_TOKEN_DECIMALS) revert BurnerLoans_InvalidDecimals(decimals_);
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
        _validateTokenDecimals(ohmDecimals_);
        return FullMath.mulDivUp(debtOhm_, ohmUsdPrice_, _scale(ohmDecimals_));
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
        _validateTokenDecimals(collateralDecimals_);
        return FullMath.mulDiv(collateralAmount_, collateralUsdPrice_, _scale(collateralDecimals_));
    }

    /// @notice Applies the collateral factor to collateral USD value, rounding down.
    /// @dev Inputs and output are PRICE decimals.
    function _riskAdjustedCollateralUsd(
        uint256 collateralValueUsd_,
        uint256 collateralFactorBps_
    ) internal pure returns (uint256) {
        _validateBps(collateralFactorBps_);
        return FullMath.mulDiv(collateralValueUsd_, collateralFactorBps_, _BPS);
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
        _validateTokenDecimals(ohmDecimals_);

        uint256 backingValueUsd = FullMath.mulDivUp(
            debtOhm_,
            backingPerOhmUsd_,
            _scale(ohmDecimals_)
        );
        return FullMath.mulDivUp(backingValueUsd, backingMultiplierBps_, _BPS);
    }

    /// @notice Calculates the collateral requirement in USD, rounding requirements up.
    /// @dev Inputs and output are PRICE decimals except `debtOhm_`, which is OHM decimals.
    function _requiredCollateralUsd(
        RequiredCollateralUsdInputs memory inputs_
    ) internal pure returns (uint256) {
        uint256 marketRequirementUsd = FullMath.mulDivUp(
            inputs_.debtValueUsd,
            inputs_.minCollateralRatioBps,
            _BPS
        );
        uint256 backingRequirementUsd = _requiredBackingUsd(
            inputs_.debtOhm,
            inputs_.backingPerOhmUsd,
            inputs_.ohmDecimals,
            inputs_.backingMultiplierBps
        );

        return
            marketRequirementUsd > backingRequirementUsd
                ? marketRequirementUsd
                : backingRequirementUsd;
    }

    /// @notice Converts required USD collateral to collateral token units, rounding up.
    /// @dev Input: USD in PRICE decimals. Output: collateral amount in token-native decimals.
    function _requiredCollateralAsset(
        uint256 requiredCollateralUsd_,
        uint256 collateralUsdPrice_,
        uint8 collateralDecimals_
    ) internal pure returns (uint256) {
        if (collateralUsdPrice_ == 0) revert BurnerLoans_InvalidPrice();
        _validateTokenDecimals(collateralDecimals_);
        return
            FullMath.mulDivUp(
                requiredCollateralUsd_,
                _scale(collateralDecimals_),
                collateralUsdPrice_
            );
    }

    /// @notice Converts required backing USD to collateral token units, rounding up.
    /// @dev Input: USD in PRICE decimals. Output: collateral amount in token-native decimals.
    function _requiredBackingAsset(
        uint256 requiredBackingUsd_,
        uint256 collateralUsdPrice_,
        uint8 collateralDecimals_
    ) internal pure returns (uint256) {
        return
            _requiredCollateralAsset(requiredBackingUsd_, collateralUsdPrice_, collateralDecimals_);
    }

    /// @notice Calculates borrower health, rounding down.
    /// @dev Inputs: `riskAdjustedCollateralUsd_` and `requiredCollateralUsd_` in PRICE decimals.
    ///      Output: WAD health factor; 1e18 is the seizure boundary.
    function _healthFactor(
        uint256 riskAdjustedCollateralUsd_,
        uint256 requiredCollateralUsd_
    ) internal pure returns (uint256) {
        if (requiredCollateralUsd_ == 0) return type(uint256).max;
        return FullMath.mulDiv(riskAdjustedCollateralUsd_, _WAD, requiredCollateralUsd_);
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
        if (cap_ == 0) {
            if (debt_ == 0) return 0;
            revert BurnerLoans_InvalidCap();
        }

        return FullMath.mulDivUp(debt_, _WAD, cap_);
    }

    /// @notice Calculates fee utilization from asset open interest only.
    /// @dev Global utilization is a capacity constraint, not a fee input. Output: WAD.
    function _effectiveUtilizationWad(
        UtilizationInputs memory inputs_
    ) internal pure returns (uint256) {
        return _assetUtilizationWad(inputs_.assetDebtOhm, inputs_.assetDebtCapOhm);
    }

    /// @notice Calculates utilization fee rate from the piecewise linear kink curve.
    /// @dev `utilizationWad_` is WAD. Fee config values are bps. Output is WAD.
    function _feeRateWad(
        uint256 utilizationWad_,
        FeeConfig memory feeConfig_
    ) internal pure returns (uint256) {
        if (utilizationWad_ > _WAD) revert BurnerLoans_InvalidParam();
        _validateBps(feeConfig_.kinkBps);

        uint256 baseFeeRateWad = uint256(feeConfig_.baseFeeBps) * (_WAD / _BPS);
        uint256 kinkWad = uint256(feeConfig_.kinkBps) * (_WAD / _BPS);

        if (utilizationWad_ <= kinkWad) {
            return baseFeeRateWad + FullMath.mulDiv(utilizationWad_, feeConfig_.slope1Bps, _BPS);
        }

        return
            baseFeeRateWad +
            FullMath.mulDiv(kinkWad, feeConfig_.slope1Bps, _BPS) +
            FullMath.mulDiv(utilizationWad_ - kinkWad, feeConfig_.slope2Bps, _BPS);
    }

    /// @notice Calculates the borrow fee in collateral units, rounding value transfers up.
    /// @dev Output is in collateral token decimals.
    function _borrowFee(
        uint256 incrementalRequiredCollateral_,
        uint256 feeRateWad_
    ) internal pure returns (uint256) {
        return FullMath.mulDivUp(incrementalRequiredCollateral_, feeRateWad_, _WAD);
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
    function _keeperRewardAsset(KeeperRewardInputs memory inputs_) internal pure returns (uint256) {
        _validateBps(inputs_.rewardBps);

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
            inputs_.ohmDecimals,
            inputs_.backingMultiplierBps
        );
        uint256 requiredBackingAsset = _requiredBackingAsset(
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

    /// @notice Reverts if a bps value exceeds 100%.
    function _validateBps(uint256 bps_) internal pure {
        if (bps_ > _BPS) revert BurnerLoans_InvalidBps(bps_);
    }

    // ========== VERSION ========== //

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== ERC165 ========== //

    /// @notice ERC165 interface support.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2) returns (bool) {
        return
            interfaceId_ == type(IBurnerLoans).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
