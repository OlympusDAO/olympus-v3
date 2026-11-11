// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {stdJson} from "@forge-std-1.16.2/StdJson.sol";

// Contracts
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Generic lifecycle calls, executed in the operator-supplied target order.
contract EnablerBatch is BatchScriptV2 {
    using stdJson for string;

    /// @notice Initial enablement; each target enforces its administrator authority and payload.
    // Encode the reviewed target list; the standard batch simulator executes every call.
    // forge-lint: disable-next-item(calls-loop)
    function enable(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        address[] memory targets = _argsFile.readAddressArray(
            ".functions[?(@.name == 'enable')].args.targets"
        );
        bytes[] memory data = _argsFile.readBytesArray(
            ".functions[?(@.name == 'enable')].args.data"
        );
        assert(targets.length == data.length);
        for (uint256 i; i < targets.length; ++i)
            addToBatch(targets[i], abi.encodeCall(IEnabler.enable, (data[i])));
        proposeBatch();
    }

    /// @notice Emergency disablement with one payload per target, in the supplied order.
    // Encode the reviewed target list; the standard batch simulator executes every call.
    // forge-lint: disable-next-item(calls-loop)
    function disable(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUpWithEmergencyMS(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        address[] memory targets = _argsFile.readAddressArray(
            ".functions[?(@.name == 'disable')].args.targets"
        );
        bytes[] memory data = _argsFile.readBytesArray(
            ".functions[?(@.name == 'disable')].args.data"
        );
        assert(targets.length == data.length);
        for (uint256 i; i < targets.length; ++i)
            addToBatch(targets[i], abi.encodeCall(IEnabler.disable, (data[i])));
        proposeBatch();
    }

    /// @notice Re-enable initialized targets; their own role and grace-window checks apply.
    // Encode the reviewed target list; the standard batch simulator executes every call.
    // forge-lint: disable-next-item(calls-loop)
    function reEnable(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        address[] memory targets = _argsFile.readAddressArray(
            ".functions[?(@.name == 'reEnable')].args.targets"
        );
        for (uint256 i; i < targets.length; ++i)
            addToBatch(targets[i], abi.encodeCall(IReEnabler.reEnable, ()));
        proposeBatch();
    }
}
