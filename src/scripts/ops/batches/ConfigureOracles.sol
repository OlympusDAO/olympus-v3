// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

// Interfaces
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {Kernel, Actions, Policy, toKeycode} from "src/Kernel.sol";

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
        address erc7726Factory = _envAddressNotZero("olympus.policies.ERC7726OracleFactory");

        console2.log("ChainlinkOracleFactory:", chainlinkFactory);
        console2.log("MorphoOracleFactory:", morphoFactory);
        console2.log("ERC7726OracleFactory:", erc7726Factory);

        // Activate each factory/policy
        _activateFactory(kernel, chainlinkFactory, "ChainlinkOracleFactory");
        _activateFactory(kernel, morphoFactory, "MorphoOracleFactory");
        _activateFactory(kernel, erc7726Factory, "ERC7726OracleFactory");

        console2.log("\n=== Oracle Policies Configuration Batch Prepared ===");
        console2.log("\nPost-Batch Steps:");
        console2.log("1. Enable contracts through OCG (On-Chain Governance)");
        console2.log("2. Grant necessary role(s) to oracle factories");
        console2.log("3. Deploy specific oracles for token pairs using the factories");

        // Set post-batch validation selector
        _setPostBatchValidateSelector(this.validateOraclesConfigured.selector);

        proposeBatch();
    }

    // ========== POST-BATCH VALIDATION ========== //

    /// @notice Validates that oracle policies are properly activated
    /// @dev    Checks that all factories are activated and can deploy oracles
    function validateOraclesConfigured() external view {
        console2.log("\n=== Validating Oracle Configuration ===");

        address kernel = _envAddressNotZero("olympus.Kernel");
        address chainlinkFactory = _envAddressNotZero("olympus.policies.ChainlinkOracleFactory");
        address morphoFactory = _envAddressNotZero("olympus.policies.MorphoOracleFactory");
        address erc7726Factory = _envAddressNotZero("olympus.policies.ERC7726OracleFactory");

        // Verify policies are activated in Kernel and resolved dependencies from the same Kernel
        _verifyFactoryKernel(kernel, chainlinkFactory, "ChainlinkOracleFactory");
        _verifyPolicyActivated(kernel, chainlinkFactory, "ChainlinkOracleFactory");
        _verifyFactoryPriceModule(kernel, chainlinkFactory, "ChainlinkOracleFactory", false);

        _verifyFactoryKernel(kernel, morphoFactory, "MorphoOracleFactory");
        _verifyPolicyActivated(kernel, morphoFactory, "MorphoOracleFactory");
        _verifyFactoryPriceModule(kernel, morphoFactory, "MorphoOracleFactory", false);

        _verifyFactoryKernel(kernel, erc7726Factory, "ERC7726OracleFactory");
        _verifyPolicyActivated(kernel, erc7726Factory, "ERC7726OracleFactory");
        _verifyFactoryPriceModule(kernel, erc7726Factory, "ERC7726OracleFactory", true);

        console2.log("\n=== Oracle Configuration Validated ===");
    }

    /// @notice Verify a policy is activated in the Kernel
    /// @param kernel_ Address of the Kernel
    /// @param policy_ Address of the policy to check
    /// @param name_ Name of the policy for logging
    function _verifyPolicyActivated(
        address kernel_,
        address policy_,
        string memory name_
    ) internal view {
        bool active = Kernel(kernel_).isPolicyActive(Policy(policy_));
        require(active, string.concat(name_, " not activated"));
        console2.log(name_, "activated");
    }

    /// @notice Verify a factory policy was deployed against the target Kernel
    /// @param kernel_ Address of the Kernel
    /// @param factory_ Address of the factory policy
    /// @param name_ Name of the factory for logging
    function _verifyFactoryKernel(
        address kernel_,
        address factory_,
        string memory name_
    ) internal view {
        require(factory_.code.length != 0, string.concat(name_, " not deployed"));
        require(
            address(Policy(factory_).kernel()) == kernel_,
            string.concat(name_, " wrong kernel")
        );
        console2.log(name_, "kernel verified");
    }

    /// @notice Verify a factory resolved PRICE from the target Kernel after activation
    /// @param kernel_ Address of the Kernel
    /// @param factory_ Address of the factory policy
    /// @param name_ Name of the factory for logging
    /// @param isERC7726_ Whether the factory uses the ERC7726 factory interface
    function _verifyFactoryPriceModule(
        address kernel_,
        address factory_,
        string memory name_,
        bool isERC7726_
    ) internal view {
        address expectedPrice = address(Kernel(kernel_).getModuleForKeycode(toKeycode("PRICE")));
        address factoryPrice = isERC7726_
            ? IERC7726OracleFactory(factory_).getPriceModule()
            : IOracleFactory(factory_).getPriceModule();

        require(factoryPrice == expectedPrice, string.concat(name_, " wrong PRICE module"));
        console2.log(name_, "PRICE module verified");
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Activate a single oracle factory policy
    /// @param kernel_ Address of the Kernel
    /// @param factory_ Address of the factory/policy to activate
    /// @param name_ Name of the factory for logging
    function _activateFactory(address kernel_, address factory_, string memory name_) internal {
        _verifyFactoryKernel(kernel_, factory_, name_);

        if (Kernel(kernel_).isPolicyActive(Policy(factory_))) {
            console2.log(name_, "already active, skipping activation");
            return;
        }

        console2.log("\nActivating", name_);
        addToBatch(
            kernel_,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, factory_)
        );
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
