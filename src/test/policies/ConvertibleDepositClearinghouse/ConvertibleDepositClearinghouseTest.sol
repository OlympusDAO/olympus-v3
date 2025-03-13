// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

// Libraries
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

// Bophades
import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusConvertibleDepository} from "src/modules/CDEPO/OlympusConvertibleDepository.sol";
import {OlympusClearinghouseRegistry} from "src/modules/CHREG/OlympusClearinghouseRegistry.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {CDClearinghouse} from "src/policies/CDClearinghouse.sol";
import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";
import {Cooler} from "src/external/cooler/Cooler.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract ConvertibleDepositClearinghouseTest is Test {
    address internal constant EXECUTOR = address(0x1111);
    address internal constant ADMIN = address(0xAAAA);
    address internal constant EMERGENCY = address(0xEEEE);
    address internal constant USER = address(0xBBBB);
    address internal constant OTHERS = address(0xDDDD);

    uint256 internal constant MAX_REWARD_PER_LOAN = 5e18;
    uint48 internal constant DURATION = 121 days;
    uint16 internal constant LOAN_TO_COLLATERAL = 90e2;
    uint16 internal constant INTEREST_RATE = 1e2;

    CoolerFactory internal coolerFactory;
    MockERC4626 internal vault;
    MockERC20 internal asset;

    Kernel internal kernel;
    OlympusTreasury internal TRSRY;
    OlympusConvertibleDepository internal CDEPO;
    OlympusClearinghouseRegistry internal CHREG;
    OlympusRoles internal ROLES;

    RolesAdmin internal rolesAdmin;
    CDClearinghouse internal clearinghouse;

    Cooler internal cooler;

    function setUp() public {
        // Set up tokens
        asset = new MockERC20("Asset", "ASSET", 18);
        vault = new MockERC4626(asset, "Vault", "VAULT");

        coolerFactory = new CoolerFactory();

        // Kernel
        vm.startPrank(EXECUTOR);
        kernel = new Kernel();
        vm.stopPrank();

        // Modules
        TRSRY = new OlympusTreasury(kernel);
        CDEPO = new OlympusConvertibleDepository(address(kernel), address(vault), 90e2);
        CHREG = new OlympusClearinghouseRegistry(kernel, address(0), new address[](0));
        ROLES = new OlympusRoles(kernel);

        vm.startPrank(EXECUTOR);
        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.InstallModule, address(CDEPO));
        kernel.executeAction(Actions.InstallModule, address(CHREG));
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        vm.stopPrank();

        // RolesAdmin
        vm.startPrank(EXECUTOR);
        rolesAdmin = new RolesAdmin(kernel);
        clearinghouse = new CDClearinghouse(
            address(vault),
            address(coolerFactory),
            address(kernel),
            MAX_REWARD_PER_LOAN,
            DURATION,
            LOAN_TO_COLLATERAL,
            INTEREST_RATE
        );
        vm.stopPrank();

        vm.startPrank(EXECUTOR);
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(clearinghouse));
        vm.stopPrank();

        // Assign roles
        vm.startPrank(EXECUTOR);
        rolesAdmin.grantRole("admin", ADMIN);
        rolesAdmin.grantRole("emergency", EMERGENCY);
        vm.stopPrank();

        // Fund the TRSRY with vault tokens
        asset.mint(address(TRSRY), 100e18);
        vm.startPrank(address(TRSRY));
        asset.approve(address(vault), 100e18);
        vault.deposit(100e18, address(TRSRY));
        vm.stopPrank();

        // Activate
        vm.prank(ADMIN);
        clearinghouse.enable("");

        // Create a cooler for USER
        vm.prank(USER);
        cooler = Cooler(coolerFactory.generateCooler(CDEPO, vault));

        // Fund others so that TRSRY is not the only with vault shares
        asset.mint(OTHERS, 100e18);
        vm.startPrank(OTHERS);
        asset.approve(address(vault), 100e18);
        vault.deposit(100e18, OTHERS);
        vm.stopPrank();
    }

    modifier givenDisabled() {
        vm.prank(ADMIN);
        clearinghouse.disable("");
        _;
    }

    function _expectNotEnabled() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyEnabler.NotEnabled.selector
            )
        );
    }

    function _expectNotDisabled() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyEnabler.NotDisabled.selector
            )
        );
    }

    function _expectRoleRevert(bytes32 role_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ROLESv1.ROLES_RequireRole.selector,
                role_
            )
        );
    }

    function _expectNotAuthorized() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyAdmin.NotAuthorised.selector
            )
        );
    }
}
