// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "src/Kernel.sol";

//============================================================================================//
//                                        GLOBAL TYPES                                        //
//============================================================================================//

type SubKeycode is bytes20;

//============================================================================================//
//                                       UTIL FUNCTIONS                                       //
//============================================================================================//

error InvalidSubKeycode(SubKeycode subKeycode_);

// solhint-disable-next-line func-visibility
function toSubKeycode(bytes20 key_) pure returns (SubKeycode) {
    return SubKeycode.wrap(key_);
}

// solhint-disable-next-line func-visibility
function fromSubKeycode(SubKeycode key_) pure returns (bytes20) {
    return SubKeycode.unwrap(key_);
}

// solhint-disable-next-line func-visibility
function ensureValidSubKeycode(SubKeycode subKeycode_, Keycode parentKeycode_) pure {
    // The SubKeycode must have the parent Keycode as its first 5 bytes
    // The 6th character must be a period "." to separate the parent keycode from the remainder
    // The portion after the period must start with 3 non-blank characters
    // and only contain A-Z, 0-9, _, or blank characters.
    bytes5 unwrappedParent = Keycode.unwrap(parentKeycode_);
    bytes20 unwrappedSub = SubKeycode.unwrap(subKeycode_);
    for (uint256 i; i < 20; ) {
        bytes1 char = unwrappedSub[i];
        if (i < 5) {
            if (unwrappedParent[i] != char) revert InvalidSubKeycode(subKeycode_);
        } else if (i == 5) {
            // 6th character must be a period
            if (char != 0x2e) revert InvalidSubKeycode(subKeycode_); // .
        } else if (i < 9) {
            // Must have at least 3 non-blank characters after the period
            if ((char < 0x30 || char > 0x39) && (char < 0x41 || char > 0x5A) && char != 0x5f)
                revert InvalidSubKeycode(subKeycode_); // 0-9, A-Z, _
        } else {
            // Characters after the first 3 can be blank or 0-9, A-Z, _
            if (
                (char < 0x30 || char > 0x39) &&
                (char < 0x41 || char > 0x5A) &&
                char != 0x5f &&
                char != 0x00
            ) revert InvalidSubKeycode(subKeycode_); // 0-9, A-Z, _, or blank
        }

        unchecked {
            i++;
        }
    }
}

//============================================================================================//
//                                        COMPONENTS                                          //
//============================================================================================//

/// @notice Base level extension of the kernel. Modules act as independent state components to be
///         interacted with and mutated through policies.
/// @dev    Modules are installed and uninstalled via the executor.
abstract contract ModuleWithSubmodules is Module {
    // ========= ERRORS ========= //
    error Module_InvalidSubmodule();
    error Module_InvalidSubmoduleUpgrade(SubKeycode subKeycode_);
    error Module_SubmoduleAlreadyInstalled(SubKeycode subKeycode_);
    error Module_SubmoduleNotInstalled(SubKeycode subKeycode_);
    error Module_SubmoduleExecutionReverted(bytes error_);

    // ========= SUBMODULE MANAGEMENT ========= //

    /// @notice Array of all submodules currently installed.
    SubKeycode[] public submodules;

    /// @notice Mapping of SubKeycode to Submodule address.
    mapping(SubKeycode => Submodule) public getSubmoduleForKeycode;

    /// @notice Install a new submodule
    /// @dev    This function will revert if:
    /// @dev    - The new submodule is not a contract
    /// @dev    - The new submodule does not have the same keycode prefix as this module
    /// @dev    - The new submodule has the same keycode as an existing submodule
    /// @dev    - The caller is not permissioned
    ///
    /// @param newSubmodule_    The new submodule to install
    function installSubmodule(Submodule newSubmodule_) external permissioned {
        // Validate new submodule and get its subkeycode
        SubKeycode subKeycode = _validateSubmodule(newSubmodule_);

        // Check that a submodule with this keycode is not already installed
        // If this reverts, then the new submodule should be installed via upgradeSubmodule
        if (address(getSubmoduleForKeycode[subKeycode]) != address(0))
            revert Module_SubmoduleAlreadyInstalled(subKeycode);

        // Store submodule in module
        getSubmoduleForKeycode[subKeycode] = newSubmodule_;
        submodules.push(subKeycode);

        // Initialize the submodule
        newSubmodule_.INIT();
    }

    /// @notice Upgrades an existing submodule
    /// @dev    This function will revert if:
    /// @dev    - The new submodule is not a contract
    /// @dev    - The new submodule does not have the same keycode prefix as this module
    /// @dev    - The new submodule is the zero address
    /// @dev    - The new submodule has the same address as an existing submodule
    /// @dev    - The caller is not permissioned
    ///
    /// @param newSubmodule_    The new submodule to install
    function upgradeSubmodule(Submodule newSubmodule_) external permissioned {
        // Validate new submodule and get its subkeycode
        SubKeycode subKeycode = _validateSubmodule(newSubmodule_);

        // Get the existing submodule, ensure that it's not zero and not the same as the new submodule
        // If this reverts due to no submodule being installed, then the new submodule should be installed via installSubmodule
        Submodule oldSubmodule = getSubmoduleForKeycode[subKeycode];
        if (oldSubmodule == Submodule(address(0)) || oldSubmodule == newSubmodule_)
            revert Module_InvalidSubmoduleUpgrade(subKeycode);

        // Update submodule in module
        getSubmoduleForKeycode[subKeycode] = newSubmodule_;

        // Initialize the submodule
        newSubmodule_.INIT();
    }

    /// @notice Perform an action on a submodule
    /// @dev    There is no need to check if the `subKeycode_` belongs to this module,
    /// @dev    because `installSubmodule()` and `upgradeSubmodule()` (via `_validateSubmodule()`)
    /// @dev    ensure that the submodule has the same keycode as this module.
    ///
    /// @dev    This function will revert if:
    /// @dev    - The submodule is not installed
    /// @dev    - The caller is not permissioned
    /// @dev    - The call to the submodule reverts
    ///
    /// @param subKeycode_    The SubKeycode of the submodule to call
    /// @param callData_      The calldata to send to the submodule
    /// @return returnData_   The return data from the submodule call
    function execOnSubmodule(
        SubKeycode subKeycode_,
        bytes memory callData_
    ) external permissioned returns (bytes memory) {
        Submodule submodule = _getSubmoduleIfInstalled(subKeycode_);
        (bool success, bytes memory returnData) = address(submodule).call(callData_);
        if (!success) revert Module_SubmoduleExecutionReverted(returnData);
        return returnData;
    }

    function getSubmodules() external view returns (SubKeycode[] memory) {
        return submodules;
    }

    function _submoduleIsInstalled(SubKeycode subKeycode_) internal view returns (bool) {
        Submodule submodule = getSubmoduleForKeycode[subKeycode_];
        return address(submodule) != address(0);
    }

    function _getSubmoduleIfInstalled(SubKeycode subKeycode_) internal view returns (Submodule) {
        Submodule submodule = getSubmoduleForKeycode[subKeycode_];
        if (address(submodule) == address(0)) revert Module_SubmoduleNotInstalled(subKeycode_);
        return submodule;
    }

    function _validateSubmodule(Submodule newSubmodule_) internal view returns (SubKeycode) {
        // Validate new submodule is a contract, has correct parent, and has valid SubKeycode
        ensureContract(address(newSubmodule_));
        Keycode keycode = KEYCODE();
        if (fromKeycode(newSubmodule_.PARENT()) != fromKeycode(keycode))
            revert Module_InvalidSubmodule();
        SubKeycode subKeycode = newSubmodule_.SUBKEYCODE();
        ensureValidSubKeycode(subKeycode, keycode);

        return subKeycode;
    }
}

/// @notice Submodules are isolated components of a module that can be upgraded independently.
/// @dev    Submodules are installed and uninstalled directly on the module.
/// @dev    If a module is going to hold state that should be persisted across upgrades, then a submodule pattern may be a good fit.
abstract contract Submodule {
    error Submodule_OnlyParent(address caller_);
    error Submodule_ModuleDoesNotExist(Keycode keycode_);
    error Submodule_InvalidParent();

    /// @notice The parent module for this submodule.
    Module public parent;

    constructor(Module parent_) {
        if (fromKeycode(parent_.KEYCODE()) != fromKeycode(PARENT()))
            revert Submodule_InvalidParent();
        parent = parent_;
    }

    /// @notice Modifier to restrict functions to be called only by parent module.
    modifier onlyParent() {
        if (msg.sender != address(parent)) revert Submodule_OnlyParent(msg.sender);
        _;
    }

    /// @notice 5 byte identifier for the parent module.
    function PARENT() public pure virtual returns (Keycode) {}

    /// @notice 20 byte identifier for the submodule. First 5 bytes must match PARENT().
    function SUBKEYCODE() public pure virtual returns (SubKeycode) {}

    /// @notice Returns which semantic version of a submodule is being implemented.
    /// @return major - Major version upgrade indicates breaking change to the interface.
    /// @dev    A major (breaking) change may require the parent module to be updated as well.
    /// @return minor - Minor version change retains backward-compatible interface.
    function VERSION() external pure virtual returns (uint8 major, uint8 minor) {}

    /// @notice Initialization function for the submodule
    /// @dev    This function is called when the submodule is installed or upgraded by the module.
    /// @dev    MUST BE GATED BY onlyParent. Used to encompass any initialization or upgrade logic.
    function INIT() external virtual onlyParent {}
}
