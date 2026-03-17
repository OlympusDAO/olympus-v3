// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {ERC7726OracleFactory} from "src/policies/price/ERC7726OracleFactory.sol";
import {IERC7726Oracle} from "src/policies/interfaces/price/IERC7726Oracle.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {ADMIN_ROLE, MANAGER_ROLE, ORACLE_MANAGER_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @notice Parent test contract for ERC7726Oracle tests
/// @dev    Provides setup, helper functions, and modifiers for all factory test files
contract ERC7726OracleTest is Test {
    // ========== STATE ========== //

    Kernel public kernel;
    IERC7726Oracle public oracle;
    ERC7726OracleFactory public factory;
    MockPrice public priceModule;
    OlympusRoles public roles;
    RolesAdmin public rolesAdmin;

    MockERC20 public collateralToken;
    MockERC20 public loanToken;

    address public admin;
    address public manager;
    address public oracleManager;
    address public emergency;

    uint8 public constant PRICE_DECIMALS = 18;
    uint32 public constant OBSERVATION_FREQUENCY = 1 hours;
    uint48 public constant DEFAULT_MAX_AGE = 1 hours;

    // ========== SETUP ========== //

    function setUp() public virtual {
        // Create test users
        admin = makeAddr("ADMIN");
        manager = makeAddr("MANAGER");
        oracleManager = makeAddr("ORACLE_MANAGER");
        emergency = makeAddr("EMERGENCY");

        // Deploy Kernel
        kernel = new Kernel();

        // Deploy PRICE module
        priceModule = new MockPrice(kernel, PRICE_DECIMALS, OBSERVATION_FREQUENCY);

        // Deploy ROLES module
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);

        // Deploy oracle factory
        factory = new ERC7726OracleFactory(kernel);

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(priceModule));
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

        // Set prices in PRICE module
        _setPRICEPrices(address(collateralToken), 2e18); // 2 USD
        _setPRICEPrices(address(loanToken), 1e18); // 1 USD

        // Enable factory and create clone oracle
        vm.prank(admin);
        factory.enable("");

        vm.prank(admin);
        address oracleAddress = factory.createOracle(DEFAULT_MAX_AGE, bytes(""));
        oracle = IERC7726Oracle(oracleAddress);

        // Seed initial cached values consumed by clone oracles (Variant.LAST).
        priceModule.cachePrice(address(collateralToken));
        priceModule.cachePrice(address(loanToken));
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice Sets price for a token in the PRICE module
    function _setPRICEPrices(address token_, uint256 price_) internal {
        priceModule.setPrice(token_, price_);
        priceModule.cachePrice(token_);
    }

    /// @notice Enables the oracle
    function _enableOracle() internal {
        if (!factory.isOracleEnabled(address(oracle))) {
            vm.prank(admin);
            factory.enableOracle(address(oracle));
        }
    }

    /// @notice Disables the oracle
    function _disableOracle() internal {
        if (factory.isOracleEnabled(address(oracle))) {
            vm.prank(admin);
            factory.disableOracle(address(oracle));
        }
    }

    // ========== MODIFIERS ========== //

    modifier givenOracleIsEnabled() {
        _enableOracle();
        _;
    }

    modifier givenOracleIsDisabled() {
        _disableOracle();
        _;
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
