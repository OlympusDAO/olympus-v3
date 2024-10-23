// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Module} from "src/Kernel.sol";

/// @title  Contract Registry
/// @notice Interface for a module that can track the addresses of contracts
abstract contract RGSTYv1 is Module {
    // =========  EVENTS ========= //

    /// @notice Emitted when a contract is registered
    event ContractRegistered(
        bytes5 indexed name,
        address indexed contractAddress,
        bool isImmutable
    );

    /// @notice Emitted when a contract is updated
    event ContractUpdated(bytes5 indexed name, address indexed contractAddress);

    /// @notice Emitted when a contract is deregistered
    event ContractDeregistered(bytes5 indexed name);

    // =========  ERRORS ========= //

    /// @notice The provided name is invalid
    error Params_InvalidName();

    /// @notice The provided address is invalid
    error Params_InvalidAddress();

    /// @notice The provided contract name is already registered
    error Params_ContractAlreadyRegistered();

    /// @notice The provided contract name is not registered
    error Params_ContractNotRegistered();

    // =========  STATE ========= //

    /// @notice Stores the names of the registered immutable contracts
    bytes5[] internal _immutableContractNames;

    /// @notice Stores the names of the registered contracts
    bytes5[] internal _contractNames;

    /// @notice Mapping to store the immutable address of a contract
    /// @dev    The address of an immutable contract can be retrieved by `getImmutableContract()`, and the names of all immutable contracts can be retrieved by `getImmutableContractNames()`.
    mapping(bytes5 => address) internal _immutableContracts;

    /// @notice Mapping to store the address of a contract
    /// @dev    The address of a registered contract can be retrieved by `getContract()`, and the names of all registered contracts can be retrieved by `getContractNames()`.
    mapping(bytes5 => address) internal _contracts;

    // =========  REGISTRATION FUNCTIONS ========= //

    /// @notice Register an immutable contract name and address
    /// @dev    This function should be permissioned to prevent arbitrary contracts from being registered.
    ///
    /// @param  name_               The name of the contract
    /// @param  contractAddress_    The address of the contract
    function registerImmutableContract(bytes5 name_, address contractAddress_) external virtual;

    /// @notice Register a new contract name and address
    /// @dev    This function should be permissioned to prevent arbitrary contracts from being registered.
    ///
    /// @param  name_               The name of the contract
    /// @param  contractAddress_    The address of the contract
    function registerContract(bytes5 name_, address contractAddress_) external virtual;

    /// @notice Update the address of an existing contract name
    /// @dev    This function should be permissioned to prevent arbitrary contracts from being updated.
    ///
    /// @param  name_               The name of the contract
    /// @param  contractAddress_    The address of the contract
    function updateContract(bytes5 name_, address contractAddress_) external virtual;

    /// @notice Deregister an existing contract name
    /// @dev    This function should be permissioned to prevent arbitrary contracts from being deregistered.
    ///
    /// @param  name_   The name of the contract
    function deregisterContract(bytes5 name_) external virtual;

    // =========  VIEW FUNCTIONS ========= //

    /// @notice Get the address of a registered immutable contract
    ///
    /// @param  name_   The name of the contract
    /// @return The address of the contract
    function getImmutableContract(bytes5 name_) external view virtual returns (address);

    /// @notice Get the address of a registered mutable contract
    ///
    /// @param  name_   The name of the contract
    /// @return The address of the contract
    function getContract(bytes5 name_) external view virtual returns (address);

    /// @notice Get the names of all registered immutable contracts
    ///
    /// @return The names of all registered immutable contracts
    function getImmutableContractNames() external view virtual returns (bytes5[] memory);

    /// @notice Get the names of all registered mutable contracts
    ///
    /// @return The names of all registered mutable contracts
    function getContractNames() external view virtual returns (bytes5[] memory);
}
