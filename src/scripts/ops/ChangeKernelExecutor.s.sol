// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {console2} from "forge-std/console2.sol";

contract ChangeKernelExecutorScript is WithEnvironment {
    error ChangeKernelExecutor_UnexpectedExecutor(address actual_, address expected_);

    function run() external {
        changeExecutorToDaoMs(ChainUtils._getChainName(block.chainid));
    }

    function changeExecutorToDaoMs(string memory chain_) public {
        _loadEnv(chain_);

        Kernel kernel = Kernel(_envAddressNotZero("olympus.Kernel"));
        console2.log("Kernel:", address(kernel));

        address daoMs = _envAddressNotZero("olympus.multisig.dao");
        console2.log("Target executor:", daoMs);

        address currentExecutor = kernel.executor();
        console2.log("Current executor:", currentExecutor);

        if (currentExecutor != daoMs) {
            vm.startBroadcast();
            kernel.executeAction(Actions.ChangeExecutor, daoMs);
            vm.stopBroadcast();
        } else {
            console2.log("Kernel executor already set to DAO MS");
        }

        address updatedExecutor = kernel.executor();
        if (updatedExecutor != daoMs) {
            revert ChangeKernelExecutor_UnexpectedExecutor(updatedExecutor, daoMs);
        }

        console2.log("Kernel executor validated:", updatedExecutor);
    }
}
