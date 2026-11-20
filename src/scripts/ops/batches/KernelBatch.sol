// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Libraries
import {stdJson} from "@forge-std-1.16.2/StdJson.sol";

// Contracts
import {console2} from "@forge-std-1.16.2/console2.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Kernel membership operations on ordered env.json keys supplied in the args file.
/// @dev The selected owner must be the Kernel executor. Kernel guards and batch simulation apply.
contract KernelBatch is BatchScriptV2 {
    using stdJson for string;

    /// @notice Install new module keycodes in the supplied order.
    function installModules(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _queueActions("installModules", Actions.InstallModule);
        proposeBatch();
    }

    /// @notice Replace installed modules with the supplied implementations.
    function upgradeModules(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _queueActions("upgradeModules", Actions.UpgradeModule);
        proposeBatch();
    }

    /// @notice Activate policies and grant their requested module permissions.
    function activatePolicies(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _queueActions("activatePolicies", Actions.ActivatePolicy);
        proposeBatch();
    }

    /// @notice Remove policies from Kernel membership and revoke their module permissions.
    /// @dev The Kernel has no module-removal action; module replacement uses upgradeModules.
    function deactivatePolicies(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _queueActions("deactivatePolicies", Actions.DeactivatePolicy);
        proposeBatch();
    }

    // Resolve and encode every reviewed key in order; the standard batch simulator executes the calls.
    // forge-lint: disable-next-item(calls-loop)
    function _queueActions(string memory functionName_, Actions action_) internal {
        address kernel = _envAddressNotZero("olympus.Kernel");
        string[] memory keys = _argsFile.readStringArray(
            string.concat(".functions[?(@.name == '", functionName_, "')].args.targets")
        );
        console2.log(string.concat("KernelBatch: ", functionName_));
        console2.log("Kernel", kernel);
        for (uint256 i; i < keys.length; ++i) {
            address target = _envAddressNotZero(keys[i]);
            console2.log(keys[i], target);
            addToBatch(kernel, abi.encodeCall(Kernel.executeAction, (action_, target)));
        }
    }
}
