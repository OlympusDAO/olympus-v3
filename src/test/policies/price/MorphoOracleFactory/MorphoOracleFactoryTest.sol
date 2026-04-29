// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {MorphoOracleFactory} from "src/policies/price/MorphoOracleFactory.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";
import {ADMIN_ROLE, MANAGER_ROLE, ORACLE_MANAGER_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @notice Parent test contract for MorphoOracleFactory tests
/// @dev    Provides setup, helper functions, and modifiers for all factory test files
contract MorphoOracleFactoryTest is Test {
    // ========== STATE ========== //

    Kernel public kernel;
    MorphoOracleFactory public factory;
    MockPriceCache public priceCache;
    OlympusRoles public roles;
    RolesAdmin public rolesAdmin;

    MockERC20 public collateralToken;
    MockERC20 public loanToken;
    address public registeredNonContractAsset;

    address public admin;
    address public manager;
    address public oracleManager;
    address public emergency;

    uint48 public constant DEFAULT_MAX_AGE = 1 hours;
    address public constant UNIT_OF_ACCOUNT = address(0x348);

    // ========== SETUP ========== //

    function setUp() public virtual {
        // Create test users
        admin = makeAddr("ADMIN");
        manager = makeAddr("MANAGER");
        oracleManager = makeAddr("ORACLE_MANAGER");
        emergency = makeAddr("EMERGENCY");

        // Deploy Kernel
        kernel = new Kernel();

        // Deploy ROLES module
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);

        // Deploy cache policy + factory
        priceCache = new MockPriceCache(address(kernel));
        factory = new MorphoOracleFactory(kernel, address(priceCache));

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(factory));

        // Grant roles
        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(MANAGER_ROLE, manager);
        rolesAdmin.grantRole(ORACLE_MANAGER_ROLE, oracleManager);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);

        // Deploy mock tokens
        collateralToken = new MockERC20("Collateral Token", "COL", 18);
        loanToken = new MockERC20("Loan Token", "LOAN", 18);
        registeredNonContractAsset = makeAddr("REGISTERED_NON_CONTRACT_ASSET");

        // Set prices in cache policy mock
        _setCachePrice(address(collateralToken), 2e18); // 2 USD
        _setCachePrice(address(loanToken), 1e18); // 1 USD
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice Sets price for a token in the cache policy mock
    function _setCachePrice(address token_, uint256 price_) internal {
        priceCache.setUsdPrice(token_, price_);
    }

    function _setNonContractAssetMetadata(
        address asset_,
        uint8 decimals_,
        string memory symbol_
    ) internal {
        priceCache.setNonContractAssetMetadata(asset_, decimals_, symbol_);
    }

    /// @notice Creates an oracle via the factory
    function _createOracle(
        address collateralToken_,
        address loanToken_,
        uint48 maxAge_
    ) internal returns (address oracle) {
        vm.prank(admin);
        oracle = factory.createOracle(collateralToken_, loanToken_, maxAge_, bytes(""));
    }

    /// @notice Enables the factory
    function _enableFactory() internal {
        vm.prank(admin);
        factory.enable("");
    }

    /// @notice Disables the factory
    function _disableFactory() internal {
        vm.prank(admin);
        factory.disable("");
    }

    /// @notice Enables oracle creation
    function _enableCreation() internal {
        vm.prank(admin);
        factory.enableCreation();
    }

    /// @notice Disables oracle creation
    function _disableCreation() internal {
        vm.prank(admin);
        factory.disableCreation();
    }

    /// @notice Enables a specific oracle
    function _enableOracle(address oracle_) internal {
        vm.prank(admin);
        factory.enableOracle(oracle_);
    }

    /// @notice Disables a specific oracle
    function _disableOracle(address oracle_) internal {
        vm.prank(admin);
        factory.disableOracle(oracle_);
    }

    /// @notice Grants a role to a user
    function _grantRole(bytes32 role_, address user_) internal {
        vm.prank(admin);
        rolesAdmin.grantRole(role_, user_);
    }

    // ========== MODIFIERS ========== //

    modifier givenFactoryIsEnabled() {
        _enableFactory();
        _;
    }

    modifier givenFactoryIsDisabled() {
        _disableFactory();
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

    modifier givenOracleIsCreated() {
        _createOracle(address(collateralToken), address(loanToken), DEFAULT_MAX_AGE);
        _;
    }

    modifier givenOracleIsEnabled() {
        address oracle = factory.getOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );
        _enableOracle(oracle);
        _;
    }

    modifier givenOracleIsDisabled() {
        address oracle = factory.getOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );
        _disableOracle(oracle);
        _;
    }

    modifier givenUserHasRole(bytes32 role_, address user_) {
        _grantRole(role_, user_);
        _;
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
