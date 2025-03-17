// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";

// Libraries
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

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
import {ICooler} from "src/external/cooler/interfaces/ICooler.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract ConvertibleDepositClearinghouseTest is Test {
    using ModuleTestFixtureGenerator for OlympusConvertibleDepository;

    address internal constant EXECUTOR = address(0x1111);
    address internal constant ADMIN = address(0xAAAA);
    address internal constant EMERGENCY = address(0xEEEE);
    address internal constant USER = address(0xBBBB);
    address internal constant OTHERS = address(0xDDDD);

    uint256 internal constant MAX_REWARD_PER_LOAN = 5e18;
    uint48 internal constant DURATION = 121 days;
    uint256 internal constant LOAN_TO_COLLATERAL = 75e16; // 75%
    uint256 internal constant INTEREST_RATE = 1e16; // 1%

    uint256 internal constant ASSETS_PER_SHARE = 2e18;

    CoolerFactory internal coolerFactory;
    MockERC4626 internal vault;
    MockERC20 internal asset;
    IERC20 internal iAsset;

    Kernel internal kernel;
    OlympusTreasury internal TRSRY;
    OlympusConvertibleDepository internal CDEPO;
    OlympusClearinghouseRegistry internal CHREG;
    OlympusRoles internal ROLES;

    RolesAdmin internal rolesAdmin;
    CDClearinghouse internal clearinghouse;
    address internal godmode;

    ERC20 internal cdToken;

    ICooler internal cooler;

    function setUp() public {
        // Set up tokens
        asset = new MockERC20("Asset", "ASSET", 18);
        iAsset = IERC20(address(asset));
        vault = new MockERC4626(asset, "Vault", "VAULT");

        coolerFactory = new CoolerFactory();

        // Kernel
        vm.startPrank(EXECUTOR);
        kernel = new Kernel();
        vm.stopPrank();

        // Modules
        TRSRY = new OlympusTreasury(kernel);
        CDEPO = new OlympusConvertibleDepository(kernel);
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
        godmode = CDEPO.generateGodmodeFixture(type(OlympusConvertibleDepository).name);

        vm.startPrank(EXECUTOR);
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(clearinghouse));
        kernel.executeAction(Actions.ActivatePolicy, godmode);
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

        // Create a CD token
        vm.startPrank(godmode);
        cdToken = ERC20(CDEPO.createToken(IERC4626(address(vault)), 90e2));
        vm.stopPrank();

        // Activate
        vm.prank(ADMIN);
        clearinghouse.enable("");

        // Create a cooler for USER
        vm.prank(USER);
        cooler = ICooler(coolerFactory.generateCooler(cdToken, vault));

        // Fund others so that TRSRY is not the only with vault shares
        asset.mint(OTHERS, 100e18);
        vm.startPrank(OTHERS);
        asset.approve(address(vault), 100e18);
        vault.deposit(100e18, OTHERS);
        vm.stopPrank();

        // Deposit 200e18 assets into the vault so the conversion is not 1:1
        asset.mint(address(vault), 200e18);

        // Labels
        vm.label(USER, "USER");
        vm.label(OTHERS, "OTHERS");
        vm.label(address(vault), "VAULT");
        vm.label(address(asset), "ASSET");
        vm.label(address(cooler), "COOLER");
    }

    modifier givenDisabled() {
        vm.prank(ADMIN);
        clearinghouse.disable("");
        _;
    }

    function _expectNotEnabled() internal {
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));
    }

    function _expectNotDisabled() internal {
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotDisabled.selector));
    }

    function _expectRoleRevert(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
    }

    function _expectNotAuthorized() internal {
        vm.expectRevert(abi.encodeWithSelector(PolicyAdmin.NotAuthorised.selector));
    }

    modifier givenUserHasApprovedCollateralSpending(uint256 amount_) {
        vm.prank(USER);
        cdToken.approve(address(clearinghouse), amount_);
        _;
    }

    modifier givenUserHasApprovedDebtSpendingToClearinghouse(uint256 amount_) {
        vm.prank(USER);
        vault.approve(address(clearinghouse), amount_);
        _;
    }

    modifier givenUserHasApprovedDebtSpendingToCooler(uint256 amount_) {
        vm.prank(USER);
        vault.approve(address(cooler), amount_);
        _;
    }

    modifier givenUserHasCollateral(uint256 amount_) {
        // USER requires assets
        asset.mint(USER, amount_);

        // Mint CDEPO to USER
        vm.startPrank(USER);
        asset.approve(address(CDEPO), amount_);
        CDEPO.mint(iAsset, amount_);
        vm.stopPrank();
        _;
    }

    modifier givenUserHasDebt(uint256 amount_) {
        vm.prank(USER);
        clearinghouse.lendToCooler(cooler, amount_);
        _;
    }
}
