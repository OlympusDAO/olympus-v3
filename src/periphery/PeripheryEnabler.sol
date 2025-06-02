// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.15;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

/// @title PeripheryEnabler
/// @notice Abstract contract that implements the `IEnabler` interface
/// @dev    This contract is designed to be used as a base contract for periphery contracts that need to be enabled and disabled.
///         It additionally is not opionated about whether a caller is permitted to enable/disable the contract, and delegates it to a virtual function.
///         It is a periphery contract, as it does not require any privileged access to the Olympus protocol.
abstract contract PeripheryEnabler is IEnabler {
    // ========= STATE VARIABLES ========= //

    /// @notice Whether the contract is enabled
    bool public isEnabled;

    // ========= MODIFIERS ========= //

    modifier onlyEnabled() {
        if (!isEnabled) revert NotEnabled();
        _;
    }

    modifier onlyDisabled() {
        if (isEnabled) revert NotDisabled();
        _;
    }

    // ========= OWNERSHIP ========= //

    /// @notice Implementation-specific validation of ownership
    /// @dev    Implementing contracts should override this function to perform the appropriate validation and revert if the caller is not permitted to enable/disable the contract.
    function _onlyOwner() internal view virtual;

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
    function _enable(bytes calldata enableData_) internal virtual;

    /// @inheritdoc IEnabler
    function enable(bytes calldata enableData_) external onlyDisabled {
        // Validate that the caller is permissioned
        _onlyOwner();

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
    function _disable(bytes calldata disableData_) internal virtual;

    /// @inheritdoc IEnabler
    function disable(bytes calldata disableData_) external onlyEnabled {
        // Validate that the caller is permissioned
        _onlyOwner();

        // Call the implementation-specific disable function
        _disable(disableData_);

        // Change the state
        isEnabled = false;

        // Emit the disabled event
        emit Disabled();
    }

    // ========= ERC165 ========= //

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IEnabler).interfaceId;
    }
}
