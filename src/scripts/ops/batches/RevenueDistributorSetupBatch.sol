// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Contracts
import {console2} from "@forge-std-1.16.2/console2.sol";
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Prepare Kernel membership; initial configuration and enablement require governance.
contract RevenueDistributorSetupBatch is BatchScriptV2 {
    // Fixed deployment entries are checked and simulated sequentially.
    // forge-lint: disable-next-item(calls-loop)
    function setupKernel(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        Kernel kernel = Kernel(_envAddressNotZero("olympus.Kernel"));
        string[3] memory names = [
            "RevenueDistributor",
            "RevenueDistributorConfigTimelock",
            "RevenueDistributorTask"
        ];
        for (uint256 i; i < names.length; ++i) {
            address target = _envAddressNotZero(string.concat("olympus.policies.", names[i]));

            if (kernel.isPolicyActive(Policy(target))) {
                console2.log("Policy already active", target);
            } else {
                addToBatch(
                    address(kernel),
                    abi.encodeCall(Kernel.executeAction, (Actions.ActivatePolicy, target))
                );
            }
        }
        proposeBatch();
    }
}
