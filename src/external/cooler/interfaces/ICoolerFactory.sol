// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";

interface ICoolerFactory {
    // ===== ERRORS ===== //

    error NotFromFactory();
    error DecimalsNot18();

    // ===== EVENTS ===== //

    /// @notice A global event when a new loan request is created.
    event RequestLoan(address indexed cooler, address collateral, address debt, uint256 reqID);
    /// @notice A global event when a loan request is rescinded.
    event RescindRequest(address indexed cooler, uint256 reqID);
    /// @notice A global event when a loan request is fulfilled.
    event ClearRequest(address indexed cooler, uint256 reqID, uint256 loanID);
    /// @notice A global event when a loan is repaid.
    event RepayLoan(address indexed cooler, uint256 loanID, uint256 amount);
    /// @notice A global event when a loan is extended.
    event ExtendLoan(address indexed cooler, uint256 loanID, uint8 times);
    /// @notice A global event when the collateral of defaulted loan is claimed.
    event DefaultLoan(address indexed cooler, uint256 loanID, uint256 amount);

    // ===== COOLER FUNCTIONS ===== //

    /// @notice Generate a new cooler.
    ///
    /// @param  collateral_ The collateral token.
    /// @param  debt_       The debt token.
    /// @return cooler      The address of the new cooler.
    function generateCooler(IERC20 collateral_, IERC20 debt_) external returns (address cooler);

    // ===== AUX FUNCTIONS ===== //

    /// @notice Check if a cooler was created by the factory.
    ///
    /// @param  cooler_ The cooler address.
    /// @return created True if the cooler was created by the factory, false otherwise.
    function created(address cooler_) external view returns (bool);

    /// @notice Get the cooler for a given user <> collateral <> debt combination.
    ///
    /// @param  user_       The user address.
    /// @param  collateral_ The collateral token.
    /// @param  debt_       The debt token.
    /// @return cooler      The address of the cooler.
    function getCoolerFor(
        address user_,
        address collateral_,
        address debt_
    ) external view returns (address cooler);
}
