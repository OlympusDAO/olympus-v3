// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Auth, Authority} from "solmate/auth/Auth.sol";

import {Kernel, Policy} from "src/Kernel.sol";
import {OlympusPrice} from "modules/PRICE.sol";

contract OlympusPriceConfig is Policy, Auth {
    /* ========== STATE VARIABLES ========== */

    /// Modules
    OlympusPrice internal PRICE;

    /* ========== CONSTRUCTOR ========== */

    constructor(Kernel kernel_)
        Policy(kernel_)
        Auth(address(kernel_), Authority(address(0)))
    {}

    /* ========== FRAMEWORK CONFIGURATION ========== */
    function configureReads() external override {
        PRICE = OlympusPrice(getModuleAddress("PRICE"));
        setAuthority(Authority(getModuleAddress("AUTHR")));
    }

    function requestRoles()
        external
        view
        override
        returns (Kernel.Role[] memory roles)
    {
        roles = new Kernel.Role[](1);
        roles[0] = PRICE.GUARDIAN();
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /// @notice                     Initialize the price module
    /// @notice                     Access restricted to approved policies
    /// @param startObservations_   Array of observations to initialize the moving average with. Must be of length numObservations.
    /// @param lastObservationTime_ Unix timestamp of last observation being provided (in seconds).
    /// @dev This function must be called after the Price module is deployed to activate it and after updating the observationFrequency
    ///      or movingAverageDuration (in certain cases) in order for the Price module to function properly.
    function initialize(
        uint256[] memory startObservations_,
        uint48 lastObservationTime_
    ) external requiresAuth {
        PRICE.initialize(startObservations_, lastObservationTime_);
    }

    /// @notice                         Change the moving average window (duration)
    /// @param movingAverageDuration_   Moving average duration in seconds, must be a multiple of observation frequency
    /// @dev Setting the window to a larger number of observations than the current window will clear
    ///      the data in the current window and require the initialize function to be called again.
    ///      Ensure that you have saved the existing data and can re-populate before calling this
    ///      function with a number of observations larger than have been recorded.
    function changeMovingAverageDuration(uint48 movingAverageDuration_)
        external
        requiresAuth
    {
        PRICE.changeMovingAverageDuration(movingAverageDuration_);
    }

    /// @notice   Change the observation frequency of the moving average (i.e. how often a new observation is taken)
    /// @param    observationFrequency_   Observation frequency in seconds, must be a divisor of the moving average duration
    /// @dev      Changing the observation frequency clears existing observation data since it will not be taken at the right time intervals.
    ///           Ensure that you have saved the existing data and/or can re-populate before calling this function.
    function changeObservationFrequency(uint48 observationFrequency_)
        external
        requiresAuth
    {
        PRICE.changeObservationFrequency(observationFrequency_);
    }
}
