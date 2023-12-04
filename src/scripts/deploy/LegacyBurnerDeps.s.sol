// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Script, console2} from "forge-std/Script.sol";
import {MockLegacyInverseBondDepo} from "test/mocks/MockLegacyInverseBondDepo.sol";

contract LegacyBurnerDepsDeploy is Script {
    address public authority = 0x4A8c9502A34962a2C6d73c5D181dAaeF3dcDc88D;
    address public ohm = 0x0595328847AF962F951a4f8F8eE9A3Bf261e4f6b;
    
    MockLegacyInverseBondDepo public inverseBondDepo;

    function deploy() external {
        vm.broadcast();
        inverseBondDepo = new MockLegacyInverseBondDepo(authority, ohm);
        console2.log("MockLegacyInverseBondDepo deployed at:", address(inverseBondDepo));
    }
}