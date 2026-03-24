// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

// External
import {console2} from "@forge-std-1.9.6/console2.sol";

/// @notice Sets the mint cap on ConvertibleOHMTeller
/// @dev    This script calls setMintCap() on the ConvertibleOHMTeller policy
///         to adjust the maximum amount of OHM that can be minted for convertible tokens.
contract ConvertibleOHMTellerMintCap is BatchScriptV2 {
    /// @notice Set the mint cap on ConvertibleOHMTeller
    /// @dev    Requires args file with:
    ///         - mintCap: uint256 the target mint cap in OHM units (9 decimals)
    function setMintCap(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        // Read addresses from env.json
        address convertibleOHMTeller = _envAddressNotZero("olympus.policies.ConvertibleOHMTeller");

        // Read mint cap from args file
        uint256 mintCap = _readBatchArgUint256("setMintCap", "mintCap");
        require(mintCap > 0, "mintCap must be greater than zero -- update args file");

        console2.log("=== Setting ConvertibleOHMTeller Mint Cap ===");
        console2.log("ConvertibleOHMTeller:", convertibleOHMTeller);
        console2.log("Mint Cap:", mintCap);

        // Set the mint cap
        console2.log("1. Setting mint cap");
        addToBatch(convertibleOHMTeller, abi.encodeWithSignature("setMintCap(uint256)", mintCap));

        // Propose/execute the batch
        proposeBatch();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
