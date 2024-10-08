// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Kernel, Module, Keycode, toKeycode} from "src/Kernel.sol";
import {EXREGv1} from "./EXREG.v1.sol";

contract OlympusExternalRegistry is EXREGv1 {
    constructor(address kernel_) Module(Kernel(kernel_)) {}

    // =========  MODULE SETUP ========= //

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("EXREG");
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // =========  CONTRACT REGISTRATION ========= //

    /// @inheritdoc EXREGv1
    /// @dev        If the contract is already registered, the address will be updated.
    ///
    ///             This function will revert if:
    ///             - The caller is not permissioned
    ///             - The contract address is zero
    function registerContract(
        bytes5 name_,
        address contractAddress_
    ) external override permissioned {
        if (contractAddress_ == address(0)) revert Params_InvalidAddress();

        _contracts[name_] = contractAddress_;
        _updateContractNames(name_);

        emit ContractRegistered(name_, contractAddress_);
    }

    /// @inheritdoc EXREGv1
    /// @dev        This function will revert if:
    ///             - The caller is not permissioned
    ///             - The contract is not registered
    function deregisterContract(bytes5 name_) external override permissioned {
        address contractAddress = _contracts[name_];
        if (contractAddress == address(0)) revert Params_InvalidName();

        delete _contracts[name_];
        _removeContractName(name_);

        emit ContractDeregistered(name_);
    }

    // =========  VIEW FUNCTIONS ========= //

    /// @inheritdoc EXREGv1
    /// @dev        This function will revert if:
    ///             - The contract is not registered
    function getContract(bytes5 name_) external view override returns (address) {
        address contractAddress = _contracts[name_];

        if (contractAddress == address(0)) revert Params_InvalidName();

        return contractAddress;
    }

    /// @inheritdoc EXREGv1
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
}
