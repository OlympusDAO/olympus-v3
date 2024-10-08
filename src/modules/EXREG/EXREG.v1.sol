// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Module} from "src/Kernel.sol";

/// @title  External Registry
/// @notice Interface for a module that can track the addresses of external contracts
abstract contract EXREGv1 is Module {
    // =========  EVENTS ========= //

    /// @notice Emitted when a contract is registered or updated
    event ContractRegistered(bytes5 indexed name, address indexed contractAddress);

    /// @notice Emitted when a contract is deregistered
    event ContractDeregistered(bytes5 indexed name);

    // =========  ERRORS ========= //

    /// @notice Thrown when an invalid name is provided
    error Params_InvalidName();

    /// @notice Thrown when an invalid address is provided
    error Params_InvalidAddress();

    // =========  STATE ========= //

    /// @notice Stores the names of the registered contracts
    bytes5[] internal _contractNames;

    /// @notice Mapping to store the address of a contract
    /// @dev    The address of a registered contract can be retrieved by `getContract()`, and the names of all registered contracts can be retrieved by `getContractNames()`.
    mapping(bytes5 => address) internal _contracts;

    // =========  REGISTRATION FUNCTIONS ========= //

    /// @notice Function to register or update a contract
    /// @dev    This function should be permissioned to prevent arbitrary contracts from being registered.
    ///
    /// @param  name_               The name of the contract
    /// @param  contractAddress_    The address of the contract
    function registerContract(bytes5 name_, address contractAddress_) external virtual;

    /// @notice Function to deregister a contract
    /// @dev    This function should be permissioned to prevent arbitrary contracts from being deregistered.
    ///
    /// @param  name_   The name of the contract
    function deregisterContract(bytes5 name_) external virtual;

    // =========  VIEW FUNCTIONS ========= //

    /// @notice Function to get the address of a contract
    ///
    /// @param  name_   The name of the contract
    /// @return The address of the contract
    function getContract(bytes5 name_) external view virtual returns (address);

    /// @notice Function to get the names of all registered contracts
    ///
    /// @return The names of all registered contracts
    function getContractNames() external view virtual returns (bytes5[] memory);
}
