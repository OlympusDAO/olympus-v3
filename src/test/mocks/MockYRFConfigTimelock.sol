// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {Address} from "@openzeppelin-5.3.0/utils/Address.sol";

import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";

/// @notice Stand-in for the config timelock policy that YieldRepurchaseFacilityV2 pins as its
///         privileged configurator.
/// @dev The facility's constructor requires the pinned address to report the facility's own
///      kernel, so the stand-in is a bare policy: it declares no dependencies and requests no
///      module permissions, and it does not have to be activated in the kernel.
///
///      TODO: replace with the config timelock policy once it exists. The tests that route a
///      configuration call through `forward` then queue and execute it instead.
contract MockYRFConfigTimelock is Policy {
    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies()
        external
        pure
        override
        returns (Keycode[] memory dependencies)
    {
        return new Keycode[](0);
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        return new Permissions[](0);
    }

    /// @notice Calls `target_` with `data_` from this contract's address.
    /// @dev Lets a test reach a facility function that trusts this address, without pranking it.
    ///      A revert of the call is bubbled up with its original data.
    /// @param target_ The contract to call.
    /// @param data_ The calldata of the call.
    /// @return result The return data of the call.
    function forward(address target_, bytes calldata data_) external returns (bytes memory result) {
        return Address.functionCall(target_, data_);
    }
}
