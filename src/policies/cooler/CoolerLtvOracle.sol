// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Kernel, Policy, Keycode, toKeycode} from "src/Kernel.sol";
import {ROLESv1, RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {ICoolerLtvOracle} from "policies/interfaces/ICoolerLtvOracle.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCast} from "libraries/SafeCast.sol";

contract CoolerLtvOracle is ICoolerLtvOracle, Policy, RolesConsumer {
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;

    /// @inheritdoc ICoolerLtvOracle
    address public immutable override debtToken;

    /// @inheritdoc ICoolerLtvOracle
    address public immutable override collateralToken;

    struct OriginationLtvData {
        /// @notice The Origination LTV at the time `setOriginationLtvAt()` was last called
        uint96 startingValue;

        /// @notice The time at which Origination LTV was last updated via `setOriginationLtvAt()`
        uint32 startTime;

        /// @notice The target Origination LTV at the `targetTime`
        uint96 targetValue;

        /// @notice The date which the `targetValue` will be reached.
        uint32 targetTime;

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

    bytes32 public constant COOLER_OVERSEER_ROLE = bytes32("cooler_overseer");

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
        collateralToken = collateralToken_;
        debtToken = debtToken_;

        // Only handle 18dp collateral and debt tokens
        if (ERC20(collateralToken).decimals() != 18) revert InvalidParam();
        if (ERC20(debtToken).decimals() != 18) revert InvalidParam();

        originationLtvData = OriginationLtvData({
            startingValue: initialOriginationLtv_,
            startTime: uint32(block.timestamp),
            targetValue: initialOriginationLtv_,
            targetTime: uint32(block.timestamp),
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
    function setMaxOriginationLtvDelta(uint96 maxDelta) external override onlyRole(COOLER_OVERSEER_ROLE) {
        emit MaxOriginationLtvDeltaSet(maxDelta);
        maxOriginationLtvDelta = maxDelta;
    }

    /// @inheritdoc ICoolerLtvOracle
    function setMinOriginationLtvTargetTimeDelta(uint32 minTargetTimeDelta) external override onlyRole(COOLER_OVERSEER_ROLE) {
        emit MinOriginationLtvTargetTimeDeltaSet(minTargetTimeDelta);
        minOriginationLtvTargetTimeDelta = minTargetTimeDelta;
    }

    /// @inheritdoc ICoolerLtvOracle
    function setMaxOriginationLtvRateOfChange(uint96 originationLtvDelta, uint32 timeDelta) external override onlyRole(COOLER_OVERSEER_ROLE) {
        // Calculate the rate of change, rounding down.
        uint96 maxRateOfChange = originationLtvDelta / timeDelta;
        emit MaxOriginationLtvRateOfChangeSet(maxRateOfChange);
        maxOriginationLtvRateOfChange = maxRateOfChange;
    }

    /// @inheritdoc ICoolerLtvOracle
    function setOriginationLtvAt(uint96 targetValue, uint32 targetTime) external override onlyRole(COOLER_OVERSEER_ROLE) {
        uint96 _currentOriginationLtv = currentOriginationLtv();
        uint32 _now = uint32(block.timestamp);
        
        // Cannot decrease the OLTV
        if (targetValue < _currentOriginationLtv) revert CannotDecreaseLtv();
        uint96 _originationLtvDelta = targetValue - _currentOriginationLtv;

        // targetTime must be at or after (now + minOriginationLtvTargetTimeDelta)
        if (targetTime < _now + minOriginationLtvTargetTimeDelta) revert BreachedMinDateDelta(targetTime, _now, minOriginationLtvTargetTimeDelta);
        uint32 _timeDelta = targetTime - _now;

        // Check that the delta is within tolerance
        if (_originationLtvDelta > maxOriginationLtvDelta) revert BreachedMaxOriginationLtvDelta(_currentOriginationLtv, targetValue, maxOriginationLtvDelta);
        uint96 _rateOfChange = _originationLtvDelta / _timeDelta;
        if (_rateOfChange > maxOriginationLtvRateOfChange) revert BreachedMaxOriginationLtvRateOfChange(_rateOfChange, maxOriginationLtvRateOfChange);

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
    function setMaxLiquidationLtvPremiumBps(uint16 maxPremiumBps) external override onlyRole(COOLER_OVERSEER_ROLE) {
        if (maxPremiumBps > BASIS_POINTS_DIVISOR) revert InvalidParam();
        emit MaxLiquidationLtvPremiumBpsSet(maxPremiumBps);
        maxLiquidationLtvPremiumBps = maxPremiumBps;
    }

    /// @inheritdoc ICoolerLtvOracle
    function setLiquidationLtvPremiumBps(uint16 premiumBps) external override onlyRole(COOLER_OVERSEER_ROLE) {
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
    function currentLtvs() public override view returns (uint96 originationLtv, uint96 liquidationLtv) {
        originationLtv = currentOriginationLtv();
        liquidationLtv = _currentLiquidationLtv(originationLtv);
    }

    /// @inheritdoc ICoolerLtvOracle
    function currentLiquidationLtv() external override view returns (uint96) {
        return _currentLiquidationLtv(currentOriginationLtv());
    }

    /// @inheritdoc ICoolerLtvOracle
    function currentOriginationLtv() public override view returns (uint96) {
        uint32 _now = uint32(block.timestamp);
        if (_now >= originationLtvData.targetTime) {
            // Target date reached, no calculation required just return the target Origination LTV
            return originationLtvData.targetValue;  
        } else {
            unchecked {
                uint96 delta = originationLtvData.slope * (_now - originationLtvData.startTime);
                return delta + originationLtvData.startingValue;

                // int96 delta = tpiData.tpiSlope * int32(_now - tpiData.startTime);
                // return uint96(delta + int96(tpiData.startingTpi));
            }
        }
    }

    //============================================================================================//
    //                                         INTERNAL                                           //
    //============================================================================================//

    function _currentLiquidationLtv(uint96 oltv) private view returns (uint96) {
        return oltv * (BASIS_POINTS_DIVISOR + liquidationLtvPremiumBps) / BASIS_POINTS_DIVISOR;
    }

}