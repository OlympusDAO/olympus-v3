// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

/// @notice Enables a periphery contract
contract PeripheryEnable is BatchScriptV2 {
    function enable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        // Grab the contract key from the args file
        string memory contractKey = _readBatchArgString("PeripheryEnable", "contract");

        // Get the contract address from the environment file
        address contractAddress = _envAddressNotZero(contractKey);

        console2.log("Enabling contract");
        addToBatch(
            contractAddress,
            abi.encodeWithSelector(IEnabler.enable.selector, abi.encode(""))
        );

        console2.log("Periphery enable batch prepared");
        proposeBatch();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
