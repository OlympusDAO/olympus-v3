// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {ERC7726OracleFactory} from "src/policies/price/ERC7726OracleFactory.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";
import {ADMIN_ROLE, MANAGER_ROLE, ORACLE_MANAGER_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract ERC7726OracleFactoryTest is Test {
    Kernel public kernel;
    ERC7726OracleFactory public factory;
    MockPrice public priceModule;
    MockPriceCache public priceCache;
    OlympusRoles public roles;
    RolesAdmin public rolesAdmin;

    MockERC20 public baseToken;
    MockERC20 public quoteToken;

    address public admin;
    address public manager;
    address public oracleManager;
    address public emergency;

    uint8 public constant PRICE_DECIMALS = 18;
    uint32 public constant OBSERVATION_FREQUENCY = 1 hours;
    uint48 public constant DEFAULT_MAX_AGE = 1 hours;

    function setUp() public virtual {
        admin = makeAddr("ADMIN");
        manager = makeAddr("MANAGER");
        oracleManager = makeAddr("ORACLE_MANAGER");
        emergency = makeAddr("EMERGENCY");

        kernel = new Kernel();
        priceModule = new MockPrice(kernel, PRICE_DECIMALS, OBSERVATION_FREQUENCY);
        priceCache = new MockPriceCache();
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        factory = new ERC7726OracleFactory(kernel, address(priceCache));

        kernel.executeAction(Actions.InstallModule, address(priceModule));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(factory));

        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(MANAGER_ROLE, manager);
        rolesAdmin.grantRole(ORACLE_MANAGER_ROLE, oracleManager);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);

        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        priceModule.setPrice(address(baseToken), 2e18);
        priceModule.setPrice(address(quoteToken), 1e18);
        priceCache.setUsdPrice(address(baseToken), 2e18);
        priceCache.setUsdPrice(address(quoteToken), 1e18);
    }

    function _enableFactory() internal {
        vm.prank(admin);
        factory.enable("");
    }

    function _disableFactory() internal {
        vm.prank(admin);
        factory.disable("");
    }

    function _createOracle(uint48 maxAge_) internal returns (address oracle) {
        vm.prank(admin);
        oracle = factory.createOracle(maxAge_, bytes(""));
    }

    function _enableCreation() internal {
        vm.prank(admin);
        factory.enableCreation();
    }

    function _disableCreation() internal {
        vm.prank(admin);
        factory.disableCreation();
    }

    function _enableOracle(address oracle_) internal {
        vm.prank(admin);
        factory.enableOracle(oracle_);
    }

    function _disableOracle(address oracle_) internal {
        vm.prank(admin);
        factory.disableOracle(oracle_);
    }

    modifier givenFactoryIsEnabled() {
        _enableFactory();
        _;
    }

    modifier givenFactoryIsDisabled() {
        _disableFactory();
        _;
    }

    modifier givenOracleIsCreated() {
        _createOracle(DEFAULT_MAX_AGE);
        _;
    }

    modifier givenCreationIsEnabled() {
        _enableCreation();
        _;
    }

    modifier givenCreationIsDisabled() {
        _disableCreation();
        _;
    }

    modifier givenOracleIsDisabled() {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        _disableOracle(oracle);
        _;
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
