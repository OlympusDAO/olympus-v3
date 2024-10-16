// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Kernel, Module, Policy, Keycode, toKeycode} from "src/Kernel.sol";
import {RGSTYv1} from "./RGSTY.v1.sol";

/// @title  Olympus Contract Registry
/// @notice This module is used to track the addresses of contracts.
contract OlympusContractRegistry is RGSTYv1 {
    // =========  STATE ========= //

    /// @notice The keycode for the Olympus Contract Registry
    bytes5 public constant keycode = "RGSTY";

    // =========  CONSTRUCTOR ========= //

    /// @notice Constructor for the Olympus Contract Registry
    /// @dev    This function will revert if:
    ///         - The provided kernel address is zero
    ///
    /// @param  kernel_ The address of the kernel
    constructor(address kernel_) Module(Kernel(kernel_)) {
        if (kernel_ == address(0)) revert Params_InvalidAddress();
    }

    // =========  MODULE SETUP ========= //

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode(keycode);
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // =========  CONTRACT REGISTRATION ========= //

    /// @inheritdoc RGSTYv1
    /// @dev        This function performs the following steps:
    ///             - Validates the parameters
    ///             - Updates the contract address
    ///             - Updates the contract names (if needed)
    ///             - Refreshes the dependent policies
    ///
    ///             The contract name can contain:
    ///             - Lowercase letters
    ///             - Numerals
    ///
    ///             This function will revert if:
    ///             - The caller is not permissioned
    ///             - The name is empty
    ///             - The name contains punctuation or uppercase letters
    ///             - The contract address is zero
    ///             - The contract name is already registered
    function registerContract(
        bytes5 name_,
        address contractAddress_
    ) external override permissioned {
        // Check that the name is not empty
        if (name_ == bytes5(0)) revert Params_InvalidName();

        // Check that the contract has not already been registered
        if (_contracts[name_] != address(0)) revert Params_ContractAlreadyRegistered();

        // Check that the contract address is not zero
        if (contractAddress_ == address(0)) revert Params_InvalidAddress();

        // Check that the contract name is lowercase letters and numerals only
        for (uint256 i = 0; i < 5; i++) {
            bytes1 char = name_[i];

            // 0-9
            if (char >= 0x30 && char <= 0x39) continue;

            // a-z
            if (char >= 0x61 && char <= 0x7A) continue;

            // Skip if empty
            // An empty name has already been checked at the start
            if (char == 0x00) continue;

            revert Params_InvalidName();
        }

        // Register the contract
        _contracts[name_] = contractAddress_;
        _updateContractNames(name_);
        _refreshDependents();

        emit ContractRegistered(name_, contractAddress_);
    }

    /// @inheritdoc RGSTYv1
    /// @dev        This function performs the following steps:
    ///             - Validates the parameters
    ///             - Updates the contract address
    ///             - Updates the contract names (if needed)
    ///             - Refreshes the dependent policies
    ///
    ///             This function will revert if:
    ///             - The caller is not permissioned
    ///             - The name is not registered
    ///             - The contract address is zero
    function updateContract(bytes5 name_, address contractAddress_) external override permissioned {
        // Check that the contract address is not zero
        if (contractAddress_ == address(0)) revert Params_InvalidAddress();

        // Check that the contract name is registered
        if (_contracts[name_] == address(0)) revert Params_ContractNotRegistered();

        _contracts[name_] = contractAddress_;
        _refreshDependents();

        emit ContractUpdated(name_, contractAddress_);
    }

    /// @inheritdoc RGSTYv1
    /// @dev        This function performs the following steps:
    ///             - Validates the parameters
    ///             - Removes the contract address
    ///             - Removes the contract name
    ///             - Refreshes the dependent policies
    ///
    ///             This function will revert if:
    ///             - The caller is not permissioned
    ///             - The contract is not registered
    function deregisterContract(bytes5 name_) external override permissioned {
        address contractAddress = _contracts[name_];
        if (contractAddress == address(0)) revert Params_ContractNotRegistered();

        delete _contracts[name_];
        _removeContractName(name_);
        _refreshDependents();

        emit ContractDeregistered(name_);
    }

    // =========  VIEW FUNCTIONS ========= //

    /// @inheritdoc RGSTYv1
    /// @dev        This function will revert if:
    ///             - The contract is not registered
    function getContract(bytes5 name_) external view override returns (address) {
        address contractAddress = _contracts[name_];

        if (contractAddress == address(0)) revert Params_ContractNotRegistered();

        return contractAddress;
    }

    /// @inheritdoc RGSTYv1
    /// @dev        Note that the order of the names in the array is not guaranteed to be consistent.
    function getContractNames() external view override returns (bytes5[] memory) {
        return _contractNames;
    }

    // =========  INTERNAL FUNCTIONS ========= //

    /// @notice Updates the list of contract names if the name is not already present.
    ///
    /// @param  name_ The name of the contract
    function _updateContractNames(bytes5 name_) internal {
        bytes5[] memory contractNames = _contractNames;
        for (uint256 i; i < contractNames.length; ) {
            if (contractNames[i] == name_) return;
            unchecked {
                ++i;
            }
        }
        _contractNames.push(name_);
    }

    /// @notice Removes the name of a contract from the list of contract names.
    ///
    /// @param  name_ The name of the contract
    function _removeContractName(bytes5 name_) internal {
        uint256 length = _contractNames.length;
        for (uint256 i; i < length; ) {
            if (_contractNames[i] == name_) {
                // Swap the found element with the last element
                _contractNames[i] = _contractNames[length - 1];
                // Remove the last element
                _contractNames.pop();
                return;
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Refreshes the dependents of the module
    function _refreshDependents() internal {
        Keycode moduleKeycode = toKeycode(keycode);

        // Iterate over each dependent policy until the end of the array is reached
        uint256 dependentIndex;
        while (true) {
            try kernel.moduleDependents(moduleKeycode, dependentIndex) returns (Policy dependent) {
                dependent.configureDependencies();
                unchecked {
                    ++dependentIndex;
                }
            } catch {
                // If the call to the moduleDependents mapping reverts, then we have reached the end of the array
                break;
            }
        }
    }
}
