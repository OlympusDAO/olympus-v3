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

    uint48 public constant INITIAL_BLOCK = 1_000_000;
    uint256 public constant CONVERSION_PRICE = 2e18;
    uint48 public constant EXPIRY = INITIAL_BLOCK + 1 days;

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
        convertibleDepository = new OlympusConvertibleDepository(address(kernel), address(vault));
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
        rolesAdmin.grantRole(bytes32("CD_Auctioneer"), auctioneer);
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
        uint48 expiry_,
        bool wrap_
    ) internal {
        vm.prank(auctioneer);
        facility.create(account_, amount_, conversionPrice_, expiry_, wrap_);
    }

    modifier givenAddressHasPosition(address account_, uint256 amount_) {
        _createPosition(account_, amount_, CONVERSION_PRICE, EXPIRY, false);
        _;
    }
}
