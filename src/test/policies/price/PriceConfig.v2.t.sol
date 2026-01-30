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
import {fromSubKeycode, SubKeycode, Submodule, toSubKeycode} from "src/Submodules.sol";
import {PriceConfigv2} from "src/policies/price/PriceConfig.v2.sol";
import {PriceSubmodule} from "src/modules/PRICE/PRICE.v2.sol";
import {OlympusPricev1_2} from "src/modules/PRICE/OlympusPrice.v1_2.sol";
import {OlympusPricev2} from "src/modules/PRICE/OlympusPrice.v2.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {SimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

// Tests for PriceConfig v1.0.0
//
// PriceConfig Setup and Permissions
// [X] configureDependencies
// [X] requestPermissions
// [X] disabled by default
//
// PRICEv2 Configuration
// [X] addAssetPrice
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call
//     [X] inputs to IPRICEv2.addAsset are correct
// [X] removeAssetPrice
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call
//     [X] inputs to IPRICEv2.removeAsset are correct
// [X] updateAssetPriceFeeds
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call
//     [X] inputs to IPRICEv2.updateAssetPriceFeeds are correct
// [X] updateAssetPriceStrategy
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call
//     [X] inputs to IPRICEv2.updateAssetPriceStrategy are correct
// [X] updateAssetMovingAverage
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call
//     [X] inputs to IPRICEv2.updateAssetMovingAverage are correct
//
// PRICEv2 Submodule Installation/Upgrade
// [X] installSubmodule
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call
//     [X] inputs to IPRICEv2.installSubmodule are correct
// [X] upgradeSubmodule
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call
//     [X] inputs to IPRICEv2.upgradeSubmodule are correct
// [X] execOnSubmodule
//     [X] only when contract is enabled
//     [X] only admin or price_admin role can call

type Category is bytes32;
type CategoryGroup is bytes32;

contract MockStrategy is PriceSubmodule {
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

    bytes32 internal constant ROLE_ADMIN = "admin";
    bytes32 internal constant ROLE_PRICE_ADMIN = "price_admin";
    bytes32 internal constant ROLE_EMERGENCY = "emergency";

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

        vm.prank(priceManager);
        priceConfig.addAssetPrice(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strat,
            feeds
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
            funcSelector: PRICE.updateAssetPriceFeeds.selector
        });
        expectedPerms[3] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.updateAssetPriceStrategy.selector
        });
        expectedPerms[4] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.updateAssetMovingAverage.selector
        });
        expectedPerms[5] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.installSubmodule.selector
        });
        expectedPerms[6] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.upgradeSubmodule.selector
        });
        expectedPerms[7] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.execOnSubmodule.selector
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

    function test_addAssetPrice_notEnabled_reverts() public givenDisabled {
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
        priceConfig.addAssetPrice(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strategyComponent,
            feedComponents
        );
    }

    function test_addAssetPrice_unauthorizedUser_reverts(address user_) public {
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

        // Try to add asset to PRICEv2 with unauthorized account, expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(user_);
        priceConfig.addAssetPrice(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strategyComponent,
            feedComponents
        );

        // Confirm asset was not added
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, false);

        // Try to add asset to PRICEv2 with priceManager account, expect success
        vm.prank(priceManager);
        priceConfig.addAssetPrice(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strategyComponent,
            feedComponents
        );
    }

    function test_addAssetPrice(uint8 role_) public {
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
        priceConfig.addAssetPrice(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strategyComponent,
            feedComponents
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

    function test_removeAssetPrice_notEnabled_reverts() public givenDisabled {
        _expectRevertNotEnabled();

        // Call function
        vm.prank(priceManager);
        priceConfig.removeAssetPrice(address(ohm));
    }

    function test_removeAssetPrice_unauthorizedUser_reverts(address user_) public {
        vm.assume(user_ != admin && user_ != priceManager);

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm asset is approved
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);

        // Try to remove asset from PRICEv2 with unauthorized account, expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(user_);
        priceConfig.removeAssetPrice(address(ohm));

        // Confirm asset was not removed
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);

        // Try to remove asset from PRICEv2 with priceManager account, expect success
        vm.prank(priceManager);
        priceConfig.removeAssetPrice(address(ohm));

        // Confirm asset was removed
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, false);
    }

    function test_removeAssetPrice(uint8 role_) public {
        role_ = uint8(bound(role_, 0, 1));
        address caller = role_ == 0 ? admin : priceManager;

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm asset is approved
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);

        // Remove asset from PRICEv2 using authorized caller
        vm.prank(caller);
        priceConfig.removeAssetPrice(address(ohm));

        // Confirm asset is not approved and all data deleted
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

    function test_updateAssetPriceFeeds_notEnabled_reverts() public givenDisabled {
        // Setup data to update feeds
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](0);

        // Expect revert
        _expectRevertNotEnabled();

        // Update feeds
        vm.prank(priceManager);
        priceConfig.updateAssetPriceFeeds(address(ohm), newFeeds);
    }

    function test_updateAssetPriceFeeds_unauthorizedUser_reverts(address user_) public {
        vm.assume(user_ != admin && user_ != priceManager);

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm current has two feeds
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        IPRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 2);

        // Setup data to update feeds
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = feeds[0];

        // Try to update feeds for asset on PRICEv2 with unauthorized account, expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(user_);
        priceConfig.updateAssetPriceFeeds(address(ohm), newFeeds);

        // Confirm feeds were not updated
        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 2);

        // Try to update feeds for asset on PRICEv2 with priceManager account, expect success
        vm.prank(priceManager);
        priceConfig.updateAssetPriceFeeds(address(ohm), newFeeds);

        // Confirm feeds were updated
        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 1);
    }

    function test_updateAssetPriceFeeds(uint8 role_) public {
        role_ = uint8(bound(role_, 0, 1));
        address caller = role_ == 0 ? admin : priceManager;

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm current has two feeds
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        IPRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 2);

        // Setup data to update feeds
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = feeds[0];

        // Update feeds using authorized caller
        vm.prank(caller);
        priceConfig.updateAssetPriceFeeds(address(ohm), newFeeds);

        // Confirm feeds were updated
        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 1);
        assertEq(fromSubKeycode(feeds[0].target), fromSubKeycode(newFeeds[0].target));
        assertEq(feeds[0].selector, newFeeds[0].selector);
        assertEq(feeds[0].params, newFeeds[0].params);
    }

    function test_updateAssetPriceStrategy_notEnabled_reverts() public givenDisabled {
        // Prepare arguments
        IPRICEv2.Component memory newStrat = IPRICEv2.Component(
            strategy.SUBKEYCODE(),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(1)
        );

        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(priceManager);
        priceConfig.updateAssetPriceStrategy(address(ohm), newStrat, false);
    }

    function test_updateAssetPriceStrategy_unauthorizedUser_reverts(address user_) public {
        vm.assume(user_ != admin && user_ != priceManager);

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm currently uses the getFirstNonZeroPrice strategy
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        IPRICEv2.Component memory strat = abi.decode(asset.strategy, (IPRICEv2.Component));
        /// forge-lint: disable-next-line(unsafe-typecast)
        assertEq(fromSubKeycode(strat.target), bytes20("PRICE.SIMPLESTRATEGY"));
        assertEq(strat.selector, SimplePriceFeedStrategy.getFirstNonZeroPrice.selector);
        assertEq(strat.params, abi.encode(0));

        // Setup data to update strategy
        MockStrategy newStrategy = new MockStrategy(PRICE);
        IPRICEv2.Component memory newStrat = IPRICEv2.Component(
            newStrategy.SUBKEYCODE(),
            newStrategy.getOnePrice.selector,
            abi.encode(1)
        );
        vm.prank(admin);
        priceConfig.installSubmodule(address(newStrategy));

        // Try to update strategy for asset on PRICEv2 with unauthorized account, expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(user_);
        priceConfig.updateAssetPriceStrategy(address(ohm), newStrat, false);

        // Confirm strategy was not updated
        asset = PRICE.getAssetData(address(ohm));
        strat = abi.decode(asset.strategy, (IPRICEv2.Component));
        /// forge-lint: disable-next-line(unsafe-typecast)
        assertEq(fromSubKeycode(strat.target), bytes20("PRICE.SIMPLESTRATEGY"));
        assertEq(strat.selector, SimplePriceFeedStrategy.getFirstNonZeroPrice.selector);
        assertEq(strat.params, abi.encode(0));
        assertEq(asset.useMovingAverage, true);

        // Try to update strategy for asset on PRICEv2 with priceManager account, expect success
        vm.prank(priceManager);
        priceConfig.updateAssetPriceStrategy(address(ohm), newStrat, false);

        // Confirm feeds were updated
        asset = PRICE.getAssetData(address(ohm));
        strat = abi.decode(asset.strategy, (IPRICEv2.Component));
        assertEq(fromSubKeycode(strat.target), fromSubKeycode(newStrat.target));
        assertEq(strat.selector, newStrat.selector);
        assertEq(strat.params, newStrat.params);
        assertEq(asset.useMovingAverage, false);
    }

    function test_updateAssetPriceStrategy(uint8 role_) public {
        role_ = uint8(bound(role_, 0, 1));
        address caller = role_ == 0 ? admin : priceManager;

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm currently uses the getFirstNonZeroPrice strategy
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        IPRICEv2.Component memory strat = abi.decode(asset.strategy, (IPRICEv2.Component));
        /// forge-lint: disable-next-line(unsafe-typecast)
        assertEq(fromSubKeycode(strat.target), bytes20("PRICE.SIMPLESTRATEGY"));
        assertEq(strat.selector, SimplePriceFeedStrategy.getFirstNonZeroPrice.selector);
        assertEq(strat.params, abi.encode(0));
        assertEq(asset.useMovingAverage, true);

        // Setup data to update strategy
        MockStrategy newStrategy = new MockStrategy(PRICE);
        IPRICEv2.Component memory newStrat = IPRICEv2.Component(
            newStrategy.SUBKEYCODE(),
            newStrategy.getOnePrice.selector,
            abi.encode(1)
        );
        vm.prank(admin);
        priceConfig.installSubmodule(address(newStrategy));

        // Update strategy for asset on PRICEv2 with authorized caller
        vm.prank(caller);
        priceConfig.updateAssetPriceStrategy(address(ohm), newStrat, false);

        // Confirm strategy was updated
        asset = PRICE.getAssetData(address(ohm));
        strat = abi.decode(asset.strategy, (IPRICEv2.Component));
        assertEq(fromSubKeycode(strat.target), fromSubKeycode(newStrat.target));
        assertEq(strat.selector, newStrat.selector);
        assertEq(strat.params, newStrat.params);
        assertEq(asset.useMovingAverage, false);
    }

    function test_updateAssetMovingAverage_notEnabled_reverts() public givenDisabled {
        // Prepare arguments
        uint256[] memory obs = new uint256[](0);

        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(priceManager);
        priceConfig.updateAssetMovingAverage(
            address(ohm),
            true,
            uint32(5 days),
            uint48(block.timestamp - 1),
            obs
        );
    }

    function test_updateAssetMovingAverage_unauthorizedUser_reverts(address user_) public {
        vm.assume(user_ != admin && user_ != priceManager);

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Update ohm strategy to not use a moving average so we can remove it later
        vm.prank(priceManager);
        priceConfig.updateAssetPriceStrategy(
            address(ohm),
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                abi.encode(0)
            ),
            false
        );

        // Confirm that ohm currently stores a moving average
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.storeMovingAverage, true);

        // Try to update moving average for asset on PRICEv2 with unauthorized account, expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(user_);
        priceConfig.updateAssetMovingAverage(
            address(ohm),
            false,
            uint32(0),
            uint16(0),
            new uint256[](0)
        );

        // Confirm moving average was not updated
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.storeMovingAverage, true);

        // Try to update moving average for asset on PRICEv2 with priceManager account, expect success
        vm.prank(priceManager);
        priceConfig.updateAssetMovingAverage(
            address(ohm),
            false,
            uint32(0),
            uint16(0),
            new uint256[](0)
        );

        // Confirm moving average was updated
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.storeMovingAverage, false);
    }

    function test_updateAssetMovingAverage() public {
        // Add a new asset to PRICEv2 that doesn't have a moving average
        MockERC20 fohm = new MockERC20("Fake OHM", "FOHM", 9);

        IPRICEv2.Component memory strategyComponent = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        IPRICEv2.Component[] memory feedComponents = new IPRICEv2.Component[](1);
        feedComponents[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ChainlinkPriceFeeds.OneFeedParams(ohmUsdPriceFeed, uint48(24 hours)))
        );

        vm.prank(priceManager);
        priceConfig.addAssetPrice(
            address(fohm),
            false,
            false,
            uint32(0),
            uint48(0),
            new uint256[](0),
            strategyComponent,
            feedComponents
        );

        // Confirm that fohm currently does not store a moving average and other data is zero
        IPRICEv2.Asset memory asset = PRICE.getAssetData(address(fohm));
        assertEq(asset.storeMovingAverage, false);
        assertEq(asset.movingAverageDuration, uint32(0));
        assertEq(asset.nextObsIndex, uint16(0));
        assertEq(asset.numObservations, uint16(1)); // 1 because of cached value
        assertEq(asset.lastObservationTime, uint48(block.timestamp)); // current timestamp because of cached value
        assertEq(asset.cumulativeObs, uint256(0));
        assertEq(asset.obs.length, uint256(1)); // cached value

        // Update moving average with priceManager account
        uint256[] memory obs = _makeObservations(fohm, feedComponents[0], 15);
        vm.prank(priceManager);
        priceConfig.updateAssetMovingAverage(
            address(fohm),
            true,
            uint32(5 days),
            uint48(block.timestamp - 1),
            obs
        );

        // Confirm moving average was updated and other data is correct
        asset = PRICE.getAssetData(address(fohm));
        assertEq(asset.storeMovingAverage, true);
        assertEq(asset.movingAverageDuration, uint32(5 days));
        assertEq(asset.nextObsIndex, uint16(0));
        assertEq(asset.numObservations, uint16(15));
        assertEq(asset.lastObservationTime, uint48(block.timestamp - 1));
        uint256 cumObs;
        for (uint256 i = 0; i < obs.length; i++) {
            cumObs += obs[i];
        }
        assertEq(asset.cumulativeObs, cumObs);
        assertEq(asset.obs.length, uint256(15));
    }

    /* ========== PRICEv2 Submodule Installation/Upgrade ========== */

    function test_installSubmodule_notEnabled_reverts() public givenDisabled {
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

        // Confirm submodule was installed
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

        // Confirm submodule was installed
        submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(newStrategy));
    }

    function test_upgradeSubmodule_notEnabled_reverts() public givenDisabled {
        // Create mock upgrade for chainlink submodule
        MockUpgradedSubmodulePrice newChainlink = new MockUpgradedSubmodulePrice(PRICE);

        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(admin);
        priceConfig.upgradeSubmodule(address(newChainlink));
    }

    function test_upgradeSubmodule_unauthorizedUser_reverts(address user_) public {
        vm.assume(user_ != admin && user_ != priceManager);

        // Create mock upgrade for chainlink submodule
        MockUpgradedSubmodulePrice newChainlink = new MockUpgradedSubmodulePrice(PRICE);

        // Confirm chainlink submodule is installed on PRICE and the version is 1.0
        address chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(chainlinkPrice));
        (uint8 major, uint8 minor) = Submodule(chainlink).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        // Try to upgrade chainlink submodule with unauthorized account, expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);
        vm.prank(user_);
        priceConfig.upgradeSubmodule(address(newChainlink));

        // Confirm chainlink submodule was not upgraded
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(chainlinkPrice));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        // Try to upgrade chainlink submodule with admin account, expect success
        vm.prank(admin);
        priceConfig.upgradeSubmodule(address(newChainlink));

        // Confirm chainlink submodule was upgraded
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(newChainlink));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 2);
        assertEq(minor, 0);
    }

    function test_upgradeSubmodule() public {
        // Create mock upgrade for chainlink submodule
        MockUpgradedSubmodulePrice newChainlink = new MockUpgradedSubmodulePrice(PRICE);

        // Confirm chainlink submodule is installed on PRICE and the version is 1.0
        address chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(chainlinkPrice));
        (uint8 major, uint8 minor) = Submodule(chainlink).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        // Upgrade chainlink submodule with admin account, expect success
        vm.prank(admin);
        priceConfig.upgradeSubmodule(address(newChainlink));

        // Confirm chainlink submodule was upgraded
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(newChainlink));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 2);
        assertEq(minor, 0);
    }

    function test_execOnSubmodule_notEnabled_reverts() public givenDisabled {
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

        // Perform an action on the submodule
        uint256[] memory samplePrices = new uint256[](1);
        samplePrices[0] = 11e18;

        vm.prank(caller);
        priceConfig.execOnSubmodule(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            abi.encodeWithSelector(
                SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                samplePrices,
                bytes("")
            )
        );

        // No error
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
