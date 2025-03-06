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
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

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
    address public emissionManager = address(0x3);
    address public admin = address(0x4);
    address public emergency = address(0x5);

    uint48 public constant INITIAL_BLOCK = 1_000_000;

    // @dev This should result in multiple ticks being filled
    uint256 public constant BID_LARGE_AMOUNT = 3000e18;

    uint256 public constant TICK_SIZE = 10e9;
    uint24 public constant TICK_STEP = 110e2; // 110%
    uint256 public constant MIN_PRICE = 15e18;
    uint256 public constant TARGET = 20e9;
    uint48 public constant TIME_TO_EXPIRY = 1 days;
    uint48 public constant REDEMPTION_PERIOD = 2 days;
    uint8 public constant AUCTION_TRACKING_PERIOD = 7;
    uint16 public constant RECLAIM_RATE = 90e2;

    // Events
    event Enabled();
    event Disabled();
    event TickStepUpdated(uint24 newTickStep);
    event TimeToExpiryUpdated(uint48 newTimeToExpiry);
    event RedemptionPeriodUpdated(uint48 newRedemptionPeriod);
    event AuctionParametersUpdated(uint256 newTarget, uint256 newTickSize, uint256 newMinPrice);
    event AuctionTrackingPeriodUpdated(uint8 newAuctionTrackingPeriod);
    event AuctionResult(uint256 ohmConvertible, uint256 target, uint8 periodIndex);

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
        rolesAdmin.grantRole(bytes32("cd_emissionmanager"), emissionManager);
        rolesAdmin.grantRole(bytes32("admin"), admin);
        rolesAdmin.grantRole(bytes32("emergency"), emergency);
        rolesAdmin.grantRole(bytes32("cd_auctioneer"), address(auctioneer));

        // Activate policy dependencies
        vm.prank(admin);
        facility.enable("");
    }

    // ========== HELPERS ========== //

    function _expectRoleRevert(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
    }

    function _expectNotEnabledRevert() internal {
        vm.expectRevert(PolicyEnabler.NotEnabled.selector);
    }

    function _expectNotDisabledRevert() internal {
        vm.expectRevert(PolicyEnabler.NotDisabled.selector);
    }

    function _assertAuctionParameters(
        uint256 target_,
        uint256 tickSize_,
        uint256 minPrice_
    ) internal {
        IConvertibleDepositAuctioneer.AuctionParameters memory auctionParameters = auctioneer
            .getAuctionParameters();

        assertEq(auctionParameters.target, target_, "target");
        assertEq(auctionParameters.tickSize, tickSize_, "tickSize");
        assertEq(auctionParameters.minPrice, minPrice_, "minPrice");
    }

    function _assertPreviousTick(
        uint256 capacity_,
        uint256 price_,
        uint256 tickSize_,
        uint48 lastUpdate_
    ) internal {
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getPreviousTick();

        assertEq(tick.capacity, capacity_, "previous tick capacity");
        assertEq(tick.price, price_, "previous tick price");
        assertEq(tick.tickSize, tickSize_, "previous tick size");
        assertEq(tick.lastUpdate, lastUpdate_, "previous tick lastUpdate");
    }

    function _assertDayState(uint256 deposits_, uint256 convertible_) internal {
        IConvertibleDepositAuctioneer.Day memory day = auctioneer.getDayState();

        assertEq(day.deposits, deposits_, "deposits");
        assertEq(day.convertible, convertible_, "convertible");
    }

    function _assertAuctionResults(
        int256 resultOne_,
        int256 resultTwo_,
        int256 resultThree_,
        int256 resultFour_,
        int256 resultFive_,
        int256 resultSix_,
        int256 resultSeven_
    ) internal {
        int256[] memory auctionResults = auctioneer.getAuctionResults();

        assertEq(auctionResults.length, 7, "auction results length");
        assertEq(auctionResults[0], resultOne_, "result one");
        assertEq(auctionResults[1], resultTwo_, "result two");
        assertEq(auctionResults[2], resultThree_, "result three");
        assertEq(auctionResults[3], resultFour_, "result four");
        assertEq(auctionResults[4], resultFive_, "result five");
        assertEq(auctionResults[5], resultSix_, "result six");
        assertEq(auctionResults[6], resultSeven_, "result seven");
    }

    function _assertAuctionResultsEmpty(uint8 length_) internal {
        int256[] memory auctionResults = auctioneer.getAuctionResults();

        assertEq(auctionResults.length, length_, "auction results length");
        for (uint256 i = 0; i < auctionResults.length; i++) {
            assertEq(auctionResults[i], 0, string.concat("result ", vm.toString(i)));
        }
    }

    function _assertAuctionResults(int256[] memory auctionResults_) internal {
        int256[] memory auctionResults = auctioneer.getAuctionResults();

        assertEq(auctionResults.length, auctionResults_.length, "auction results length");
        for (uint256 i = 0; i < auctionResults.length; i++) {
            assertEq(
                auctionResults[i],
                auctionResults_[i],
                string.concat("result ", vm.toString(i))
            );
        }
    }

    function _assertAuctionResultsNextIndex(uint8 nextIndex_) internal {
        assertEq(auctioneer.getAuctionResultsNextIndex(), nextIndex_, "next index");
    }

    // ========== MODIFIERS ========== //

    modifier givenEnabled() {
        vm.prank(admin);
        auctioneer.enable(
            abi.encode(
                IConvertibleDepositAuctioneer.EnableParams({
                    target: TARGET,
                    tickSize: TICK_SIZE,
                    minPrice: MIN_PRICE,
                    tickStep: TICK_STEP,
                    timeToExpiry: TIME_TO_EXPIRY,
                    redemptionPeriod: REDEMPTION_PERIOD,
                    auctionTrackingPeriod: AUCTION_TRACKING_PERIOD
                })
            )
        );
        _;
    }

    modifier givenEnabledWithParameters(
        uint256 target_,
        uint256 tickSize_,
        uint256 minPrice_
    ) {
        vm.prank(admin);
        auctioneer.enable(
            abi.encode(
                IConvertibleDepositAuctioneer.EnableParams({
                    target: target_,
                    tickSize: tickSize_,
                    minPrice: minPrice_,
                    tickStep: TICK_STEP,
                    timeToExpiry: TIME_TO_EXPIRY,
                    redemptionPeriod: REDEMPTION_PERIOD,
                    auctionTrackingPeriod: AUCTION_TRACKING_PERIOD
                })
            )
        );
        _;
    }

    modifier givenDisabled() {
        vm.prank(emergency);
        auctioneer.disable("");
        _;
    }

    function _mintReserveToken(address to_, uint256 amount_) internal {
        reserveToken.mint(to_, amount_);
    }

    modifier givenAddressHasReserveToken(address to_, uint256 amount_) {
        _mintReserveToken(to_, amount_);
        _;
    }

    function _approveReserveTokenSpending(
        address owner_,
        address spender_,
        uint256 amount_
    ) internal {
        vm.prank(owner_);
        reserveToken.approve(spender_, amount_);
    }

    modifier givenReserveTokenSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        _approveReserveTokenSpending(owner_, spender_, amount_);
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

    modifier givenTickStep(uint24 tickStep_) {
        vm.prank(admin);
        auctioneer.setTickStep(tickStep_);
        _;
    }

    function _setAuctionParameters(uint256 target_, uint256 tickSize_, uint256 minPrice_) internal {
        vm.prank(emissionManager);
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

    function _bid(address owner_, uint256 deposit_) internal {
        vm.prank(owner_);
        auctioneer.bid(deposit_);
    }

    function _mintAndBid(address owner_, uint256 deposit_) internal {
        // Mint
        _mintReserveToken(owner_, deposit_);

        // Approve spending
        _approveReserveTokenSpending(owner_, address(convertibleDepository), deposit_);

        // Bid
        _bid(owner_, deposit_);
    }

    modifier givenRecipientHasBid(uint256 deposit_) {
        _mintAndBid(recipient, deposit_);
        _;
    }

    modifier givenReserveTokenHasDecimals(uint8 decimals_) {
        // Create the tokens
        reserveToken = new MockERC20("Reserve Token", "RES", decimals_);
        vault = new MockERC4626(reserveToken, "Vault", "VAULT");

        // Re-instantiate the module
        convertibleDepository = new OlympusConvertibleDepository(
            address(kernel),
            address(vault),
            RECLAIM_RATE
        );

        // Upgrade the module
        kernel.executeAction(Actions.UpgradeModule, address(convertibleDepository));
        _;
    }
}
