// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-variable)
pragma solidity ^0.8.15;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Olympus Kernel, Modules, and Policies
import {Kernel, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";

// Role definitions
import {ADMIN_ROLE, ORACLE_MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Script
import {ProposalScript} from "./ProposalScript.sol";
import {console2} from "forge-std/console2.sol";

/// @notice OracleProposal: Enable Oracle Policies and Deploy OHM/USDS Oracles
/// @dev    This proposal enables the oracle policies and deploys initial OHM/USDS oracles
contract OracleProposal is GovernorBravoProposal {
    Kernel internal _kernel;
    uint48 internal constant DEFAULT_ORACLE_MAX_AGE = 1 hours;

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 14;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "OracleProposal";
    }

    // Provides a detailed description of the proposal.
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Enable Oracle Policies and OHM/USDS Oracles\n",
                "\n",
                "## Summary\n",
                "\n",
                "This proposal enables the oracle policies and deploys OHM/USDS oracles.\n",
                "\n",
                "## Oracle Policies\n",
                "\n",
                "This proposal enables three oracle factories:\n",
                "\n",
                "### 1. ERC7726OracleFactory\n\n",
                "- **Purpose**: Factory for deploying ERC7726-compatible oracle clones\n",
                "- **Function**: Creates ERC7726-compatible cached-price oracles from PRICE data\n",
                "- **Use Cases**: General lending integrations requiring ERC7726 quote interfaces\n",
                "\n",
                "### 2. ChainlinkOracleFactory\n\n",
                "- **Purpose**: Factory for deploying gas-efficient Chainlink oracle clones\n",
                "- **Function**: Creates ERC7726-compliant oracles using PRICE as the price source\n",
                "- **Use Cases**: Protocols requiring Chainlink-compatible oracles\n",
                "\n",
                "### 3. MorphoOracleFactory\n\n",
                "- **Purpose**: Factory for deploying Morpho-compatible oracle clones\n",
                "- **Function**: Creates oracles with Morpho-specific price scaling (36 decimals)\n",
                "- **Use Cases**: Morpho lending protocol integration\n",
                "\n",
                "## Actions\n",
                "\n",
                "This proposal will execute the following actions:\n",
                "\n",
                "1. **Grant `admin` role to Timelock** (if needed)\n",
                "2. **Grant `oracle_manager` role to DAO MS and Timelock** (if needed)\n",
                "3. **Enable ERC7726OracleFactory policy**\n",
                "4. **Enable ChainlinkOracleFactory policy**\n",
                "5. **Enable MorphoOracleFactory policy**\n",
                "6. **Deploy ERC7726 oracle** (via ERC7726OracleFactory)\n",
                "7. **Deploy OHM/USDS Chainlink oracle** (via ChainlinkOracleFactory)\n",
                "8. **Deploy OHM/USDS Morpho oracle** (via MorphoOracleFactory)\n",
                "\n",
                "## Technical Details\n",
                "\n",
                "### Oracle Factory Benefits\n",
                "\n",
                "- **Gas Efficiency**: Uses ClonesWithImmutableArgs for minimal deployment cost\n",
                "- **Security**: Oracles inherit access control from PRICE and factory policies\n",
                "- **Flexibility**: New oracles can be deployed by `oracle_manager` role holders without additional governance\n",
                "\n",
                "## Risks and Considerations\n",
                "\n",
                "- **Oracle Availability**: Enabled oracle policies depend on PRICE functioning correctly\n",
                "- **Price Feed Dependencies**: Oracle accuracy depends on underlying PRICE feeds\n",
                "\n",
                "## Resources\n",
                "\n",
                "- [Audit Report](TODO: add link)\n",
                "- [Implementation PR](TODO: add link)\n",
                "- [PRICE Documentation](https://github.com/OlympusDAO/olympus-v3/blob/78958ae5248210eac5cfb29077b9aae05be6707a/documentation/price.md)\n"
            );
    }

    // Cache addresses in _deploy
    function _deploy(Addresses addresses, address) internal override {
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        address timelock = addresses.getAddress("olympus-timelock");
        address daoMS = addresses.getAddress("olympus-multisig-dao");

        address erc7726Factory = addresses.getAddress("olympus-policy-erc7726-oracle-factory-1_0");
        address chainlinkFactory = addresses.getAddress(
            "olympus-policy-chainlink-oracle-factory-1_0"
        );
        address morphoFactory = addresses.getAddress("olympus-policy-morpho-oracle-factory-1_0");

        _verifyFactoryConfiguration(erc7726Factory, "ERC7726OracleFactory", true);
        _verifyFactoryConfiguration(chainlinkFactory, "ChainlinkOracleFactory", false);
        _verifyFactoryConfiguration(morphoFactory, "MorphoOracleFactory", false);

        address ohm = addresses.getAddress("olympus-legacy-ohm");
        address usds = addresses.getAddress("external-tokens-usds");

        // STEP 1: Grant admin role to Timelock, if needed
        // Required for enable() calls on PolicyEnabler contracts
        if (!roles.hasRole(timelock, ADMIN_ROLE)) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, ADMIN_ROLE, timelock),
                "Grant admin to Timelock"
            );
        } else {
            console2.log("Timelock already has the admin role");
        }

        // STEP 2: Grant ORACLE_MANAGER_ROLE to DAO MS and Timelock
        if (!roles.hasRole(daoMS, ORACLE_MANAGER_ROLE)) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, ORACLE_MANAGER_ROLE, daoMS),
                "Grant oracle_manager role to DAO MS"
            );
        } else {
            console2.log("DAO MS already has the oracle_manager role");
        }

        if (!roles.hasRole(timelock, ORACLE_MANAGER_ROLE)) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    ORACLE_MANAGER_ROLE,
                    timelock
                ),
                "Grant oracle_manager role to Timelock"
            );
        } else {
            console2.log("Timelock already has the oracle_manager role");
        }

        // STEP 3: Enable oracle policies
        _pushAction(
            erc7726Factory,
            abi.encodeWithSelector(IEnabler.enable.selector, ""),
            "Enable ERC7726OracleFactory"
        );

        _pushAction(
            chainlinkFactory,
            abi.encodeWithSelector(IEnabler.enable.selector, ""),
            "Enable ChainlinkOracleFactory"
        );

        _pushAction(
            morphoFactory,
            abi.encodeWithSelector(IEnabler.enable.selector, ""),
            "Enable MorphoOracleFactory"
        );

        // STEP 4: Deploy oracles
        _pushAction(
            erc7726Factory,
            abi.encodeWithSelector(
                IERC7726OracleFactory.createOracle.selector,
                DEFAULT_ORACLE_MAX_AGE,
                ""
            ),
            "Deploy ERC7726 oracle"
        );

        _pushAction(
            chainlinkFactory,
            abi.encodeWithSelector(
                IOracleFactory.createOracle.selector,
                ohm,
                usds,
                DEFAULT_ORACLE_MAX_AGE,
                ""
            ),
            "Deploy OHM/USDS Chainlink oracle"
        );

        _pushAction(
            morphoFactory,
            abi.encodeWithSelector(
                IOracleFactory.createOracle.selector,
                ohm,
                usds,
                DEFAULT_ORACLE_MAX_AGE,
                ""
            ),
            "Deploy OHM/USDS Morpho oracle"
        );
    }

    // Executes the proposal actions.
    function _run(Addresses addresses, address) internal override {
        _simulateActions(
            address(_kernel),
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );
    }

    // Validates the post-execution state.
    function _validate(Addresses addresses, address) internal view override {
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address timelock = addresses.getAddress("olympus-timelock");
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        address ohm = addresses.getAddress("olympus-legacy-ohm");
        address usds = addresses.getAddress("external-tokens-usds");

        address chainlinkFactory = addresses.getAddress(
            "olympus-policy-chainlink-oracle-factory-1_0"
        );
        address morphoFactory = addresses.getAddress("olympus-policy-morpho-oracle-factory-1_0");
        address erc7726Factory = addresses.getAddress("olympus-policy-erc7726-oracle-factory-1_0");

        _verifyFactoryConfiguration(erc7726Factory, "ERC7726OracleFactory", true);
        _verifyFactoryConfiguration(chainlinkFactory, "ChainlinkOracleFactory", false);
        _verifyFactoryConfiguration(morphoFactory, "MorphoOracleFactory", false);

        // Verify admin role granted to Timelock
        require(roles.hasRole(timelock, ADMIN_ROLE), "Timelock does not have admin role");

        // Verify oracle_manager role granted
        require(
            roles.hasRole(daoMS, ORACLE_MANAGER_ROLE),
            "DAO MS does not have oracle_manager role"
        );
        require(
            roles.hasRole(timelock, ORACLE_MANAGER_ROLE),
            "Timelock does not have oracle_manager role"
        );

        // Verify oracle policies are enabled
        require(IEnabler(erc7726Factory).isEnabled(), "ERC7726OracleFactory not enabled");
        require(IEnabler(chainlinkFactory).isEnabled(), "ChainlinkOracleFactory not enabled");
        require(IEnabler(morphoFactory).isEnabled(), "MorphoOracleFactory not enabled");

        // Verify oracles were deployed
        address erc7726Oracle = IERC7726OracleFactory(erc7726Factory).getOracle(
            DEFAULT_ORACLE_MAX_AGE
        );
        require(erc7726Oracle != address(0), "ERC7726 oracle not deployed");
        require(
            IERC7726OracleFactory(erc7726Factory).isOracleEnabled(erc7726Oracle),
            "ERC7726 oracle not enabled"
        );

        address chainlinkOracle = IOracleFactory(chainlinkFactory).getOracle(
            ohm,
            usds,
            DEFAULT_ORACLE_MAX_AGE
        );
        require(chainlinkOracle != address(0), "OHM/USDS Chainlink oracle not deployed");
        require(
            IOracleFactory(chainlinkFactory).isOracleEnabled(chainlinkOracle),
            "OHM/USDS Chainlink oracle not enabled"
        );

        address morphoOracle = IOracleFactory(morphoFactory).getOracle(
            ohm,
            usds,
            DEFAULT_ORACLE_MAX_AGE
        );
        require(morphoOracle != address(0), "OHM/USDS Morpho oracle not deployed");
        require(
            IOracleFactory(morphoFactory).isOracleEnabled(morphoOracle),
            "OHM/USDS Morpho oracle not enabled"
        );
    }

    function _verifyFactoryConfiguration(
        address factory_,
        string memory name_,
        bool isERC7726_
    ) internal view {
        require(factory_.code.length != 0, string.concat(name_, " not deployed"));
        require(
            address(Policy(factory_).kernel()) == address(_kernel),
            string.concat(name_, " wrong kernel")
        );
        require(_kernel.isPolicyActive(Policy(factory_)), string.concat(name_, " not activated"));

        address expectedPrice = address(_kernel.getModuleForKeycode(toKeycode("PRICE")));
        address factoryPrice = isERC7726_
            ? IERC7726OracleFactory(factory_).getPriceModule()
            : IOracleFactory(factory_).getPriceModule();

        require(factoryPrice == expectedPrice, string.concat(name_, " wrong PRICE module"));
    }
}

contract OracleProposalScript is ProposalScript {
    constructor() ProposalScript(new OracleProposal()) {}
}
/// forge-lint: disable-end(mixed-case-variable)
