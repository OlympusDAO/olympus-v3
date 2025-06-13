// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {Test} from "@forge-std-1.9.6/Test.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {DepositManager} from "src/policies/DepositManager.sol";

import {IDepositManager} from "src/policies/interfaces/IDepositManager.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IPolicyEnabler} from "src/policies/interfaces/utils/IPolicyEnabler.sol";

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
    OlympusRoles public roles;
    RolesAdmin public rolesAdmin;
    DepositManager public depositManager;

    MockERC20 public asset;
    MockERC4626 public vault;
    IERC20 public iAsset;
    IERC4626 public iVault;

    uint8 public constant DEPOSIT_PERIOD = 1;
    uint256 public constant MINT_AMOUNT = 100e18;
    uint16 public constant RECLAIM_RATE = 90e2;

    function setUp() public {
        ADMIN = makeAddr("ADMIN");
        MANAGER = makeAddr("MANAGER");
        DEPOSIT_OPERATOR = makeAddr("DEPOSIT_OPERATOR");
        DEPOSITOR = makeAddr("DEPOSITOR");

        // Kernel
        vm.startPrank(ADMIN);
        kernel = new Kernel();

        // Create modules and policies
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        depositManager = new DepositManager(address(kernel));
        vm.stopPrank();

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
        iAsset = IERC20(address(asset));
        iVault = IERC4626(address(vault));

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

    modifier givenAssetVaultIsConfigured() {
        vm.prank(ADMIN);
        depositManager.configureAssetVault(iAsset, iVault);
        _;
    }

    modifier givenDepositIsConfigured() {
        vm.prank(ADMIN);
        depositManager.addDepositConfiguration(iAsset, DEPOSIT_PERIOD, RECLAIM_RATE);
        _;
    }

    modifier givenDepositorHasApprovedSpendingAsset(uint256 amount_) {
        vm.prank(DEPOSITOR);
        asset.approve(address(depositManager), amount_);
        _;
    }

    // ========== REVERT HELPERS ========== //

    function _expectRevertNotEnabled() internal {
        vm.expectRevert(abi.encodeWithSelector(IPolicyEnabler.NotEnabled.selector));
    }

    function _expectRevertNotManagerOrAdmin() internal {
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
    }

    function _expectRevertInvalidConfiguration(IERC20 asset_, uint8 depositPeriod_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_InvalidConfiguration.selector,
                address(asset_),
                depositPeriod_
            )
        );
    }

    function _expectRevertConfigurationEnabled(IERC20 asset_, uint8 depositPeriod_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_ConfigurationEnabled.selector,
                address(asset_),
                depositPeriod_
            )
        );
    }

    function _expectRevertConfigurationDisabled(IERC20 asset_, uint8 depositPeriod_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_ConfigurationDisabled.selector,
                address(asset_),
                depositPeriod_
            )
        );
    }
}
