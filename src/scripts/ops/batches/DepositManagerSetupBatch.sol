// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Contracts
import {console2} from "@forge-std-1.16.2/console2.sol";
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Activate shared DepositManager v1.1; OCG configures custody assets and enables it.
contract DepositManagerSetupBatch is BatchScriptV2 {
    function setupKernel(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        Kernel kernel = Kernel(_envAddressNotZero("olympus.Kernel"));
        address manager = _envAddressNotZero("olympus.policies.DepositManager");

        if (kernel.isPolicyActive(Policy(manager))) {
            console2.log("Policy already active", manager);
        } else {
            addToBatch(
                address(kernel),
                abi.encodeCall(Kernel.executeAction, (Actions.ActivatePolicy, manager))
            );
        }
        proposeBatch();
    }
}
