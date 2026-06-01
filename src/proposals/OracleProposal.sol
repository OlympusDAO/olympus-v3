// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-variable)
pragma solidity ^0.8.15;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Olympus Kernel, Modules, and Policies
import {Kernel, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ITimelock} from "src/external/governance/interfaces/ITimelock.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
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

    address internal constant CHAINLINK_BTC_USD = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address internal constant CHAINLINK_DAI_USD = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address internal constant CHAINLINK_ETH_BTC = 0xAc559F25B1619171CbC396a50854A3240b6A4e99;
    address internal constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address internal constant CHAINLINK_OHM_ETH = 0x9a72298ae3886221820B1c878d12D872087D3a23;
    address internal constant CHAINLINK_USDS_USD = 0xfF30586cD0F29eD462364C7e81375FC0C71219b1;
    address internal constant API3_ETH_USD = 0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473;
    address internal constant API3_USDS_USD = address(0);
    address internal constant REDSTONE_ETH_USD = 0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4;

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
        return string.concat(
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
            "3. **Enable PriceCache policy** (if needed)\n",
            "4. **Enable ERC7726OracleFactory policy**\n",
            "5. **Enable ChainlinkOracleFactory policy**\n",
            "6. **Enable MorphoOracleFactory policy**\n",
            "7. **Deploy ERC7726 oracle** (via ERC7726OracleFactory)\n",
            "8. **Deploy OHM/USDS Chainlink oracle** (via ChainlinkOracleFactory)\n",
            "9. **Deploy OHM/USDS Morpho oracle** (via MorphoOracleFactory)\n",
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
            "- [Audit Report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2026-05_Olympus_Price_Feed_Updates_Report.pdf)\n",
            "- [Implementation PR](https://github.com/OlympusDAO/olympus-v3/pull/187)\n",
            "- [PRICE Documentation](https://github.com/OlympusDAO/olympus-v3/blob/4248bd6d45e160f7d369c1d44f126d8cef0b7f57/documentation/price.md)\n",
            "- [Oracle Documentation](https://github.com/OlympusDAO/olympus-v3/blob/4248bd6d45e160f7d369c1d44f126d8cef0b7f57/documentation/oracle_factories.md)\n"
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
        address chainlinkFactory = addresses.getAddress("olympus-policy-chainlink-oracle-factory-1_0");
        address morphoFactory = addresses.getAddress("olympus-policy-morpho-oracle-factory-1_0");
        address priceCache = addresses.getAddress("olympus-policy-price-cache-1_0");

        _verifyFactoryConfiguration(erc7726Factory, "ERC7726OracleFactory", true, priceCache);
        _verifyFactoryConfiguration(chainlinkFactory, "ChainlinkOracleFactory", false, priceCache);
        _verifyFactoryConfiguration(morphoFactory, "MorphoOracleFactory", false, priceCache);

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
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, ORACLE_MANAGER_ROLE, timelock),
                "Grant oracle_manager role to Timelock"
            );
        } else {
            console2.log("Timelock already has the oracle_manager role");
        }

        // STEP 3: Enable PriceCache, if needed
        if (!IEnabler(priceCache).isEnabled()) {
            _pushAction(priceCache, abi.encodeWithSelector(IEnabler.enable.selector, ""), "Enable PriceCache");
        } else {
            console2.log("PriceCache already enabled");
        }

        // STEP 4: Enable oracle policies
        _pushAction(erc7726Factory, abi.encodeWithSelector(IEnabler.enable.selector, ""), "Enable ERC7726OracleFactory");

        _pushAction(
            chainlinkFactory, abi.encodeWithSelector(IEnabler.enable.selector, ""), "Enable ChainlinkOracleFactory"
        );

        _pushAction(morphoFactory, abi.encodeWithSelector(IEnabler.enable.selector, ""), "Enable MorphoOracleFactory");

        // STEP 5: Deploy oracles
        _pushAction(
            erc7726Factory,
            abi.encodeWithSelector(IERC7726OracleFactory.createOracle.selector, DEFAULT_ORACLE_MAX_AGE, ""),
            "Deploy ERC7726 oracle"
        );

        _pushAction(
            chainlinkFactory,
            abi.encodeWithSelector(IOracleFactory.createOracle.selector, ohm, usds, DEFAULT_ORACLE_MAX_AGE, ""),
            "Deploy OHM/USDS Chainlink oracle"
        );

        _pushAction(
            morphoFactory,
            abi.encodeWithSelector(IOracleFactory.createOracle.selector, ohm, usds, DEFAULT_ORACLE_MAX_AGE, ""),
            "Deploy OHM/USDS Morpho oracle"
        );
    }

    // Executes the proposal actions.
    function _run(Addresses addresses, address) internal override {
        _mockPriceFeedsAtTimelockExecution(addresses);

        _simulateActions(
            address(_kernel),
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );

        vm.clearMockedCalls();
    }

    /// @dev GovernorBravoProposal simulates execution after the timelock delay by warping the fork
    ///      forward. On a static fork, external oracle contracts do not receive the
    ///      Chainlink/API3/RedStone updates that would occur during that real elapsed time, so PRICE
    ///      can reject otherwise valid proposal actions with stale-feed errors.
    ///
    ///      The proposal actions depend on PRICE during simulation because deploying the
    ///      cache-backed oracle clones seeds/validates the OHM/USDS cache. Preserve the feed answers
    ///      from the fork, but move their timestamps to the simulated timelock execution time so the
    ///      simulation exercises the proposal logic instead of failing on fork-only clock drift.
    ///      These mocks are cleared immediately after simulation and do not affect the calldata
    ///      submitted to governance.
    function _mockPriceFeedsAtTimelockExecution(Addresses addresses) internal {
        uint256 executionTimestamp = block.timestamp + ITimelock(addresses.getAddress("olympus-timelock")).delay();

        _mockChainlinkFeedAt(CHAINLINK_BTC_USD, executionTimestamp);
        _mockChainlinkFeedAt(CHAINLINK_DAI_USD, executionTimestamp);
        _mockChainlinkFeedAt(CHAINLINK_ETH_BTC, executionTimestamp);
        _mockChainlinkFeedAt(CHAINLINK_ETH_USD, executionTimestamp);
        _mockChainlinkFeedAt(CHAINLINK_OHM_ETH, executionTimestamp);
        _mockChainlinkFeedAt(CHAINLINK_USDS_USD, executionTimestamp);
        _mockChainlinkFeedAt(API3_ETH_USD, executionTimestamp);
        if (API3_USDS_USD != address(0)) {
            _mockChainlinkFeedAt(API3_USDS_USD, executionTimestamp);
        }
        _mockChainlinkFeedAt(REDSTONE_ETH_USD, executionTimestamp);
    }

    function _mockChainlinkFeedAt(address feed_, uint256 updatedAt_) internal {
        (uint80 roundId, int256 answer,,, uint80 answeredInRound) = AggregatorV2V3Interface(feed_).latestRoundData();

        vm.mockCall(
            feed_,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(roundId, answer, updatedAt_, updatedAt_, answeredInRound)
        );
    }

    // Validates the post-execution state.
    function _validate(Addresses addresses, address) internal view override {
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address timelock = addresses.getAddress("olympus-timelock");
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        address ohm = addresses.getAddress("olympus-legacy-ohm");
        address usds = addresses.getAddress("external-tokens-usds");

        address chainlinkFactory = addresses.getAddress("olympus-policy-chainlink-oracle-factory-1_0");
        address morphoFactory = addresses.getAddress("olympus-policy-morpho-oracle-factory-1_0");
        address erc7726Factory = addresses.getAddress("olympus-policy-erc7726-oracle-factory-1_0");
        address priceCache = addresses.getAddress("olympus-policy-price-cache-1_0");

        _verifyFactoryConfiguration(erc7726Factory, "ERC7726OracleFactory", true, priceCache);
        _verifyFactoryConfiguration(chainlinkFactory, "ChainlinkOracleFactory", false, priceCache);
        _verifyFactoryConfiguration(morphoFactory, "MorphoOracleFactory", false, priceCache);

        // Verify admin role granted to Timelock
        require(roles.hasRole(timelock, ADMIN_ROLE), "Timelock does not have admin role");

        // Verify oracle_manager role granted
        require(roles.hasRole(daoMS, ORACLE_MANAGER_ROLE), "DAO MS does not have oracle_manager role");
        require(roles.hasRole(timelock, ORACLE_MANAGER_ROLE), "Timelock does not have oracle_manager role");

        // Verify price cache and oracle policies are enabled
        require(IEnabler(priceCache).isEnabled(), "PriceCache not enabled");
        require(IEnabler(erc7726Factory).isEnabled(), "ERC7726OracleFactory not enabled");
        require(IEnabler(chainlinkFactory).isEnabled(), "ChainlinkOracleFactory not enabled");
        require(IEnabler(morphoFactory).isEnabled(), "MorphoOracleFactory not enabled");

        // Verify oracles were deployed
        address erc7726Oracle = IERC7726OracleFactory(erc7726Factory).getOracle(DEFAULT_ORACLE_MAX_AGE);
        require(erc7726Oracle != address(0), "ERC7726 oracle not deployed");
        require(IERC7726OracleFactory(erc7726Factory).isOracleEnabled(erc7726Oracle), "ERC7726 oracle not enabled");

        address chainlinkOracle = IOracleFactory(chainlinkFactory).getOracle(ohm, usds, DEFAULT_ORACLE_MAX_AGE);
        require(chainlinkOracle != address(0), "OHM/USDS Chainlink oracle not deployed");
        require(
            IOracleFactory(chainlinkFactory).isOracleEnabled(chainlinkOracle), "OHM/USDS Chainlink oracle not enabled"
        );

        address morphoOracle = IOracleFactory(morphoFactory).getOracle(ohm, usds, DEFAULT_ORACLE_MAX_AGE);
        require(morphoOracle != address(0), "OHM/USDS Morpho oracle not deployed");
        require(IOracleFactory(morphoFactory).isOracleEnabled(morphoOracle), "OHM/USDS Morpho oracle not enabled");
    }

    function _verifyFactoryConfiguration(address factory_, string memory name_, bool isERC7726_, address priceCache_)
        internal
        view
    {
        require(factory_.code.length != 0, string.concat(name_, " not deployed"));
        require(address(Policy(factory_).kernel()) == address(_kernel), string.concat(name_, " wrong kernel"));
        require(_kernel.isPolicyActive(Policy(factory_)), string.concat(name_, " not activated"));

        address expectedSource = priceCache_;
        address factorySource =
            isERC7726_ ? IERC7726OracleFactory(factory_).getPriceCache() : IOracleFactory(factory_).getPriceCache();

        require(factorySource == expectedSource, string.concat(name_, " wrong price cache"));
    }
}

contract OracleProposalScript is ProposalScript {
    constructor() ProposalScript(new OracleProposal()) {}
}
/// forge-lint: disable-end(mixed-case-variable)
