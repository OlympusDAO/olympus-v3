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
    // Additionally, the SubKeycode must only contain A-Z, _, or space characters
    bytes5 unwrappedParent = Keycode.unwrap(parentKeycode_);
    bytes20 unwrappedSub = SubKeycode.unwrap(subKeycode_);
    for (uint256 i; i < 20; ) {
        bytes1 char = unwrappedSub[i];
        if (i < 5) {
            if (unwrappedParent[i] != char) revert InvalidSubKeycode(subKeycode_);
        }
        if (i == 5) {
            // 6th character must be a period
            if (char != 0x2e) revert InvalidSubKeycode(subKeycode_); // .
        } else {
            if ((char < 0x41 || char > 0x5A) && char != 0x5f && char != 0x00)
                revert InvalidSubKeycode(subKeycode_); // A-Z, _, or blank
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

    function installSubmodule(Submodule newSubmodule_) external permissioned {
        // Validate new submodule is a contract, has correct parent, and has valid SubKeycode
        ensureContract(address(newSubmodule_));
        Keycode keycode = KEYCODE();
        if (fromKeycode(newSubmodule_.PARENT()) != fromKeycode(keycode))
            revert Module_InvalidSubmodule();
        ensureValidSubKeycode(newSubmodule_.SUBKEYCODE(), keycode);

        // Check that submodule is not already installed
        SubKeycode subKeycode = newSubmodule_.SUBKEYCODE();

        if (address(getSubmoduleForKeycode[subKeycode]) != address(0))
            revert Module_SubmoduleAlreadyInstalled(subKeycode);

        // Store submodule in kernel
        getSubmoduleForKeycode[subKeycode] = newSubmodule_;
        // getKeycodeForSubmodule[newSubmodule_] = subKeycode;
        submodules.push(subKeycode);

        // Initialize the submodule
        newSubmodule_.INIT();
    }

    function upgradeSubmodule(Submodule newSubmodule_) external permissioned {
        // Validate new submodule is a contract, has correct parent, and has valid SubKeycode
        ensureContract(address(newSubmodule_));
        Keycode keycode = KEYCODE();
        if (fromKeycode(newSubmodule_.PARENT()) != fromKeycode(keycode))
            revert Module_InvalidSubmodule();
        ensureValidSubKeycode(newSubmodule_.SUBKEYCODE(), keycode);

        // Check that submodule is already installed
        SubKeycode subKeycode = newSubmodule_.SUBKEYCODE();
        Submodule oldSubmodule = getSubmoduleForKeycode[subKeycode];

        if (oldSubmodule == Submodule(address(0)) || oldSubmodule == newSubmodule_)
            revert Module_InvalidSubmoduleUpgrade(subKeycode);

        // Update submodule in module
        getSubmoduleForKeycode[subKeycode] = newSubmodule_;

        // Initialize the submodule
        newSubmodule_.INIT();
    }

    function execOnSubmodule(
        SubKeycode subKeycode_,
        bytes memory callData_
    ) external permissioned returns (bytes memory) {
        Submodule submodule = _getSubmoduleIfInstalled(subKeycode_);
        (bool success, bytes memory returnData) = address(submodule).call(callData_);
        if (!success) revert Module_SubmoduleExecutionReverted(returnData);
        return returnData;
    }

    function _submoduleIsInstalled(SubKeycode subKeycode_) internal view returns (bool) {
        Submodule submodule = getSubmoduleForKeycode[subKeycode_];
        return submodule != Submodule(address(0));
    }

    function _getSubmoduleIfInstalled(SubKeycode subKeycode_) internal view returns (Submodule) {
        Submodule submodule = getSubmoduleForKeycode[subKeycode_];
        if (submodule == Submodule(address(0))) revert Module_SubmoduleNotInstalled(subKeycode_);
        return submodule;
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