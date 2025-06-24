// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {CDFacility} from "src/policies/CDFacility.sol";
import {CDAuctioneer} from "src/policies/CDAuctioneer.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusDepositPositionManager} from "src/modules/DEPOS/OlympusDepositPositionManager.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {DepositManager} from "src/policies/DepositManager.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

// solhint-disable max-states-count
contract ConvertibleDepositAuctioneerTest is Test {
    Kernel public kernel;
    CDFacility public facility;
    CDAuctioneer public auctioneer;
    OlympusTreasury public treasury;
    OlympusMinter public minter;
    OlympusRoles public roles;
    OlympusDepositPositionManager public convertibleDepositPositions;
    RolesAdmin public rolesAdmin;
    DepositManager public depositManager;

    MockERC20 public ohm;
    MockERC20 public reserveToken;
    MockERC4626 public vault;
    IERC20 public iReserveToken;
    uint256 public receiptTokenId;

    address public recipient;
    address public emissionManager;
    address public admin;
    address public emergency;
    address public manager;

    uint48 public constant INITIAL_BLOCK = 1_000_000;

    // @dev This should result in multiple ticks being filled
    uint256 public constant BID_LARGE_AMOUNT = 3000e18;

    uint256 public constant TICK_SIZE = 10e9;
    uint24 public constant TICK_STEP = 110e2; // 110%
    uint256 public constant MIN_PRICE = 15e18;
    uint256 public constant TARGET = 20e9;
    uint8 public constant AUCTION_TRACKING_PERIOD = 7;
    uint16 public constant RECLAIM_RATE = 90e2;
    uint8 public constant PERIOD_MONTHS = 6;
    uint48 public constant CONVERSION_EXPIRY = INITIAL_BLOCK + (30 days) * PERIOD_MONTHS;

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

        // Addresses
        recipient = makeAddr("recipient");
        emissionManager = makeAddr("emissionManager");
        admin = makeAddr("admin");
        emergency = makeAddr("emergency");
        manager = makeAddr("manager");

        ohm = new MockERC20("Olympus", "OHM", 9);
        reserveToken = new MockERC20("Reserve Token", "RES", 18);
        vault = new MockERC4626(reserveToken, "Vault", "VAULT");
        vm.label(address(reserveToken), "RES");
        vm.label(address(vault), "sRES");
        iReserveToken = IERC20(address(reserveToken));

        _createStack();
    }

    // ========== HELPERS ========== //

    function _createStack() internal {
        // Instantiate bophades
        kernel = new Kernel();
        treasury = new OlympusTreasury(kernel);
        minter = new OlympusMinter(kernel, address(ohm));
        roles = new OlympusRoles(kernel);
        convertibleDepositPositions = new OlympusDepositPositionManager(
            address(kernel),
            address(0)
        );
        depositManager = new DepositManager(address(kernel));
        facility = new CDFacility(address(kernel), address(depositManager));
        auctioneer = new CDAuctioneer(address(kernel), address(facility));
        rolesAdmin = new RolesAdmin(kernel);

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.InstallModule, address(minter));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(convertibleDepositPositions));
        kernel.executeAction(Actions.ActivatePolicy, address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(facility));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Grant roles
        rolesAdmin.grantRole(bytes32("cd_emissionmanager"), emissionManager);
        rolesAdmin.grantRole(bytes32("admin"), admin);
        rolesAdmin.grantRole(bytes32("emergency"), emergency);
        rolesAdmin.grantRole(bytes32("manager"), manager);
        rolesAdmin.grantRole(bytes32("deposit_operator"), address(facility));
        rolesAdmin.grantRole(bytes32("cd_auctioneer"), address(auctioneer));

        // Enable the deposit manager policy
        vm.prank(admin);
        depositManager.enable("");

        // Enable the facility
        vm.prank(admin);
        facility.enable("");

        // Create a receipt token
        // Required at the time of activation of the auctioneer policy
        vm.startPrank(admin);
        depositManager.configureAssetVault(iReserveToken, IERC4626(address(vault)));

        depositManager.addDepositConfiguration(iReserveToken, PERIOD_MONTHS, 90e2);

        receiptTokenId = depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS);
        vm.stopPrank();

        // Activate the auctioneer policy
        kernel.executeAction(Actions.ActivatePolicy, address(auctioneer));
    }

    function _expectRoleRevert(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
    }

    function _expectRevertNotAuthorised() internal {
        vm.expectRevert(abi.encodeWithSelector(PolicyAdmin.NotAuthorised.selector));
    }

    function _expectNotEnabledRevert() internal {
        vm.expectRevert(PolicyEnabler.NotEnabled.selector);
    }

    function _expectNotDisabledRevert() internal {
        vm.expectRevert(PolicyEnabler.NotDisabled.selector);
    }

    function _expectDepositAssetAndPeriodNotEnabledRevert(
        IERC20 depositAsset_,
        uint8 depositPeriod_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_DepositPeriodNotEnabled.selector,
                address(depositAsset_),
                depositPeriod_
            )
        );
    }

    function _assertAuctionParameters(
        uint256 target_,
        uint256 tickSize_,
        uint256 minPrice_
    ) internal view {
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
    ) internal view {
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getPreviousTick(
            iReserveToken,
            PERIOD_MONTHS
        );

        assertEq(tick.capacity, capacity_, "previous tick capacity");
        assertEq(tick.price, price_, "previous tick price");
        assertEq(tick.lastUpdate, lastUpdate_, "previous tick lastUpdate");

        assertEq(auctioneer.getCurrentTickSize(), tickSize_, "current tick size");
    }

    function _assertDayState(uint256 convertible_) internal view {
        IConvertibleDepositAuctioneer.Day memory day = auctioneer.getDayState();

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
    ) internal view {
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

    function _assertAuctionResultsEmpty(uint8 length_) internal view {
        int256[] memory auctionResults = auctioneer.getAuctionResults();

        assertEq(auctionResults.length, length_, "auction results length");
        for (uint256 i = 0; i < auctionResults.length; i++) {
            assertEq(auctionResults[i], 0, string.concat("result ", vm.toString(i)));
        }
    }

    function _assertAuctionResults(int256[] memory auctionResults_) internal view {
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

    function _assertAuctionResultsNextIndex(uint8 nextIndex_) internal view {
        assertEq(auctioneer.getAuctionResultsNextIndex(), nextIndex_, "next index");
    }

    function _assertDepositAssetAndPeriodEnabled(
        IERC20 depositAsset_,
        uint8 depositPeriod_,
        uint256 otherDepositAssetCount_,
        uint256 otherDepositPeriodCount_,
        uint256 totalDepositAssetAndPeriodCount_
    ) internal view {
        // Check the deposit asset is enabled
        assertEq(
            auctioneer.isDepositEnabled(depositAsset_, depositPeriod_),
            true,
            "deposit asset and period enabled"
        );

        // Check that the deposit asset is listed
        IERC20[] memory depositAssets = auctioneer.getDepositAssets();
        assertEq(depositAssets.length, otherDepositAssetCount_ + 1, "deposit assets length");
        bool depositAssetFound = false;
        for (uint256 i = 0; i < depositAssets.length; i++) {
            if (depositAssets[i] == depositAsset_) {
                depositAssetFound = true;
                break;
            }
        }
        assertEq(depositAssetFound, true, "deposit asset found");

        // Check that the deposit period is listed
        uint8[] memory depositPeriods = auctioneer.getDepositPeriods(depositAsset_);
        assertEq(depositPeriods.length, otherDepositPeriodCount_ + 1, "deposit periods length");
        bool depositPeriodFound = false;
        for (uint256 i = 0; i < depositPeriods.length; i++) {
            if (depositPeriods[i] == depositPeriod_) {
                depositPeriodFound = true;
                break;
            }
        }
        assertEq(depositPeriodFound, true, "deposit period found");

        // Check that the total is correct
        assertEq(
            auctioneer.getDepositAssetsAndPeriodsCount(),
            totalDepositAssetAndPeriodCount_,
            "deposit assets and periods count"
        );
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

    modifier givenWrappedReceiptTokenSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        IERC20 wrappedReceiptToken = IERC20(depositManager.getWrappedToken(receiptTokenId));

        vm.prank(owner_);
        wrappedReceiptToken.approve(spender_, amount_);
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
        // Irrespective of the current block timestamp, this will shift to the next period (day)
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
        auctioneer.bid(iReserveToken, PERIOD_MONTHS, deposit_, false, false);
    }

    function _mintAndBid(address owner_, uint256 deposit_) internal {
        // Mint
        _mintReserveToken(owner_, deposit_);

        // Approve spending
        _approveReserveTokenSpending(owner_, address(depositManager), deposit_);

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
        iReserveToken = IERC20(address(reserveToken));

        // Re-create the stack
        _createStack();
        _;
    }

    modifier givenDepositAssetAndPeriodEnabled(IERC20 depositAsset_, uint8 depositPeriod_) {
        vm.prank(admin);
        auctioneer.enableDepositPeriod(depositAsset_, depositPeriod_);
        _;
    }

    modifier givenDepositAssetAndPeriodDisabled(IERC20 depositAsset_, uint8 depositPeriod_) {
        vm.prank(admin);
        auctioneer.disableDepositPeriod(depositAsset_, depositPeriod_);
        _;
    }
}
