// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Kernel, Policy, Keycode, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {ICoolerLtvOracle} from "policies/interfaces/cooler/ICoolerLtvOracle.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {SafeCast} from "libraries/SafeCast.sol";

/**
 * @title Cooler LTV Oracle
 * @notice It is a custom oracle (not dependant on external markets/AMMs/dependencies) to give the
 * serve both the Origination LTV and Liquidation LTV
 *  - They are both quoted in [debtToken / collateralToken] units
 *  - It is a fixed 18dp price
 *  - Origination LTV updates on a per second basis according to a policy set rate of change (and is up only or flat)
 *  - Liquidation LTV is a policy set percentage above the Origination LTV
 */
contract CoolerLtvOracle is ICoolerLtvOracle, Policy, PolicyAdmin {
    using SafeCast for uint256;

    /// @dev The debt token
    ERC20 private immutable _DEBT_TOKEN;

    /// @dev The collateral token
    ERC20 private immutable _COLLATERAL_TOKEN;

    struct OriginationLtvData {
        /// @notice The Origination LTV at the time `setOriginationLtvAt()` was last called
        uint96 startingValue;
        /// @notice The time at which Origination LTV was last updated via `setOriginationLtvAt()`
        uint40 startTime;
        /// @notice The target Origination LTV at the `targetTime`
        uint96 targetValue;
        /// @notice The date which the `targetValue` will be reached.
        uint40 targetTime;
        /// @notice The rate at which the `startingValue` will change over time from `startTime` until `targetTime`.
        uint96 slope;
    }

    /// @inheritdoc ICoolerLtvOracle
    OriginationLtvData public override originationLtvData;

    /// @inheritdoc ICoolerLtvOracle
    uint96 public override maxOriginationLtvDelta;

    /// @inheritdoc ICoolerLtvOracle
    uint32 public override minOriginationLtvTargetTimeDelta;

    /// @inheritdoc ICoolerLtvOracle
    uint96 public override maxOriginationLtvRateOfChange;

    /// @inheritdoc ICoolerLtvOracle
    uint16 public override maxLiquidationLtvPremiumBps;

    /// @inheritdoc ICoolerLtvOracle
    uint16 public override liquidationLtvPremiumBps;

    /// @inheritdoc ICoolerLtvOracle
    uint8 public constant override DECIMALS = 18;

    uint96 public constant BASIS_POINTS_DIVISOR = 10_000;

    constructor(
        address kernel_,
        address collateralToken_,
        address debtToken_,
        uint96 initialOriginationLtv_,
        uint96 maxOriginationLtvDelta_,
        uint32 minOriginationLtvTargetTimeDelta_,
        uint96 maxOriginationLtvRateOfChange_,
        uint16 maxLiquidationLtvPremiumBps_,
        uint16 liquidationLtvPremiumBps_
    ) Policy(Kernel(kernel_)) {
        _COLLATERAL_TOKEN = ERC20(collateralToken_);
        _DEBT_TOKEN = ERC20(debtToken_);

        // Only handle 18dp collateral and debt tokens
        if (_COLLATERAL_TOKEN.decimals() != 18) revert InvalidParam();
        if (_DEBT_TOKEN.decimals() != 18) revert InvalidParam();

        originationLtvData = OriginationLtvData({
            startingValue: initialOriginationLtv_,
            startTime: uint40(block.timestamp),
            targetValue: initialOriginationLtv_,
            targetTime: uint40(block.timestamp),
            slope: 0
        });
        maxOriginationLtvDelta = maxOriginationLtvDelta_;
        minOriginationLtvTargetTimeDelta = minOriginationLtvTargetTimeDelta_;
        maxOriginationLtvRateOfChange = maxOriginationLtvRateOfChange_;

        if (maxLiquidationLtvPremiumBps_ > BASIS_POINTS_DIVISOR) revert InvalidParam();
        if (liquidationLtvPremiumBps_ > maxLiquidationLtvPremiumBps_) revert InvalidParam();
        maxLiquidationLtvPremiumBps = maxLiquidationLtvPremiumBps_;
        liquidationLtvPremiumBps = liquidationLtvPremiumBps_;
    }

    //============================================================================================//
    //                                          ADMIN                                             //
    //============================================================================================//

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1]);
        if (ROLES_MAJOR != 1) revert Policy_WrongModuleVersion(expected);
    }

    /// @inheritdoc ICoolerLtvOracle
    function setMaxOriginationLtvDelta(uint96 maxDelta) external override onlyAdminRole {
        emit MaxOriginationLtvDeltaSet(maxDelta);
        maxOriginationLtvDelta = maxDelta;
    }

    /// @inheritdoc ICoolerLtvOracle
    function setMinOriginationLtvTargetTimeDelta(
        uint32 minTargetTimeDelta
    ) external override onlyAdminRole {
        emit MinOriginationLtvTargetTimeDeltaSet(minTargetTimeDelta);
        minOriginationLtvTargetTimeDelta = minTargetTimeDelta;
    }

    /// @inheritdoc ICoolerLtvOracle
    function setMaxOriginationLtvRateOfChange(
        uint96 originationLtvDelta,
        uint32 timeDelta
    ) external override onlyAdminRole {
        // Calculate the rate of change, rounding down.
        uint96 maxRateOfChange = originationLtvDelta / timeDelta;
        emit MaxOriginationLtvRateOfChangeSet(maxRateOfChange);
        maxOriginationLtvRateOfChange = maxRateOfChange;
    }

    /// @inheritdoc ICoolerLtvOracle
    function setOriginationLtvAt(
        uint96 targetValue,
        uint40 targetTime
    ) external override onlyAdminRole {
        uint96 _currentOriginationLtv = currentOriginationLtv();
        uint40 _now = uint40(block.timestamp);

        // Cannot decrease the OLTV
        if (targetValue < _currentOriginationLtv) revert CannotDecreaseLtv();
        uint96 _originationLtvDelta = targetValue - _currentOriginationLtv;

        // targetTime must be at or after (now + minOriginationLtvTargetTimeDelta)
        if (targetTime < _now + minOriginationLtvTargetTimeDelta)
            revert BreachedMinDateDelta(targetTime, _now, minOriginationLtvTargetTimeDelta);
        uint40 _timeDelta = targetTime - _now;

        // Check that the delta is within tolerance
        if (_originationLtvDelta > maxOriginationLtvDelta)
            revert BreachedMaxOriginationLtvDelta(
                _currentOriginationLtv,
                targetValue,
                maxOriginationLtvDelta
            );
        uint96 _rateOfChange = _originationLtvDelta / _timeDelta;
        if (_rateOfChange > maxOriginationLtvRateOfChange)
            revert BreachedMaxOriginationLtvRateOfChange(
                _rateOfChange,
                maxOriginationLtvRateOfChange
            );

        originationLtvData = OriginationLtvData({
            startingValue: _currentOriginationLtv,
            startTime: _now,
            targetValue: targetValue,
            targetTime: targetTime,
            slope: _rateOfChange
        });

        emit OriginationLtvSetAt(_currentOriginationLtv, targetValue, targetTime);
    }

    /// @inheritdoc ICoolerLtvOracle
    function setMaxLiquidationLtvPremiumBps(uint16 maxPremiumBps) external override onlyAdminRole {
        if (maxPremiumBps > BASIS_POINTS_DIVISOR) revert InvalidParam();
        emit MaxLiquidationLtvPremiumBpsSet(maxPremiumBps);
        maxLiquidationLtvPremiumBps = maxPremiumBps;
    }

    /// @inheritdoc ICoolerLtvOracle
    function setLiquidationLtvPremiumBps(uint16 premiumBps) external override onlyAdminRole {
        // Cannot set LLTV higher than the max
        if (premiumBps > maxLiquidationLtvPremiumBps) revert InvalidParam();

        // Cannot lower the LLTV
        if (premiumBps < liquidationLtvPremiumBps) revert CannotDecreaseLtv();
        emit LiquidationLtvPremiumBpsSet(premiumBps);
        liquidationLtvPremiumBps = premiumBps;
    }

    //============================================================================================//
    //                                          VIEWS                                             //
    //============================================================================================//

    /// @inheritdoc ICoolerLtvOracle
    function collateralToken() external view override returns (IERC20) {
        return IERC20(address(_COLLATERAL_TOKEN));
    }

    /// @inheritdoc ICoolerLtvOracle
    function debtToken() external view override returns (IERC20) {
        return IERC20(address(_DEBT_TOKEN));
    }

    function currentLtvs()
        public
        view
        override
        returns (uint96 originationLtv, uint96 liquidationLtv)
    {
        originationLtv = currentOriginationLtv();
        liquidationLtv = _currentLiquidationLtv(originationLtv);
    }

    /// @inheritdoc ICoolerLtvOracle
    function currentLiquidationLtv() external view override returns (uint96) {
        return _currentLiquidationLtv(currentOriginationLtv());
    }

    /// @inheritdoc ICoolerLtvOracle
    function currentOriginationLtv() public view override returns (uint96) {
        uint40 _now = uint40(block.timestamp);
        if (_now >= originationLtvData.targetTime) {
            // Target date reached, no calculation required just return the target Origination LTV
            return originationLtvData.targetValue;
        } else {
            unchecked {
                uint96 delta = originationLtvData.slope * (_now - originationLtvData.startTime);
                return delta + originationLtvData.startingValue;
            }
        }
    }

    //============================================================================================//
    //                                         INTERNAL                                           //
    //============================================================================================//

    function _currentLiquidationLtv(uint96 oltv) private view returns (uint96) {
        return (oltv * (BASIS_POINTS_DIVISOR + liquidationLtvPremiumBps)) / BASIS_POINTS_DIVISOR;
    }
}
