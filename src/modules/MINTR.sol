// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {OlympusERC20Token as OHM} from "src/external/OlympusERC20.sol";
import {Kernel, Module} from "src/Kernel.sol";

// Wrapper for minting and burning functions of OHM token
contract OlympusMinter is Module {
    // ######################## ~ CONSTANTS ~ ########################

    Kernel.Role public constant MINTER = Kernel.Role.wrap("MINTR_Minter");
    Kernel.Role public constant BURNER = Kernel.Role.wrap("MINTR_Burner");

    OHM public immutable ohm;

    // ######################## ~ KERNEL INTERFACE ~ ########################

    constructor(Kernel kernel_, address ohm_) Module(kernel_) {
        ohm = OHM(ohm_);
    }

    function KEYCODE() public pure override returns (Kernel.Keycode) {
        return Kernel.Keycode.wrap("MINTR");
    }

    function ROLES() public pure override returns (Kernel.Role[] memory roles) {
        roles = new Kernel.Role[](2);
        roles[0] = MINTER;
        roles[1] = BURNER;
    }

    // ######################## ~ INTERFACE ~ ########################

    function mintOhm(address to_, uint256 amount_) public onlyRole(MINTER) {
        ohm.mint(to_, amount_);
    }

    function burnOhm(address from_, uint256 amount_) public onlyRole(BURNER) {
        ohm.burnFrom(from_, amount_);
    }
}
