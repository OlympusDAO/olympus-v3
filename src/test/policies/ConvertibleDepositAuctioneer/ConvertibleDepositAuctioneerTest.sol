// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {CDFacility} from "src/policies/CDFacility.sol";
import {CDAuctioneer} from "src/policies/CDAuctioneer.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusConvertibleDepository} from "src/modules/CDEPO/OlympusConvertibleDepository.sol";
import {OlympusConvertibleDepositPositions} from "src/modules/CDPOS/OlympusConvertibleDepositPositions.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

// solhint-disable max-states-count
contract ConvertibleDepositAuctioneerTest is Test {
    Kernel public kernel;
    CDFacility public facility;
    CDAuctioneer public auctioneer;
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
    address public recipientTwo = address(0x2);
    address public heart = address(0x3);
    address public admin = address(0x4);
    address public emergency = address(0x5);

    uint48 public constant INITIAL_BLOCK = 1_000_000;
    uint256 public constant CONVERSION_PRICE = 2e18;
    uint48 public constant EXPIRY = INITIAL_BLOCK + 1 days;
    uint256 public constant RESERVE_TOKEN_AMOUNT = 10e18;

    uint256 public constant TICK_SIZE = 10e9;
    uint256 public constant TICK_STEP = 9e17; // 90%
    uint256 public constant MIN_PRICE = 15e18;
    uint256 public constant TARGET = 20e9;
    uint256 public constant TIME_TO_EXPIRY = 1 days;

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
        auctioneer = new CDAuctioneer(address(kernel), address(facility));
        rolesAdmin = new RolesAdmin(kernel);

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.InstallModule, address(minter));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(convertibleDepository));
        kernel.executeAction(Actions.InstallModule, address(convertibleDepositPositions));
        kernel.executeAction(Actions.ActivatePolicy, address(facility));
        kernel.executeAction(Actions.ActivatePolicy, address(auctioneer));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Grant roles
        rolesAdmin.grantRole(bytes32("heart"), heart);
        rolesAdmin.grantRole(bytes32("cd_admin"), admin);
        rolesAdmin.grantRole(bytes32("emergency_shutdown"), emergency);
    }

    // ========== HELPERS ========== //

    function _expectRoleRevert(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
    }

    function _assertState(
        uint256 target_,
        uint256 tickSize_,
        uint256 minPrice_,
        uint256 tickStep_,
        uint48 timeToExpiry_,
        uint48 lastUpdate_
    ) internal {
        IConvertibleDepositAuctioneer.State memory state = auctioneer.getState();

        assertEq(state.target, target_);
        assertEq(state.tickSize, tickSize_);
        assertEq(state.minPrice, minPrice_);
        assertEq(state.tickStep, tickStep_);
        assertEq(state.timeToExpiry, timeToExpiry_);
        assertEq(state.lastUpdate, lastUpdate_);
    }

    // ========== MODIFIERS ========== //

    modifier givenContractActive() {
        vm.prank(emergency);
        auctioneer.activate();
        _;
    }

    modifier givenContractInactive() {
        vm.prank(emergency);
        auctioneer.deactivate();
        _;
    }

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

    modifier givenConvertibleDepositTokenSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        vm.prank(owner_);
        convertibleDepository.approve(spender_, amount_);
        _;
    }

    modifier givenTimeToExpiry(uint48 timeToExpiry_) {
        vm.prank(admin);
        auctioneer.setTimeToExpiry(timeToExpiry_);
        _;
    }

    modifier givenTickStep(uint256 tickStep_) {
        vm.prank(admin);
        auctioneer.setTickStep(tickStep_);
        _;
    }

    function _setAuctionParameters(uint256 target_, uint256 tickSize_, uint256 minPrice_) internal {
        vm.prank(heart);
        auctioneer.setAuctionParameters(target_, tickSize_, minPrice_);
    }

    modifier givenAuctionParametersStandard() {
        _setAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);
        _;
    }

    modifier givenAuctionParameters(
        uint256 target_,
        uint256 tickSize_,
        uint256 minPrice_
    ) {
        _setAuctionParameters(target_, tickSize_, minPrice_);
        _;
    }
}
