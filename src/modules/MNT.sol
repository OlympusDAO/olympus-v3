// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {OlympusERC20Token as OHM} from "../external/OlympusERC20.sol";
import {Kernel, Module} from "../Kernel.sol";

// Wrapper for minting and burning functions of OHM token
contract OlympusMinter is Module {
    OHM immutable ohm;

    constructor(Kernel kernel_, OHM ohm_) Module(kernel_) {
        ohm = ohm_;
    }

    function KEYCODE() external pure override returns (bytes3) {
        return "MNT";
    }

    function mintOhm(address to_, uint256 amount_) public onlyPermitted {
        ohm.mint(to_, amount_);
    }

    function burnOhm(address from_, uint256 amount_) public onlyPermitted {
        ohm.burnFrom(from_, amount_);
    }
}
