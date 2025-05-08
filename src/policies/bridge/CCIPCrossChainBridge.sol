// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

contract CCIPCrossChainBridge is Policy, PolicyEnabler {
    // Tasks
    // [X] Add PolicyEnabler
    // [ ] Add function for user to send OHM
    // [ ] Import TokenPool abstract
    // [ ] Implement minting of OHM
    // [ ] Implement burning of OHM
    // [ ] Implement support for rate-limiting
    // [ ] Implement tracking of bridged supply from mainnet
    // [ ] _ccipReceive: validate source chain and sender against allowlist
    // [ ] _ccipSend: validate destination chain against allowlist
    // [ ] _ccipReceive: validate router address
    // [ ] immutable extraArgs
    // [ ] failure handling

    // =========  STATE VARIABLES ========= //

    /// @notice Bophades module for minting and burning OHM
    MINTRv1 public MINTR;

    /// @notice OHM token
    IERC20 public ohm;

    // =========  CONSTRUCTOR ========= //

    constructor(address kernel_, address ccipRouter_) Policy(Kernel(kernel_)) {
        // TODO set router
        // Disabled by default
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("ROLES");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1]);
        if (MINTR_MAJOR != 1 || ROLES_MAJOR != 1) revert Policy_WrongModuleVersion(expected);

        // Cache the OHM address
        ohm = IERC20(address(MINTR.ohm()));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode MINTR_KEYCODE = MINTR.KEYCODE();

        permissions = new Permissions[](4);
        permissions[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        permissions[1] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        permissions[2] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        permissions[3] = Permissions(MINTR_KEYCODE, MINTR.decreaseMintApproval.selector);
    }

    /// @notice Returns the version of the policy
    ///
    /// @return major The major version of the policy
    /// @return minor The minor version of the policy
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }
}
