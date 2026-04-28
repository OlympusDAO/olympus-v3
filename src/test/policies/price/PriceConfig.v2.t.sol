// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
// solhint-disable custom-errors
/// forge-lint: disable-start(mixed-case-variable,mixed-case-function,unwrapped-modifier-logic)
pragma solidity >=0.8.0;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {UserFactory} from "src/test/lib/UserFactory.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";

// Mocks
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "src/test/mocks/MockPriceFeed.sol";

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Bophades
import {Actions, fromKeycode, Kernel, Keycode, Module, Permissions, toKeycode} from "src/Kernel.sol";
import {fromSubKeycode, ModuleWithSubmodules, SubKeycode, Submodule, toSubKeycode} from "src/Submodules.sol";
import {PriceConfigv2} from "src/policies/price/PriceConfig.v2.sol";
import {PriceSubmodule} from "src/modules/PRICE/PRICE.v2.sol";
import {OlympusPricev1_2} from "src/modules/PRICE/OlympusPrice.v1_2.sol";
import {OlympusPricev2} from "src/modules/PRICE/OlympusPrice.v2.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {SimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {MockInvalidSubmodule} from "src/test/mocks/MockInvalidSubmodule.sol";
import {MockSubmoduleNoERC165} from "src/test/mocks/MockSubmoduleNoERC165.sol";

// Tests for PriceConfig v1.0.0
//
// PriceConfig Setup and Permissions
// [X] configureDependencies
// [X] requestPermissions
// [X] disabled by default
//
// PRICEv2 Configuration
// [X] addAsset
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call
//     [X] inputs to IPRICEv2.addAsset are correct
// [X] queueRemoveAsset
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call
//     [X] inputs to IPRICEv2.removeAsset are correct
// [X] queueUpdateAsset
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call
//     [X] inputs to IPRICEv2.updateAsset are correct
//
// PRICEv2 Submodule Installation/Upgrade
// [X] installSubmodule
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call
//     [X] inputs to IPRICEv2.installSubmodule are correct
// [X] queueUpgradeSubmodule
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call
//     [X] inputs to IPRICEv2.upgradeSubmodule are correct
// [X] execOnSubmodule
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call

type Category is bytes32;
type CategoryGroup is bytes32;

enum QueuedActionCase {
    RemoveAsset,
    UpdateAsset,
    UpgradeSubmodule,
    TimelockDelay
}

contract MockStrategy is PriceSubmodule {
    uint256 public storedValue;

    constructor(Module parent_) Submodule(parent_) {}

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.MOCKSTRATEGY");
    }

    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    function getOnePrice() external pure returns (uint256) {
        return 1;
    }

    function setStoredValue(uint256 value_) external onlyParent {
        storedValue = value_;
    }
}

contract MockUpgradedSubmodulePrice is PriceSubmodule {
    constructor(Module parent_) Submodule(parent_) {}

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.CHAINLINK");
    }

    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }
}

contract PriceConfigv2Test is Test {
    MockPriceFeed internal ohmUsdPriceFeed;
    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal reserveUsdPriceFeed;
    MockPriceFeed internal reserveEthPriceFeed;
    MockPriceFeed internal ethUsdPriceFeed;

    MockERC20 internal ohm;
    MockERC20 internal _reserve;

    Kernel internal kernel;
    PriceConfigv2 internal priceConfig;
    OlympusPricev2 internal PRICE;
    RolesAdmin internal rolesAdmin;
    OlympusRoles internal ROLES;
    ChainlinkPriceFeeds internal chainlinkPrice;
    SimplePriceFeedStrategy internal strategy;

    address internal admin;
    address internal priceManager;
    address internal emergency;

    int256 internal constant CHANGE_DECIMALS = 1e4;
    uint32 internal constant OBSERVATION_FREQUENCY = 8 hours;
    uint8 internal constant DECIMALS = 18;
    address internal constant _UNIT_OF_ACCOUNT = address(840);

    bytes32 internal constant ROLE_ADMIN = "admin";
    bytes32 internal constant ROLE_PRICE_ADMIN = "price_admin";
    bytes32 internal constant ROLE_EMERGENCY = "emergency";

    uint48 internal constant TIMELOCK_DELAY = 1 days;
    uint48 internal constant EXECUTION_WINDOW = 7 days;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Create accounts
        UserFactory userFactory = new UserFactory();
        address[] memory users = userFactory.create(3);
        admin = users[0];
        priceManager = users[1];
        emergency = users[2];

        // Tokens
        ohm = new MockERC20("Olympus", "OHM", 9);
        _reserve = new MockERC20("Reserve", "RSV", 18);

        // Price Feeds
        ethUsdPriceFeed = new MockPriceFeed();
        ethUsdPriceFeed.setDecimals(8);
        ethUsdPriceFeed.setLatestAnswer(int256(2000e8));
        ethUsdPriceFeed.setTimestamp(block.timestamp);
        ethUsdPriceFeed.setRoundId(1);
        ethUsdPriceFeed.setAnsweredInRound(1);

        ohmUsdPriceFeed = new MockPriceFeed();
        ohmUsdPriceFeed.setDecimals(8);
        ohmUsdPriceFeed.setLatestAnswer(int256(10e8));
        ohmUsdPriceFeed.setTimestamp(block.timestamp);
        ohmUsdPriceFeed.setRoundId(1);
        ohmUsdPriceFeed.setAnsweredInRound(1);

        ohmEthPriceFeed = new MockPriceFeed();
        ohmEthPriceFeed.setDecimals(18);
        ohmEthPriceFeed.setLatestAnswer(int256(0.005e18));
        ohmEthPriceFeed.setTimestamp(block.timestamp);
        ohmEthPriceFeed.setRoundId(1);
        ohmEthPriceFeed.setAnsweredInRound(1);

        reserveUsdPriceFeed = new MockPriceFeed();
        reserveUsdPriceFeed.setDecimals(8);
        reserveUsdPriceFeed.setLatestAnswer(int256(1e8));
        reserveUsdPriceFeed.setTimestamp(block.timestamp);
        reserveUsdPriceFeed.setRoundId(1);
        reserveUsdPriceFeed.setAnsweredInRound(1);

        // Deploy system contracts
        kernel = new Kernel();
        PRICE = new OlympusPricev2(kernel, DECIMALS, OBSERVATION_FREQUENCY);
        ROLES = new OlympusRoles(kernel);
        priceConfig = new PriceConfigv2(kernel);
        rolesAdmin = new RolesAdmin(kernel);

        // Deploy submodules for PRICE
        chainlinkPrice = new ChainlinkPriceFeeds(PRICE);
        strategy = new SimplePriceFeedStrategy(PRICE);

        // Install contracts on kernel
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.InstallModule, address(PRICE));
        kernel.executeAction(Actions.ActivatePolicy, address(priceConfig));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Configure permissioned roles
        rolesAdmin.grantRole(ROLE_ADMIN, admin);
        rolesAdmin.grantRole(ROLE_PRICE_ADMIN, priceManager);
        rolesAdmin.grantRole(ROLE_EMERGENCY, emergency);

        // Install base submodules on PRICE
        vm.startPrank(admin);
        priceConfig.installSubmodule(address(chainlinkPrice));
        priceConfig.installSubmodule(address(strategy));
        vm.stopPrank();
    }

    /* ========== Helper Functions ========== */

    function _makeObservations(
        MockERC20 asset,
        IPRICEv2.Component memory feed,
        uint256 numObs
    ) internal view returns (uint256[] memory) {
        // Get current price from feed
        (bool success, bytes memory data) = address(PRICE.getSubmoduleForKeycode(feed.target))
            .staticcall(
                abi.encodeWithSelector(feed.selector, address(asset), PRICE.decimals(), feed.params)
            );

        require(success, "Price feed call failed");
        int256 fetchedPrice = int256(abi.decode(data, (uint256)));

        /// Perform a random walk and create observations array
        uint256[] memory obs = new uint256[](numObs);
        int256 change; // percentage with two decimals
        for (uint256 i = numObs; i > 0; --i) {
            // Add current price to obs array
            /// forge-lint: disable-next-line(unsafe-typecast)
            obs[i - 1] = uint256(fetchedPrice);

            /// Calculate a random percentage change from -10% to + 10% using the nonce and observation number
            change = int256(uint256(keccak256(abi.encodePacked(i)))) % int256(1000);

            /// Calculate the new ohmEth price
            fetchedPrice = (fetchedPrice * (CHANGE_DECIMALS + change)) / CHANGE_DECIMALS;
        }

        return obs;
    }

    function _makeFeedExpectations(
        uint256 count_,
        uint256 expectedPrice_,
        uint16 toleranceBps_
    ) internal pure returns (IPriceConfigv2.PriceFeedExpectation[] memory) {
        IPriceConfigv2.PriceFeedExpectation[]
            memory expectations = new IPriceConfigv2.PriceFeedExpectation[](count_);

        for (uint256 i; i < count_; i++) {
            expectations[i] = IPriceConfigv2.PriceFeedExpectation({
                expectedPrice: expectedPrice_,
                toleranceBps: toleranceBps_
            });
        }

        return expectations;
    }

    function _warpPastTimelockDelay() internal {
        vm.warp(block.timestamp + TIMELOCK_DELAY);
    }

    function _refreshPriceFeedTimestamps(uint256 timestamp_) internal {
        ethUsdPriceFeed.setTimestamp(timestamp_);
        ohmUsdPriceFeed.setTimestamp(timestamp_);
        ohmEthPriceFeed.setTimestamp(timestamp_);
        reserveUsdPriceFeed.setTimestamp(timestamp_);
    }

    function _executeQueuedAction(uint256 actionId_) internal {
        _warpPastTimelockDelay();
        priceConfig.executeQueuedAction(actionId_);
    }

    function _queueAndExecuteUpdateAsset(
        address asset_,
        IPRICEv2.UpdateAssetParams memory params_,
        IPriceConfigv2.PriceFeedExpectation[] memory expectations_
    ) internal returns (uint256 actionId_) {
        vm.prank(priceManager);
        actionId_ = priceConfig.queueUpdateAsset(asset_, params_, expectations_);
        _executeQueuedAction(actionId_);
    }

    function _makeFeedOnlyUpdateParams() internal view returns (IPRICEv2.UpdateAssetParams memory) {
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        IPRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](1),
            strategy: IPRICEv2.Component(SubKeycode.wrap(bytes20(0)), bytes4(0), bytes("")),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: 0,
            lastObservationTime: 0,
            observations: new uint256[](0)
        });
        params.feeds[0] = feeds[0];

        return params;
    }

    function _makeStrategyOnlyUpdateParams()
        internal
        view
        returns (IPRICEv2.UpdateAssetParams memory)
    {
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        IPRICEv2.Component memory strategyComponent = abi.decode(
            asset.strategy,
            (IPRICEv2.Component)
        );

        return
            IPRICEv2.UpdateAssetParams({
                updateFeeds: false,
                updateStrategy: true,
                updateMovingAverage: false,
                feeds: new IPRICEv2.Component[](0),
                strategy: strategyComponent,
                useMovingAverage: asset.useMovingAverage,
                storeMovingAverage: false,
                movingAverageDuration: 0,
                lastObservationTime: 0,
                observations: new uint256[](0)
            });
    }

    function _queueActionCase(QueuedActionCase actionCase_) internal returns (uint256 actionId_) {
        if (actionCase_ == QueuedActionCase.RemoveAsset) {
            _addBaseAssets();

            vm.prank(priceManager);
            return priceConfig.queueRemoveAsset(address(ohm));
        }

        if (actionCase_ == QueuedActionCase.UpdateAsset) {
            _addBaseAssets();

            IPRICEv2.UpdateAssetParams memory params = _makeStrategyOnlyUpdateParams();

            vm.prank(priceManager);
            return
                priceConfig.queueUpdateAsset(
                    address(ohm),
                    params,
                    new IPriceConfigv2.PriceFeedExpectation[](0)
                );
        }

        if (actionCase_ == QueuedActionCase.UpgradeSubmodule) {
            MockUpgradedSubmodulePrice newChainlink = new MockUpgradedSubmodulePrice(PRICE);

            vm.prank(admin);
            return priceConfig.queueUpgradeSubmodule(address(newChainlink));
        }

        vm.prank(admin);
        return priceConfig.queueTimelockDelay(2 days);
    }

    function _expectQueuedAction(
        IPriceConfigv2.TimelockAction action_,
        address proposer_,
        bytes memory payload_
    )
        internal
        returns (
            uint256 expectedActionId_,
            uint48 queuedAt_,
            uint48 executableAt_,
            uint48 expiresAt_
        )
    {
        expectedActionId_ = priceConfig.nextActionId();
        queuedAt_ = uint48(block.timestamp);
        executableAt_ = queuedAt_ + priceConfig.timelockDelay();
        expiresAt_ = executableAt_ + EXECUTION_WINDOW;

        vm.expectEmit(true, true, true, true);
        emit IPriceConfigv2.PriceConfigActionQueued(
            expectedActionId_,
            action_,
            proposer_,
            keccak256(payload_),
            executableAt_,
            expiresAt_
        );
    }

    function _assertQueuedAction(
        uint256 actionId_,
        uint256 expectedActionId_,
        IPriceConfigv2.TimelockAction action_,
        address proposer_,
        uint48 queuedAt_,
        uint48 executableAt_,
        uint48 expiresAt_,
        bytes memory payload_
    ) internal view {
        assertEq(actionId_, expectedActionId_, "Action ID");

        IPriceConfigv2.QueuedAction memory action = priceConfig.getQueuedAction(actionId_);
        assertEq(uint8(action.action), uint8(action_), "Action");
        assertEq(action.proposer, proposer_, "Proposer");
        assertEq(action.queuedAt, queuedAt_, "Queued at");
        assertEq(action.executableAt, executableAt_, "Executable at");
        assertEq(action.expiresAt, expiresAt_, "Expires at");
        assertEq(action.executed, false, "Executed");
        assertEq(action.cancelled, false, "Cancelled");
        assertEq(action.payload, payload_, "Payload");
    }

    function _assertExecuteWhenDisabledReverts(QueuedActionCase actionCase_) internal {
        uint256 actionId = _queueActionCase(actionCase_);
        IPriceConfigv2.QueuedAction memory action = priceConfig.getQueuedAction(actionId);

        vm.warp(action.executableAt);
        if (actionCase_ == QueuedActionCase.UpdateAsset) {
            _refreshPriceFeedTimestamps(action.executableAt);
        }

        vm.prank(admin);
        priceConfig.disable(abi.encode(""));

        _expectRevertNotEnabled();
        priceConfig.executeQueuedAction(actionId);
    }

    function _assertCancelWhenDisabled(QueuedActionCase actionCase_, address caller_) internal {
        uint256 actionId = _queueActionCase(actionCase_);

        vm.prank(admin);
        priceConfig.disable(abi.encode(""));

        if (caller_ != emergency) {
            vm.expectRevert(
                abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ROLE_EMERGENCY)
            );
        }
        vm.prank(caller_);
        priceConfig.cancelQueuedAction(actionId);

        IPriceConfigv2.QueuedAction memory action = priceConfig.getQueuedAction(actionId);
        assertEq(action.cancelled, caller_ == emergency, "Only emergency should cancel action");

        if (caller_ == emergency) {
            assertEq(action.payload.length, 0, "Payload should be cleared");
        } else {
            assertGt(action.payload.length, 0, "Payload should remain");
        }
    }

    function _assertExecuteBeforeDelayReverts(
        QueuedActionCase actionCase_,
        uint256 warpedTimestamp_
    ) internal {
        uint256 actionId = _queueActionCase(actionCase_);
        IPriceConfigv2.QueuedAction memory action = priceConfig.getQueuedAction(actionId);
        uint256 targetTimestamp = bound(warpedTimestamp_, action.queuedAt, action.executableAt - 1);

        vm.warp(targetTimestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceConfigv2.IPriceConfigv2_ActionNotReady.selector,
                actionId,
                action.executableAt
            )
        );
        priceConfig.executeQueuedAction(actionId);
    }

    function _assertExecuteReadySucceeds(
        QueuedActionCase actionCase_,
        uint256 warpedTimestamp_,
        address executor_
    ) internal {
        uint256 actionId = _queueActionCase(actionCase_);
        IPriceConfigv2.QueuedAction memory action = priceConfig.getQueuedAction(actionId);
        uint256 targetTimestamp = bound(warpedTimestamp_, action.executableAt, action.expiresAt);

        vm.warp(targetTimestamp);
        if (actionCase_ == QueuedActionCase.UpdateAsset) {
            _refreshPriceFeedTimestamps(targetTimestamp);
        }
        vm.prank(executor_);
        priceConfig.executeQueuedAction(actionId);

        action = priceConfig.getQueuedAction(actionId);
        assertEq(action.executed, true, "Action should be executed");
        assertEq(action.payload.length, 0, "Payload should be cleared");
    }

    function _assertExecuteAfterExpiryReverts(
        QueuedActionCase actionCase_,
        uint256 warpedTimestamp_
    ) internal {
        uint256 actionId = _queueActionCase(actionCase_);
        IPriceConfigv2.QueuedAction memory action = priceConfig.getQueuedAction(actionId);
        uint256 targetTimestamp = bound(
            warpedTimestamp_,
            uint256(action.expiresAt) + 1,
            uint256(action.expiresAt) + 365 days
        );

        vm.warp(targetTimestamp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceConfigv2.IPriceConfigv2_ActionExpired.selector,
                actionId,
                action.expiresAt
            )
        );
        priceConfig.executeQueuedAction(actionId);
    }

    function _assertExecuteAfterCancelReverts(QueuedActionCase actionCase_) internal {
        uint256 actionId = _queueActionCase(actionCase_);

        vm.prank(emergency);
        priceConfig.cancelQueuedAction(actionId);

        _warpPastTimelockDelay();
        vm.expectRevert(
            abi.encodeWithSelector(IPriceConfigv2.IPriceConfigv2_ActionCancelled.selector, actionId)
        );
        priceConfig.executeQueuedAction(actionId);
    }

    function _assertExecuteAfterExecutedReverts(QueuedActionCase actionCase_) internal {
        uint256 actionId = _queueActionCase(actionCase_);

        _executeQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceConfigv2.IPriceConfigv2_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        priceConfig.executeQueuedAction(actionId);
    }

    function _addBaseAssets() internal {
        // OHM
        IPRICEv2.Component memory strat = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ChainlinkPriceFeeds.OneFeedParams(ohmUsdPriceFeed, uint48(24 hours)))
        );
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(
                ChainlinkPriceFeeds.TwoFeedParams(
                    ohmEthPriceFeed,
                    uint48(24 hours),
                    ethUsdPriceFeed,
                    uint48(24 hours)
                )
            )
        );

        uint256[] memory obs = _makeObservations(ohm, feeds[0], 15);
        IPriceConfigv2.PriceFeedExpectation[] memory expectations = _makeFeedExpectations(
            feeds.length,
            10e18,
            100
        );

        vm.prank(priceManager);
        priceConfig.addAsset(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strat,
            feeds,
            expectations
        );
    }

    function _addReserveAsset() internal {
        IPRICEv2.Component memory strategyComponent = _emptyStrategy();

        IPRICEv2.Component[] memory feeds = _reserveFeeds();
        IPriceConfigv2.PriceFeedExpectation[] memory expectations = _makeFeedExpectations(
            feeds.length,
            1e18,
            100
        );

        vm.prank(priceManager);
        priceConfig.addAsset(
            address(_reserve),
            false,
            false,
            uint32(0),
            uint48(0),
            new uint256[](0),
            strategyComponent,
            feeds,
            expectations
        );
    }

    function _emptyStrategy() internal pure returns (IPRICEv2.Component memory) {
        return IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), bytes(""));
    }

    function _reserveFeeds() internal view returns (IPRICEv2.Component[] memory) {
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ChainlinkPriceFeeds.OneFeedParams(reserveUsdPriceFeed, uint48(24 hours)))
        );

        return feeds;
    }

    function _addReserveAssetWithExpectations(
        IPriceConfigv2.PriceFeedExpectation[] memory expectations_
    ) internal {
        IPRICEv2.Component memory strategyComponent = IPRICEv2.Component(
            toSubKeycode(bytes20(0)),
            bytes4(0),
            bytes("")
        );

        IPRICEv2.Component[] memory feeds = _reserveFeeds();

        vm.prank(priceManager);
        priceConfig.addAsset(
            address(_reserve),
            false,
            false,
            uint32(0),
            uint48(0),
            new uint256[](0),
            strategyComponent,
            feeds,
            expectations_
        );
    }

    modifier givenDisabled() {
        vm.prank(admin);
        priceConfig.disable(abi.encode(""));
        _;
    }

    function _expectRevertNotEnabled() internal {
        vm.expectRevert(IEnabler.NotEnabled.selector);
    }

    /* ========== PriceConfig Setup and Permissions ========== */

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](2);
        expectedDeps[0] = toKeycode("ROLES");
        expectedDeps[1] = toKeycode("PRICE");

        Keycode[] memory deps = priceConfig.configureDependencies();
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
    }

    function test_requestPermissions() public view {
        Permissions[] memory expectedPerms = new Permissions[](8);
        Keycode PRICE_KEYCODE = toKeycode("PRICE");

        // PRICE Permissions
        expectedPerms[0] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.addAsset.selector
        });
        expectedPerms[1] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.removeAsset.selector
        });
        expectedPerms[2] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.updateAsset.selector
        });
        expectedPerms[3] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.installSubmodule.selector
        });
        expectedPerms[4] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.upgradeSubmodule.selector
        });
        expectedPerms[5] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.execOnSubmodule.selector
        });
        expectedPerms[6] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.storeObservation.selector
        });
        expectedPerms[7] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.storeObservations.selector
        });

        Permissions[] memory perms = priceConfig.requestPermissions();
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    function test_constructor() public {
        // Create a fresh PriceConfigv2 to test initial constructor state
        PriceConfigv2 freshPriceConfig = new PriceConfigv2(kernel);
        assertEq(freshPriceConfig.isEnabled(), true, "Enabled by default");
    }

    function test_usingOlympusPricev1_2() public {
        // Install OlympusPricev1_2
        OlympusPricev1_2 newPrice = new OlympusPricev1_2(
            kernel,
            address(ohm),
            OBSERVATION_FREQUENCY,
            1e18
        );

        // Upgrade the module in the kernel
        // This will cause PriceConfig v2 to use the new OlympusPricev1_2 module
        kernel.executeAction(Actions.UpgradeModule, address(newPrice));

        // Verify that the module version is correct
        address priceModule = address(kernel.getModuleForKeycode(toKeycode("PRICE")));
        (uint8 major, uint8 minor) = Module(priceModule).VERSION();
        assertEq(major, 1, "Major version should be 1");
        assertEq(minor, 2, "Minor version should be 2");
    }

    /* ========== PRICEv2 Configuration ========== */

    function test_addAsset_givenDisabled_reverts() public givenDisabled {
        // Prepare arguments
        uint256[] memory obs = new uint256[](0);
        IPRICEv2.Component[] memory feedComponents = new IPRICEv2.Component[](0);
        IPRICEv2.Component memory strategyComponent = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(priceManager);
        priceConfig.addAsset(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strategyComponent,
            feedComponents,
            new IPriceConfigv2.PriceFeedExpectation[](0)
        );
    }

    function test_addAsset_unauthorizedUser_reverts(address user_) public {
        vm.assume(user_ != admin && user_ != priceManager);

        // Setup data to add asset
        IPRICEv2.Component memory strategyComponent = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        IPRICEv2.Component[] memory feedComponents = new IPRICEv2.Component[](2);
        feedComponents[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ChainlinkPriceFeeds.OneFeedParams(ohmUsdPriceFeed, uint48(24 hours)))
        );
        feedComponents[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(
                ChainlinkPriceFeeds.TwoFeedParams(
                    ohmEthPriceFeed,
                    uint48(24 hours),
                    ethUsdPriceFeed,
                    uint48(24 hours)
                )
            )
        );

        // Get observation data to initialize moving average with
        uint256[] memory obs = _makeObservations(ohm, feedComponents[0], 15);
        IPriceConfigv2.PriceFeedExpectation[] memory expectations = _makeFeedExpectations(
            feedComponents.length,
            10e18,
            100
        );

        // Try to add asset to PRICEv2 with unauthorized account, expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(user_);
        priceConfig.addAsset(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strategyComponent,
            feedComponents,
            expectations
        );

        // Confirm asset was not added
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, false);

        // Try to add asset to PRICEv2 with priceManager account, expect success
        vm.prank(priceManager);
        priceConfig.addAsset(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strategyComponent,
            feedComponents,
            expectations
        );
    }

    function test_addAsset(uint8 role_) public {
        role_ = uint8(bound(role_, 0, 1));
        address caller = role_ == 0 ? admin : priceManager;

        // Setup data to add asset
        IPRICEv2.Component memory strategyComponent = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        IPRICEv2.Component[] memory feedComponents = new IPRICEv2.Component[](2);
        feedComponents[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ChainlinkPriceFeeds.OneFeedParams(ohmUsdPriceFeed, uint48(24 hours)))
        );
        feedComponents[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(
                ChainlinkPriceFeeds.TwoFeedParams(
                    ohmEthPriceFeed,
                    uint48(24 hours),
                    ethUsdPriceFeed,
                    uint48(24 hours)
                )
            )
        );

        // Get observation data to initialize moving average with
        uint256[] memory obs = _makeObservations(ohm, feedComponents[0], 15);
        IPriceConfigv2.PriceFeedExpectation[] memory expectations = _makeFeedExpectations(
            feedComponents.length,
            10e18,
            100
        );

        // Confirm asset is not approved yet and data is not set
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, false);
        assertEq(asset.storeMovingAverage, false);
        assertEq(asset.useMovingAverage, false);
        assertEq(asset.movingAverageDuration, uint32(0));
        assertEq(asset.nextObsIndex, uint16(0));
        assertEq(asset.numObservations, uint16(0));
        assertEq(asset.lastObservationTime, uint48(0));
        assertEq(asset.cumulativeObs, uint256(0));
        assertEq(asset.obs.length, uint256(0));
        assertEq(asset.strategy, bytes(""));
        assertEq(asset.feeds, bytes(""));

        // Add asset to PRICEv2 using authorized caller
        vm.prank(caller);
        priceConfig.addAsset(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strategyComponent,
            feedComponents,
            expectations
        );

        // Confirm asset is approved and data is correct
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);
        assertEq(asset.storeMovingAverage, true);
        assertEq(asset.useMovingAverage, true);
        assertEq(asset.movingAverageDuration, uint32(5 days));
        assertEq(asset.nextObsIndex, uint16(0));
        assertEq(asset.numObservations, uint16(15));
        assertEq(asset.lastObservationTime, uint48(block.timestamp));
        uint256 cumObs;
        for (uint256 i = 0; i < obs.length; i++) {
            cumObs += obs[i];
        }
        assertEq(asset.cumulativeObs, cumObs);
        assertEq(asset.obs.length, uint256(15));
        assertEq(asset.strategy, abi.encode(strategyComponent));
        assertEq(asset.feeds, abi.encode(feedComponents));
    }

    function test_addAsset_feedExpectationCountInvalid_revertsAndRollsBack() public {
        IPRICEv2.Component[] memory feeds = _reserveFeeds();

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceConfigv2.IPriceConfigv2_FeedExpectationCountInvalid.selector,
                address(_reserve),
                0,
                feeds.length
            )
        );

        _addReserveAssetWithExpectations(new IPriceConfigv2.PriceFeedExpectation[](0));

        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(_reserve));
        assertEq(asset.approved, false, "Asset should not be approved after failed validation");
    }

    function test_addAsset_feedExpectationInvalid_revertsAndRollsBack() public {
        IPriceConfigv2.PriceFeedExpectation[]
            memory expectations = new IPriceConfigv2.PriceFeedExpectation[](1);
        expectations[0] = IPriceConfigv2.PriceFeedExpectation({
            expectedPrice: 0,
            toleranceBps: 100
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceConfigv2.IPriceConfigv2_FeedExpectationInvalid.selector,
                address(_reserve),
                0
            )
        );

        _addReserveAssetWithExpectations(expectations);

        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(_reserve));
        assertEq(asset.approved, false, "Asset should not be approved after failed validation");
    }

    function test_addAsset_feedPriceOutOfBounds_revertsAndRollsBack() public {
        IPriceConfigv2.PriceFeedExpectation[]
            memory expectations = new IPriceConfigv2.PriceFeedExpectation[](1);
        expectations[0] = IPriceConfigv2.PriceFeedExpectation({
            expectedPrice: 2e18,
            toleranceBps: 0
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceConfigv2.IPriceConfigv2_PriceFeedOutOfBounds.selector,
                address(_reserve),
                0,
                1e18,
                2e18,
                2e18
            )
        );

        _addReserveAssetWithExpectations(expectations);

        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(_reserve));
        assertEq(asset.approved, false, "Asset should not be approved after failed validation");
    }

    /* ========== queueRemoveAsset ========== */

    // given the contract is not enabled
    //  [X] it reverts
    // given the caller is not admin nor price admin
    //  [X] it reverts
    // when the asset is not approved
    //  [X] it reverts
    // when the asset is the unit of account
    //  [X] it reverts
    // [X] it queues the removeAsset action
    // [X] the removeAsset action can be executed after the timelock

    function test_queueRemoveAsset_givenDisabled_reverts() public givenDisabled {
        _expectRevertNotEnabled();

        // Call function
        vm.prank(priceManager);
        priceConfig.queueRemoveAsset(address(ohm));
    }

    function test_queueRemoveAsset_unauthorizedUser_reverts(address user_) public {
        vm.assume(user_ != admin && user_ != priceManager);

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm asset is approved
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);

        // Try to queue asset removal with unauthorized account, expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(user_);
        priceConfig.queueRemoveAsset(address(ohm));

        // Confirm asset was not removed
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);

        // Try to queue asset removal with priceManager account, expect success
        vm.prank(priceManager);
        uint256 actionId = priceConfig.queueRemoveAsset(address(ohm));

        // Confirm asset is not removed until the timelock is executed
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);

        _executeQueuedAction(actionId);

        // Confirm asset was removed after execution
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, false);
    }

    function test_queueRemoveAsset_whenAssetIsUnapproved_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(ohm))
        );
        vm.prank(priceManager);
        priceConfig.queueRemoveAsset(address(ohm));
    }

    function test_queueRemoveAsset_whenAssetIsUnitOfAccount_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetReserved.selector, _UNIT_OF_ACCOUNT)
        );
        vm.prank(priceManager);
        priceConfig.queueRemoveAsset(_UNIT_OF_ACCOUNT);
    }

    function test_queueRemoveAsset(uint8 role_) public {
        role_ = uint8(bound(role_, 0, 1));
        address caller = role_ == 0 ? admin : priceManager;

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm asset is approved
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);

        // Queue asset removal using authorized caller
        vm.prank(caller);
        uint256 actionId = priceConfig.queueRemoveAsset(address(ohm));

        // Confirm asset is not removed until the timelock is executed
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);

        _executeQueuedAction(actionId);

        // Confirm asset is not approved and all data deleted after execution
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, false);
        assertEq(asset.storeMovingAverage, false);
        assertEq(asset.useMovingAverage, false);
        assertEq(asset.movingAverageDuration, uint32(0));
        assertEq(asset.nextObsIndex, uint16(0));
        assertEq(asset.numObservations, uint16(0));
        assertEq(asset.lastObservationTime, uint48(0));
        assertEq(asset.cumulativeObs, uint256(0));
        assertEq(asset.obs.length, uint256(0));
        assertEq(asset.strategy, bytes(""));
        assertEq(asset.feeds, bytes(""));
    }

    function test_queueRemoveAsset_queuesExpectedAction() public {
        _addBaseAssets();

        bytes memory payload = abi.encode(address(ohm));
        (
            uint256 expectedActionId,
            uint48 queuedAt,
            uint48 executableAt,
            uint48 expiresAt
        ) = _expectQueuedAction(IPriceConfigv2.TimelockAction.RemoveAsset, priceManager, payload);

        vm.prank(priceManager);
        uint256 actionId = priceConfig.queueRemoveAsset(address(ohm));

        _assertQueuedAction(
            actionId,
            expectedActionId,
            IPriceConfigv2.TimelockAction.RemoveAsset,
            priceManager,
            queuedAt,
            executableAt,
            expiresAt,
            payload
        );
    }

    /* ========== queueUpdateAsset ========== */

    // given the contract is not enabled
    //  [X] it reverts
    // given the caller is not admin nor price admin
    //  [X] it reverts
    // when no update flags are set
    //  [X] it reverts
    // when updateFeeds is true and the price feed expectation count does not match the input feeds
    //  [X] it reverts and rolls back
    // when updateFeeds is true and the price feed expectations are not met at execution
    //  [X] it reverts and rolls back
    // when updateFeeds is false and price feed expectations are provided
    //  [X] it reverts and rolls back
    // [X] it queues the updateAsset action
    // [X] the updateAsset action can be executed after the timelock

    function test_queueUpdateAsset_givenDisabled_reverts() public givenDisabled {
        // Prepare update params
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: IPRICEv2.Component(SubKeycode.wrap(bytes20(0)), bytes4(0), bytes("")),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: 0,
            lastObservationTime: 0,
            observations: new uint256[](0)
        });

        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(priceManager);
        priceConfig.queueUpdateAsset(
            address(ohm),
            params,
            new IPriceConfigv2.PriceFeedExpectation[](0)
        );
    }

    function test_queueUpdateAsset_queuesExpectedAction() public {
        _addBaseAssets();

        IPRICEv2.UpdateAssetParams memory params = _makeStrategyOnlyUpdateParams();
        IPriceConfigv2.PriceFeedExpectation[]
            memory expectations = new IPriceConfigv2.PriceFeedExpectation[](0);
        bytes memory payload = abi.encode(address(ohm), params, expectations);
        (
            uint256 expectedActionId,
            uint48 queuedAt,
            uint48 executableAt,
            uint48 expiresAt
        ) = _expectQueuedAction(IPriceConfigv2.TimelockAction.UpdateAsset, priceManager, payload);

        vm.prank(priceManager);
        uint256 actionId = priceConfig.queueUpdateAsset(address(ohm), params, expectations);

        _assertQueuedAction(
            actionId,
            expectedActionId,
            IPriceConfigv2.TimelockAction.UpdateAsset,
            priceManager,
            queuedAt,
            executableAt,
            expiresAt,
            payload
        );
    }

    function test_queueUpdateAsset_unauthorizedUser_reverts(address user_) public {
        vm.assume(user_ != admin && user_ != priceManager);

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm currently has two feeds
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        IPRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 2);

        // Setup params to update feeds
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](1),
            strategy: IPRICEv2.Component(SubKeycode.wrap(bytes20(0)), bytes4(0), bytes("")),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: 0,
            lastObservationTime: 0,
            observations: new uint256[](0)
        });
        params.feeds[0] = feeds[0];
        IPriceConfigv2.PriceFeedExpectation[] memory expectations = _makeFeedExpectations(
            params.feeds.length,
            10e18,
            100
        );

        // Try to queue asset update with unauthorized account, expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);

        vm.prank(user_);
        priceConfig.queueUpdateAsset(address(ohm), params, expectations);

        // Confirm feeds were not updated
        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 2);

        // Try with priceManager account, expect success
        vm.prank(priceManager);
        uint256 actionId = priceConfig.queueUpdateAsset(address(ohm), params, expectations);

        // Confirm feeds are not updated until the timelock is executed
        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 2);

        _executeQueuedAction(actionId);

        // Confirm feeds were updated after execution
        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 1);
    }

    function test_queueUpdateAsset_whenNoUpdatesRequested_reverts() public {
        _addBaseAssets();

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: IPRICEv2.Component(SubKeycode.wrap(bytes20(0)), bytes4(0), bytes("")),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: 0,
            lastObservationTime: 0,
            observations: new uint256[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_NoUpdatesRequested.selector, address(ohm))
        );
        vm.prank(priceManager);
        priceConfig.queueUpdateAsset(
            address(ohm),
            params,
            new IPriceConfigv2.PriceFeedExpectation[](0)
        );
    }

    function test_queueUpdateAsset_whenUpdateFeesIsTrue_whenPriceFeedExpectationCountInvalid_revertsAndRollsBack()
        public
    {
        _addBaseAssets();

        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        IPRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 2, "Initial feed count");

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](1),
            strategy: IPRICEv2.Component(SubKeycode.wrap(bytes20(0)), bytes4(0), bytes("")),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: 0,
            lastObservationTime: 0,
            observations: new uint256[](0)
        });
        params.feeds[0] = feeds[0];

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceConfigv2.IPriceConfigv2_FeedExpectationCountInvalid.selector,
                address(ohm),
                0,
                params.feeds.length
            )
        );

        vm.prank(priceManager);
        priceConfig.queueUpdateAsset(
            address(ohm),
            params,
            new IPriceConfigv2.PriceFeedExpectation[](0)
        );

        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 2, "Feed update should roll back");
    }

    function test_queueUpdateAsset_whenUpdateFeedsIsTrue_feedPriceOutOfBounds_revertsAndRollsBack()
        public
    {
        _addBaseAssets();

        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        IPRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 2, "Initial feed count");

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](1),
            strategy: IPRICEv2.Component(SubKeycode.wrap(bytes20(0)), bytes4(0), bytes("")),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: 0,
            lastObservationTime: 0,
            observations: new uint256[](0)
        });
        params.feeds[0] = feeds[0];

        IPriceConfigv2.PriceFeedExpectation[]
            memory expectations = new IPriceConfigv2.PriceFeedExpectation[](1);
        expectations[0] = IPriceConfigv2.PriceFeedExpectation({
            expectedPrice: 20e18,
            toleranceBps: 0
        });

        vm.prank(priceManager);
        uint256 actionId = priceConfig.queueUpdateAsset(address(ohm), params, expectations);

        _warpPastTimelockDelay();
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceConfigv2.IPriceConfigv2_PriceFeedOutOfBounds.selector,
                address(ohm),
                0,
                10e18,
                20e18,
                20e18
            )
        );
        priceConfig.executeQueuedAction(actionId);

        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 2, "Feed update should roll back");
    }

    function test_queueUpdateAsset_whenUpdateFeedsIsTrue(uint8 role_) public {
        role_ = uint8(bound(role_, 0, 1));
        address caller = role_ == 0 ? admin : priceManager;

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm currently has two feeds
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        IPRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 2);

        // Setup params to update feeds
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](1),
            strategy: IPRICEv2.Component(SubKeycode.wrap(bytes20(0)), bytes4(0), bytes("")),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: 0,
            lastObservationTime: 0,
            observations: new uint256[](0)
        });
        params.feeds[0] = feeds[0];
        IPriceConfigv2.PriceFeedExpectation[] memory expectations = _makeFeedExpectations(
            params.feeds.length,
            10e18,
            100
        );

        // Queue asset update using authorized caller
        vm.prank(caller);
        uint256 actionId = priceConfig.queueUpdateAsset(address(ohm), params, expectations);

        IPriceConfigv2.QueuedAction memory action = priceConfig.getQueuedAction(actionId);
        assertEq(action.executed, false, "Queued update action should not be executed");

        // Confirm feeds are not updated until the timelock is executed
        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 2);

        _executeQueuedAction(actionId);

        // Confirm feeds were updated after execution
        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 1);
        assertEq(fromSubKeycode(feeds[0].target), fromSubKeycode(params.feeds[0].target));
        assertEq(feeds[0].selector, params.feeds[0].selector);
        assertEq(feeds[0].params, params.feeds[0].params);
    }

    function test_queueUpdateAsset_whenUpdateFeedsIsFalse_whenPriceFeedsExpectationsIsNotEmpty_reverts()
        public
    {
        _addBaseAssets();

        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        IPRICEv2.Component memory currentStrategy = abi.decode(
            asset.strategy,
            (IPRICEv2.Component)
        );
        IPRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: currentStrategy,
            useMovingAverage: asset.useMovingAverage,
            storeMovingAverage: false,
            movingAverageDuration: 0,
            lastObservationTime: 0,
            observations: new uint256[](0)
        });

        IPriceConfigv2.PriceFeedExpectation[] memory expectations = _makeFeedExpectations(
            feeds.length,
            10e18,
            100
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceConfigv2.IPriceConfigv2_FeedExpectationCountInvalid.selector,
                address(ohm),
                expectations.length,
                0
            )
        );

        vm.prank(priceManager);
        priceConfig.queueUpdateAsset(address(ohm), params, expectations);

        IPRICEv2.Asset memory updatedAsset = PRICE.getAssetData(address(ohm));
        assertEq(updatedAsset.strategy, asset.strategy, "Strategy update should roll back");
    }

    /* ========== queueTimelockDelay ========== */

    // given the contract is disabled
    //  [X] it reverts
    // given the caller is not admin
    //  [X] it reverts
    // when the delay is below the minimum
    //  [X] it reverts
    // when the delay is above the maximum
    //  [X] it reverts
    // [X] it queues the setTimelockDelay action
    // [X] the setTimelockDelay action can be executed after the timelock

    function test_queueTimelockDelay_givenDisabled_reverts() public givenDisabled {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(admin);
        priceConfig.queueTimelockDelay(2 days);
    }

    function test_queueTimelockDelay_queuesExpectedAction() public {
        uint48 newDelay = 2 days;
        bytes memory payload = abi.encode(newDelay);
        (
            uint256 expectedActionId,
            uint48 queuedAt,
            uint48 executableAt,
            uint48 expiresAt
        ) = _expectQueuedAction(IPriceConfigv2.TimelockAction.SetTimelockDelay, admin, payload);

        vm.prank(admin);
        uint256 actionId = priceConfig.queueTimelockDelay(newDelay);

        _assertQueuedAction(
            actionId,
            expectedActionId,
            IPriceConfigv2.TimelockAction.SetTimelockDelay,
            admin,
            queuedAt,
            executableAt,
            expiresAt,
            payload
        );
    }

    function test_queueTimelockDelay_isTimelocked() public {
        uint48 newDelay = 2 days;

        vm.prank(admin);
        uint256 actionId = priceConfig.queueTimelockDelay(newDelay);

        assertEq(
            priceConfig.timelockDelay(),
            TIMELOCK_DELAY,
            "Delay should not update immediately"
        );

        _executeQueuedAction(actionId);

        assertEq(priceConfig.timelockDelay(), newDelay, "Delay should update after execution");
    }

    function test_queueTimelockDelay_nonAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ROLE_ADMIN));
        vm.prank(caller_);
        priceConfig.queueTimelockDelay(2 days);
    }

    function test_queueTimelockDelay_belowMinimum_revertsAtQueueTime() public {
        uint48 invalidDelay = TIMELOCK_DELAY - 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceConfigv2.IPriceConfigv2_TimelockDelayInvalid.selector,
                invalidDelay,
                priceConfig.MIN_TIMELOCK_DELAY(),
                priceConfig.MAX_TIMELOCK_DELAY()
            )
        );
        vm.prank(admin);
        priceConfig.queueTimelockDelay(invalidDelay);
    }

    function test_queueTimelockDelay_aboveMaximum_revertsAtQueueTime() public {
        uint48 invalidDelay = priceConfig.MAX_TIMELOCK_DELAY() + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceConfigv2.IPriceConfigv2_TimelockDelayInvalid.selector,
                invalidDelay,
                priceConfig.MIN_TIMELOCK_DELAY(),
                priceConfig.MAX_TIMELOCK_DELAY()
            )
        );
        vm.prank(admin);
        priceConfig.queueTimelockDelay(invalidDelay);
    }

    /* ========== TIMELOCK ========== */

    // given an action has been queued
    //  given the timelock delay has not been reached
    //   [X] queueRemoveAsset reverts for any timestamp before executableAt
    //   [X] queueUpdateAsset reverts for any timestamp before executableAt
    //   [X] queueUpgradeSubmodule reverts for any timestamp before executableAt
    //   [X] queueTimelockDelay reverts for any timestamp before executableAt

    function test_executeQueuedAction_beforeDelay_givenQueueRemoveAsset_reverts(
        uint256 warpedTimestamp_
    ) public {
        _assertExecuteBeforeDelayReverts(QueuedActionCase.RemoveAsset, warpedTimestamp_);
    }

    function test_executeQueuedAction_beforeDelay_givenQueueUpdateAsset_reverts(
        uint256 warpedTimestamp_
    ) public {
        _assertExecuteBeforeDelayReverts(QueuedActionCase.UpdateAsset, warpedTimestamp_);
    }

    function test_executeQueuedAction_beforeDelay_givenQueueUpgradeSubmodule_reverts(
        uint256 warpedTimestamp_
    ) public {
        _assertExecuteBeforeDelayReverts(QueuedActionCase.UpgradeSubmodule, warpedTimestamp_);
    }

    function test_executeQueuedAction_beforeDelay_givenTimelockDelay_reverts(
        uint256 warpedTimestamp_
    ) public {
        _assertExecuteBeforeDelayReverts(QueuedActionCase.TimelockDelay, warpedTimestamp_);
    }

    // given an action has been queued
    //  given the timelock has passed
    //   given the timelock expiry has not been reached
    //   [X] any caller can execute queueRemoveAsset
    //   [X] any caller can execute queueUpdateAsset
    //   [X] any caller can execute queueUpgradeSubmodule
    //   [X] any caller can execute queueTimelockDelay

    function test_executeQueuedAction_ready_givenQueueRemoveAsset_succeeds(
        uint256 warpedTimestamp_,
        address executor_
    ) public {
        _assertExecuteReadySucceeds(QueuedActionCase.RemoveAsset, warpedTimestamp_, executor_);
    }

    function test_executeQueuedAction_ready_givenQueueUpdateAsset_succeeds(
        uint256 warpedTimestamp_,
        address executor_
    ) public {
        _assertExecuteReadySucceeds(QueuedActionCase.UpdateAsset, warpedTimestamp_, executor_);
    }

    function test_executeQueuedAction_ready_givenQueueUpgradeSubmodule_succeeds(
        uint256 warpedTimestamp_,
        address executor_
    ) public {
        _assertExecuteReadySucceeds(QueuedActionCase.UpgradeSubmodule, warpedTimestamp_, executor_);
    }

    function test_executeQueuedAction_ready_givenTimelockDelay_succeeds(
        uint256 warpedTimestamp_,
        address executor_
    ) public {
        _assertExecuteReadySucceeds(QueuedActionCase.TimelockDelay, warpedTimestamp_, executor_);
    }

    // given an action has been queued
    //  given the action has expired
    //   [X] queueRemoveAsset execution reverts for any timestamp after expiresAt
    //   [X] queueUpdateAsset execution reverts for any timestamp after expiresAt
    //   [X] queueUpgradeSubmodule execution reverts for any timestamp after expiresAt
    //   [X] queueTimelockDelay execution reverts for any timestamp after expiresAt

    function test_executeQueuedAction_afterExpiry_givenQueueRemoveAsset_reverts(
        uint256 warpedTimestamp_
    ) public {
        _assertExecuteAfterExpiryReverts(QueuedActionCase.RemoveAsset, warpedTimestamp_);
    }

    function test_executeQueuedAction_afterExpiry_givenQueueUpdateAsset_reverts(
        uint256 warpedTimestamp_
    ) public {
        _assertExecuteAfterExpiryReverts(QueuedActionCase.UpdateAsset, warpedTimestamp_);
    }

    function test_executeQueuedAction_afterExpiry_givenQueueUpgradeSubmodule_reverts(
        uint256 warpedTimestamp_
    ) public {
        _assertExecuteAfterExpiryReverts(QueuedActionCase.UpgradeSubmodule, warpedTimestamp_);
    }

    function test_executeQueuedAction_afterExpiry_givenTimelockDelay_reverts(
        uint256 warpedTimestamp_
    ) public {
        _assertExecuteAfterExpiryReverts(QueuedActionCase.TimelockDelay, warpedTimestamp_);
    }

    // given an action has been queued
    //  when the action has been cancelled
    //   [X] queueRemoveAsset execution reverts
    //   [X] queueUpdateAsset execution reverts
    //   [X] queueUpgradeSubmodule execution reverts
    //   [X] queueTimelockDelay execution reverts

    function test_executeQueuedAction_cancelled_givenQueueRemoveAsset_reverts() public {
        _assertExecuteAfterCancelReverts(QueuedActionCase.RemoveAsset);
    }

    function test_executeQueuedAction_cancelled_givenQueueUpdateAsset_reverts() public {
        _assertExecuteAfterCancelReverts(QueuedActionCase.UpdateAsset);
    }

    function test_executeQueuedAction_cancelled_givenQueueUpgradeSubmodule_reverts() public {
        _assertExecuteAfterCancelReverts(QueuedActionCase.UpgradeSubmodule);
    }

    function test_executeQueuedAction_cancelled_givenTimelockDelay_reverts() public {
        _assertExecuteAfterCancelReverts(QueuedActionCase.TimelockDelay);
    }

    // given an action has been queued
    //  when the action has already been executed
    //   [X] queueRemoveAsset execution reverts
    //   [X] queueUpdateAsset execution reverts
    //   [X] queueUpgradeSubmodule execution reverts
    //   [X] queueTimelockDelay execution reverts

    function test_executeQueuedAction_executed_givenQueueRemoveAsset_reverts() public {
        _assertExecuteAfterExecutedReverts(QueuedActionCase.RemoveAsset);
    }

    function test_executeQueuedAction_executed_givenQueueUpdateAsset_reverts() public {
        _assertExecuteAfterExecutedReverts(QueuedActionCase.UpdateAsset);
    }

    function test_executeQueuedAction_executed_givenQueueUpgradeSubmodule_reverts() public {
        _assertExecuteAfterExecutedReverts(QueuedActionCase.UpgradeSubmodule);
    }

    function test_executeQueuedAction_executed_givenTimelockDelay_reverts() public {
        _assertExecuteAfterExecutedReverts(QueuedActionCase.TimelockDelay);
    }

    // given the contract is not enabled
    //  when the action is ready
    //   [X] queueRemoveAsset execution reverts
    //   [X] queueUpdateAsset execution reverts
    //   [X] queueUpgradeSubmodule execution reverts
    //   [X] queueTimelockDelay execution reverts

    function test_executeQueuedAction_whenDisabled_givenQueueRemoveAsset_reverts() public {
        _assertExecuteWhenDisabledReverts(QueuedActionCase.RemoveAsset);
    }

    function test_executeQueuedAction_whenDisabled_givenQueueUpdateAsset_reverts() public {
        _assertExecuteWhenDisabledReverts(QueuedActionCase.UpdateAsset);
    }

    function test_executeQueuedAction_whenDisabled_givenQueueUpgradeSubmodule_reverts() public {
        _assertExecuteWhenDisabledReverts(QueuedActionCase.UpgradeSubmodule);
    }

    function test_executeQueuedAction_whenDisabled_givenTimelockDelay_reverts() public {
        _assertExecuteWhenDisabledReverts(QueuedActionCase.TimelockDelay);
    }

    // when the action ID does not exist
    //  [X] executeQueuedAction reverts

    function test_executeQueuedAction_givenActionIdDoesNotExist_reverts(uint256 actionId_) public {
        vm.expectRevert(
            abi.encodeWithSelector(IPriceConfigv2.IPriceConfigv2_ActionNotFound.selector, actionId_)
        );
        priceConfig.executeQueuedAction(actionId_);
    }

    // given the contract is not enabled
    //  [X] only emergency can cancel queueRemoveAsset
    //  [X] only emergency can cancel queueUpdateAsset
    //  [X] only emergency can cancel queueUpgradeSubmodule
    //  [X] only emergency can cancel queueTimelockDelay

    function test_cancelQueuedAction_whenDisabled_givenQueueRemoveAsset_onlyEmergency(
        address caller_
    ) public {
        _assertCancelWhenDisabled(QueuedActionCase.RemoveAsset, caller_);
    }

    function test_cancelQueuedAction_whenDisabled_givenQueueUpdateAsset_onlyEmergency(
        address caller_
    ) public {
        _assertCancelWhenDisabled(QueuedActionCase.UpdateAsset, caller_);
    }

    function test_cancelQueuedAction_whenDisabled_givenQueueUpgradeSubmodule_onlyEmergency(
        address caller_
    ) public {
        _assertCancelWhenDisabled(QueuedActionCase.UpgradeSubmodule, caller_);
    }

    function test_cancelQueuedAction_whenDisabled_givenTimelockDelay_onlyEmergency(
        address caller_
    ) public {
        _assertCancelWhenDisabled(QueuedActionCase.TimelockDelay, caller_);
    }

    // when execution reverts
    //  [X] it leaves the action pending
    //  [X] emergency can cancel the pending action

    function test_executeQueuedAction_givenExecutionFails_canBeCancelled() public {
        _addBaseAssets();

        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        IPRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](1),
            strategy: IPRICEv2.Component(SubKeycode.wrap(bytes20(0)), bytes4(0), bytes("")),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: 0,
            lastObservationTime: 0,
            observations: new uint256[](0)
        });
        params.feeds[0] = feeds[0];

        IPriceConfigv2.PriceFeedExpectation[]
            memory expectations = new IPriceConfigv2.PriceFeedExpectation[](1);
        expectations[0] = IPriceConfigv2.PriceFeedExpectation({
            expectedPrice: 20e18,
            toleranceBps: 0
        });

        vm.prank(priceManager);
        uint256 actionId = priceConfig.queueUpdateAsset(address(ohm), params, expectations);

        _warpPastTimelockDelay();
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceConfigv2.IPriceConfigv2_PriceFeedOutOfBounds.selector,
                address(ohm),
                0,
                10e18,
                20e18,
                20e18
            )
        );
        priceConfig.executeQueuedAction(actionId);

        IPriceConfigv2.QueuedAction memory action = priceConfig.getQueuedAction(actionId);
        assertEq(action.executed, false, "Failed action should remain unexecuted");
        assertEq(action.cancelled, false, "Failed action should not be cancelled");
        assertGt(action.payload.length, 0, "Failed action payload should remain");

        vm.prank(emergency);
        priceConfig.cancelQueuedAction(actionId);

        action = priceConfig.getQueuedAction(actionId);
        assertEq(action.cancelled, true, "Failed action should be cancellable");
        assertEq(action.payload.length, 0, "Cancelled action payload should be cleared");
    }

    // given the contract is enabled
    //  given the caller is emergency
    //   [X] cancellation succeeds
    //  given the caller is not emergency
    //   [X] cancellation reverts
    //  when the action is cancelled
    //   [X] later execution reverts

    function test_cancelQueuedAction_onlyEmergency(address caller_) public {
        _addBaseAssets();

        vm.prank(priceManager);
        uint256 actionId = priceConfig.queueRemoveAsset(address(ohm));

        if (caller_ != emergency) {
            vm.expectRevert(
                abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ROLE_EMERGENCY)
            );
        }
        vm.prank(caller_);
        priceConfig.cancelQueuedAction(actionId);

        if (caller_ != emergency) {
            IPriceConfigv2.QueuedAction memory pendingAction = priceConfig.getQueuedAction(
                actionId
            );
            assertEq(pendingAction.cancelled, false, "Non-emergency should not cancel action");

            vm.prank(emergency);
            priceConfig.cancelQueuedAction(actionId);
        }

        _warpPastTimelockDelay();
        vm.expectRevert(
            abi.encodeWithSelector(IPriceConfigv2.IPriceConfigv2_ActionCancelled.selector, actionId)
        );
        priceConfig.executeQueuedAction(actionId);
    }

    /* ========== PRICEv2 Submodule Installation/Upgrade ========== */

    function test_installSubmodule_givenDisabled_reverts() public givenDisabled {
        // Create new submodule to install
        MockStrategy newStrategy = new MockStrategy(PRICE);

        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(admin);
        priceConfig.installSubmodule(address(newStrategy));
    }

    function test_installSubmodule_unauthorizedUser_reverts(address user_) public {
        vm.assume(user_ != admin && user_ != priceManager);

        // Create new submodule to install
        MockStrategy newStrategy = new MockStrategy(PRICE);

        // Confirm submodule is not installed on PRICE
        address submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(0));

        // Try to install submodule with unauthorized account, expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);
        vm.prank(user_);
        priceConfig.installSubmodule(address(newStrategy));

        // Confirm submodule was not installed
        submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(0));

        // Try to install submodule with admin account, expect success
        vm.prank(admin);
        priceConfig.installSubmodule(address(newStrategy));

        // Confirm submodule was installed immediately
        submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(newStrategy));
    }

    function test_installSubmodule() public {
        // Create new submodule to install
        MockStrategy newStrategy = new MockStrategy(PRICE);

        // Confirm submodule is not installed on PRICE
        address submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(0));

        // Install new submodule with admin account
        vm.prank(admin);
        priceConfig.installSubmodule(address(newStrategy));

        // Confirm submodule was installed immediately
        submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(newStrategy));
    }

    // given the contract is not enabled
    //  [X] it reverts
    // given the caller is not admin nor price admin
    //  [X] it reverts
    // when no installed submodule has the keycode
    //  [X] it reverts
    // when replacement has the same address
    //  [X] it reverts
    // when replacement does not implement ISubmodule
    //  [X] it reverts
    // when replacement does not support ERC165
    //  [X] it reverts
    // [X] it queues the upgradeSubmodule action
    // [X] the upgradeSubmodule action can be executed after the timelock

    function test_queueUpgradeSubmodule_givenDisabled_reverts() public givenDisabled {
        // Create mock upgrade for chainlink submodule
        MockUpgradedSubmodulePrice newChainlink = new MockUpgradedSubmodulePrice(PRICE);

        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(admin);
        priceConfig.queueUpgradeSubmodule(address(newChainlink));
    }

    function test_queueUpgradeSubmodule_queuesExpectedAction() public {
        MockUpgradedSubmodulePrice newChainlink = new MockUpgradedSubmodulePrice(PRICE);

        bytes memory payload = abi.encode(address(newChainlink));
        (
            uint256 expectedActionId,
            uint48 queuedAt,
            uint48 executableAt,
            uint48 expiresAt
        ) = _expectQueuedAction(IPriceConfigv2.TimelockAction.UpgradeSubmodule, admin, payload);

        vm.prank(admin);
        uint256 actionId = priceConfig.queueUpgradeSubmodule(address(newChainlink));

        _assertQueuedAction(
            actionId,
            expectedActionId,
            IPriceConfigv2.TimelockAction.UpgradeSubmodule,
            admin,
            queuedAt,
            executableAt,
            expiresAt,
            payload
        );
    }

    function test_queueUpgradeSubmodule_givenNoInstalledSubmoduleForKeycode_reverts() public {
        MockStrategy newStrategy = new MockStrategy(PRICE);

        vm.expectRevert(
            abi.encodeWithSelector(
                ModuleWithSubmodules.Module_InvalidSubmoduleUpgrade.selector,
                newStrategy.SUBKEYCODE()
            )
        );
        vm.prank(admin);
        priceConfig.queueUpgradeSubmodule(address(newStrategy));
    }

    function test_queueUpgradeSubmodule_givenSameSubmoduleAddress_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ModuleWithSubmodules.Module_InvalidSubmoduleUpgrade.selector,
                toSubKeycode("PRICE.CHAINLINK")
            )
        );
        vm.prank(admin);
        priceConfig.queueUpgradeSubmodule(address(chainlinkPrice));
    }

    function test_queueUpgradeSubmodule_givenInvalidSubmoduleInterface_reverts() public {
        MockInvalidSubmodule invalidSubmodule = new MockInvalidSubmodule(PRICE);

        vm.expectRevert(
            abi.encodeWithSelector(
                ModuleWithSubmodules.Module_SubmoduleInterfaceNotImplemented.selector,
                address(invalidSubmodule)
            )
        );
        vm.prank(admin);
        priceConfig.queueUpgradeSubmodule(address(invalidSubmodule));
    }

    function test_queueUpgradeSubmodule_givenSubmoduleWithoutERC165_reverts() public {
        MockSubmoduleNoERC165 noERC165Submodule = new MockSubmoduleNoERC165(PRICE);

        vm.expectRevert(
            abi.encodeWithSelector(
                ModuleWithSubmodules.Module_SubmoduleInterfaceNotImplemented.selector,
                address(noERC165Submodule)
            )
        );
        vm.prank(admin);
        priceConfig.queueUpgradeSubmodule(address(noERC165Submodule));
    }

    function test_queueUpgradeSubmodule_unauthorizedUser_reverts(address user_) public {
        vm.assume(user_ != admin && user_ != priceManager);

        // Create mock upgrade for chainlink submodule
        MockUpgradedSubmodulePrice newChainlink = new MockUpgradedSubmodulePrice(PRICE);

        // Confirm chainlink submodule is installed on PRICE and the version is 1.0
        address chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(chainlinkPrice));
        (uint8 major, uint8 minor) = Submodule(chainlink).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        // Try to queue chainlink submodule upgrade with unauthorized account, expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);
        vm.prank(user_);
        priceConfig.queueUpgradeSubmodule(address(newChainlink));

        // Confirm chainlink submodule was not upgraded
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(chainlinkPrice));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        // Try to queue chainlink submodule upgrade with admin account, expect success
        vm.prank(admin);
        uint256 actionId = priceConfig.queueUpgradeSubmodule(address(newChainlink));

        // Confirm chainlink submodule is not upgraded until the timelock is executed
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(chainlinkPrice));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        _executeQueuedAction(actionId);

        // Confirm chainlink submodule was upgraded after execution
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(newChainlink));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 2);
        assertEq(minor, 0);
    }

    function test_queueUpgradeSubmodule() public {
        // Create mock upgrade for chainlink submodule
        MockUpgradedSubmodulePrice newChainlink = new MockUpgradedSubmodulePrice(PRICE);

        // Confirm chainlink submodule is installed on PRICE and the version is 1.0
        address chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(chainlinkPrice));
        (uint8 major, uint8 minor) = Submodule(chainlink).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        // Queue chainlink submodule upgrade with admin account
        vm.prank(admin);
        uint256 actionId = priceConfig.queueUpgradeSubmodule(address(newChainlink));

        // Confirm chainlink submodule is not upgraded until the timelock is executed
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(chainlinkPrice));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        _executeQueuedAction(actionId);

        // Confirm chainlink submodule was upgraded after execution
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(newChainlink));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 2);
        assertEq(minor, 0);
    }

    function test_execOnSubmodule_givenDisabled_reverts() public givenDisabled {
        // Perform an action on the submodule
        uint256[] memory samplePrices = new uint256[](1);
        samplePrices[0] = 11e18;

        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(priceManager);
        priceConfig.execOnSubmodule(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            abi.encodeWithSelector(
                SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                samplePrices,
                bytes("")
            )
        );
    }

    function test_execOnSubmodule(uint8 role_) public {
        role_ = uint8(bound(role_, 0, 1));
        address caller = role_ == 0 ? admin : priceManager;
        MockStrategy newStrategy = new MockStrategy(PRICE);

        vm.prank(admin);
        priceConfig.installSubmodule(address(newStrategy));
        SubKeycode newStrategyKeycode = newStrategy.SUBKEYCODE();

        assertEq(newStrategy.storedValue(), 0, "Initial stored value");

        vm.prank(caller);
        priceConfig.execOnSubmodule(
            newStrategyKeycode,
            abi.encodeWithSelector(MockStrategy.setStoredValue.selector, uint256(11))
        );

        assertEq(newStrategy.storedValue(), 11, "Value should update immediately");
    }

    function test_execOnSubmodule_unauthorizedUser_reverts(address user_) public {
        vm.assume(user_ != admin && user_ != priceManager);

        // Perform an action on the submodule
        uint256[] memory samplePrices = new uint256[](1);
        samplePrices[0] = 11e18;

        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);

        vm.prank(user_);
        priceConfig.execOnSubmodule(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            abi.encodeWithSelector(
                SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                samplePrices,
                bytes("")
            )
        );
    }

    /* ========== PRICE STORAGE ========== */

    function test_storePrice_givenDisabled_reverts() public givenDisabled {
        _expectRevertNotEnabled();

        // Call function
        vm.prank(priceManager);
        priceConfig.storeObservation(address(ohm));
    }

    function test_storePrice_unauthorizedUser_reverts(address user_) public {
        vm.assume(user_ != admin && user_ != priceManager);

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Try to store price with unauthorized account, expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);

        vm.prank(user_);
        priceConfig.storeObservation(address(ohm));

        // Try with priceManager account, expect success
        vm.prank(priceManager);
        priceConfig.storeObservation(address(ohm));

        // Verify price was stored by checking Variant.LAST returns a price
        (uint256 price, uint48 timestamp) = PRICE.getPrice(address(ohm), IPRICEv2.Variant.LAST);
        assertGt(price, 0, "Price should be stored");
        assertGt(timestamp, 0, "Timestamp should be set");
    }

    function test_storePrice(uint8 role_) public {
        role_ = uint8(bound(role_, 0, 1));
        address caller = role_ == 0 ? admin : priceManager;

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Store price using authorized caller
        vm.prank(caller);
        priceConfig.storeObservation(address(ohm));

        // Verify price was stored by checking Variant.LAST returns a price
        (uint256 price, uint48 timestamp) = PRICE.getPrice(address(ohm), IPRICEv2.Variant.LAST);
        assertGt(price, 0, "Price should be stored");
        assertEq(timestamp, block.timestamp, "Timestamp should match block timestamp");
    }

    function test_storeObservations_givenDisabled_reverts() public givenDisabled {
        _expectRevertNotEnabled();

        // Call function
        vm.prank(priceManager);
        priceConfig.storeObservations();
    }

    function test_storeObservations_unauthorizedUser_reverts(address user_) public {
        vm.assume(user_ != admin && user_ != priceManager);

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Try to store observations with unauthorized account, expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);

        vm.prank(user_);
        priceConfig.storeObservations();

        // Try with priceManager account, expect success
        vm.prank(priceManager);
        priceConfig.storeObservations();

        // Verify observations were stored by checking Variant.LAST returns a price
        (uint256 price, uint48 timestamp) = PRICE.getPrice(address(ohm), IPRICEv2.Variant.LAST);
        assertGt(price, 0, "Price should be stored");
        assertGt(timestamp, 0, "Timestamp should be set");
    }

    function test_storeObservations(uint8 role_) public {
        role_ = uint8(bound(role_, 0, 1));
        address caller = role_ == 0 ? admin : priceManager;

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Store observations using authorized caller
        vm.prank(caller);
        priceConfig.storeObservations();

        // Verify observations were stored by checking Variant.LAST returns a price
        (uint256 price, uint48 timestamp) = PRICE.getPrice(address(ohm), IPRICEv2.Variant.LAST);
        assertGt(price, 0, "Price should be stored");
        assertEq(timestamp, block.timestamp, "Timestamp should match block timestamp");
    }

    function test_supportsInterface() public view {
        ERC165Helper.validateSupportsInterface(address(priceConfig));
        assertEq(
            priceConfig.supportsInterface(type(IERC165).interfaceId),
            true,
            "IERC165 mismatch"
        );
        assertEq(
            priceConfig.supportsInterface(type(IPriceConfigv2).interfaceId),
            true,
            "IPriceConfigv2 mismatch"
        );
        assertEq(
            priceConfig.supportsInterface(type(IEnabler).interfaceId),
            true,
            "IEnabler mismatch"
        );
        assertEq(
            priceConfig.supportsInterface(type(IVersioned).interfaceId),
            true,
            "IVersioned mismatch"
        );
    }
}
/// forge-lint: disable-end(mixed-case-variable,mixed-case-function,unwrapped-modifier-logic)
