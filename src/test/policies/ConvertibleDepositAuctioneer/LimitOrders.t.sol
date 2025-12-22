// SPDX-License-Identifier: AGPL-3.0
// solhint-disable use-natspec
// solhint-disable gas-small-strings
// solhint-disable function-max-lines
// solhint-disable gas-increment-by-one
// solhint-disable one-contract-per-file
pragma solidity >=0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin-5.3.0/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin-5.3.0/token/ERC721/ERC721.sol";
import {ERC4626} from "@openzeppelin-5.3.0/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin-5.3.0/utils/math/Math.sol";

import {CDAuctioneerLimitOrders} from "src/policies/deposits/LimitOrders.sol";
import {MockConvertibleDepositAuctioneer} from "src/test/mocks/MockConvertibleDepositAuctioneer.sol";
import {Kernel} from "src/Kernel.sol";

// ========== MOCKS ========== //

contract MockUSDS is ERC20 {
    constructor() ERC20("USDS", "USDS") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

contract MockSUSDS is ERC4626 {
    uint256 public exchangeRate = 1e18; // 1:1 initially

    constructor(IERC20 asset_) ERC4626(asset_) ERC20("sUSDS", "sUSDS") {}

    function setExchangeRate(uint256 rate_) external {
        exchangeRate = rate_;
    }

    function totalAssets() public view override returns (uint256) {
        return (totalSupply() * exchangeRate) / 1e18;
    }

    function _convertToShares(
        uint256 assets,
        Math.Rounding
    ) internal view override returns (uint256) {
        return (assets * 1e18) / exchangeRate;
    }

    function _convertToAssets(
        uint256 shares,
        Math.Rounding
    ) internal view override returns (uint256) {
        return (shares * exchangeRate) / 1e18;
    }
}

contract MockReceiptToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockPositionNFT is ERC721 {
    uint256 public nextTokenId = 1;

    constructor() ERC721("Position", "POS") {}

    function mint(address to) external returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }
}

// ========== TESTS ========== //

contract CDAuctioneerLimitOrdersTest is Test {
    CDAuctioneerLimitOrders public limitOrders;
    MockUSDS public usds;
    MockSUSDS public sUsds;
    MockReceiptToken public receiptToken3;
    MockReceiptToken public receiptToken6;
    MockPositionNFT public positionNFT;
    MockConvertibleDepositAuctioneer public cdAuctioneer;
    Kernel public kernel;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public filler = makeAddr("filler");
    address public yieldRecipient = makeAddr("yieldRecipient");

    uint8 public constant PERIOD_3 = 3;
    uint8 public constant PERIOD_6 = 6;

    uint256 public constant MIN_BID = 100e18;

    function setUp() public {
        // Deploy kernel
        kernel = new Kernel();

        // Deploy mocks
        usds = new MockUSDS();
        sUsds = new MockSUSDS(IERC20(address(usds)));
        receiptToken3 = new MockReceiptToken("Receipt3", "RCT3");
        receiptToken6 = new MockReceiptToken("Receipt6", "RCT6");
        positionNFT = new MockPositionNFT();

        // Deploy mock auctioneer
        cdAuctioneer = new MockConvertibleDepositAuctioneer(kernel, address(usds));

        // Configure mock auctioneer
        cdAuctioneer.setMinimumBid(MIN_BID);
        cdAuctioneer.setMockPrice(30e18);
        cdAuctioneer.setDepositPeriodEnabled(PERIOD_3, true);
        cdAuctioneer.setDepositPeriodEnabled(PERIOD_6, true);
        cdAuctioneer.setReceiptToken(PERIOD_3, address(receiptToken3));
        cdAuctioneer.setReceiptToken(PERIOD_6, address(receiptToken6));
        cdAuctioneer.setPositionNFT(address(positionNFT));

        // Deploy limit orders contract
        uint8[] memory periods = new uint8[](2);
        periods[0] = PERIOD_3;
        periods[1] = PERIOD_6;

        address[] memory receiptTokens = new address[](2);
        receiptTokens[0] = address(receiptToken3);
        receiptTokens[1] = address(receiptToken6);

        limitOrders = new CDAuctioneerLimitOrders(
            owner,
            address(cdAuctioneer),
            address(usds),
            address(sUsds),
            address(positionNFT),
            yieldRecipient,
            periods,
            receiptTokens
        );

        // Fund users
        usds.mint(alice, 100_000e18);
        usds.mint(bob, 100_000e18);

        // Approve limit orders contract
        vm.prank(alice);
        usds.approve(address(limitOrders), type(uint256).max);

        vm.prank(bob);
        usds.approve(address(limitOrders), type(uint256).max);
    }

    // ========== HELPER FUNCTIONS ========== //

    struct OrderParams {
        uint256 id;
        uint256 total;
        uint256 spent;
    }

    function _checkOrderInvariants(
        uint256 orderId_,
        uint256 orderTotal_,
        uint256 orderSpent_
    )
        internal
        returns (
            uint256 depositBudget,
            uint256 incentiveBudget,
            uint256 depositSpent,
            uint256 incentiveSpent
        )
    {
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId_);

        // Accumulate totals
        depositBudget = order.depositBudget;
        incentiveBudget = order.incentiveBudget;
        depositSpent = order.depositSpent;
        incentiveSpent = order.incentiveSpent;

        // Get receipt token for the order's deposit period
        ERC20 receiptToken = limitOrders.receiptTokens(order.depositPeriod);

        // Check per-order invariant: depositBudget + incentiveBudget = orderTotal_
        assertEq(
            order.depositBudget + order.incentiveBudget,
            orderTotal_,
            "Invariant: depositBudget + incentiveBudget should equal expected order total"
        );

        // Check per-order invariant: depositSpent = owner balance of receipt token
        assertEq(
            receiptToken.balanceOf(order.owner),
            order.depositSpent,
            "Invariant: depositSpent should equal owner's receipt token balance"
        );

        // Check per-order invariant: orderSpent = depositSpent + incentiveSpent
        assertEq(
            order.depositSpent + order.incentiveSpent,
            orderSpent_,
            "Invariant: orderSpent should equal depositSpent + incentiveSpent"
        );

        // Check per-order invariant: order total - order spent = depositBudget + incentiveBudget - depositSpent - incentiveSpent
        assertEq(
            order.depositBudget + order.incentiveBudget - order.depositSpent - order.incentiveSpent,
            orderTotal_ - orderSpent_,
            "Invariant: order total - order spent should equal depositBudget + incentiveBudget - depositSpent - incentiveSpent"
        );

        return (depositBudget, incentiveBudget, depositSpent, incentiveSpent);
    }

    /// @notice Checks balances and invariants for orders
    /// @param orderOne_ Order one parameters (id, total, spent)
    /// @param orderTwo_ Order two parameters (id, total, spent) - use id=type(uint256).max to skip
    /// @param fillers_ Array of filler addresses for each order (for checking filler USDS balance)
    /// @param expectedFillerBalances_ Array of expected total incentive received by fillers for each order (for checking incentiveSpent = filler balance)
    /// @param expectedShares_ Expected total sUSDS shares (calculated before action using previewDeposit)
    function checkOrdersInvariants(
        OrderParams memory orderOne_,
        OrderParams memory orderTwo_,
        address[] memory fillers_,
        uint256[] memory expectedFillerBalances_,
        uint256 expectedShares_
    ) internal {
        // Calculate totals across all orders
        uint256 totalDepositBudget;
        uint256 totalIncentiveBudget;
        uint256 totalDepositSpent;
        uint256 totalIncentiveSpent;

        // Order one
        {
            (
                uint256 orderOneDepositBudget,
                uint256 orderOneIncentiveBudget,
                uint256 orderOneDepositSpent,
                uint256 orderOneIncentiveSpent
            ) = _checkOrderInvariants(orderOne_.id, orderOne_.total, orderOne_.spent);
            totalDepositBudget += orderOneDepositBudget;
            totalIncentiveBudget += orderOneIncentiveBudget;
            totalDepositSpent += orderOneDepositSpent;
            totalIncentiveSpent += orderOneIncentiveSpent;
        }
        // Order two
        if (orderTwo_.id != type(uint256).max) {
            (
                uint256 orderTwoDepositBudget,
                uint256 orderTwoIncentiveBudget,
                uint256 orderTwoDepositSpent,
                uint256 orderTwoIncentiveSpent
            ) = _checkOrderInvariants(orderTwo_.id, orderTwo_.total, orderTwo_.spent);
            totalDepositBudget += orderTwoDepositBudget;
            totalIncentiveBudget += orderTwoIncentiveBudget;
            totalDepositSpent += orderTwoDepositSpent;
            totalIncentiveSpent += orderTwoIncentiveSpent;
        }

        // Check filler USDS balances match accumulated expected totals
        uint256 totalFillerBalances;
        for (uint256 i = 0; i < fillers_.length; i++) {
            if (fillers_[i] == address(0)) continue;

            assertEq(
                usds.balanceOf(fillers_[i]),
                expectedFillerBalances_[i],
                "Invariant: filler USDS balance should equal expected filler balance"
            );

            totalFillerBalances += expectedFillerBalances_[i];
        }

        // Invariant: totalIncentiveSpent = totalFillerBalances
        assertEq(
            totalFillerBalances,
            totalIncentiveSpent,
            "Invariant: totalFillerBalances should equal totalIncentiveSpent"
        );

        // Calculate expected USDS owed from order totals
        uint256 expectedUsdsOwed = totalDepositBudget +
            totalIncentiveBudget -
            totalDepositSpent -
            totalIncentiveSpent;

        // Check contract-level balances
        assertEq(
            usds.balanceOf(address(limitOrders)),
            0,
            "USDS balance should be 0 (all converted to sUSDS)"
        );
        assertEq(
            sUsds.balanceOf(address(limitOrders)),
            expectedShares_,
            "sUSDS balance should match expected shares"
        );
        assertEq(
            limitOrders.totalUsdsOwed(),
            expectedUsdsOwed,
            "Total USDS owed should equal calculated remaining from all orders"
        );

        // Check contract-level invariant: calculated remaining = totalUsdsOwed()
        assertEq(
            expectedUsdsOwed,
            limitOrders.totalUsdsOwed(),
            "Invariant: sum of (depositBudget + incentiveBudget - depositSpent - incentiveSpent) should equal totalUsdsOwed()"
        );

        // Check contract-level invariant: USDS value of sUSDS shares >= totalUsdsOwed()
        uint256 usdsValueOfShares = sUsds.convertToAssets(sUsds.balanceOf(address(limitOrders)));
        assertGe(
            usdsValueOfShares,
            limitOrders.totalUsdsOwed(),
            "Invariant: USDS value of sUSDS shares should be >= totalUsdsOwed()"
        );
    }

    /// @notice Convenience helper for single-order tests
    /// @param orderOneId_ The order ID to check
    /// @param expectedOrderOneTotal_ Expected total for the order (depositBudget + incentiveBudget)
    /// @param expectedOrderOneSpent_ Expected spent for the order (depositSpent + incentiveSpent)
    /// @param filler_ Filler address (for checking filler USDS balance)
    /// @param expectedFillerBalance_ Expected total incentive received by filler (for checking incentiveSpent = filler balance)
    /// @param expectedShares_ Expected total sUSDS shares (calculated before action using previewDeposit)
    function checkOrderInvariants(
        uint256 orderOneId_,
        uint256 expectedOrderOneTotal_,
        uint256 expectedOrderOneSpent_,
        address filler_,
        uint256 expectedFillerBalance_,
        uint256 expectedShares_
    ) internal {
        address[] memory fillers = new address[](1);
        fillers[0] = filler_;
        uint256[] memory expectedFillerBalances = new uint256[](1);
        expectedFillerBalances[0] = expectedFillerBalance_;
        checkOrdersInvariants(
            OrderParams({
                id: orderOneId_,
                total: expectedOrderOneTotal_,
                spent: expectedOrderOneSpent_
            }),
            OrderParams({id: type(uint256).max, total: 0, spent: 0}),
            fillers,
            expectedFillerBalances,
            expectedShares_
        );
    }

    // ========== CREATE ORDER TESTS ========== //

    // when all parameters are valid
    //  [X] it creates order successfully
    function test_createOrder_success() public {
        uint256 depositBudget = 10_000e18;
        uint256 incentiveBudget = 50e18;
        uint256 maxPrice = 35e18;
        uint256 minFillSize = 1_000e18;

        uint256 expectedShares = sUsds.previewDeposit(depositBudget + incentiveBudget);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            depositBudget, // depositBudget
            incentiveBudget, // incentiveBudget
            maxPrice, // maxPrice
            minFillSize // minFillSize
        );

        assertEq(orderId, 0, "First order should have ID 0");

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.owner, alice, "Order owner should be alice");
        assertEq(order.depositPeriod, PERIOD_3, "Order deposit period should be PERIOD_3");
        assertEq(order.depositBudget, depositBudget, "Order deposit budget should match input");
        assertEq(
            order.incentiveBudget,
            incentiveBudget,
            "Order incentive budget should match input"
        );
        assertEq(order.depositSpent, 0, "Order deposit spent should be 0 initially");
        assertEq(order.incentiveSpent, 0, "Order incentive spent should be 0 initially");
        assertEq(order.maxPrice, maxPrice, "Order max price should match input");
        assertEq(order.minFillSize, minFillSize, "Order min fill size should match input");
        assertTrue(order.active, "Order should be active");

        // Check balances and invariants
        checkOrderInvariants(
            orderId,
            depositBudget + incentiveBudget,
            0,
            address(0),
            0,
            expectedShares
        );
    }

    function test_createOrder_fuzz(
        uint256 depositBudget,
        uint256 incentiveBudget,
        uint256 maxPrice,
        uint256 minFillSize
    ) public {
        // Bound the parameters
        depositBudget = bound(depositBudget, MIN_BID, 50_000e18);
        incentiveBudget = bound(incentiveBudget, 0, depositBudget);
        maxPrice = bound(maxPrice, 1e18, 100_000e18);
        minFillSize = bound(minFillSize, MIN_BID, depositBudget);

        uint256 expectedShares = sUsds.previewDeposit(depositBudget + incentiveBudget);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            depositBudget, // depositBudget
            incentiveBudget, // incentiveBudget
            maxPrice, // maxPrice
            minFillSize // minFillSize
        );

        assertEq(orderId, 0, "First order should have ID 0");

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.owner, alice, "Order owner should be alice");
        assertEq(order.depositPeriod, PERIOD_3, "Order deposit period should be PERIOD_3");
        assertEq(order.depositBudget, depositBudget, "Order deposit budget should match input");
        assertEq(
            order.incentiveBudget,
            incentiveBudget,
            "Order incentive budget should match input"
        );
        assertEq(order.depositSpent, 0, "Order deposit spent should be 0 initially");
        assertEq(order.incentiveSpent, 0, "Order incentive spent should be 0 initially");
        assertEq(order.maxPrice, maxPrice, "Order max price should match input");
        assertEq(order.minFillSize, minFillSize, "Order min fill size should match input");
        assertTrue(order.active, "Order should be active");

        // Check balances and invariants
        checkOrderInvariants(
            orderId,
            depositBudget + incentiveBudget,
            0,
            address(0),
            0,
            expectedShares
        );
    }

    // when there are multiple orders
    //  [X] it creates multiple orders with sequential IDs
    function test_createOrder_multipleOrders() public {
        uint256 expectedShares = sUsds.previewDeposit(8_040e18);

        vm.startPrank(alice);
        uint256 orderId1 = limitOrders.createOrder(PERIOD_3, 5_000e18, 25e18, 35e18, 500e18);
        uint256 orderId2 = limitOrders.createOrder(PERIOD_6, 3_000e18, 15e18, 32e18, 300e18);
        vm.stopPrank();

        assertEq(orderId1, 0, "First order should have ID 0");
        assertEq(orderId2, 1, "Second order should have ID 1");

        // Check balances and invariants for both orders
        address[] memory fillers = new address[](2);
        uint256[] memory expectedFillerBalances = new uint256[](2);
        checkOrdersInvariants(
            OrderParams({id: orderId1, total: 5_025e18, spent: 0}),
            OrderParams({id: orderId2, total: 3_015e18, spent: 0}),
            fillers,
            expectedFillerBalances,
            expectedShares
        );
    }

    // when multiple users create orders
    //  [X] it tracks orders correctly per user
    function test_createOrder_multipleUsers() public {
        uint256 expectedShares = sUsds.previewDeposit(8_040e18);

        vm.prank(alice);
        uint256 aliceOrder = limitOrders.createOrder(PERIOD_3, 5_000e18, 25e18, 35e18, 500e18);

        vm.prank(bob);
        uint256 bobOrder = limitOrders.createOrder(PERIOD_3, 3_000e18, 15e18, 32e18, 300e18);

        assertEq(aliceOrder, 0, "Alice's order should have ID 0");
        assertEq(bobOrder, 1, "Bob's order should have ID 1");

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory aliceOrderData = limitOrders.getOrder(aliceOrder);
        CDAuctioneerLimitOrders.LimitOrder memory bobOrderData = limitOrders.getOrder(bobOrder);
        assertEq(aliceOrderData.owner, alice, "Alice's order owner should be alice");
        assertEq(bobOrderData.owner, bob, "Bob's order owner should be bob");

        // Check balances and invariants for both orders
        address[] memory fillers = new address[](2);
        uint256[] memory expectedFillerBalances = new uint256[](2);
        checkOrdersInvariants(
            OrderParams({id: aliceOrder, total: 5_000e18 + 25e18, spent: 0}),
            OrderParams({id: bobOrder, total: 3_000e18 + 15e18, spent: 0}),
            fillers,
            expectedFillerBalances,
            expectedShares
        );
    }

    // when the incentive budget is zero
    //  [X] it creates the order successfully
    function test_createOrder_zeroIncentive() public {
        uint256 expectedShares = sUsds.previewDeposit(10_000e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 0, 35e18, 1_000e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.incentiveBudget, 0, "Order incentive budget should be 0");

        // Check balances and invariants
        checkOrderInvariants(orderId, 10_000e18, 0, address(0), 0, expectedShares);
    }

    // when the recipient cannot receive ERC721 tokens
    //  [X] it reverts
    function test_createOrder_revert_recipientCannotReceiveERC721() public {
        // Create a contract that cannot receive ERC721 tokens
        MockUSDS newOwner = new MockUSDS();

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(CDAuctioneerLimitOrders.InvalidParam.selector, "recipient")
        );

        vm.prank(address(newOwner));
        limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);
    }

    // when depositBudget is zero
    //  [X] it reverts
    function test_createOrder_revert_zeroDeposit() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(CDAuctioneerLimitOrders.InvalidParam.selector, "depositBudget")
        );
        limitOrders.createOrder(PERIOD_3, 0, 50e18, 35e18, 1_000e18);
    }

    // when maxPrice is zero
    //  [X] it reverts
    function test_createOrder_revert_zeroMaxPrice() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(CDAuctioneerLimitOrders.InvalidParam.selector, "maxPrice")
        );
        limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 0, 1_000e18);
    }

    // when minFillSize is zero
    //  [X] it reverts
    function test_createOrder_revert_zeroMinFill() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(CDAuctioneerLimitOrders.InvalidParam.selector, "minFillSize")
        );
        limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 0);
    }

    // when minFillSize exceeds depositBudget
    //  [X] it reverts
    function test_createOrder_revert_minFillExceedsDeposit() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                CDAuctioneerLimitOrders.InvalidParam.selector,
                "minFillSize > depositBudget"
            )
        );
        limitOrders.createOrder(PERIOD_3, 1_000e18, 50e18, 35e18, 2_000e18);
    }

    // when minFillSize is below auctioneer minimum
    //  [X] it reverts
    function test_createOrder_revert_minFillBelowAuctioneerMin() public {
        cdAuctioneer.setMinimumBid(500e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                CDAuctioneerLimitOrders.InvalidParam.selector,
                "minFillSize < auctioneer minimum"
            )
        );
        limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 100e18);
    }

    // when depositPeriod is not enabled in the auctioneer
    //  [X] it reverts
    function test_createOrder_revert_depositPeriodDisabled() public {
        cdAuctioneer.setDepositPeriodEnabled(PERIOD_3, false);

        vm.prank(alice);
        vm.expectRevert(CDAuctioneerLimitOrders.DepositPeriodNotEnabled.selector);
        limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);
    }

    // when the deposit period is not configured
    //  [X] it reverts
    function test_createOrder_revert_receiptTokenNotConfigured() public {
        vm.prank(alice);
        vm.expectRevert(CDAuctioneerLimitOrders.ReceiptTokenNotConfigured.selector);
        limitOrders.createOrder(12, 10_000e18, 50e18, 35e18, 1_000e18);
    }

    // given the auctioneer despoit period has been enabled
    //  [X] it creates an order with the new deposit period
    function test_createOrder_depositPeriodEnabled() public {
        uint256 depositBudget = 10_000e18;
        uint256 incentiveBudget = 50e18;
        uint256 maxPrice = 35e18;
        uint256 minFillSize = 1_000e18;

        uint256 expectedShares = sUsds.previewDeposit(depositBudget + incentiveBudget);

        // Create and enable a new deposit period
        uint8 newPeriod = 12;
        {
            // Enable on the auctioneer
            cdAuctioneer.setDepositPeriodEnabled(newPeriod, true);

            // Create the receipt token
            MockReceiptToken newReceiptToken = new MockReceiptToken("Receipt12", "RCT12");

            // Set receipt token on auctioneer
            cdAuctioneer.setReceiptToken(newPeriod, address(newReceiptToken));
        }

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            newPeriod,
            depositBudget, // depositBudget
            incentiveBudget, // incentiveBudget
            maxPrice, // maxPrice
            minFillSize // minFillSize
        );

        assertEq(orderId, 0, "First order should have ID 0");

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.owner, alice, "Order owner should be alice");
        assertEq(order.depositPeriod, newPeriod, "Order deposit period should be newPeriod");
        assertEq(order.depositBudget, depositBudget, "Order deposit budget should match input");
        assertEq(
            order.incentiveBudget,
            incentiveBudget,
            "Order incentive budget should match input"
        );
        assertEq(order.depositSpent, 0, "Order deposit spent should be 0 initially");
        assertEq(order.incentiveSpent, 0, "Order incentive spent should be 0 initially");
        assertEq(order.maxPrice, maxPrice, "Order max price should match input");
        assertEq(order.minFillSize, minFillSize, "Order min fill size should match input");
        assertTrue(order.active, "Order should be active");

        // Check balances and invariants
        checkOrderInvariants(
            orderId,
            depositBudget + incentiveBudget,
            0,
            address(0),
            0,
            expectedShares
        );
    }

    // ========== FILL ORDER TESTS ========== //

    // when order is active and price is below max
    //  [X] it fills order successfully
    //  [X] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_success() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        // Calculate expected values before fill
        uint256 remainingBudget = 9_000e18 + 45e18; // Remaining deposit + remaining incentive
        uint256 expectedShares = sUsds.previewWithdraw(remainingBudget);

        vm.prank(filler);
        limitOrders.fillOrder(orderId, 1_000e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, 1000e18, "Deposit spent should equal fill amount");
        assertEq(order.incentiveSpent, 5e18, "Incentive spent should be 5e18 (1000 * 50 / 10000)"); // 1000 * 50 / 10000 = 5

        // Check alice received NFT
        assertEq(positionNFT.ownerOf(1), alice, "Alice should own NFT token ID 1");

        // Check balances and invariants after fill
        checkOrderInvariants(orderId, 10_050e18, 1000e18 + 5e18, filler, 5e18, expectedShares);
    }

    // when order is active and price is below max
    //  [X] it handles multiple fills correctly
    //  [X] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_multipleFills() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        // First fill
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 2_000e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(
            order.depositSpent,
            2_000e18,
            "After first fill, deposit spent should be 2_000e18"
        );
        assertEq(order.incentiveSpent, 10e18, "After first fill, incentive spent should be 10e18");

        // Determine the expected shares after second fill
        uint256 remainingBudget = 5_000e18 + 25e18; // Remaining deposit + remaining incentive
        uint256 expectedShares = sUsds.previewWithdraw(remainingBudget);

        // Second fill
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 3_000e18);

        // Check order status
        order = limitOrders.getOrder(orderId);
        assertEq(
            order.depositSpent,
            5_000e18,
            "After second fill, deposit spent should be 5_000e18"
        );
        assertEq(order.incentiveSpent, 25e18, "After second fill, incentive spent should be 25e18");

        // Check alice received 2 NFTs
        assertEq(positionNFT.balanceOf(alice), 2, "Alice should own 2 NFTs after two fills");

        // Check balances and invariants after fills
        checkOrderInvariants(
            orderId,
            10000e18 + 50e18,
            5_000e18 + 25e18,
            filler,
            25e18,
            expectedShares
        );
    }

    // when the remaining deposit is less than the fill amount
    //  [X] it caps fill to remaining deposit
    //  [X] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_capToRemainingDeposit() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 5_000e18, 25e18, 35e18, 1_000e18);

        // Try to fill more than remaining
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 10_000e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, 5_000e18, "Deposit spent should be capped to deposit budget"); // Capped to max
        assertEq(order.incentiveSpent, 25e18, "Incentive spent should equal incentive budget"); // All incentive paid

        // Check balances and invariants after fill
        checkOrderInvariants(orderId, 5000e18 + 25e18, 5_000e18 + 25e18, filler, 25e18, 0);
    }

    // when there have been previous fills
    //  when the fill amount completes the order
    //   when the remaining deposit is less than the minFillSize
    //    [X] it allows fill below minFillSize if final fill
    //    [X] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_belowMinFillAllowedIfFinalFill() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 2_500e18, 25e18, 35e18, 1_000e18);

        // First fill
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 2_000e18);

        // Remaining is 500e18 which is below minFill of 1000e18
        // Should still be allowed as final fill
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 500e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(
            order.depositSpent,
            2_500e18,
            "Deposit spent should equal full deposit budget after final fill"
        );
        assertEq(order.incentiveSpent, 25e18, "Incentive spent should equal incentive budget");

        // Check balances and invariants after final fill
        checkOrderInvariants(orderId, 2500e18 + 25e18, 2_500e18 + 25e18, filler, 25e18, 0);
    }

    //   [X] it gives final fill all remaining incentive
    //   [X] the deposit spent is the total deposit budget
    //   [X] the incentive spent is the total incentive budget
    //   [X] the USDS owed is 0
    function test_fillOrder_finalFillGetsAllRemainingIncentive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        // Fill most of the order
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 9_000e18);

        // Final fill - should get all remaining incentive (avoids dust)
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 1_000e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, 10_000e18, "Deposit spent should equal full deposit budget");
        assertEq(order.incentiveSpent, 50e18, "Incentive spent should equal full incentive budget");

        // Check balances and invariants after final fill
        checkOrderInvariants(orderId, 10_000e18 + 50e18, 10_000e18 + 50e18, filler, 50e18, 0);
    }

    // when filling order with zero incentive
    //  [X] it fills without paying incentive
    function test_fillOrder_zeroIncentive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 0, 35e18, 1_000e18);

        // Calculate expected values before fill
        uint256 remainingBudget = 9_000e18; // Remaining deposit (no incentive)
        uint256 expectedShares = sUsds.previewDeposit(remainingBudget);

        vm.prank(filler);
        limitOrders.fillOrder(orderId, 1_000e18);

        // Check balances and invariants after fill
        checkOrderInvariants(orderId, 10_000e18, 1_000e18, filler, 0, expectedShares);
    }

    // when minFillSize equals remaining deposit
    //  [X] it allows fill
    //  [X] the deposit spent is the fill amount
    //  [X] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_exactMinFillEqualsRemaining() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 1_000e18, 5e18, 35e18, 1_000e18);

        // minFillSize == depositBudget == 1000
        // This should work as it's both the min and final fill
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 1_000e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(
            order.depositSpent,
            1_000e18,
            "Deposit spent should equal fill amount when minFillSize equals deposit budget"
        );
        assertEq(order.incentiveSpent, 5e18, "Incentive spent should equal incentive budget");

        // Check balances and invariants after fill
        checkOrderInvariants(orderId, 1000e18 + 5e18, 1_000e18 + 5e18, filler, 5e18, 0);
    }

    // when different fillers fill same order
    //  [X] it distributes incentives correctly
    function test_fillOrder_differentFillers() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        address filler2 = makeAddr("filler2");

        vm.prank(filler);
        limitOrders.fillOrder(orderId, 2_000e18);

        // Calculate expected values before second fill
        uint256 remainingBudget = 5_000e18 + 25e18; // Remaining deposit + remaining incentive
        uint256 expectedShares = sUsds.previewDeposit(remainingBudget);

        vm.prank(filler2);
        limitOrders.fillOrder(orderId, 3_000e18);

        // Check balances and invariants after fills
        address[] memory fillers = new address[](2);
        fillers[0] = filler;
        fillers[1] = filler2;
        uint256[] memory expectedFillerBalances = new uint256[](2);
        expectedFillerBalances[0] = 10e18;
        expectedFillerBalances[1] = 15e18;
        checkOrdersInvariants(
            OrderParams({id: orderId, total: 10_000e18 + 50e18, spent: 5000e18 + 25e18}),
            OrderParams({id: type(uint256).max, total: 0, spent: 0}),
            fillers,
            expectedFillerBalances,
            expectedShares
        );
    }

    // when order is not active
    //  [X] it reverts
    function test_fillOrder_revert_orderNotActive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        vm.prank(filler);
        vm.expectRevert(CDAuctioneerLimitOrders.OrderNotActive.selector);
        limitOrders.fillOrder(orderId, 1_000e18);
    }

    // when the remaining deposit is zero
    //  [X] it reverts
    function test_fillOrder_revert_orderFullySpent() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 1_000e18, 5e18, 35e18, 1_000e18);

        vm.prank(filler);
        limitOrders.fillOrder(orderId, 1_000e18);

        vm.prank(filler);
        vm.expectRevert(CDAuctioneerLimitOrders.OrderFullySpent.selector);
        limitOrders.fillOrder(orderId, 1_000e18);
    }

    // when the fill amount is below minimum (and not final fill)
    //  [X] it reverts
    function test_fillOrder_revert_fillBelowMinimum() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        vm.prank(filler);
        vm.expectRevert(CDAuctioneerLimitOrders.FillBelowMinimum.selector);
        limitOrders.fillOrder(orderId, 500e18);
    }

    // when price is above max
    //  [X] it reverts
    function test_fillOrder_revert_priceAboveMax() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 25e18, 1_000e18); // maxPrice = 25

        cdAuctioneer.setMockPrice(30e18); // Current price is 30

        vm.prank(filler);
        vm.expectRevert(CDAuctioneerLimitOrders.PriceAboveMax.selector);
        limitOrders.fillOrder(orderId, 1_000e18);
    }

    // when ohmOut is zero
    //  [X] it reverts
    function test_fillOrder_revert_zeroOhmOut() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        cdAuctioneer.setMinimumBid(5_000e18); // Raise minimum after order creation

        vm.prank(filler);
        vm.expectRevert(CDAuctioneerLimitOrders.ZeroOhmOut.selector);
        limitOrders.fillOrder(orderId, 1_000e18);
    }

    // TODO fuzz OHM out from CD auctioneer
    // TODO fuzz incentive amount
    // TODO fuzz fill amount
    // TODO fuzz vault rate
    // TODO fuzz final fill
    // TODO fuzz multiple orders, final fill

    // ========== CANCEL ORDER TESTS ========== //

    // when order is active and not filled
    //  [X] it cancels order
    //  [X] it refunds the amount of deposit and incentive budgets
    //  [ ] it reduces the USDS owed by the full amount of deposit and incentive budgets
    function test_cancelOrder_success() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertFalse(order.active, "Order should be inactive after cancellation");

        // Alice should receive full refund
        assertEq(
            usds.balanceOf(alice) - aliceBalanceBefore,
            10_050e18,
            "Alice should receive full refund of deposit + incentive budgets"
        );

        // Check balances and invariants after cancellation (no fills, so incentiveSpent = 0)
        // TODO add handling of USDS owed for cancelled order
        checkOrderInvariants(orderId, 10000e18 + 50e18, 0, address(0), 0, 0);
    }

    // when order is active and partially filled
    //  [X] it cancels order
    //  [X] it refunds the remaining amount of deposit and incentive budgets
    //  [ ] it reduces the USDS owed by the remaining amount of deposit and incentive budgets
    function test_cancelOrder_afterPartialFill() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        // Partial fill
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 3_000e18);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        // Alice should receive remaining: 7000 deposit + 35 incentive
        uint256 expectedRefund = 7_000e18 + 35e18;
        assertEq(
            usds.balanceOf(alice) - aliceBalanceBefore,
            expectedRefund,
            "Alice should receive remaining deposit + incentive budgets after partial fill"
        );

        // Partial fill: 3000 deposit spent, so 15e18 incentive spent (3000 * 50 / 10000)
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.incentiveSpent, 15e18, "Incentive spent should be 15e18 from partial fill");

        // Check balances and invariants after cancellation
        checkOrderInvariants(orderId, 10_000e18 + 50e18, 3_000e18 + 15e18, filler, 15e18, 0);
    }

    // when caller is not order owner
    //  [X] it reverts
    function test_cancelOrder_revert_notOwner() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        vm.prank(bob);
        vm.expectRevert(CDAuctioneerLimitOrders.NotOrderOwner.selector);
        limitOrders.cancelOrder(orderId);
    }

    // when order is already cancelled
    //  [X] it reverts
    function test_cancelOrder_revert_alreadyCancelled() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        vm.prank(alice);
        vm.expectRevert(CDAuctioneerLimitOrders.OrderNotActive.selector);
        limitOrders.cancelOrder(orderId);
    }

    // TODO Fuzz tests, ensure entire amount can be withdrawn

    // ========== YIELD TESTS ========== //

    // when yield has accrued
    //  [X] it sweeps yield successfully
    function test_sweepYield_success() public {
        vm.prank(alice);
        limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        // Simulate yield by increasing exchange rate
        sUsds.setExchangeRate(1.1e18); // 10% yield

        uint256 yield = limitOrders.getAccruedYield();
        assertApproxEqRel(
            yield,
            1_005e18,
            0.01e18,
            "Accrued yield should be approximately 10% of 10_050"
        ); // ~10% of 10_050

        uint256 recipientSharesBefore = sUsds.balanceOf(yieldRecipient);

        limitOrders.sweepYield();

        assertGt(
            sUsds.balanceOf(yieldRecipient),
            recipientSharesBefore,
            "Yield recipient should receive shares after sweep"
        );

        // TODO assert solvent
    }

    // when yield has accrued
    //  [X] it transfers shares to recipient
    function test_sweepYield_transfersShares() public {
        vm.prank(alice);
        limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        sUsds.setExchangeRate(1.1e18);

        uint256 expectedShares = limitOrders.getAccruedYieldShares();

        uint256 shares = limitOrders.sweepYield();

        assertEq(shares, expectedShares, "Swept shares should equal expected accrued yield shares");
        assertEq(
            sUsds.balanceOf(yieldRecipient),
            shares,
            "Yield recipient should have received the swept shares"
        );

        // TODO assert solvent
    }

    // when no yield has accrued
    //  [X] it returns zero shares
    function test_sweepYield_revert_noYield() public {
        vm.prank(alice);
        limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        uint256 shares = limitOrders.sweepYield();
        assertEq(shares, 0, "Swept shares should be 0 when no yield has accrued");
    }

    // TODO fuzz tests

    // when yield has accrued after partial fills
    //  [X] it calculates yield correctly
    function test_getAccruedYield_afterFills() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        // Fill half
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 5_000e18);

        // Simulate yield
        sUsds.setExchangeRate(1.1e18);

        // Yield should be calculated on remaining balance
        uint256 yield = limitOrders.getAccruedYield();
        assertGt(yield, 0, "Yield should be greater than 0 after exchange rate increase");
    }

    // ========== ADMIN TESTS ========== //

    // when caller is owner
    //  [X] it sets yield recipient successfully
    function test_setYieldRecipient_success() public {
        address newRecipient = makeAddr("newRecipient");

        vm.prank(owner);
        limitOrders.setYieldRecipient(newRecipient);

        assertEq(
            limitOrders.yieldRecipient(),
            newRecipient,
            "Yield recipient should be updated to new recipient"
        );
    }

    // when caller is not owner
    //  [X] it reverts
    function test_setYieldRecipient_revert_notOwner() public {
        address newRecipient = makeAddr("newRecipient");

        vm.prank(alice);
        vm.expectRevert();
        limitOrders.setYieldRecipient(newRecipient);
    }

    // when newRecipient is zero address
    //  [X] it reverts
    function test_setYieldRecipient_revert_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(CDAuctioneerLimitOrders.InvalidParam.selector, "yieldRecipient")
        );
        limitOrders.setYieldRecipient(address(0));
    }

    // when caller is owner
    //  [X] it transfers ownership successfully
    function test_transferOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        limitOrders.transferOwnership(newOwner);

        assertEq(limitOrders.owner(), newOwner, "Contract owner should be updated to new owner");
    }

    // ========== VIEW FUNCTION TESTS ========== //

    // canFillOrder
    // when order can be filled
    //  [X] it returns true with correct price
    function test_canFillOrder_success() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        (bool canFill, string memory reason, uint256 effectivePrice) = limitOrders.canFillOrder(
            orderId,
            1_000e18
        );

        assertTrue(canFill, "Order should be fillable");
        assertEq(bytes(reason).length, 0, "Reason should be empty when order is fillable");
        assertEq(effectivePrice, 30e18, "Effective price should equal mock price"); // Mock price
    }

    // when price is above max
    //  [X] it returns false with reason
    function test_canFillOrder_priceAboveMax() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 25e18, 1_000e18);

        (bool canFill, string memory reason, uint256 effectivePrice) = limitOrders.canFillOrder(
            orderId,
            1_000e18
        );

        assertFalse(canFill, "Order should not be fillable when price is above max");
        assertEq(reason, "Price above max", "Reason should indicate price is above max");
        assertEq(effectivePrice, 30e18, "Effective price should equal mock price");
    }

    // when order is not active
    //  [X] it returns false with reason
    function test_canFillOrder_orderNotActive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        (bool canFill, string memory reason, ) = limitOrders.canFillOrder(orderId, 1_000e18);

        assertFalse(canFill, "Order should not be fillable when not active");
        assertEq(reason, "Order not active", "Reason should indicate order is not active");
    }

    // TODO shift canFillOrder tests to fillOrder tests

    // calculateIncentive
    //  [X] it calculates incentive and rate correctly
    function test_calculateIncentive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        (uint256 incentive, uint256 rate) = limitOrders.calculateIncentive(orderId, 2_000e18);
        assertEq(incentive, 10e18, "Incentive should be 10e18 (2000 * 50 / 10000)"); // 2000 * 50 / 10000
        assertEq(rate, 50, "Rate should be 50 bps (0.5%)"); // 50 bps = 0.5%
    }

    // TODO shift calculateIncentive tests to fillOrder tests

    // TODO fuzz test

    // getRemaining
    //  [X] it returns correct remaining deposit and incentive
    function test_getRemainingDeposit() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        (uint256 deposit, uint256 incentive) = limitOrders.getRemaining(orderId);

        assertEq(deposit, 10_000e18, "Remaining deposit should equal deposit budget initially");
        assertEq(incentive, 50e18, "Remaining incentive should equal incentive budget initially");

        vm.prank(filler);
        limitOrders.fillOrder(orderId, 2_000e18);

        (deposit, incentive) = limitOrders.getRemaining(orderId);

        assertEq(deposit, 8_000e18, "Remaining deposit should decrease by fill amount");
        assertEq(incentive, 40e18, "Remaining incentive should decrease proportionally");
    }

    // getFillableOrders
    //  [X] it returns only fillable orders for period
    function test_getFillableOrders() public {
        // Create multiple orders
        vm.startPrank(alice);
        limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18); // Fillable
        limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 25e18, 1_000e18); // Price too high
        limitOrders.createOrder(PERIOD_6, 10_000e18, 50e18, 35e18, 1_000e18); // Different period
        vm.stopPrank();

        uint256[] memory fillable = limitOrders.getFillableOrders(PERIOD_3);

        assertEq(fillable.length, 1, "Should return 1 fillable order for PERIOD_3");
        assertEq(fillable[0], 0, "Fillable order should be order ID 0");
    }

    // ========== ERC721 RECEIVER TEST ========== //

    // [X] it returns correct selector
    function test_onERC721Received() public {
        bytes4 selector = limitOrders.onERC721Received(address(0), address(0), 0, "");
        assertEq(
            selector,
            limitOrders.onERC721Received.selector,
            "Should return onERC721Received selector"
        );
    }

    // ========== CHANGE ORDER TESTS ========== //

    // changeOrder
    // when increasing the deposit and incentive budgets
    //  [X] it transfers additional budget from the user
    //  [X] it increases budgets
    //  [X] it increases the USDS owed by the additional budget
    function test_changeOrder_increaseBudgets() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 5_000e18, 25e18, 35e18, 500e18);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 10_000e18, 50e18, 35e18, 500e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, 10_000e18, "Deposit budget should be updated to 10_000e18");
        assertEq(order.incentiveBudget, 50e18, "Incentive budget should be updated to 50e18");
        assertEq(order.depositSpent, 0, "Deposit spent should be reset to 0");
        assertEq(order.incentiveSpent, 0, "Incentive spent should be reset to 0");
        assertEq(order.maxPrice, 35e18, "Max price should be unchanged");
        assertEq(order.minFillSize, 500e18, "Min fill size should be unchanged");
        assertEq(order.active, true, "Order should be active");

        // Alice paid additional 5025
        assertEq(
            aliceBalanceBefore - usds.balanceOf(alice),
            5_025e18,
            "Alice should pay additional 5_025e18"
        );

        // Invariant: USDS owed is new deposit + new incentive
        assertEq(limitOrders.totalUsdsOwed(), 10_050e18, "Total USDS owed should be increased");
    }

    // when decreasing the deposit and incentive budgets
    //  [X] it decreases budgets
    //  [X] it refunds the additional budget to the user
    //  [X] it reduces the USDS owed by the additional budget
    function test_changeOrder_decreaseBudgets() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 5_000e18, 25e18, 35e18, 500e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, 5_000e18, "Deposit budget should be decreased to 5_000e18");
        assertEq(order.incentiveBudget, 25e18, "Incentive budget should be decreased to 25e18");
        assertEq(order.depositSpent, 0, "Deposit spent should be reset to 0");
        assertEq(order.incentiveSpent, 0, "Incentive spent should be reset to 0");
        assertEq(order.maxPrice, 35e18, "Max price should be unchanged");
        assertEq(order.minFillSize, 500e18, "Min fill size should be unchanged");
        assertEq(order.active, true, "Order should be active");

        // Alice received 5025 back
        assertEq(
            usds.balanceOf(alice) - aliceBalanceBefore,
            5_025e18,
            "Alice should receive 5_025e18 refund"
        );

        // Invariant: USDS owed is new deposit + new incentive
        assertEq(limitOrders.totalUsdsOwed(), 5_025e18, "Total USDS owed should be decreased");
    }

    // given there has been a partial fill
    //  when decreasing the deposit and incentive budgets below the remaining budget
    //   [X] it resets spent amounts
    //   [X] it refunds the additional budget to the user
    //   [X] it decreases budgets
    //   [X] it reduces the USDS owed by the additional budget
    function test_changeOrder_afterPartialFill_decreasedBudget() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        // Partial fill: spends 3000 deposit + 15 incentive
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 3_000e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory orderBefore = limitOrders.getOrder(orderId);
        assertEq(
            orderBefore.depositSpent,
            3_000e18,
            "Before change: deposit spent should be 3_000e18"
        );
        assertEq(
            orderBefore.incentiveSpent,
            15e18,
            "Before change: incentive spent should be 15e18"
        );

        // Remaining: 7000 + 35 = 7035
        // New total: 5000 + 25 = 5025
        // User receives: 7035 - 5025 = 2010

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 5_000e18, 25e18, 32e18, 500e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory orderAfter = limitOrders.getOrder(orderId);
        assertEq(
            orderAfter.depositBudget,
            5_000e18,
            "After change: deposit budget should be 5_000e18"
        );
        assertEq(
            orderAfter.incentiveBudget,
            25e18,
            "After change: incentive budget should be 25e18"
        );
        assertEq(orderAfter.depositSpent, 0, "Deposit spent should be reset to 0"); // Reset!
        assertEq(orderAfter.incentiveSpent, 0, "Incentive spent should be reset to 0"); // Reset!
        assertEq(orderAfter.maxPrice, 32e18, "Max price should be updated to 32e18");
        assertEq(orderAfter.minFillSize, 500e18, "Min fill size should be unchanged");
        assertEq(orderAfter.active, true, "Order should be active");

        // User receives refund
        assertEq(
            usds.balanceOf(alice) - aliceBalanceBefore,
            2_010e18,
            "Alice should receive 2_010e18 refund (remaining - new total)"
        );

        // Invariant: USDS owed is new deposit + new incentive
        assertEq(limitOrders.totalUsdsOwed(), 5_025e18, "Total USDS owed should be decreased");
    }

    //  when increasing the deposit and incentive budgets above the remaining
    //   [X] it resets spent amounts
    //   [X] it transfers additional budget from the user
    //   [X] it increases budgets
    //   [X] it increases the USDS owed by the additional budget
    function test_changeOrder_afterPartialFill_increasedBudget() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        // Partial fill: spends 3000 deposit + 15 incentive
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 3_000e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory orderBefore = limitOrders.getOrder(orderId);
        assertEq(
            orderBefore.depositSpent,
            3_000e18,
            "Before change: deposit spent should be 3_000e18"
        );
        assertEq(
            orderBefore.incentiveSpent,
            15e18,
            "Before change: incentive spent should be 15e18"
        );

        // Remaining: 7000 + 35 = 7035
        // New total: 11000 + 110 = 11110
        // User spends: 11110 - 7035 = 4075

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 11_000e18, 110e18, 32e18, 500e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory orderAfter = limitOrders.getOrder(orderId);
        assertEq(
            orderAfter.depositBudget,
            11_000e18,
            "After change: deposit budget should be 11_000e18"
        );
        assertEq(
            orderAfter.incentiveBudget,
            110e18,
            "After change: incentive budget should be 110e18"
        );
        assertEq(orderAfter.depositSpent, 0, "Deposit spent should be reset to 0"); // Reset!
        assertEq(orderAfter.incentiveSpent, 0, "Incentive spent should be reset to 0"); // Reset!
        assertEq(orderAfter.maxPrice, 32e18, "Max price should be updated to 32e18");
        assertEq(orderAfter.minFillSize, 500e18, "Min fill size should be unchanged");
        assertEq(orderAfter.active, true, "Order should be active");

        // User spends additional
        assertEq(
            aliceBalanceBefore - usds.balanceOf(alice),
            4075e18,
            "Alice should pay additional 4075e18"
        );

        // Invariant: USDS owed is new deposit + new incentive
        assertEq(limitOrders.totalUsdsOwed(), 11_110e18, "Total USDS owed should be increased");
    }

    //  when the total budget is the same as the remaining
    //   [X] it resets spent amounts
    //   [X] it does not transfer additional budget from the user
    //   [X] it does not change budgets
    //   [X] it does not change the USDS owed
    function test_changeOrder_afterPartialFill_sameBudget(
        uint256 newMaxPrice_,
        uint256 newMinFillSize_
    ) public {
        newMaxPrice_ = bound(newMaxPrice_, 1, 100e18);
        newMinFillSize_ = bound(newMinFillSize_, MIN_BID, 7_000e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        // Partial fill: spends 3000 deposit + 15 incentive
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 3_000e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory orderBefore = limitOrders.getOrder(orderId);
        assertEq(
            orderBefore.depositSpent,
            3_000e18,
            "Before change: deposit spent should be 3_000e18"
        );
        assertEq(
            orderBefore.incentiveSpent,
            15e18,
            "Before change: incentive spent should be 15e18"
        );

        // Remaining: 7000 + 35 = 7035

        // Invariant: USDS owed is original deposit + original incentive - spent amounts
        assertEq(
            limitOrders.totalUsdsOwed(),
            7_000e18 + 35e18,
            "Total USDS owed should be unchanged"
        );

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 7_000e18, 35e18, newMaxPrice_, newMinFillSize_);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory orderAfter = limitOrders.getOrder(orderId);
        assertEq(
            orderAfter.depositBudget,
            7_000e18,
            "After change: deposit budget should be 7_000e18"
        );
        assertEq(
            orderAfter.incentiveBudget,
            35e18,
            "After change: incentive budget should be 35e18"
        );
        assertEq(orderAfter.depositSpent, 0, "Deposit spent should be reset to 0"); // Reset!
        assertEq(orderAfter.incentiveSpent, 0, "Incentive spent should be reset to 0"); // Reset!
        assertEq(orderAfter.maxPrice, newMaxPrice_, "Max price should be updated to new value");
        assertEq(
            orderAfter.minFillSize,
            newMinFillSize_,
            "Min fill size should be updated to new value"
        );
        assertEq(orderAfter.active, true, "Order should be active");

        // User does not spend additional
        assertEq(
            usds.balanceOf(alice),
            aliceBalanceBefore,
            "Alice should not spend additional funds"
        );

        // Invariant: USDS owed is original deposit + original incentive - spent amounts
        assertEq(
            limitOrders.totalUsdsOwed(),
            7_000e18 + 35e18,
            "Total USDS owed should be unchanged"
        );
    }

    //  [X] it allows changing incentive rate freely
    function test_changeOrder_afterPartialFill_canChangeIncentiveRateFreely() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 100e18, 35e18, 500e18); // 1% rate

        // Fill half
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 5_000e18); // Pays 50 incentive

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        // Remaining: 5000 + 50 = 5050
        // Can now set 0.1% rate - no problem since spent is reset
        vm.prank(alice);
        limitOrders.changeOrder(orderId, 5_000e18, 5e18, 35e18, 500e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, 5_000e18, "Deposit budget should be updated to 5_000e18");
        assertEq(order.incentiveBudget, 5e18, "Incentive budget should be updated to 5e18");
        assertEq(order.depositSpent, 0, "Deposit spent should be reset to 0");
        assertEq(order.incentiveSpent, 0, "Incentive spent should be reset to 0");
        assertEq(order.maxPrice, 35e18, "Max price should be unchanged");
        assertEq(order.minFillSize, 500e18, "Min fill size should be unchanged");
        assertEq(order.active, true, "Order should be active");

        // User received excess: 5050 - 5005 = 45
        assertEq(
            usds.balanceOf(alice) - aliceBalanceBefore,
            45e18,
            "Alice should receive 45e18 refund (remaining - new total)"
        );

        // Invariant: USDS owed is new deposit + new incentive
        assertEq(limitOrders.totalUsdsOwed(), 5_005e18, "Total USDS owed should be decreased");
    }

    // when the budget is the same
    //  when only the maxPrice is changed
    //   [X] it changes the max price
    //   [X] it makes no transfer
    //   [X] it resets the spent amounts
    function test_changeOrder_onlyMaxPrice(uint256 newMaxPrice_) public {
        newMaxPrice_ = bound(newMaxPrice_, 1, 100e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, MIN_BID);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 10_000e18, 50e18, newMaxPrice_, MIN_BID);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, 10_000e18, "Deposit budget should be unchanged");
        assertEq(order.incentiveBudget, 50e18, "Incentive budget should be unchanged");
        assertEq(order.depositSpent, 0, "Deposit spent should be reset to 0");
        assertEq(order.incentiveSpent, 0, "Incentive spent should be reset to 0");
        assertEq(order.maxPrice, newMaxPrice_, "Max price should be updated");
        assertEq(order.minFillSize, MIN_BID, "Min fill size should be unchanged");
        assertEq(order.active, true, "Order should be active");

        // Check owner balance
        assertEq(
            usds.balanceOf(alice),
            aliceBalanceBefore,
            "Alice balance should not change when budgets are unchanged"
        );

        // Invariant: USDS owed is new deposit + new incentive
        assertEq(
            limitOrders.totalUsdsOwed(),
            10_000e18 + 50e18,
            "Total USDS owed should be unchanged"
        );
    }

    //  when only the minFillSize is changed
    //   [X] it changes the min fill size
    //   [X] it makes no transfer
    //   [X] it resets the spent amounts
    function test_changeOrder_onlyMinFillSize(uint256 newMinFillSize_) public {
        uint256 depositBudget = 10_000e18;
        newMinFillSize_ = bound(newMinFillSize_, MIN_BID, depositBudget);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, depositBudget, 50e18, 35e18, 500e18);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 10_000e18, 50e18, 35e18, newMinFillSize_);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, 10_000e18, "Deposit budget should be unchanged");
        assertEq(order.incentiveBudget, 50e18, "Incentive budget should be unchanged");
        assertEq(order.depositSpent, 0, "Deposit spent should be reset to 0");
        assertEq(order.incentiveSpent, 0, "Incentive spent should be reset to 0");
        assertEq(order.maxPrice, 35e18, "Max price should be unchanged");
        assertEq(
            order.minFillSize,
            newMinFillSize_,
            "Min fill size should be updated to new value"
        );
        assertEq(order.active, true, "Order should be active");

        // Check owner balance
        assertEq(
            usds.balanceOf(alice),
            aliceBalanceBefore,
            "Alice balance should not change when budgets are unchanged"
        );

        // Invariant: USDS owed is new deposit + new incentive
        assertEq(
            limitOrders.totalUsdsOwed(),
            depositBudget + 50e18,
            "Total USDS owed should be unchanged"
        );
    }

    // when the order has been completely filled
    //  [X] it changes the budget
    //  [X] it changes the min fill size
    //  [X] it changes the max price
    //  [X] it resets the spent amounts
    //  [X] it transfers additional budget from the user
    //  [X] it increases the USDS owed by the additional budget
    function test_changeOrder_completelyFilled() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 5_000e18, 25e18, 35e18, 500e18);

        // Completely fill the order
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 5_000e18);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        // Change order
        vm.prank(alice);
        limitOrders.changeOrder(orderId, 10_000e18, 50e18, 32e18, 499e18);

        // Check order status
        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, 10_000e18, "Deposit budget should be updated to 10_000e18");
        assertEq(order.incentiveBudget, 50e18, "Incentive budget should be updated to 50e18");
        assertEq(order.depositSpent, 0, "Deposit spent should be reset to 0");
        assertEq(order.incentiveSpent, 0, "Incentive spent should be reset to 0");
        assertEq(order.maxPrice, 32e18, "Max price should be updated to 32e18");
        assertEq(order.minFillSize, 499e18, "Min fill size should be updated to 499e18");
        assertEq(order.active, true, "Order should be active");

        // Alice paid additional 10050
        assertEq(
            aliceBalanceBefore - usds.balanceOf(alice),
            10_050e18,
            "Alice should pay additional 10_050e18"
        );

        // Invariant: USDS owed is new deposit + new incentive
        assertEq(limitOrders.totalUsdsOwed(), 10_050e18, "Total USDS owed should be increased");
    }

    // when caller is not order owner
    //  [X] it reverts
    function test_changeOrder_revert_notOwner() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        vm.prank(bob);
        vm.expectRevert(CDAuctioneerLimitOrders.NotOrderOwner.selector);
        limitOrders.changeOrder(orderId, 10_000e18, 50e18, 40e18, 500e18);
    }

    // when order is not active
    //  [X] it reverts
    function test_changeOrder_revert_orderNotActive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        vm.prank(alice);
        vm.expectRevert(CDAuctioneerLimitOrders.OrderNotActive.selector);
        limitOrders.changeOrder(orderId, 10_000e18, 50e18, 40e18, 500e18);
    }

    // when newDepositBudget is zero
    //  [X] it reverts
    function test_changeOrder_revert_zeroDeposit() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(CDAuctioneerLimitOrders.InvalidParam.selector, "depositBudget")
        );
        limitOrders.changeOrder(orderId, 0, 50e18, 35e18, 500e18);
    }

    // when newMaxPrice is zero
    //  [X] it reverts
    function test_changeOrder_revert_zeroMaxPrice() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(CDAuctioneerLimitOrders.InvalidParam.selector, "maxPrice")
        );
        limitOrders.changeOrder(orderId, 10_000e18, 50e18, 0, 500e18);
    }

    // when newMinFillSize is zero
    //  [X] it reverts
    function test_changeOrder_revert_zeroMinFill() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(CDAuctioneerLimitOrders.InvalidParam.selector, "minFillSize")
        );
        limitOrders.changeOrder(orderId, 10_000e18, 50e18, 35e18, 0);
    }

    // when newMinFillSize exceeds newDepositBudget
    //  [X] it reverts
    function test_changeOrder_revert_minFillExceedsDeposit() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                CDAuctioneerLimitOrders.InvalidParam.selector,
                "minFillSize > depositBudget"
            )
        );
        limitOrders.changeOrder(orderId, 1_000e18, 50e18, 35e18, 2_000e18);
    }

    // when newMinFillSize is below auctioneer minimum
    //  [X] it reverts
    function test_changeOrder_revert_minFillBelowAuctioneerMin() public {
        cdAuctioneer.setMinimumBid(500e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                CDAuctioneerLimitOrders.InvalidParam.selector,
                "minFillSize < auctioneer minimum"
            )
        );
        limitOrders.changeOrder(orderId, 10_000e18, 50e18, 35e18, 100e18);
    }

    // when setting incentiveBudget to zero
    //  [X] it decreases budgets
    //  [X] it refunds the additional budget to the user
    //  [X] it reduces the USDS owed by the additional budget
    function test_changeOrder_zeroIncentive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 10_000e18, 0, 35e18, 500e18);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, 10_000e18, "Deposit budget should be unchanged");
        assertEq(order.incentiveBudget, 0, "Incentive budget should be updated to 0");
        assertEq(order.depositSpent, 0, "Deposit spent should be reset to 0");
        assertEq(order.incentiveSpent, 0, "Incentive spent should be reset to 0");
        assertEq(order.maxPrice, 35e18, "Max price should be unchanged");
        assertEq(order.minFillSize, 500e18, "Min fill size should be unchanged");
        assertEq(order.active, true, "Order should be active");

        // Alice returned 50e18 incentive
        assertEq(
            usds.balanceOf(alice) - aliceBalanceBefore,
            50e18,
            "Alice should receive 50e18 incentive"
        );

        // Invariant: USDS owed is deposit + incentive
        assertEq(limitOrders.totalUsdsOwed(), 10_000e18, "Total USDS owed should be decreased");
    }
}
