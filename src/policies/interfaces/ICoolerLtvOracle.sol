// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// Origination LTV drips
/**
 * @title Cooler LTV Oracle
 * @notice It is a custom oracle (not dependant on external markets/AMMs/dependencies) to give the
 * serve both the Origination LTV and Liquidation LTV
 *  - They are both quoted in [debtToken / collateralToken] units
 *  - It is a fixed 18dp price
 *  - Origination LTV updates on a per second basis according to a policy set rate of change (and is up only or flat)
 *  - Liquidation LTV is a policy set percentage above the Origination LTV
 */
interface ICoolerLtvOracle {
    event OriginationLtvSetAt(uint96 oldOriginationLtv, uint96 newOriginationLtvTarget, uint256 targetTime);
    event MaxOriginationLtvDeltaSet(uint256 maxDelta);
    event MinOriginationLtvTargetTimeDeltaSet(uint32 maxTargetTimeDelta);
    event MaxOriginationLtvRateOfChangeSet(uint96 maxRateOfChange);
    event MaxLiquidationLtvPremiumBpsSet(uint96 maxPremiumBps);
    event LiquidationLtvPremiumBpsSet(uint96 premiumBps);

    error BreachedMaxOriginationLtvDelta(uint96 oldOriginationLtv, uint96 newOriginationLtv, uint256 maxDelta);
    error BreachedMinDateDelta(uint32 targetTime, uint32 currentDate, uint32 maxTargetTimeDelta);
    error BreachedMaxOriginationLtvRateOfChange(uint96 targetRateOfChange, uint96 maxRateOfChange);
    error CannotDecreaseLtv();
    error InvalidParam();

    /// @notice The collateral asset of the LTV [debtToken / collateralToken]
    function collateralToken() external view returns (address);

    /// @notice The debt asset of the LTV [debtToken / collateralToken]
    function debtToken() external view returns (address);

    /// @notice The current Origination LTV and Liquidation LTV
    function currentLtvs() external view returns (uint96 originationLtv, uint96 liquidationLtv);

    /// @notice The current Origination LTV
    function currentOriginationLtv() external view returns (uint96);

    /// @notice The current Liquidation LTV
    function currentLiquidationLtv() external view returns (uint96);

    /// @notice The maximum allowed Origination LTV change on any single `setOriginationLtvAt()`, in absolute terms
    /// between the Origination LTV as of now and the targetOriginationLtv
    /// @dev 18 decimal places, 0.20e18 == $0.20. 
    /// Used as a bound to avoid unintended/fat fingering when updating Origination LTV
    function maxOriginationLtvDelta() external view returns (uint96);

    /// @notice The minimum time delta required for Origination LTV to reach it's target value when 
    /// `setOriginationLtvAt()` is called.
    /// @dev In seconds.
    /// Used as a bound to avoid unintended/fat fingering when updating Origination LTV
    function minOriginationLtvTargetTimeDelta() external view returns (uint32);

    /// @notice The maximum (positive) rate of change of Origination LTV allowed, when 
    /// `setOriginationLtvAt()` is called.
    /// @dev Units: [Origination LTV / second]
    function maxOriginationLtvRateOfChange() external view returns (uint96);

    /// @notice The current Origination LTV state data
    function originationLtvData() external view returns (
        uint96 startingValue,
        uint32 startTime,
        uint96 targetValue,
        uint32 targetTime,
        uint96 slope
    );

    /// @notice The maximum Liquidation LTV premium (in basis points) which is allowed to be set when calling
    /// `setLiquidationLtvPremiumBps()`
    function maxLiquidationLtvPremiumBps() external view returns (uint16);

    /// @notice The premium (in basis points) of the Liquidation LTV above the Origination LTV
    function liquidationLtvPremiumBps() external view returns (uint16);

    /// @notice Set maximum Liquidation LTV premium (in basis points) which is allowed to be set when calling
    /// `setLiquidationLtvPremiumBps()`.
    function setLiquidationLtvPremiumBps(uint16 premiumBps) external;

    /// @notice Set Liquidation LTV premium (in basis points) of the Liquidation LTV above the Origination LTV
    function setMaxLiquidationLtvPremiumBps(uint16 premiumBps) external;

    /// @notice Set the maximum allowed Origination LTV change on any single `setOriginationLtvAt()`, in absolute terms
    /// between the Origination LTV as of now and the targetOriginationLtv
    /// @dev 18 decimal places, 0.20e18 == $0.20
    function setMaxOriginationLtvDelta(uint96 maxDelta) external;

    /// @notice Set the minimum time delta required for Origination LTV to reach it's target value when 
    /// `setOriginationLtvAt()` is called.
    /// @dev In seconds.
    function setMinOriginationLtvTargetTimeDelta(uint32 maxTargetTimeDelta) external;

    /// @notice Set the maximum (positive) rate of change of Origination LTV allowed, when 
    /// `setOriginationLtvAt()` is called.
    /// @dev Units: [Origination LTV / second]
    function setMaxOriginationLtvRateOfChange(uint96 originationLtvDelta, uint32 timeDelta) external;

    /// @notice Set the target Origination LTV which will incrementally increase from it's current value to `targetOriginationLtv`
    /// between now and `targetTime`.
    /// @dev targetTime is unixtime, targetOriginationLtv is 18 decimal places, 1.05e18 == $1.05
    function setOriginationLtvAt(uint96 targetOriginationLtv, uint32 targetTime) external;

    /// @notice The decimal precision of both the Origination LTV and Liquidation LTV
    function DECIMALS() external view returns (uint8);
}
