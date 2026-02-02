// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

// Interfaces
import {Kernel, Actions} from "src/Kernel.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

/// @notice Configures oracle policies
/// @dev    Deployment happens separately - this script activates all oracle factories/policies
///
///         Post-Batch Steps:
///         1. Enable contracts through OCG (On-Chain Governance)
///         2. Grant necessary role(s) to oracle factories
///         3. Deploy specific oracles for token pairs using the factories
contract ConfigureOracles is BatchScriptV2 {
    // ========== CONFIGURATION FUNCTIONS ========== //

    /// @notice Configure all oracle policies
    /// @param useDaoMS_ Whether to use the DAO multisig
    /// @param signOnly_ Whether to only sign the batch
    function configureOracles(
        bool useDaoMS_,
        bool signOnly_,
        string calldata,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, "", ledgerDerivationPath, signature_) {
        console2.log("=== Configuring Oracle Policies ===");

        // Load kernel
        address kernel = _envAddressNotZero("olympus.Kernel");
        console2.log("Kernel:", kernel);

        // Load factory addresses from env
        address chainlinkFactory = _envAddressNotZero("olympus.policies.ChainlinkOracleFactory");
        address morphoFactory = _envAddressNotZero("olympus.policies.MorphoOracleFactory");
        address erc7726Oracle = _envAddressNotZero("olympus.policies.ERC7726Oracle");

        console2.log("ChainlinkOracleFactory:", chainlinkFactory);
        console2.log("MorphoOracleFactory:", morphoFactory);
        console2.log("ERC7726Oracle:", erc7726Oracle);

        // Activate each factory/policy
        _activateFactory(kernel, chainlinkFactory, "ChainlinkOracleFactory");
        _activateFactory(kernel, morphoFactory, "MorphoOracleFactory");
        _activateFactory(kernel, erc7726Oracle, "ERC7726Oracle");

        console2.log("\n=== Oracle Policies Configuration Batch Prepared ===");
        console2.log("\nPost-Batch Steps:");
        console2.log("1. Enable contracts through OCG (On-Chain Governance)");
        console2.log("2. Grant necessary role(s) to oracle factories");
        console2.log("3. Deploy specific oracles for token pairs using the factories");

        proposeBatch();
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Activate a single oracle factory policy
    /// @param kernel_ Address of the Kernel
    /// @param factory_ Address of the factory/policy to activate
    /// @param name_ Name of the factory for logging
    function _activateFactory(address kernel_, address factory_, string memory name_) internal {
        console2.log("\nActivating", name_);

        addToBatch(
            kernel_,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, factory_)
        );
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
