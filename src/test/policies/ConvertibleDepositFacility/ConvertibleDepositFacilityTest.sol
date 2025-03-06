// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {CDFacility} from "src/policies/CDFacility.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusConvertibleDepository} from "src/modules/CDEPO/OlympusConvertibleDepository.sol";
import {OlympusConvertibleDepositPositions} from "src/modules/CDPOS/OlympusConvertibleDepositPositions.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

// solhint-disable max-states-count
contract ConvertibleDepositFacilityTest is Test {
    Kernel public kernel;
    CDFacility public facility;
    OlympusTreasury public treasury;
    OlympusMinter public minter;
    OlympusRoles public roles;
    OlympusConvertibleDepository public convertibleDepository;
    OlympusConvertibleDepositPositions public convertibleDepositPositions;
    RolesAdmin public rolesAdmin;

    MockERC20 public ohm;
    MockERC20 public reserveToken;
    MockERC4626 public vault;

    address public recipient = address(0x1);
    address public auctioneer = address(0x2);
    address public recipientTwo = address(0x3);
    address public emergency = address(0x4);
    address public admin = address(0xEEEEEE);

    uint48 public constant INITIAL_BLOCK = 1_000_000;
    uint256 public constant CONVERSION_PRICE = 2e18;
    uint48 public constant CONVERSION_EXPIRY = INITIAL_BLOCK + 1 days;
    uint48 public constant REDEMPTION_EXPIRY = INITIAL_BLOCK + 2 days;
    uint256 public constant RESERVE_TOKEN_AMOUNT = 10e18;
    uint16 public constant RECLAIM_RATE = 90e2;

    function setUp() public {
        vm.warp(INITIAL_BLOCK);

        ohm = new MockERC20("Olympus", "OHM", 9);
        reserveToken = new MockERC20("Reserve Token", "RES", 18);
        vault = new MockERC4626(reserveToken, "Vault", "VAULT");

        // Instantiate bophades
        kernel = new Kernel();
        treasury = new OlympusTreasury(kernel);
        minter = new OlympusMinter(kernel, address(ohm));
        roles = new OlympusRoles(kernel);
        convertibleDepository = new OlympusConvertibleDepository(
            address(kernel),
            address(vault),
            RECLAIM_RATE
        );
        convertibleDepositPositions = new OlympusConvertibleDepositPositions(address(kernel));
        facility = new CDFacility(address(kernel));
        rolesAdmin = new RolesAdmin(kernel);

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.InstallModule, address(minter));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(convertibleDepository));
        kernel.executeAction(Actions.InstallModule, address(convertibleDepositPositions));
        kernel.executeAction(Actions.ActivatePolicy, address(facility));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Grant roles
        rolesAdmin.grantRole(bytes32("cd_auctioneer"), auctioneer);
        rolesAdmin.grantRole(bytes32("emergency"), emergency);
        rolesAdmin.grantRole(bytes32("admin"), admin);
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

    function _createPosition(
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        uint48 conversionExpiry_,
        uint48 redemptionExpiry_,
        bool wrap_
    ) internal returns (uint256 positionId) {
        vm.prank(auctioneer);
        positionId = facility.create(
            account_,
            amount_,
            conversionPrice_,
            conversionExpiry_,
            redemptionExpiry_,
            wrap_
        );
    }

    modifier mintConvertibleDepositToken(address account_, uint256 amount_) {
        vm.prank(account_);
        convertibleDepository.mint(amount_);
        _;
    }

    modifier givenAddressHasPosition(address account_, uint256 amount_) {
        _createPosition(
            account_,
            amount_,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );
        _;
    }

    modifier givenConvertibleDepositTokenSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        vm.prank(owner_);
        convertibleDepository.approve(spender_, amount_);
        _;
    }

    modifier givenLocallyActive() {
        vm.prank(admin);
        facility.enable("");
        _;
    }

    modifier givenLocallyInactive() {
        vm.prank(emergency);
        facility.disable("");
        _;
    }

    modifier givenReserveTokenHasDecimals(uint8 decimals_) {
        reserveToken = new MockERC20("Reserve Token", "RES", decimals_);
        vault = new MockERC4626(reserveToken, "Vault", "VAULT");

        // Re-instantiate the CDEPO module
        convertibleDepository = new OlympusConvertibleDepository(
            address(kernel),
            address(vault),
            RECLAIM_RATE
        );

        // Upgrade the module
        kernel.executeAction(Actions.UpgradeModule, address(convertibleDepository));
        _;
    }

    // ========== ASSERTIONS ========== //

    function _expectRoleRevert(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
    }
}
