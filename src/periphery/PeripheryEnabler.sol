// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.15;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {Owned} from "solmate/auth/Owned.sol";

/// @title PeripheryEnabler
/// @notice Abstract contract that implements the `IEnabler` interface
/// @dev    This contract is designed to be used as a base contract for periphery contracts that need to be enabled and disabled
///         It is a periphery contract, as it does not require any privileged access to the Olympus protocol.
abstract contract PeripheryEnabler is Owned, IEnabler {
    // ========= STATE VARIABLES ========= //

    /// @notice Whether the contract is enabled
    bool public isEnabled;

    // ========= CONSTRUCTOR ========= //

    constructor(address owner_) Owned(owner_) {}

    // ========= MODIFIERS ========= //

    modifier onlyEnabled() {
        if (!isEnabled) revert NotEnabled();
        _;
    }

    modifier onlyDisabled() {
        if (isEnabled) revert NotDisabled();
        _;
    }

    // ========= ENABLER FUNCTIONS ========= //

    /// @notice Implementation-specific enable function
    /// @dev    This function is called by the `enable()` function
    ///
    ///         The implementing contract can override this function and perform the following:
    ///         1. Validate any parameters (if needed) or revert
    ///         2. Validate state (if needed) or revert
    ///         3. Perform any necessary actions, apart from modifying the `isEnabled` state variable
    ///
    /// @param  enableData_ Custom data that can be used by the implementation. The format of this data is
    ///         left to the discretion of the implementation.
    function _enable(bytes calldata enableData_) internal virtual {}

    /// @inheritdoc IEnabler
    function enable(bytes calldata enableData_) external onlyOwner onlyDisabled {
        // Call the implementation-specific enable function
        _enable(enableData_);

        // Change the state
        isEnabled = true;

        // Emit the enabled event
        emit Enabled();
    }

    /// @notice Implementation-specific disable function
    /// @dev    This function is called by the `disable()` function
    ///
    ///         The implementing contract can override this function and perform the following:
    ///         1. Validate any parameters (if needed) or revert
    ///         2. Validate state (if needed) or revert
    ///         3. Perform any necessary actions, apart from modifying the `isEnabled` state variable
    ///
    /// @param  disableData_ Custom data that can be used by the implementation. The format of this data is
    ///         left to the discretion of the implementation.
    function _disable(bytes calldata disableData_) internal virtual {}

    /// @inheritdoc IEnabler
    function disable(bytes calldata disableData_) external onlyOwner onlyEnabled {
        // Call the implementation-specific disable function
        _disable(disableData_);

        // Change the state
        isEnabled = false;

        // Emit the disabled event
        emit Disabled();
    }
}
