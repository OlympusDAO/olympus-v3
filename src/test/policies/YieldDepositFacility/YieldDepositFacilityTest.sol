// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {CDFacility} from "src/policies/CDFacility.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusConvertibleDepository} from "src/modules/CDEPO/OlympusConvertibleDepository.sol";
import {OlympusConvertibleDepositPositions} from "src/modules/CDPOS/OlympusConvertibleDepositPositions.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {YieldDepositFacility} from "src/policies/YieldDepositFacility.sol";

// solhint-disable max-states-count
contract YieldDepositFacilityTest is Test {
    Kernel public kernel;
    YieldDepositFacility public yieldDepositFacility;
    OlympusRoles public roles;
    OlympusConvertibleDepository public convertibleDepository;
    OlympusConvertibleDepositPositions public convertibleDepositPositions;
    OlympusTreasury public treasury;
    RolesAdmin public rolesAdmin;

    MockERC20 public reserveToken;
    MockERC4626 public vault;
    IERC20 internal iReserveToken;
    IConvertibleDepositERC20 internal cdToken;

    MockERC20 public reserveTokenTwo;
    MockERC4626 public vaultTwo;
    IERC20 internal iReserveTokenTwo;
    IConvertibleDepositERC20 internal cdTokenTwo;

    address public recipient = address(0x1);
    address public auctioneer = address(0x2);
    address public recipientTwo = address(0x3);
    address public emergency = address(0x4);
    address public admin = address(0xEEEEEE);

    uint48 public constant INITIAL_BLOCK = 1_000_000;
    uint256 public constant RESERVE_TOKEN_AMOUNT = 10e18;
    uint8 public constant PERIOD_MONTHS = 6;
    uint48 public constant CONVERSION_EXPIRY = INITIAL_BLOCK + (30 days) * PERIOD_MONTHS;

    function setUp() public {
        vm.warp(INITIAL_BLOCK);

        reserveToken = new MockERC20("Reserve Token", "RES", 18);
        iReserveToken = IERC20(address(reserveToken));
        vault = new MockERC4626(reserveToken, "Vault", "VAULT");
        vm.label(address(reserveToken), "RES");
        vm.label(address(vault), "sRES");

        reserveTokenTwo = new MockERC20("Reserve Token Two", "RES2", 18);
        iReserveTokenTwo = IERC20(address(reserveTokenTwo));
        vaultTwo = new MockERC4626(reserveTokenTwo, "Vault Two", "VAULT2");
        vm.label(address(reserveTokenTwo), "RES2");
        vm.label(address(vaultTwo), "sRES2");

        // Instantiate bophades
        _createStack();

        // Deposit into the vault to create a non-equal conversion rate
        reserveToken.mint(address(this), 10e18);
        reserveToken.approve(address(vault), 10e18);
        vault.deposit(10e18, address(this));
        reserveToken.mint(address(vault), 1e18);
        require(vault.convertToAssets(1e18) != 1e18, "Vault conversion rate is equal to 1");
    }

    function _createStack() internal {
        kernel = new Kernel();
        roles = new OlympusRoles(kernel);
        convertibleDepository = new OlympusConvertibleDepository(kernel);
        convertibleDepositPositions = new OlympusConvertibleDepositPositions(address(kernel));
        treasury = new OlympusTreasury(kernel);
        yieldDepositFacility = new YieldDepositFacility(address(kernel));
        rolesAdmin = new RolesAdmin(kernel);

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(roles));

        kernel.executeAction(Actions.InstallModule, address(convertibleDepository));
        kernel.executeAction(Actions.InstallModule, address(convertibleDepositPositions));
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.ActivatePolicy, address(yieldDepositFacility));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Grant roles
        rolesAdmin.grantRole(bytes32("emergency"), emergency);
        rolesAdmin.grantRole(bytes32("admin"), admin);

        // Enable the facility
        vm.prank(admin);
        yieldDepositFacility.enable("");

        // Create a CD token
        vm.startPrank(admin);
        cdToken = yieldDepositFacility.create(IERC4626(address(vault)), PERIOD_MONTHS, 90e2);
        vm.stopPrank();
        vm.label(address(cdToken), "cdToken");

        // Create a CD token
        vm.startPrank(admin);
        cdTokenTwo = yieldDepositFacility.create(IERC4626(address(vaultTwo)), PERIOD_MONTHS, 90e2);
        vm.stopPrank();
        vm.label(address(cdTokenTwo), "cdTokenTwo");

        // Disable the facility
        vm.prank(emergency);
        yieldDepositFacility.disable("");
    }

    // ========== MODIFIERS ========== //

    modifier givenAddressHasReserveToken(address to_, uint256 amount_) {
        reserveToken.mint(to_, amount_);
        _;
    }

    modifier givenReserveTokenSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        vm.prank(owner_);
        reserveToken.approve(spender_, amount_);
        _;
    }

    modifier mintConvertibleDepositToken(address account_, uint256 amount_) {
        vm.prank(account_);
        convertibleDepository.mint(cdToken, amount_);
        _;
    }

    function _createYieldDepositPosition(
        address account_,
        uint256 amount_
    ) internal returns (uint256 positionId) {
        vm.prank(account_);
        positionId = yieldDepositFacility.mint(cdToken, amount_, false);
    }

    modifier givenAddressHasYieldDepositPosition(address account_, uint256 amount_) {
        _createYieldDepositPosition(account_, amount_);
        _;
    }

    modifier givenLocallyActive() {
        vm.prank(admin);
        yieldDepositFacility.enable("");
        _;
    }

    modifier givenLocallyInactive() {
        vm.prank(emergency);
        yieldDepositFacility.disable("");
        _;
    }

    modifier givenReserveTokenHasDecimals(uint8 decimals_) {
        reserveToken = new MockERC20("Reserve Token", "RES", decimals_);
        iReserveToken = IERC20(address(reserveToken));
        vault = new MockERC4626(reserveToken, "Vault", "VAULT");

        _createStack();
        _;
    }

    // ========== ASSERTIONS ========== //

    function _expectRoleRevert(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
    }
}
