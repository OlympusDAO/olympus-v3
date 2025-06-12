// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {Test} from "@forge-std-1.9.6/Test.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {DepositManager} from "src/policies/DepositManager.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

contract DepositManagerTest is Test {
    address public ADMIN;
    address public MANAGER;
    address public DEPOSIT_OPERATOR;
    address public DEPOSITOR;

    Kernel public kernel;
    ROLESv1 public roles;
    RolesAdmin public rolesAdmin;
    DepositManager public depositManager;

    MockERC20 public asset;
    MockERC4626 public vault;
    uint8 public constant DEPOSIT_PERIOD = 1;
    uint256 public constant MINT_AMOUNT = 100e18;

    function setUp() public {
        ADMIN = makeAddr("ADMIN");
        MANAGER = makeAddr("MANAGER");
        DEPOSIT_OPERATOR = makeAddr("DEPOSIT_OPERATOR");
        DEPOSITOR = makeAddr("DEPOSITOR");

        // Kernel
        vm.prank(ADMIN);
        kernel = new Kernel();

        // Create modules and policies
        roles = new ROLESv1(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        depositManager = new DepositManager(address(kernel));

        // Install modules and policies
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(depositManager));
        vm.stopPrank();

        // Grant roles
        vm.startPrank(ADMIN);
        rolesAdmin.grantRole("admin", ADMIN);
        rolesAdmin.grantRole("manager", MANAGER);
        rolesAdmin.grantRole("deposit_operator", DEPOSIT_OPERATOR);
        vm.stopPrank();

        // Configure asset
        asset = new MockERC20("Asset", "ASSET", 18);
        vault = new MockERC4626(ERC20(address(asset)), "Vault", "VAULT");

        // Mint balance to the depositor
        asset.mint(DEPOSITOR, MINT_AMOUNT);

        // Deposit manager is disabled by default
    }

    // ========== MODIFIERS ========== //

    modifier givenIsEnabled() {
        vm.prank(ADMIN);
        depositManager.enable("");
        _;
    }

    modifier givenIsDisabled() {
        vm.prank(ADMIN);
        depositManager.disable("");
        _;
    }

    modifier givenAssetIsConfigured(address vault_) {
        vm.prank(ADMIN);
        depositManager.configureDeposit(IERC20(address(asset)), IERC4626(vault_), DEPOSIT_PERIOD, 100e2);
        _;
    }

    modifier givenDepositorHasApprovedSpendingAsset(uint256 amount_) {
        vm.prank(DEPOSITOR);
        asset.approve(address(depositManager), amount_);
        _;
    }
}
