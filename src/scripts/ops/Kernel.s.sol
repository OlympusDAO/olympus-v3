// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {Kernel, Actions} from "src/Kernel.sol";
import {console2} from "forge-std/console2.sol";

contract KernelScript is WithEnvironment {
    function activatePolicy(string calldata chain_, address policy_) external {
        _loadEnv(chain_);

        console2.log("Activating policy", policy_);
        Kernel(_envAddressNotZero("olympus.Kernel")).executeAction(Actions.ActivatePolicy, policy_);
        console2.log("Policy activated");
    }

    function installModule(string calldata chain_, address module_) external {
        _loadEnv(chain_);
        console2.log("Installing module", module_);
        Kernel(_envAddressNotZero("olympus.Kernel")).executeAction(Actions.InstallModule, module_);
        console2.log("Module installed");
    }
}
