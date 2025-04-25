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
import {YieldDepositFacility} from "src/policies/YieldDepositFacility.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusConvertibleDepository} from "src/modules/CDEPO/OlympusConvertibleDepository.sol";
import {OlympusConvertibleDepositPositionManager} from "src/modules/CDPOS/OlympusConvertibleDepositPositionManager.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

// solhint-disable max-states-count
contract ConvertibleDepositFacilityTest is Test {
    Kernel public kernel;
    CDFacility public facility;
    YieldDepositFacility public yieldDepositFacility;
    OlympusTreasury public treasury;
    OlympusMinter public minter;
    OlympusRoles public roles;
    OlympusConvertibleDepository public convertibleDepository;
    OlympusConvertibleDepositPositionManager public convertibleDepositPositions;
    RolesAdmin public rolesAdmin;

    MockERC20 public ohm;
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
    uint256 public constant CONVERSION_PRICE = 2e18;
    uint256 public constant RESERVE_TOKEN_AMOUNT = 10e18;
    uint16 public constant RECLAIM_RATE = 90e2;
    uint8 public constant PERIOD_MONTHS = 6;
    uint48 public constant CONVERSION_EXPIRY = INITIAL_BLOCK + (30 days) * PERIOD_MONTHS;

    function setUp() public {
        vm.warp(INITIAL_BLOCK);

        ohm = new MockERC20("Olympus", "OHM", 9);
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
    }

    function _createStack() internal {
        kernel = new Kernel();
        treasury = new OlympusTreasury(kernel);
        minter = new OlympusMinter(kernel, address(ohm));
        roles = new OlympusRoles(kernel);
        convertibleDepository = new OlympusConvertibleDepository(kernel);
        convertibleDepositPositions = new OlympusConvertibleDepositPositionManager(address(kernel));
        facility = new CDFacility(address(kernel));
        yieldDepositFacility = new YieldDepositFacility(address(kernel));
        rolesAdmin = new RolesAdmin(kernel);

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.InstallModule, address(minter));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(convertibleDepository));
        kernel.executeAction(Actions.InstallModule, address(convertibleDepositPositions));
        kernel.executeAction(Actions.ActivatePolicy, address(facility));
        kernel.executeAction(Actions.ActivatePolicy, address(yieldDepositFacility));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Grant roles
        rolesAdmin.grantRole(bytes32("cd_auctioneer"), auctioneer);
        rolesAdmin.grantRole(bytes32("emergency"), emergency);
        rolesAdmin.grantRole(bytes32("admin"), admin);

        // Enable the facility
        vm.prank(admin);
        facility.enable("");

        // Create a CD token
        vm.startPrank(admin);
        cdToken = facility.create(IERC4626(address(vault)), PERIOD_MONTHS, 90e2);
        vm.stopPrank();
        vm.label(address(cdToken), "cdToken");

        // Create a CD token
        vm.startPrank(admin);
        cdTokenTwo = facility.create(IERC4626(address(vaultTwo)), PERIOD_MONTHS, 90e2);
        vm.stopPrank();
        vm.label(address(cdTokenTwo), "cdTokenTwo");

        // Disable the facility
        vm.prank(emergency);
        facility.disable("");

        // Enable the yield deposit facility
        vm.prank(admin);
        yieldDepositFacility.enable("");
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
        bool wrap_
    ) internal returns (uint256 positionId) {
        return _createPosition(cdToken, account_, amount_, conversionPrice_, wrap_);
    }

    function _createPosition(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        bool wrap_
    ) internal returns (uint256 positionId) {
        vm.prank(auctioneer);
        positionId = facility.mint(cdToken_, account_, amount_, conversionPrice_, wrap_);
    }

    modifier mintConvertibleDepositToken(address account_, uint256 amount_) {
        vm.prank(account_);
        convertibleDepository.mint(cdToken, amount_);
        _;
    }

    modifier givenAddressHasConvertibleDepositToken(
        address account_,
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) {
        MockERC20 underlyingToken = MockERC20(address(cdToken_.asset()));

        // Mint reserve tokens to the account
        underlyingToken.mint(account_, amount_);

        // Approve CDEPO to spend the reserve tokens
        vm.prank(account_);
        underlyingToken.approve(address(convertibleDepository), amount_);

        // Mint the CD token to the account
        vm.prank(account_);
        convertibleDepository.mint(cdToken_, amount_);
        _;
    }

    modifier givenAddressHasPosition(address account_, uint256 amount_) {
        _createPosition(account_, amount_, CONVERSION_PRICE, false);
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

    modifier givenAddressHasDifferentTokenAndPosition(address account_, uint256 amount_) {
        // Mint
        reserveTokenTwo.mint(account_, amount_);

        // Approve
        vm.prank(account_);
        reserveTokenTwo.approve(address(convertibleDepository), amount_);

        // Create position
        _createPosition(cdTokenTwo, account_, amount_, CONVERSION_PRICE, false);
        _;
    }

    modifier givenConvertibleDepositTokenSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        vm.prank(owner_);
        cdToken.approve(spender_, amount_);
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
        iReserveToken = IERC20(address(reserveToken));
        vault = new MockERC4626(reserveToken, "Vault", "VAULT");

        _createStack();
        _;
    }

    modifier givenCommitted(
        address user_,
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) {
        // Mint reserve tokens to the user
        MockERC20 underlyingToken = MockERC20(address(cdToken_.asset()));
        underlyingToken.mint(user_, amount_);

        // Approve spending of the reserve tokens
        vm.prank(user_);
        underlyingToken.approve(address(convertibleDepository), amount_);

        // Mint the CD token to the user
        vm.prank(user_);
        convertibleDepository.mint(cdToken_, amount_);

        // Approve spending of the CD token
        vm.prank(user_);
        cdToken_.approve(address(facility), amount_);

        // Commit
        vm.prank(user_);
        facility.commitRedeem(cdToken_, amount_);
        _;
    }

    modifier givenRedeemed(address user_, uint16 commitmentId_) {
        vm.prank(user_);
        facility.redeem(commitmentId_);
        _;
    }

    // ========== ASSERTIONS ========== //

    function _expectRoleRevert(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
    }

    function _assertMintApproval(uint256 expected_) internal {
        assertEq(
            minter.mintApproval(address(facility)),
            expected_,
            "minter.mintApproval(address(facility))"
        );
    }
}
