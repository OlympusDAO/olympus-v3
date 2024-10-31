// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

interface IEmissionManager {
    // ========== ERRORS ========== //

    error OnlyTeller();
    error InvalidMarket();
    error InvalidCallback();
    error InvalidParam(string parameter);
    error CannotRestartYet(uint48 availableAt);
    error RestartTimeframePassed();
    error NotActive();
    error AlreadyActive();

    // ========== EVENTS ========== //

    event SaleCreated(uint256 marketID, uint256 saleAmount);
    event BackingUpdated(uint256 newBacking, uint256 supplyAdded, uint256 reservesAdded);

    // ========== DATA STRUCTURES ========== //

    struct BaseRateChange {
        uint256 changeBy;
        uint48 beatsLeft;
        bool addition;
    }

    // ========== EXECUTE ========== //

    /// @notice calculate and execute sale, if applicable, once per day (every 3 beats)
    /// @dev this function is restricted to the heart role and is called on each heart beat
    /// @dev if the contract is not active, the function does nothing
    function execute() external;
}
