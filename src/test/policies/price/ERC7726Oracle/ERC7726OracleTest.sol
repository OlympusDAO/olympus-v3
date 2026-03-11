// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {ERC7726Oracle} from "src/policies/price/ERC7726Oracle.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {ADMIN_ROLE, MANAGER_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @notice Parent test contract for ERC7726Oracle tests
/// @dev    Provides setup, helper functions, and modifiers for all factory test files
contract ERC7726OracleTest is Test {
    // ========== STATE ========== //

    Kernel public kernel;
    ERC7726Oracle public oracle;
    MockPrice public priceModule;
    OlympusRoles public roles;
    RolesAdmin public rolesAdmin;

    MockERC20 public collateralToken;
    MockERC20 public loanToken;

    address public admin;
    address public manager;
    address public emergency;

    uint8 public constant PRICE_DECIMALS = 18;
    uint32 public constant OBSERVATION_FREQUENCY = 1 hours;

    // ========== SETUP ========== //

    function setUp() public virtual {
        // Create test users
        admin = makeAddr("ADMIN");
        manager = makeAddr("MANAGER");
        emergency = makeAddr("EMERGENCY");

        // Deploy Kernel
        kernel = new Kernel();

        // Deploy PRICE module
        priceModule = new MockPrice(kernel, PRICE_DECIMALS, OBSERVATION_FREQUENCY);

        // Deploy ROLES module
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);

        // Deploy oracle
        oracle = new ERC7726Oracle(kernel);

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(priceModule));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(oracle));

        // Grant roles
        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(MANAGER_ROLE, manager);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);

        // Deploy mock tokens
        collateralToken = new MockERC20("Collateral Token", "COL", 18);
        loanToken = new MockERC20("Loan Token", "LOAN", 18);

        // Set prices in PRICE module
        _setPRICEPrices(address(collateralToken), 2e18); // 2 USD
        _setPRICEPrices(address(loanToken), 1e18); // 1 USD
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice Sets price for a token in the PRICE module
    function _setPRICEPrices(address token_, uint256 price_) internal {
        priceModule.setPrice(token_, price_);
    }

    /// @notice Enables the oracle
    function _enableOracle() internal {
        vm.prank(admin);
        oracle.enable("");
    }

    /// @notice Disables the oracle
    function _disableOracle() internal {
        vm.prank(admin);
        oracle.disable("");
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
