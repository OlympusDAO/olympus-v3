// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.30;

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusAuthority} from "src/external/OlympusAuthority.sol";
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

/// @title LZTestnetMockStack
/// @notice Deploys a minimal but real Default Framework stack on a testnet that does not yet
///         have one, so the LZ bridge gateway has a Kernel, a ROLES module, a MINTR module and
///         a mintable OHM token to plug into.
/// @dev Used ONLY on chains where env.json has no Kernel (e.g. arbitrum-sepolia). The stack is a
///      real deployment rather than a fake: the gateway mints and burns OHM through MINTR, which
///      must be the OlympusAuthority vault, so a fake token would not exercise the real path.
///
///      Every action below assumes it runs inside an active `vm.startBroadcast(deployer_)` /
///      `vm.stopBroadcast()` window so that:
///      - the freshly deployed Kernel records `deployer_` as its executor, and
///      - the freshly deployed RolesAdmin records `deployer_` as its admin.
///      The caller (the script) is responsible for opening that window.
library LZTestnetMockStack {
    /// @notice Addresses of the minimal stack deployed by {deploy}.
    struct Stack {
        address kernel;
        address ohm;
        address authority;
        address mintr;
        address roles;
        address rolesAdmin;
    }

    /// @notice Deploys the minimal Kernel stack and wires OHM minting through MINTR.
    /// @param deployer_ The address that must become the Kernel executor and RolesAdmin admin.
    ///        It is passed explicitly so the function can assert the broadcast context is correct.
    /// @return stack The deployed addresses.
    function deploy(address deployer_) internal returns (Stack memory stack) {
        // The deployer holds every OlympusAuthority role initially; the vault role moves to MINTR
        // below so that MINTR is the only minter of OHM.
        OlympusAuthority authority = new OlympusAuthority(
            deployer_,
            deployer_,
            deployer_,
            deployer_
        );
        OlympusERC20Token ohm = new OlympusERC20Token(address(authority));

        Kernel kernel = new Kernel();
        // solhint-disable-next-line custom-errors,gas-custom-errors
        require(
            kernel.executor() == deployer_,
            "LZTestnetMockStack: deployer is not Kernel executor"
        );

        OlympusMinter mintr = new OlympusMinter(kernel, address(ohm));
        OlympusRoles roles = new OlympusRoles(kernel);
        RolesAdmin rolesAdmin = new RolesAdmin(kernel);
        // solhint-disable-next-line custom-errors,gas-custom-errors
        require(
            rolesAdmin.admin() == deployer_,
            "LZTestnetMockStack: deployer is not RolesAdmin admin"
        );

        kernel.executeAction(Actions.InstallModule, address(mintr));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Hand the OHM mint authority to MINTR so the gateway can mint and burn bridged OHM.
        authority.pushVault(address(mintr), true);

        stack = Stack({
            kernel: address(kernel),
            ohm: address(ohm),
            authority: address(authority),
            mintr: address(mintr),
            roles: address(roles),
            rolesAdmin: address(rolesAdmin)
        });
    }
}
