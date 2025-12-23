// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-variable)
// solhint-disable use-natspec
// solhint-disable gas-small-strings
// solhint-disable function-max-lines
// solhint-disable gas-increment-by-one
// solhint-disable one-contract-per-file
pragma solidity >=0.8.20;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {MockConvertibleDepositAuctioneer} from "src/test/mocks/MockConvertibleDepositAuctioneer.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";

// Interfaces
import {IERC721Errors} from "@openzeppelin-5.3.0/interfaces/draft-IERC6093.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {ERC20} from "@openzeppelin-5.3.0/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin-5.3.0/token/ERC721/ERC721.sol";

// Bophades
import {CDAuctioneerLimitOrders} from "src/policies/deposits/LimitOrders.sol";
import {ILimitOrders} from "src/policies/interfaces/deposits/ILimitOrders.sol";
import {Kernel} from "src/Kernel.sol";

// ========== MOCKS ========== //

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
    MockERC20 public usds;
    MockERC4626 public sUsds;
    MockERC20 public receiptToken3;
    MockERC20 public receiptToken6;
    MockERC20 public receiptToken12;
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
    uint8 public constant PERIOD_12 = 12;

    uint256 public constant MIN_BID = 100e18;
    uint256 public constant MOCK_PRICE = 30e18;

    // Default order parameters
    uint256 public constant DEFAULT_DEPOSIT_BUDGET = 10_000e18;
    uint256 public constant DEFAULT_INCENTIVE_BUDGET = 50e18;
    uint256 public constant DEFAULT_MAX_PRICE = 35e18;
    uint256 public constant DEFAULT_MIN_FILL_SIZE = 1_000e18;
    uint256 public constant DEFAULT_INCENTIVE_RATE = 50; // 50 / 10000 = 0.5%

    // Alternative order parameters (for variety in tests)
    uint256 public constant SMALL_DEPOSIT_BUDGET = 5_000e18;
    uint256 public constant SMALL_INCENTIVE_BUDGET = 25e18;
    uint256 public constant LOWER_MAX_PRICE = 25e18;
    uint256 public constant SMALL_MIN_FILL_SIZE = 500e18;

    function setUp() public {
        // Deploy kernel
        kernel = new Kernel();

        // Deploy mocks
        usds = new MockERC20("USDS", "USDS", 18);
        sUsds = new MockERC4626(usds, "sUSDS", "sUSDS");
        receiptToken3 = new MockERC20("Receipt3", "RCT3", 18);
        receiptToken6 = new MockERC20("Receipt6", "RCT6", 18);
        receiptToken12 = new MockERC20("Receipt12", "RCT12", 18);
        positionNFT = new MockPositionNFT();

        // Deploy mock auctioneer
        cdAuctioneer = new MockConvertibleDepositAuctioneer(kernel, address(usds));

        // Configure mock auctioneer
        cdAuctioneer.setMinimumBid(MIN_BID);
        cdAuctioneer.setMockPrice(MOCK_PRICE);
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

        // Initial deposit into sUSDS
        usds.mint(address(this), 1000e18);
        usds.approve(address(sUsds), 1000e18);
        sUsds.deposit(1000e18, address(this));

        // Enable the contract
        vm.prank(owner);
        limitOrders.enable("");
    }

    // ========== HELPER FUNCTIONS ========== //

    function _disableContract() internal {
        vm.prank(owner);
        limitOrders.disable("");
    }

    modifier givenDisabled() {
        _disableContract();
        _;
    }

    function _accrueYield(uint256 amount_) internal {
        usds.mint(address(sUsds), amount_);
    }

    struct OrderParams {
        uint256 id;
        uint256 total;
        uint256 spent;
        uint256 receiptTokenBalance;
    }

    function _checkOrderInvariants(
        OrderParams memory orderParams_
    )
        internal
        view
        returns (
            uint256 depositBudget,
            uint256 incentiveBudget,
            uint256 depositSpent,
            uint256 incentiveSpent
        )
    {
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderParams_.id);

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
            orderParams_.total,
            "Invariant: depositBudget + incentiveBudget should equal expected order total"
        );

        // Check per-order invariant: depositSpent = owner balance of receipt token
        if (orderParams_.receiptTokenBalance == type(uint256).max) {
            assertEq(
                receiptToken.balanceOf(order.owner),
                order.depositSpent,
                "Invariant: owner's receipt token balance should equal depositSpent"
            );
        } else {
            assertEq(
                receiptToken.balanceOf(order.owner),
                orderParams_.receiptTokenBalance,
                "Invariant: owner's receipt token balance should equal expected receipt token balance"
            );
        }

        // Check per-order invariant: orderSpent = depositSpent + incentiveSpent
        assertEq(
            order.depositSpent + order.incentiveSpent,
            orderParams_.spent,
            "Invariant: orderSpent should equal depositSpent + incentiveSpent"
        );

        // Check per-order invariant: order total - order spent = depositBudget + incentiveBudget - depositSpent - incentiveSpent
        assertEq(
            order.depositBudget + order.incentiveBudget - order.depositSpent - order.incentiveSpent,
            orderParams_.total - orderParams_.spent,
            "Invariant: order total - order spent should equal depositBudget + incentiveBudget - depositSpent - incentiveSpent"
        );

        return (depositBudget, incentiveBudget, depositSpent, incentiveSpent);
    }

    /// @notice Get effective price for a fill amount
    /// @dev    This is needed as there will be rounding that affects the effective price
    function _getEffectivePrice(
        uint256 price_,
        uint256 fillAmount_
    ) internal pure returns (uint256) {
        uint256 ohmOut = (fillAmount_ * 1e9) / price_;
        if (ohmOut == 0) return 0;
        return (fillAmount_ * 1e9) / ohmOut;
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
    ) internal view {
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
            ) = _checkOrderInvariants(orderOne_);
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
            ) = _checkOrderInvariants(orderTwo_);
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
    ) internal view {
        address[] memory fillers = new address[](1);
        fillers[0] = filler_;
        uint256[] memory expectedFillerBalances = new uint256[](1);
        expectedFillerBalances[0] = expectedFillerBalance_;
        checkOrdersInvariants(
            OrderParams({
                id: orderOneId_,
                total: expectedOrderOneTotal_,
                spent: expectedOrderOneSpent_,
                receiptTokenBalance: type(uint256).max
            }),
            OrderParams({
                id: type(uint256).max,
                total: 0,
                spent: 0,
                receiptTokenBalance: type(uint256).max
            }),
            fillers,
            expectedFillerBalances,
            expectedShares_
        );
    }

    // ========== CREATE ORDER TESTS ========== //

    // when all parameters are valid
    //  [X] it creates order successfully
    function test_createOrder_success() public {
        uint256 expectedShares = sUsds.previewDeposit(
            DEFAULT_DEPOSIT_BUDGET + DEFAULT_INCENTIVE_BUDGET
        );

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET, // depositBudget
            DEFAULT_INCENTIVE_BUDGET, // incentiveBudget
            DEFAULT_MAX_PRICE, // maxPrice
            DEFAULT_MIN_FILL_SIZE // minFillSize
        );

        assertEq(orderId, 0, "First order should have ID 0");

        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.owner, alice, "Order owner should be alice");
        assertEq(order.depositPeriod, PERIOD_3, "Order deposit period should be PERIOD_3");
        assertEq(
            order.depositBudget,
            DEFAULT_DEPOSIT_BUDGET,
            "Order deposit budget should match input"
        );
        assertEq(
            order.incentiveBudget,
            DEFAULT_INCENTIVE_BUDGET,
            "Order incentive budget should match input"
        );
        assertEq(order.depositSpent, 0, "Order deposit spent should be 0 initially");
        assertEq(order.incentiveSpent, 0, "Order incentive spent should be 0 initially");
        assertEq(order.maxPrice, DEFAULT_MAX_PRICE, "Order max price should match input");
        assertEq(
            order.minFillSize,
            DEFAULT_MIN_FILL_SIZE,
            "Order min fill size should match input"
        );
        assertTrue(order.active, "Order should be active");

        // Check balances and invariants
        checkOrderInvariants(
            orderId,
            DEFAULT_DEPOSIT_BUDGET + DEFAULT_INCENTIVE_BUDGET,
            0,
            address(0),
            0,
            expectedShares
        );
    }

    // TODO ordersForUser

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

        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
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
            OrderParams({
                id: orderId1,
                total: 5_025e18,
                spent: 0,
                receiptTokenBalance: type(uint256).max
            }),
            OrderParams({
                id: orderId2,
                total: 3_015e18,
                spent: 0,
                receiptTokenBalance: type(uint256).max
            }),
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
        ILimitOrders.LimitOrder memory aliceOrderData = limitOrders.getOrder(aliceOrder);
        ILimitOrders.LimitOrder memory bobOrderData = limitOrders.getOrder(bobOrder);
        assertEq(aliceOrderData.owner, alice, "Alice's order owner should be alice");
        assertEq(bobOrderData.owner, bob, "Bob's order owner should be bob");

        // Check balances and invariants for both orders
        address[] memory fillers = new address[](2);
        uint256[] memory expectedFillerBalances = new uint256[](2);
        checkOrdersInvariants(
            OrderParams({
                id: aliceOrder,
                total: 5_000e18 + 25e18,
                spent: 0,
                receiptTokenBalance: type(uint256).max
            }),
            OrderParams({
                id: bobOrder,
                total: 3_000e18 + 15e18,
                spent: 0,
                receiptTokenBalance: type(uint256).max
            }),
            fillers,
            expectedFillerBalances,
            expectedShares
        );
    }

    // when the incentive budget is zero
    //  [X] it creates the order successfully
    function test_createOrder_zeroIncentive() public {
        uint256 expectedShares = sUsds.previewDeposit(DEFAULT_DEPOSIT_BUDGET);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            0,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.incentiveBudget, 0, "Order incentive budget should be 0");

        // Check balances and invariants
        checkOrderInvariants(orderId, DEFAULT_DEPOSIT_BUDGET, 0, address(0), 0, expectedShares);
    }

    // when the recipient cannot receive ERC721 tokens
    //  [X] it reverts
    function test_createOrder_revert_recipientCannotReceiveERC721() public {
        // Create a contract that cannot receive ERC721 tokens
        MockERC20 newOwner = new MockERC20("New Owner", "NEW", 18);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(newOwner))
        );

        vm.prank(address(newOwner));
        limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );
    }

    // when depositBudget is zero
    //  [X] it reverts
    function test_createOrder_revert_zeroDeposit() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ILimitOrders.InvalidParam.selector, "depositBudget")
        );
        limitOrders.createOrder(
            PERIOD_3,
            0,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );
    }

    // when maxPrice is zero
    //  [X] it reverts
    function test_createOrder_revert_zeroMaxPrice() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILimitOrders.InvalidParam.selector, "maxPrice"));
        limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            0,
            DEFAULT_MIN_FILL_SIZE
        );
    }

    // when minFillSize is zero
    //  [X] it reverts
    function test_createOrder_revert_zeroMinFill() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILimitOrders.InvalidParam.selector, "minFillSize"));
        limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            0
        );
    }

    // when minFillSize exceeds depositBudget
    //  [X] it reverts
    function test_createOrder_revert_minFillExceedsDeposit() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILimitOrders.InvalidParam.selector,
                "minFillSize > depositBudget"
            )
        );
        limitOrders.createOrder(
            PERIOD_3,
            1_000e18,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            2_000e18
        );
    }

    // when minFillSize is below auctioneer minimum
    //  [X] it reverts
    function test_createOrder_revert_minFillBelowAuctioneerMin() public {
        cdAuctioneer.setMinimumBid(500e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILimitOrders.InvalidParam.selector,
                "minFillSize < auctioneer minimum"
            )
        );
        limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            100e18
        );
    }

    // when depositPeriod is not enabled in the auctioneer
    //  [X] it reverts
    function test_createOrder_revert_depositPeriodDisabled() public {
        cdAuctioneer.setDepositPeriodEnabled(PERIOD_3, false);

        vm.prank(alice);
        vm.expectRevert(ILimitOrders.DepositPeriodNotEnabled.selector);
        limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );
    }

    // when the deposit period is not configured
    //  [X] it reverts
    function test_createOrder_revert_receiptTokenNotConfigured() public {
        vm.prank(alice);
        vm.expectRevert(ILimitOrders.ReceiptTokenNotConfigured.selector);
        limitOrders.createOrder(
            12,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );
    }

    // when the contract is disabled
    //  [X] it reverts

    function test_createOrder_givenDisabled_reverts() public givenDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);

        vm.prank(alice);
        limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );
    }

    // ========== FILL ORDER TESTS ========== //

    // when order is active and price is below max
    //  [X] it fills order successfully
    //  [X] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_success() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Calculate expected values before fill
        uint256 fillAmount = 1000e18;
        uint256 expectedIncentive = 5e18; // 1000 * 50 / 10000 = 5
        uint256 expectedShares = sUsds.balanceOf(address(limitOrders)) -
            sUsds.previewWithdraw(fillAmount + expectedIncentive);

        // Check canFillOrder returns true before fill
        {
            (bool canFill, string memory reason, uint256 effectivePrice) = limitOrders.canFillOrder(
                orderId,
                fillAmount
            );
            assertTrue(canFill, "Order should be fillable");
            assertEq(bytes(reason).length, 0, "Reason should be empty when order is fillable");
            assertEq(
                effectivePrice,
                _getEffectivePrice(MOCK_PRICE, fillAmount),
                "Effective price should equal mock price"
            );
        }

        // Check incentive
        {
            (uint256 incentive, uint256 incentiveRate) = limitOrders.calculateIncentive(
                orderId,
                fillAmount
            );
            assertEq(incentive, expectedIncentive, "Incentive should be 5e18 (1000 * 50 / 10000)");
            assertEq(
                incentiveRate,
                DEFAULT_INCENTIVE_RATE,
                "Incentive rate should be 50 bps (0.5%)"
            );
        }

        // Fill order
        vm.prank(filler);
        (
            uint256 actualFillAmount,
            uint256 returnedIncentive,
            uint256 remainingDeposit
        ) = limitOrders.fillOrder(orderId, fillAmount);

        // Check return values
        assertEq(
            actualFillAmount,
            fillAmount,
            "Actual fill amount should equal requested fill amount"
        );
        assertEq(
            returnedIncentive,
            expectedIncentive,
            "Returned incentive should be 5e18 (1000 * 50 / 10000)"
        );
        assertEq(
            remainingDeposit,
            DEFAULT_DEPOSIT_BUDGET - fillAmount,
            "Remaining deposit should be deposit budget minus fill amount"
        );

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, fillAmount, "Deposit spent should equal fill amount");
        assertEq(
            order.incentiveSpent,
            expectedIncentive,
            "Incentive spent should be 5e18 (1000 * 50 / 10000)"
        );

        // Check alice received NFT
        assertEq(positionNFT.ownerOf(1), alice, "Alice should own NFT token ID 1");

        // Check balances and invariants after fill
        checkOrderInvariants(
            orderId,
            DEFAULT_DEPOSIT_BUDGET + DEFAULT_INCENTIVE_BUDGET,
            fillAmount + expectedIncentive,
            filler,
            expectedIncentive,
            expectedShares
        );
    }

    // when order is active and price is below max
    //  [X] it handles multiple fills correctly
    //  [X] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_multipleFills() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Calculate expected values before first fill
        uint256 fillAmountOne = 2_000e18;
        uint256 expectedIncentiveOne = 10e18; // 2000 * 50 / 10000 = 10
        uint256 fillAmountTwo = 3_000e18;
        uint256 expectedIncentiveTwo = 15e18; // 3000 * 50 / 10000 = 15
        uint256 expectedShares = sUsds.balanceOf(address(limitOrders)) -
            sUsds.previewWithdraw(
                fillAmountOne + expectedIncentiveOne + fillAmountTwo + expectedIncentiveTwo
            );

        // Check canFillOrder returns true before first fill
        {
            (bool canFill, , ) = limitOrders.canFillOrder(orderId, fillAmountOne);
            assertTrue(canFill, "Order should be fillable before first fill");
        }

        // Check incentive
        {
            (uint256 incentive, uint256 incentiveRate) = limitOrders.calculateIncentive(
                orderId,
                fillAmountOne
            );
            assertEq(
                incentive,
                expectedIncentiveOne,
                "Incentive should be 10e18 (2000 * 50 / 10000)"
            );
            assertEq(
                incentiveRate,
                DEFAULT_INCENTIVE_RATE,
                "Incentive rate should be 50 bps (0.5%)"
            );
        }

        // First fill
        vm.prank(filler);
        (
            uint256 actualFillAmountOne,
            uint256 returnedIncentiveOne,
            uint256 remainingDepositOne
        ) = limitOrders.fillOrder(orderId, fillAmountOne);

        // Check first fill return values
        assertEq(actualFillAmountOne, fillAmountOne, "First fill amount should equal requested");
        assertEq(
            returnedIncentiveOne,
            expectedIncentiveOne,
            "First fill incentive should be 10e18"
        );
        assertEq(
            remainingDepositOne,
            DEFAULT_DEPOSIT_BUDGET - fillAmountOne,
            "Remaining deposit after first fill should be correct"
        );

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(
            order.depositSpent,
            fillAmountOne,
            "After first fill, deposit spent should be 2_000e18"
        );
        assertEq(
            order.incentiveSpent,
            expectedIncentiveOne,
            "After first fill, incentive spent should be 10e18"
        );

        // Check canFillOrder returns true before second fill
        {
            (bool canFill, , ) = limitOrders.canFillOrder(orderId, fillAmountTwo);
            assertTrue(canFill, "Order should be fillable before second fill");
        }

        // Check incentive
        {
            (uint256 incentive, uint256 incentiveRate) = limitOrders.calculateIncentive(
                orderId,
                fillAmountTwo
            );
            assertEq(
                incentive,
                expectedIncentiveTwo,
                "Incentive should be 15e18 (3000 * 50 / 10000)"
            );
            assertEq(
                incentiveRate,
                DEFAULT_INCENTIVE_RATE,
                "Incentive rate should be 50 bps (0.5%)"
            );
        }

        // Second fill
        {
            vm.prank(filler);
            (
                uint256 actualFillAmountTwo,
                uint256 returnedIncentiveTwo,
                uint256 remainingDepositTwo
            ) = limitOrders.fillOrder(orderId, fillAmountTwo);

            // Check second fill return values
            assertEq(
                actualFillAmountTwo,
                fillAmountTwo,
                "Second fill amount should equal requested"
            );
            assertEq(
                returnedIncentiveTwo,
                expectedIncentiveTwo,
                "Second fill incentive should be 15e18"
            );
            assertEq(
                remainingDepositTwo,
                DEFAULT_DEPOSIT_BUDGET - fillAmountOne - fillAmountTwo,
                "Remaining deposit after second fill should be correct"
            );
        }

        // Check order status
        order = limitOrders.getOrder(orderId);
        assertEq(
            order.depositSpent,
            fillAmountOne + fillAmountTwo,
            "After second fill, deposit spent should be 5_000e18"
        );
        assertEq(
            order.incentiveSpent,
            expectedIncentiveOne + expectedIncentiveTwo,
            "After second fill, incentive spent should be 25e18"
        );

        // Check alice received 2 NFTs
        assertEq(positionNFT.balanceOf(alice), 2, "Alice should own 2 NFTs after two fills");

        // Check balances and invariants after fills
        checkOrderInvariants(
            orderId,
            DEFAULT_DEPOSIT_BUDGET + DEFAULT_INCENTIVE_BUDGET,
            fillAmountOne + fillAmountTwo + expectedIncentiveOne + expectedIncentiveTwo,
            filler,
            expectedIncentiveOne + expectedIncentiveTwo,
            expectedShares
        );
    }

    // when the remaining deposit is less than the fill amount
    //  [X] it caps fill to remaining deposit
    //  [X] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_capToRemainingDeposit() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            SMALL_DEPOSIT_BUDGET,
            SMALL_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        uint256 fillAmount = 10_000e18; // Will cap to remaining deposit
        uint256 expectedIncentive = 25e18; // 5000 * 25 / 5000 = 25
        uint256 expectedIncentiveRate = 50; // 25 / 5000 = 0.5%

        // Check canFillOrder returns true (will cap to remaining)
        {
            (bool canFill, , ) = limitOrders.canFillOrder(orderId, fillAmount);
            assertTrue(canFill, "Order should be fillable even when fill amount exceeds remaining");
        }

        // Check incentive
        {
            (uint256 incentive, uint256 incentiveRate) = limitOrders.calculateIncentive(
                orderId,
                fillAmount
            );
            assertEq(
                incentive,
                expectedIncentive,
                "Incentive should be 25e18 (10000 * 50 / 10000)"
            );
            assertEq(
                incentiveRate,
                expectedIncentiveRate,
                "Incentive rate should be 50 bps (0.5%)"
            );
        }

        // Try to fill more than remaining
        vm.prank(filler);
        (
            uint256 actualFillAmount,
            uint256 returnedIncentive,
            uint256 remainingDeposit
        ) = limitOrders.fillOrder(orderId, fillAmount);

        // Check return values
        assertEq(
            actualFillAmount,
            SMALL_DEPOSIT_BUDGET,
            "Fill amount should be capped to remaining deposit"
        );
        assertEq(
            returnedIncentive,
            SMALL_INCENTIVE_BUDGET,
            "Incentive should be all remaining (final fill)"
        );
        assertEq(remainingDeposit, 0, "Remaining deposit should be zero after final fill");

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(
            order.depositSpent,
            SMALL_DEPOSIT_BUDGET,
            "Deposit spent should be capped to deposit budget"
        ); // Capped to max
        assertEq(
            order.incentiveSpent,
            SMALL_INCENTIVE_BUDGET,
            "Incentive spent should equal incentive budget"
        ); // All incentive paid

        // Check balances and invariants after fill
        checkOrderInvariants(
            orderId,
            SMALL_DEPOSIT_BUDGET + SMALL_INCENTIVE_BUDGET,
            SMALL_DEPOSIT_BUDGET + SMALL_INCENTIVE_BUDGET,
            filler,
            SMALL_INCENTIVE_BUDGET,
            0
        );
    }

    function test_fillOrder_capToRemainingDeposit_fuzz(uint256 fillAmount_) public {
        fillAmount_ = bound(fillAmount_, SMALL_DEPOSIT_BUDGET, 10_000e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            SMALL_DEPOSIT_BUDGET,
            SMALL_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Calculate expected budget use
        uint256 expectedIncentive = 25e18; // 5000 * 25 / 5000 = 25
        uint256 expectedIncentiveRate = 50; // 25 / 5000 = 0.5%

        // Check incentive
        {
            (uint256 incentive, uint256 incentiveRate) = limitOrders.calculateIncentive(
                orderId,
                fillAmount_
            );
            assertEq(
                incentive,
                expectedIncentive,
                "Incentive should be 25e18 (10000 * 50 / 10000)"
            );
            assertEq(
                incentiveRate,
                expectedIncentiveRate,
                "Incentive rate should be 50 bps (0.5%)"
            );
        }

        // Check canFillOrder returns true (will cap to remaining)
        {
            (bool canFill, , ) = limitOrders.canFillOrder(orderId, fillAmount_);
            assertTrue(canFill, "Order should be fillable even when fill amount exceeds remaining");
        }

        // Try to fill more than remaining
        vm.prank(filler);
        limitOrders.fillOrder(orderId, fillAmount_);

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(
            order.depositSpent,
            SMALL_DEPOSIT_BUDGET,
            "Deposit spent should be capped to deposit budget"
        ); // Capped to max
        assertEq(
            order.incentiveSpent,
            SMALL_INCENTIVE_BUDGET,
            "Incentive spent should equal incentive budget"
        ); // All incentive paid

        // Check balances and invariants after fill
        checkOrderInvariants(
            orderId,
            SMALL_DEPOSIT_BUDGET + SMALL_INCENTIVE_BUDGET,
            SMALL_DEPOSIT_BUDGET + SMALL_INCENTIVE_BUDGET,
            filler,
            SMALL_INCENTIVE_BUDGET,
            0
        );
    }

    function test_fillOrder_capToRemainingDeposit_givenYield_fuzz(uint256 fillAmount_) public {
        fillAmount_ = bound(fillAmount_, SMALL_DEPOSIT_BUDGET, 10_000e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            SMALL_DEPOSIT_BUDGET,
            SMALL_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Yield accrual
        _accrueYield(123e18);

        // Calculate expected budget use
        uint256 expectedIncentive = 25e18; // 500 * 25 / 5000 = 25
        uint256 expectedIncentiveRate = 50; // 25 / 5000 = 0.5%
        uint256 expectedShares = sUsds.balanceOf(address(limitOrders)) -
            sUsds.previewWithdraw(SMALL_DEPOSIT_BUDGET + SMALL_INCENTIVE_BUDGET);

        // Check incentive
        {
            (uint256 incentive, uint256 incentiveRate) = limitOrders.calculateIncentive(
                orderId,
                fillAmount_
            );
            assertEq(
                incentive,
                expectedIncentive,
                "Incentive should be 25e18 (10000 * 50 / 10000)"
            );
            assertEq(
                incentiveRate,
                expectedIncentiveRate,
                "Incentive rate should be 50 bps (0.5%)"
            );
        }

        // Check canFillOrder returns true (will cap to remaining)
        {
            (bool canFill, , ) = limitOrders.canFillOrder(orderId, fillAmount_);
            assertTrue(canFill, "Order should be fillable even when fill amount exceeds remaining");
        }

        // Try to fill more than remaining
        vm.prank(filler);
        (
            uint256 actualFillAmount,
            uint256 returnedIncentive,
            uint256 remainingDeposit
        ) = limitOrders.fillOrder(orderId, fillAmount_);

        // Check return values
        assertEq(
            actualFillAmount,
            SMALL_DEPOSIT_BUDGET,
            "Fill amount should be capped to remaining deposit"
        );
        assertEq(
            returnedIncentive,
            SMALL_INCENTIVE_BUDGET,
            "Incentive should be all remaining (final fill)"
        );
        assertEq(remainingDeposit, 0, "Remaining deposit should be zero after final fill");

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(
            order.depositSpent,
            SMALL_DEPOSIT_BUDGET,
            "Deposit spent should be capped to deposit budget"
        ); // Capped to max
        assertEq(
            order.incentiveSpent,
            SMALL_INCENTIVE_BUDGET,
            "Incentive spent should equal incentive budget"
        ); // All incentive paid

        // Check balances and invariants after fill
        checkOrderInvariants(
            orderId,
            SMALL_DEPOSIT_BUDGET + SMALL_INCENTIVE_BUDGET,
            SMALL_DEPOSIT_BUDGET + SMALL_INCENTIVE_BUDGET,
            filler,
            SMALL_INCENTIVE_BUDGET,
            expectedShares
        );
    }

    // when there have been previous fills
    //  when the fill amount completes the order
    //   when the remaining deposit is less than the minFillSize
    //    [X] it allows fill below minFillSize if final fill
    //    [X] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_belowMinFillAllowedIfFinalFill() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            2_500e18,
            SMALL_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // First fill
        vm.prank(filler);
        (
            uint256 actualFillAmountOne,
            uint256 returnedIncentiveOne,
            uint256 remainingDepositOne
        ) = limitOrders.fillOrder(orderId, 2_000e18);

        // Check first fill return values
        assertEq(actualFillAmountOne, 2_000e18, "First fill amount should equal requested");
        uint256 expectedIncentiveOne = (2_000e18 * SMALL_INCENTIVE_BUDGET) / 2_500e18; // 20e18
        assertEq(
            returnedIncentiveOne,
            expectedIncentiveOne,
            "First fill incentive should be proportional"
        );
        assertEq(
            remainingDepositOne,
            500e18,
            "Remaining deposit after first fill should be 500e18"
        );

        // Calculate expected budget use
        uint256 fillAmountTwo = 500e18;
        uint256 expectedIncentive = 5e18; // 500 * 25 / 2500 = 5
        uint256 expectedIncentiveRate = 100; // 25 / 2500 = 1%

        // Check incentive
        {
            (uint256 incentive, uint256 incentiveRate) = limitOrders.calculateIncentive(
                orderId,
                fillAmountTwo
            );
            assertEq(incentive, expectedIncentive, "Incentive should be 5e18 (500 * 25 / 2500)");
            assertEq(incentiveRate, expectedIncentiveRate, "Incentive rate should be 100 bps (1%)");
        }

        // Remaining is 500e18 which is below minFill of 1000e18
        // Should still be allowed as final fill
        // Check canFillOrder returns true for final fill below minFillSize
        {
            (bool canFill, , ) = limitOrders.canFillOrder(orderId, fillAmountTwo);
            assertTrue(canFill, "Order should be fillable for final fill below minFillSize");
        }

        vm.prank(filler);
        (
            uint256 actualFillAmountTwo,
            uint256 returnedIncentiveTwo,
            uint256 remainingDepositTwo
        ) = limitOrders.fillOrder(orderId, fillAmountTwo);

        // Check second fill return values
        assertEq(actualFillAmountTwo, fillAmountTwo, "Second fill amount should equal requested");
        assertEq(returnedIncentiveTwo, expectedIncentive, "Second fill incentive should be 5e18");
        assertEq(remainingDepositTwo, 0, "Remaining deposit after second fill should be zero");

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(
            order.depositSpent,
            2500e18,
            "Deposit spent should equal full deposit budget after final fill"
        );
        assertEq(
            order.incentiveSpent,
            SMALL_INCENTIVE_BUDGET,
            "Incentive spent should equal incentive budget"
        );

        // Check balances and invariants after final fill
        checkOrderInvariants(
            orderId,
            2500e18 + SMALL_INCENTIVE_BUDGET,
            2500e18 + SMALL_INCENTIVE_BUDGET,
            filler,
            SMALL_INCENTIVE_BUDGET,
            0
        );
    }

    //   [X] it gives final fill all remaining incentive
    //   [X] the deposit spent is the total deposit budget
    //   [X] the incentive spent is the total incentive budget
    //   [X] the USDS owed is 0
    function test_fillOrder_finalFillGetsAllRemainingIncentive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Fill most of the order
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 9_000e18);

        // Calculate expected incentive
        uint256 expectedIncentiveTwo = 5e18; // 1000 * 5 / 10000 = 5

        // Final fill - should get all remaining incentive (avoids dust)
        vm.prank(filler);
        (
            uint256 actualFillAmountTwo,
            uint256 returnedIncentiveTwo,
            uint256 remainingDepositTwo
        ) = limitOrders.fillOrder(orderId, 1_000e18);

        // Check final fill return values
        assertEq(actualFillAmountTwo, 1_000e18, "Final fill amount should equal requested");
        assertEq(
            returnedIncentiveTwo,
            expectedIncentiveTwo,
            "Final fill should get all remaining incentive"
        );
        assertEq(remainingDepositTwo, 0, "Remaining deposit after final fill should be zero");

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, 10_000e18, "Deposit spent should equal full deposit budget");
        assertEq(order.incentiveSpent, 50e18, "Incentive spent should equal full incentive budget");

        // Check balances and invariants after final fill
        checkOrderInvariants(orderId, 10_000e18 + 50e18, 10_000e18 + 50e18, filler, 50e18, 0);
    }

    function test_fillOrder_finalFillGetsAllRemainingIncentive_fuzz(
        uint256 incentiveBudget_
    ) public {
        incentiveBudget_ = bound(incentiveBudget_, 1, DEFAULT_INCENTIVE_BUDGET);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            incentiveBudget_,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Fill most of the order
        uint256 fillAmountOne = 9_000e18;
        vm.prank(filler);
        limitOrders.fillOrder(orderId, fillAmountOne);

        // Determine the remaining incentive budget
        uint256 fillAmountTwo = DEFAULT_DEPOSIT_BUDGET - fillAmountOne;
        uint256 remainingIncentive = incentiveBudget_ -
            (fillAmountOne * incentiveBudget_) /
            DEFAULT_DEPOSIT_BUDGET;
        uint256 expectedIncentiveRate = (incentiveBudget_ * 10_000) / DEFAULT_DEPOSIT_BUDGET;

        // Check incentive
        {
            (uint256 incentive, uint256 incentiveRate) = limitOrders.calculateIncentive(
                orderId,
                fillAmountTwo
            );
            assertEq(
                incentive,
                remainingIncentive,
                "Incentive should be the remaining incentive budget"
            );
            assertEq(incentiveRate, expectedIncentiveRate, "Incentive rate mismatch");
        }

        // Final fill - should get all remaining incentive (avoids dust)
        vm.prank(filler);
        (
            uint256 actualFillAmountTwo,
            uint256 returnedIncentiveTwo,
            uint256 remainingDepositTwo
        ) = limitOrders.fillOrder(orderId, fillAmountTwo);

        // Check final fill return values
        assertEq(actualFillAmountTwo, fillAmountTwo, "Final fill amount should equal requested");
        assertEq(
            returnedIncentiveTwo,
            remainingIncentive,
            "Final fill should get all remaining incentive"
        );
        assertEq(remainingDepositTwo, 0, "Remaining deposit after final fill should be zero");

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(
            order.depositSpent,
            DEFAULT_DEPOSIT_BUDGET,
            "Deposit spent should equal full deposit budget"
        );
        assertEq(
            order.incentiveSpent,
            incentiveBudget_,
            "Incentive spent should equal full incentive budget"
        );

        // Check balances and invariants after final fill
        checkOrderInvariants(
            orderId,
            DEFAULT_DEPOSIT_BUDGET + incentiveBudget_,
            DEFAULT_DEPOSIT_BUDGET + incentiveBudget_,
            filler,
            incentiveBudget_,
            0
        );
    }

    // when filling order with zero incentive
    //  [X] it fills without paying incentive
    function test_fillOrder_zeroIncentive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            0,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        uint256 fillAmount = 1_000e18;

        // Check incentive
        {
            (uint256 incentive, uint256 incentiveRate) = limitOrders.calculateIncentive(
                orderId,
                fillAmount
            );
            assertEq(incentive, 0, "Incentive should be 0 (1000 * 0 / 10000)");
            assertEq(incentiveRate, 0, "Incentive rate should be 0 bps (0%)");
        }

        // Check canFillOrder returns true before fill
        {
            (bool canFill, , ) = limitOrders.canFillOrder(orderId, fillAmount);
            assertTrue(canFill, "Order should be fillable with zero incentive");
        }

        // Calculate expected values before fill
        uint256 remainingBudget = 9_000e18; // Remaining deposit (no incentive)
        uint256 expectedShares = sUsds.previewDeposit(remainingBudget);

        vm.prank(filler);
        limitOrders.fillOrder(orderId, fillAmount);

        // Check balances and invariants after fill
        checkOrderInvariants(
            orderId,
            DEFAULT_DEPOSIT_BUDGET,
            fillAmount,
            filler,
            0,
            expectedShares
        );
    }

    // when minFillSize equals remaining deposit
    //  [X] it allows fill
    //  [X] the deposit spent is the fill amount
    //  [X] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_exactMinFillEqualsRemaining() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            1_000e18,
            5e18,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        uint256 fillAmount = 1_000e18;
        uint256 expectedIncentive = 5e18; // 1000 * 5 / 1000 = 5
        uint256 expectedIncentiveRate = 50; // 5 / 1000 = 0.5%

        // Check incentive
        {
            (uint256 incentive, uint256 incentiveRate) = limitOrders.calculateIncentive(
                orderId,
                fillAmount
            );
            assertEq(incentive, expectedIncentive, "Incentive should be 5e18 (1000 * 5 / 1000)");
            assertEq(
                incentiveRate,
                expectedIncentiveRate,
                "Incentive rate should be 50 bps (0.5%)"
            );
        }

        // minFillSize == depositBudget == 1000
        // This should work as it's both the min and final fill
        // Check canFillOrder returns true
        {
            (bool canFill, , ) = limitOrders.canFillOrder(orderId, fillAmount);
            assertTrue(
                canFill,
                "Order should be fillable when minFillSize equals remaining deposit"
            );
        }

        vm.prank(filler);
        limitOrders.fillOrder(orderId, fillAmount);

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(
            order.depositSpent,
            fillAmount,
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
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        address filler2 = makeAddr("filler2");

        // Check canFillOrder returns true before first fill
        {
            (bool canFill, , ) = limitOrders.canFillOrder(orderId, 2_000e18);
            assertTrue(canFill, "Order should be fillable before first fill");
        }

        vm.prank(filler);
        limitOrders.fillOrder(orderId, 2_000e18);

        // Calculate expected values before second fill
        uint256 remainingBudget = 5_000e18 + 25e18; // Remaining deposit + remaining incentive
        uint256 expectedShares = sUsds.previewDeposit(remainingBudget);

        // Check canFillOrder returns true before second fill
        {
            (bool canFill, , ) = limitOrders.canFillOrder(orderId, 3_000e18);
            assertTrue(canFill, "Order should be fillable before second fill");
        }

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
            OrderParams({
                id: orderId,
                total: 10_000e18 + 50e18,
                spent: 5000e18 + 25e18,
                receiptTokenBalance: type(uint256).max
            }),
            OrderParams({
                id: type(uint256).max,
                total: 0,
                spent: 0,
                receiptTokenBalance: type(uint256).max
            }),
            fillers,
            expectedFillerBalances,
            expectedShares
        );
    }

    // when order is not active
    //  [X] it reverts
    function test_fillOrder_revert_orderNotActive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        // Check canFillOrder returns false with reason before fill
        {
            (bool canFill, string memory reason, ) = limitOrders.canFillOrder(orderId, 1_000e18);
            assertFalse(canFill, "Order should not be fillable when not active");
            assertEq(reason, "Order not active", "Reason should indicate order is not active");
        }

        vm.prank(filler);
        vm.expectRevert(ILimitOrders.OrderNotActive.selector);
        limitOrders.fillOrder(orderId, 1_000e18);
    }

    // when the remaining deposit is zero
    //  [X] it reverts
    function test_fillOrder_revert_orderFullySpent() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            1_000e18,
            5e18,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        vm.prank(filler);
        limitOrders.fillOrder(orderId, 1_000e18);

        // Check canFillOrder returns false with reason after order is fully spent
        {
            (bool canFill, string memory reason, ) = limitOrders.canFillOrder(orderId, 1_000e18);
            assertFalse(canFill, "Order should not be fillable when fully spent");
            assertEq(reason, "Order fully spent", "Reason should indicate order is fully spent");
        }

        vm.prank(filler);
        vm.expectRevert(ILimitOrders.OrderFullySpent.selector);
        limitOrders.fillOrder(orderId, 1_000e18);
    }

    // when the fill amount is below minimum (and not final fill)
    //  [X] it reverts
    function test_fillOrder_revert_fillBelowMinimum() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Check canFillOrder returns false with reason before fill
        {
            (bool canFill, string memory reason, ) = limitOrders.canFillOrder(orderId, 500e18);
            assertFalse(canFill, "Order should not be fillable when fill amount is below minimum");
            assertEq(reason, "Fill below minimum", "Reason should indicate fill is below minimum");
        }

        vm.prank(filler);
        vm.expectRevert(ILimitOrders.FillBelowMinimum.selector);
        limitOrders.fillOrder(orderId, 500e18);
    }

    // when price is above max
    //  [X] it reverts
    function test_fillOrder_revert_priceAboveMax() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            LOWER_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        ); // maxPrice = 25

        cdAuctioneer.setMockPrice(MOCK_PRICE); // Current price is 30

        // Check canFillOrder returns false with reason before fill
        {
            (bool canFill, string memory reason, uint256 effectivePrice) = limitOrders.canFillOrder(
                orderId,
                1_000e18
            );
            assertFalse(canFill, "Order should not be fillable when price is above max");
            assertEq(reason, "Price above max", "Reason should indicate price is above max");
            assertEq(
                effectivePrice,
                _getEffectivePrice(MOCK_PRICE, 1_000e18),
                "Effective price should equal mock price"
            );
        }

        vm.prank(filler);
        vm.expectRevert(ILimitOrders.PriceAboveMax.selector);
        limitOrders.fillOrder(orderId, 1_000e18);
    }

    // when ohmOut is zero
    //  [X] it reverts
    function test_fillOrder_revert_zeroOhmOut() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        cdAuctioneer.setMinimumBid(5_000e18); // Raise minimum after order creation

        // Check canFillOrder returns false with reason before fill
        {
            (bool canFill, string memory reason, ) = limitOrders.canFillOrder(orderId, 1_000e18);
            assertFalse(canFill, "Order should not be fillable when OHM output is zero");
            assertEq(reason, "Zero OHM output", "Reason should indicate zero OHM output");
        }

        vm.prank(filler);
        vm.expectRevert(ILimitOrders.ZeroOhmOut.selector);
        limitOrders.fillOrder(orderId, 1_000e18);
    }

    // when the contract is disabled
    //  [X] it reverts
    function test_fillOrder_givenDisabled_reverts() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Disable
        _disableContract();

        // Check canFillOrder returns false with reason before fill
        {
            (bool canFill, string memory reason, ) = limitOrders.canFillOrder(orderId, 1_000e18);
            assertFalse(canFill, "Order should not be fillable when contract is disabled");
            assertEq(reason, "Contract disabled", "Reason should indicate contract is disabled");
        }

        // Check incentive
        {
            (uint256 incentive, uint256 incentiveRate) = limitOrders.calculateIncentive(
                orderId,
                1_000e18
            );
            assertEq(incentive, 0, "Incentive should be 0");
            assertEq(incentiveRate, 0, "Incentive rate should be 0");
        }

        // Expect revert
        vm.expectRevert(IEnabler.NotEnabled.selector);

        // Call function
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 1_000e18);
    }

    // given the deposit period has been disabled
    //  [X] it reverts
    function test_fillOrder_revert_depositPeriodDisabled() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Disable deposit period
        cdAuctioneer.setDepositPeriodEnabled(PERIOD_3, false);

        // Check canFillOrder returns false with reason before fill
        {
            (bool canFill, string memory reason, ) = limitOrders.canFillOrder(orderId, 1_000e18);
            assertFalse(canFill, "Order should not be fillable when deposit period is disabled");
            assertEq(
                reason,
                "Deposit period not enabled",
                "Reason should indicate deposit period is not enabled"
            );
        }

        // Expect revert
        vm.expectRevert(ILimitOrders.DepositPeriodNotEnabled.selector);

        // Call function
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 1_000e18);
    }

    function test_fillOrder_incentiveBudgetFuzz(uint256 incentiveBudget_) public {
        incentiveBudget_ = bound(incentiveBudget_, 0, 50_000e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            incentiveBudget_,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Calculate expected values before fill
        uint256 fillAmount = 1_000e18;
        uint256 expectedIncentive = (fillAmount * incentiveBudget_) / DEFAULT_DEPOSIT_BUDGET;
        uint256 expectedShares = sUsds.balanceOf(address(limitOrders)) -
            sUsds.previewWithdraw(fillAmount + expectedIncentive);

        // Check canFillOrder returns true before fill
        {
            (bool canFill, string memory reason, uint256 effectivePrice) = limitOrders.canFillOrder(
                orderId,
                fillAmount
            );
            assertTrue(canFill, "Order should be fillable");
            assertEq(bytes(reason).length, 0, "Reason should be empty when order is fillable");
            assertEq(
                effectivePrice,
                _getEffectivePrice(MOCK_PRICE, fillAmount),
                "Effective price should equal mock price"
            );
        }

        vm.prank(filler);
        limitOrders.fillOrder(orderId, fillAmount);

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, fillAmount, "Deposit spent should equal fill amount");
        assertEq(order.incentiveSpent, expectedIncentive, "Incentive spent mismatch");

        // Check alice received NFT
        assertEq(positionNFT.ownerOf(1), alice, "Alice should own NFT token ID 1");

        // Check balances and invariants after fill
        checkOrderInvariants(
            orderId,
            DEFAULT_DEPOSIT_BUDGET + incentiveBudget_,
            fillAmount + expectedIncentive,
            filler,
            expectedIncentive,
            expectedShares
        );
    }

    function test_fillOrder_depositBudgetFuzz(uint256 depositBudget_) public {
        depositBudget_ = bound(depositBudget_, 1_000e18, 50_000e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            depositBudget_,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Calculate expected budget use
        uint256 fillAmount = 1_000e18;
        uint256 expectedIncentive = (fillAmount * DEFAULT_INCENTIVE_BUDGET) / depositBudget_;
        uint256 expectedShares = sUsds.balanceOf(address(limitOrders)) -
            sUsds.previewWithdraw(fillAmount + expectedIncentive);

        // Check canFillOrder returns true before fill
        {
            (bool canFill, string memory reason, uint256 effectivePrice) = limitOrders.canFillOrder(
                orderId,
                fillAmount
            );
            assertTrue(canFill, "Order should be fillable");
            assertEq(bytes(reason).length, 0, "Reason should be empty when order is fillable");
            assertEq(
                effectivePrice,
                _getEffectivePrice(MOCK_PRICE, fillAmount),
                "Effective price should equal mock price"
            );
        }

        vm.prank(filler);
        limitOrders.fillOrder(orderId, fillAmount);

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, fillAmount, "Deposit spent should equal fill amount");
        assertEq(order.incentiveSpent, expectedIncentive, "Incentive spent mismatch");

        // Check alice received NFT
        assertEq(positionNFT.ownerOf(1), alice, "Alice should own NFT token ID 1");

        // Check balances and invariants after fill
        checkOrderInvariants(
            orderId,
            depositBudget_ + DEFAULT_INCENTIVE_BUDGET,
            fillAmount + expectedIncentive,
            filler,
            expectedIncentive,
            expectedShares
        );
    }

    function test_fillOrder_fillAmountFuzz(uint256 fillAmount_) public {
        fillAmount_ = bound(fillAmount_, 1_000e18, 10_000e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Calculate expected budget use
        uint256 expectedIncentive = (fillAmount_ * DEFAULT_INCENTIVE_BUDGET) /
            DEFAULT_DEPOSIT_BUDGET;
        uint256 expectedShares = sUsds.balanceOf(address(limitOrders)) -
            sUsds.previewWithdraw(fillAmount_ + expectedIncentive);

        // Check canFillOrder returns true before fill
        {
            (bool canFill, string memory reason, uint256 effectivePrice) = limitOrders.canFillOrder(
                orderId,
                fillAmount_
            );
            assertTrue(canFill, "Order should be fillable");
            assertEq(bytes(reason).length, 0, "Reason should be empty when order is fillable");
            assertEq(
                effectivePrice,
                _getEffectivePrice(MOCK_PRICE, fillAmount_),
                "Effective price should equal mock price"
            );
        }

        vm.prank(filler);
        limitOrders.fillOrder(orderId, fillAmount_);

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, fillAmount_, "Deposit spent should equal fill amount");
        assertEq(order.incentiveSpent, expectedIncentive, "Incentive spent mismatch");

        // Check alice received NFT
        assertEq(positionNFT.ownerOf(1), alice, "Alice should own NFT token ID 1");

        // Check balances and invariants after fill
        checkOrderInvariants(
            orderId,
            DEFAULT_DEPOSIT_BUDGET + DEFAULT_INCENTIVE_BUDGET,
            fillAmount_ + expectedIncentive,
            filler,
            expectedIncentive,
            expectedShares
        );
    }

    function test_fillOrder_givenYield_fillAmountFuzz(uint256 fillAmount_) public {
        fillAmount_ = bound(fillAmount_, 1_000e18, 10_000e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Yield accrual
        _accrueYield(123e18);

        // Check canFillOrder returns true before fill
        {
            (bool canFill, string memory reason, uint256 effectivePrice) = limitOrders.canFillOrder(
                orderId,
                fillAmount_
            );
            assertTrue(canFill, "Order should be fillable");
            assertEq(bytes(reason).length, 0, "Reason should be empty when order is fillable");
            assertEq(
                effectivePrice,
                _getEffectivePrice(MOCK_PRICE, fillAmount_),
                "Effective price should equal mock price"
            );
        }

        // Calculate expected budget use
        uint256 expectedIncentive = (fillAmount_ * DEFAULT_INCENTIVE_BUDGET) /
            DEFAULT_DEPOSIT_BUDGET;
        uint256 expectedShares = sUsds.balanceOf(address(limitOrders)) -
            sUsds.previewWithdraw(fillAmount_ + expectedIncentive);

        vm.prank(filler);
        limitOrders.fillOrder(orderId, fillAmount_);

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, fillAmount_, "Deposit spent should equal fill amount");
        assertEq(order.incentiveSpent, expectedIncentive, "Incentive spent mismatch");

        // Check alice received NFT
        assertEq(positionNFT.ownerOf(1), alice, "Alice should own NFT token ID 1");

        // Check balances and invariants after fill
        checkOrderInvariants(
            orderId,
            DEFAULT_DEPOSIT_BUDGET + DEFAULT_INCENTIVE_BUDGET,
            fillAmount_ + expectedIncentive,
            filler,
            expectedIncentive,
            expectedShares
        );
    }

    function test_fillOrder_priceFuzz(uint256 price_) public {
        price_ = bound(price_, MOCK_PRICE, 50e18);
        cdAuctioneer.setMockPrice(price_);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            50e18,
            DEFAULT_MIN_FILL_SIZE
        );

        // Calculate expected budget use
        uint256 fillAmount = 1_000e18;
        uint256 expectedIncentive = (fillAmount * DEFAULT_INCENTIVE_BUDGET) /
            DEFAULT_DEPOSIT_BUDGET;
        uint256 expectedShares = sUsds.balanceOf(address(limitOrders)) -
            sUsds.previewWithdraw(fillAmount + expectedIncentive);

        // Check canFillOrder returns true before fill
        {
            (bool canFill, string memory reason, uint256 effectivePrice) = limitOrders.canFillOrder(
                orderId,
                fillAmount
            );
            assertTrue(canFill, "Order should be fillable");
            assertEq(bytes(reason).length, 0, "Reason should be empty when order is fillable");
            assertEq(
                effectivePrice,
                _getEffectivePrice(price_, fillAmount),
                "Effective price should equal mock price"
            );
        }

        vm.prank(filler);
        limitOrders.fillOrder(orderId, fillAmount);

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, fillAmount, "Deposit spent should equal fill amount");
        assertEq(order.incentiveSpent, expectedIncentive, "Incentive spent mismatch");

        // Check alice received NFT
        assertEq(positionNFT.ownerOf(1), alice, "Alice should own NFT token ID 1");

        // Check balances and invariants after fill
        checkOrderInvariants(
            orderId,
            DEFAULT_DEPOSIT_BUDGET + DEFAULT_INCENTIVE_BUDGET,
            fillAmount + expectedIncentive,
            filler,
            expectedIncentive,
            expectedShares
        );
    }

    // when the auctioneer returns a different actual deposit amount
    //  [X] the incentive is calculated based on the actual deposit amount
    //  [X] the deposit spent is reduced by the actual deposit amount
    //  [X] the incentive spent is reduced by the actual incentive amount
    //  [X] the total USDS owed is reduced by the actual deposit amount
    //  [X] the actual deposit amount is returned
    //  [X] the actual incentive amount is returned
    function test_fillOrder_givenDifferentActualAmount(uint256 actualAmountDifference_) public {
        actualAmountDifference_ = bound(actualAmountDifference_, 0, 100);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Set a slight difference in the actual amount
        cdAuctioneer.setActualAmountDifference(actualAmountDifference_);

        // Accrue yield
        _accrueYield(123e18);

        // Calculate expected budget use
        uint256 fillAmount = 1_000e18;
        uint256 expectedIncentive = (fillAmount * DEFAULT_INCENTIVE_BUDGET) /
            DEFAULT_DEPOSIT_BUDGET;
        uint256 expectedShares = sUsds.balanceOf(address(limitOrders)) -
            sUsds.previewWithdraw(fillAmount + expectedIncentive);

        // Check canFillOrder returns true before fill
        {
            (bool canFill, string memory reason, uint256 effectivePrice) = limitOrders.canFillOrder(
                orderId,
                fillAmount
            );
            assertTrue(canFill, "Order should be fillable");
            assertEq(bytes(reason).length, 0, "Reason should be empty when order is fillable");
            assertEq(
                effectivePrice,
                _getEffectivePrice(MOCK_PRICE, fillAmount),
                "Effective price should equal mock price"
            );
        }

        vm.prank(filler);
        (
            uint256 actualFillAmount,
            uint256 returnedIncentive,
            uint256 remainingDeposit
        ) = limitOrders.fillOrder(orderId, fillAmount);

        // Check return values
        assertEq(
            actualFillAmount,
            fillAmount,
            "Actual fill amount should equal requested fill amount"
        );
        assertEq(
            returnedIncentive,
            expectedIncentive,
            "Returned incentive should equal expected incentive"
        );
        assertEq(
            remainingDeposit,
            DEFAULT_DEPOSIT_BUDGET - fillAmount,
            "Remaining deposit should equal deposit budget minus fill amount"
        );

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, fillAmount, "Deposit spent should equal fill amount");
        assertEq(order.incentiveSpent, expectedIncentive, "Incentive spent mismatch");

        // Check alice received NFT
        assertEq(positionNFT.ownerOf(1), alice, "Alice should own NFT token ID 1");

        // Check balances and invariants after fill
        {
            address[] memory fillers = new address[](1);
            fillers[0] = filler;
            uint256[] memory expectedFillerBalances = new uint256[](1);
            expectedFillerBalances[0] = expectedIncentive;
            checkOrdersInvariants(
                OrderParams({
                    id: 0,
                    total: DEFAULT_DEPOSIT_BUDGET + DEFAULT_INCENTIVE_BUDGET,
                    spent: fillAmount + expectedIncentive,
                    receiptTokenBalance: fillAmount - actualAmountDifference_
                }),
                OrderParams({
                    id: type(uint256).max,
                    total: 0,
                    spent: 0,
                    receiptTokenBalance: type(uint256).max
                }),
                fillers,
                expectedFillerBalances,
                expectedShares
            );
        }
    }

    // ========== CANCEL ORDER TESTS ========== //

    // when order is active and not filled
    //  [X] it cancels order
    //  [X] it refunds the amount of deposit and incentive budgets
    //  [X] it reduces the USDS owed by the full amount of deposit and incentive budgets
    function test_cancelOrder_success() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Create a second order
        vm.prank(alice);
        limitOrders.createOrder(
            PERIOD_3,
            SMALL_DEPOSIT_BUDGET,
            SMALL_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, DEFAULT_DEPOSIT_BUDGET, "Deposit budget should be unchanged");
        assertEq(
            order.incentiveBudget,
            DEFAULT_INCENTIVE_BUDGET,
            "Incentive budget should be unchanged"
        );
        assertEq(order.depositSpent, 0, "Deposit spent should be 0");
        assertEq(order.incentiveSpent, 0, "Incentive spent should be 0");
        assertFalse(order.active, "Order should be inactive after cancellation");

        // USDS owed should be reduced by the full amount of deposit and incentive budgets
        assertEq(
            limitOrders.totalUsdsOwed(),
            SMALL_DEPOSIT_BUDGET + SMALL_INCENTIVE_BUDGET,
            "Total USDS owed should be the sum of the deposit and incentive budgets of the second order"
        );

        // Alice should receive full refund
        assertEq(
            usds.balanceOf(alice) - aliceBalanceBefore,
            DEFAULT_DEPOSIT_BUDGET + DEFAULT_INCENTIVE_BUDGET,
            "Alice should receive full refund of deposit + incentive budgets"
        );
    }

    function test_cancelOrder_givenYield(uint256 yieldAmount_) public {
        yieldAmount_ = bound(yieldAmount_, 1e18, 100_000e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Create a second order
        vm.prank(alice);
        limitOrders.createOrder(
            PERIOD_3,
            SMALL_DEPOSIT_BUDGET,
            SMALL_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Yield accrual
        _accrueYield(yieldAmount_);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, DEFAULT_DEPOSIT_BUDGET, "Deposit budget should be unchanged");
        assertEq(
            order.incentiveBudget,
            DEFAULT_INCENTIVE_BUDGET,
            "Incentive budget should be unchanged"
        );
        assertEq(order.depositSpent, 0, "Deposit spent should be 0");
        assertEq(order.incentiveSpent, 0, "Incentive spent should be 0");
        assertFalse(order.active, "Order should be inactive after cancellation");

        // USDS owed should be reduced by the full amount of deposit and incentive budgets
        assertEq(
            limitOrders.totalUsdsOwed(),
            SMALL_DEPOSIT_BUDGET + SMALL_INCENTIVE_BUDGET,
            "Total USDS owed should be the sum of the deposit and incentive budgets of the second order"
        );

        // Alice should receive full refund
        assertEq(
            usds.balanceOf(alice) - aliceBalanceBefore,
            DEFAULT_DEPOSIT_BUDGET + DEFAULT_INCENTIVE_BUDGET,
            "Alice should receive full refund of deposit + incentive budgets"
        );
    }

    // when order is active and partially filled
    //  [X] it cancels order
    //  [X] it refunds the remaining amount of deposit and incentive budgets
    //  [X] it reduces the USDS owed by the remaining amount of deposit and incentive budgets
    function test_cancelOrder_afterPartialFill() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Create a second order
        vm.prank(alice);
        limitOrders.createOrder(
            PERIOD_3,
            SMALL_DEPOSIT_BUDGET,
            SMALL_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Partial fill
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 3_000e18);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, DEFAULT_DEPOSIT_BUDGET, "Deposit budget should be unchanged");
        assertEq(
            order.incentiveBudget,
            DEFAULT_INCENTIVE_BUDGET,
            "Incentive budget should be unchanged"
        );
        assertEq(order.depositSpent, 3_000e18, "Deposit spent should be 3_000e18");
        assertEq(order.incentiveSpent, 15e18, "Incentive spent should be 15e18");
        assertEq(order.active, false, "Order should be inactive after cancellation");

        // USDS owed should be reduced by the remaining amount of deposit and incentive budgets
        assertEq(
            limitOrders.totalUsdsOwed(),
            SMALL_DEPOSIT_BUDGET + SMALL_INCENTIVE_BUDGET,
            "Total USDS owed should be the sum of the deposit and incentive budgets of the second order"
        );

        // Alice should receive remaining: 7000 deposit + 35 incentive
        uint256 expectedRefund = 7_000e18 + 35e18;
        assertEq(
            usds.balanceOf(alice) - aliceBalanceBefore,
            expectedRefund,
            "Alice should receive remaining deposit + incentive budgets after partial fill"
        );
    }

    function test_cancelOrder_afterPartialFill_givenYield(uint256 yieldAmount_) public {
        yieldAmount_ = bound(yieldAmount_, 1e18, 100_000e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Create a second order
        vm.prank(alice);
        limitOrders.createOrder(
            PERIOD_3,
            SMALL_DEPOSIT_BUDGET,
            SMALL_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Partial fill
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 3_000e18);

        // Yield accrual
        _accrueYield(yieldAmount_);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, DEFAULT_DEPOSIT_BUDGET, "Deposit budget should be unchanged");
        assertEq(
            order.incentiveBudget,
            DEFAULT_INCENTIVE_BUDGET,
            "Incentive budget should be unchanged"
        );
        assertEq(order.depositSpent, 3_000e18, "Deposit spent should be 3_000e18");
        assertEq(order.incentiveSpent, 15e18, "Incentive spent should be 15e18");
        assertEq(order.active, false, "Order should be inactive after cancellation");

        // USDS owed should be reduced by the remaining amount of deposit and incentive budgets
        assertEq(
            limitOrders.totalUsdsOwed(),
            SMALL_DEPOSIT_BUDGET + SMALL_INCENTIVE_BUDGET,
            "Total USDS owed should be the sum of the deposit and incentive budgets of the second order"
        );

        // Alice should receive remaining: 7000 deposit + 35 incentive
        uint256 expectedRefund = 7_000e18 + 35e18;
        assertEq(
            usds.balanceOf(alice) - aliceBalanceBefore,
            expectedRefund,
            "Alice should receive remaining deposit + incentive budgets after partial fill"
        );
    }

    // when the order is completely filled
    //  [X] it reverts

    function test_cancelOrder_fullyFilled() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Fill order
        vm.prank(filler);
        limitOrders.fillOrder(orderId, DEFAULT_DEPOSIT_BUDGET);

        // Cancel order
        vm.expectRevert(ILimitOrders.OrderFullySpent.selector);
        vm.prank(alice);
        limitOrders.cancelOrder(orderId);
    }

    // when caller is not order owner
    //  [X] it reverts
    function test_cancelOrder_revert_notOwner() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        vm.prank(bob);
        vm.expectRevert(ILimitOrders.NotOrderOwner.selector);
        limitOrders.cancelOrder(orderId);
    }

    // when order is already cancelled
    //  [X] it reverts
    function test_cancelOrder_revert_alreadyCancelled() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        vm.prank(alice);
        vm.expectRevert(ILimitOrders.OrderNotActive.selector);
        limitOrders.cancelOrder(orderId);
    }

    // when the contract is disabled
    //  [X] it cancels order
    //  [X] it refunds the amount of deposit and incentive budgets
    //  [X] it reduces the USDS owed by the full amount of deposit and incentive budgets
    function test_cancelOrder_givenDisabled() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        // Disable
        _disableContract();

        // Cancel the order
        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, DEFAULT_DEPOSIT_BUDGET, "Deposit budget should be unchanged");
        assertEq(
            order.incentiveBudget,
            DEFAULT_INCENTIVE_BUDGET,
            "Incentive budget should be unchanged"
        );
        assertEq(order.depositSpent, 0, "Deposit spent should be 0");
        assertEq(order.incentiveSpent, 0, "Incentive spent should be 0");
        assertFalse(order.active, "Order should be inactive after cancellation");

        // USDS owed should be reduced by the full amount of deposit and incentive budgets
        assertEq(limitOrders.totalUsdsOwed(), 0, "Total USDS owed should be 0");

        // Alice should receive full refund
        assertEq(
            usds.balanceOf(alice) - aliceBalanceBefore,
            DEFAULT_DEPOSIT_BUDGET + DEFAULT_INCENTIVE_BUDGET,
            "Alice should receive full refund of deposit + incentive budgets"
        );
    }

    // given the deposit period has been removed
    //  [X] the order is cancelled
    //  [X] it refunds the amount of deposit and incentive budgets
    //  [X] it reduces the USDS owed by the full amount of deposit and incentive budgets
    function test_cancelOrder_givenDepositPeriodRemoved() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Remove the deposit period
        vm.prank(owner);
        limitOrders.removeDepositPeriod(PERIOD_3);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        // Cancel the order
        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, DEFAULT_DEPOSIT_BUDGET, "Deposit budget should be unchanged");
        assertEq(
            order.incentiveBudget,
            DEFAULT_INCENTIVE_BUDGET,
            "Incentive budget should be unchanged"
        );
        assertEq(order.depositSpent, 0, "Deposit spent should be 0");
        assertEq(order.incentiveSpent, 0, "Incentive spent should be 0");
        assertFalse(order.active, "Order should be inactive after cancellation");

        // USDS owed should be reduced by the full amount of deposit and incentive budgets
        assertEq(limitOrders.totalUsdsOwed(), 0, "Total USDS owed should be 0");

        // Alice should receive full refund
        assertEq(
            usds.balanceOf(alice) - aliceBalanceBefore,
            DEFAULT_DEPOSIT_BUDGET + DEFAULT_INCENTIVE_BUDGET,
            "Alice should receive full refund of deposit + incentive budgets"
        );
        _assertSolvent();
    }

    // ========== YIELD TESTS ========== //

    function _assertSolvent() internal view {
        uint256 totalUsdsOwed = limitOrders.totalUsdsOwed();
        uint256 usdsOwedShares = sUsds.previewWithdraw(totalUsdsOwed);
        uint256 sUsdsBalance = sUsds.balanceOf(address(limitOrders));
        assertGe(sUsdsBalance, usdsOwedShares, "Contract should be solvent");
    }

    // when yield has accrued
    //  [X] it sweeps yield successfully
    //  [X] it transfers sUSDS shares to recipient
    //  [X] it does not transfer USDS to recipient
    //  [X] the contract remains solvent
    function test_sweepYield_success() public {
        vm.prank(alice);
        limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Yield accrual
        _accrueYield(123e18);

        // Calculate expected yield
        uint256 sUsdsBalance = sUsds.balanceOf(address(limitOrders));
        uint256 usdsOwedShares = sUsds.previewWithdraw(limitOrders.totalUsdsOwed());
        uint256 expectedYieldShares = sUsdsBalance - usdsOwedShares;
        uint256 expectedYield = sUsds.previewRedeem(expectedYieldShares);
        uint256 recipientUsdsBefore = usds.balanceOf(yieldRecipient);
        uint256 recipientSharesBefore = sUsds.balanceOf(yieldRecipient);

        // Check preview functions
        uint256 yield = limitOrders.getAccruedYield();
        assertEq(yield, expectedYield, "Yield should equal expected yield");

        uint256 yieldShares = limitOrders.getAccruedYieldShares();
        assertEq(
            yieldShares,
            expectedYieldShares,
            "Yield shares should equal expected yield shares"
        );

        // Perform sweep
        limitOrders.sweepYield();

        // Check balances
        assertEq(
            usds.balanceOf(yieldRecipient),
            recipientUsdsBefore,
            "USDS balance of yield recipient should be unchanged"
        );
        assertEq(
            sUsds.balanceOf(yieldRecipient),
            recipientSharesBefore + expectedYieldShares,
            "sUSDS balance of yield recipient should equal expected yield shares"
        );

        _assertSolvent();
    }

    // when no yield has accrued
    //  [X] it returns zero shares
    //  [X] it does not transfer sUSDS to recipient
    //  [X] it does not transfer USDS to recipient
    //  [X] the contract remains solvent
    function test_sweepYield_noYield() public {
        vm.prank(alice);
        limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        uint256 recipientUsdsBefore = usds.balanceOf(yieldRecipient);
        uint256 recipientSharesBefore = sUsds.balanceOf(yieldRecipient);

        // Check preview functions
        uint256 yield = limitOrders.getAccruedYield();
        assertEq(yield, 0, "Yield should be 0 when no yield has accrued");
        uint256 yieldShares = limitOrders.getAccruedYieldShares();
        assertEq(yieldShares, 0, "Yield shares should be 0 when no yield has accrued");

        // Perform sweep
        uint256 shares = limitOrders.sweepYield();
        assertEq(shares, 0, "Swept shares should be 0 when no yield has accrued");

        // Check balances
        assertEq(
            usds.balanceOf(yieldRecipient),
            recipientUsdsBefore,
            "USDS balance of yield recipient should be unchanged"
        );
        assertEq(
            sUsds.balanceOf(yieldRecipient),
            recipientSharesBefore,
            "sUSDS balance of yield recipient should be unchanged"
        );

        _assertSolvent();
    }

    // when there has been a partial fill
    //  [X] it sweeps yield successfully
    //  [X] it transfers sUSDS shares to recipient
    //  [X] it does not transfer USDS to recipient
    //  [X] the contract remains solvent
    function test_sweepYield_partialFill() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Fill half
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 5_000e18);

        // Yield accrual
        _accrueYield(123e18);

        // Calculate expected yield
        uint256 sUsdsBalance = sUsds.balanceOf(address(limitOrders));
        uint256 usdsOwedShares = sUsds.previewWithdraw(limitOrders.totalUsdsOwed());
        uint256 expectedYieldShares = sUsdsBalance - usdsOwedShares;
        uint256 expectedYield = sUsds.previewRedeem(expectedYieldShares);
        uint256 recipientUsdsBefore = usds.balanceOf(yieldRecipient);
        uint256 recipientSharesBefore = sUsds.balanceOf(yieldRecipient);

        // Check preview functions
        uint256 yield = limitOrders.getAccruedYield();
        assertEq(yield, expectedYield, "Yield should equal expected yield");

        uint256 yieldShares = limitOrders.getAccruedYieldShares();
        assertEq(
            yieldShares,
            expectedYieldShares,
            "Yield shares should equal expected yield shares"
        );

        // Perform sweep
        uint256 shares = limitOrders.sweepYield();
        assertEq(shares, expectedYieldShares, "Swept shares should equal expected yield shares");

        // Check balances
        assertEq(
            usds.balanceOf(yieldRecipient),
            recipientUsdsBefore,
            "USDS balance of yield recipient should be unchanged"
        );
        assertEq(
            sUsds.balanceOf(yieldRecipient),
            recipientSharesBefore + expectedYieldShares,
            "sUSDS balance of yield recipient should equal expected yield shares"
        );

        _assertSolvent();
    }

    function test_sweepYield_partialFill_fuzz(uint256 yieldAmount_) public {
        yieldAmount_ = bound(yieldAmount_, 1e18, 100_000e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Fill half
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 5_000e18);

        // Yield accrual
        _accrueYield(yieldAmount_);

        // Calculate expected yield
        uint256 sUsdsBalance = sUsds.balanceOf(address(limitOrders));
        uint256 usdsOwedShares = sUsds.previewWithdraw(limitOrders.totalUsdsOwed());
        uint256 expectedYieldShares = sUsdsBalance - usdsOwedShares;
        uint256 expectedYield = sUsds.previewRedeem(expectedYieldShares);
        uint256 recipientUsdsBefore = usds.balanceOf(yieldRecipient);
        uint256 recipientSharesBefore = sUsds.balanceOf(yieldRecipient);

        // Check preview functions
        uint256 yield = limitOrders.getAccruedYield();
        assertEq(yield, expectedYield, "Yield should equal expected yield");

        uint256 yieldShares = limitOrders.getAccruedYieldShares();
        assertEq(
            yieldShares,
            expectedYieldShares,
            "Yield shares should equal expected yield shares"
        );

        // Perform sweep
        uint256 shares = limitOrders.sweepYield();
        assertEq(shares, expectedYieldShares, "Swept shares should equal expected yield shares");

        // Check balances
        assertEq(
            usds.balanceOf(yieldRecipient),
            recipientUsdsBefore,
            "USDS balance of yield recipient should be unchanged"
        );
        assertEq(
            sUsds.balanceOf(yieldRecipient),
            recipientSharesBefore + expectedYieldShares,
            "sUSDS balance of yield recipient should equal expected yield shares"
        );

        _assertSolvent();
    }

    // when all orders have been filled
    //  [X] it sweeps yield successfully
    //  [X] it transfers sUSDS shares to recipient
    //  [X] it does not transfer USDS to recipient
    //  [X] the contract remains solvent
    function test_sweepYield_allOrdersFilled() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Fill all orders
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 10_000e18);

        // Yield accrual
        _accrueYield(123e18);

        // Calculate expected yield
        uint256 sUsdsBalance = sUsds.balanceOf(address(limitOrders));
        uint256 usdsOwedShares = 0; // No USDS owed when all orders have been filled
        uint256 expectedYieldShares = sUsdsBalance - usdsOwedShares;
        uint256 expectedYield = sUsds.previewRedeem(expectedYieldShares);
        uint256 recipientUsdsBefore = usds.balanceOf(yieldRecipient);
        uint256 recipientSharesBefore = sUsds.balanceOf(yieldRecipient);

        // Check preview functions
        uint256 yield = limitOrders.getAccruedYield();
        assertEq(yield, expectedYield, "Yield should equal expected yield");

        uint256 yieldShares = limitOrders.getAccruedYieldShares();
        assertEq(
            yieldShares,
            expectedYieldShares,
            "Yield shares should equal expected yield shares"
        );

        // Perform sweep
        uint256 shares = limitOrders.sweepYield();
        assertEq(shares, expectedYieldShares, "Swept shares should equal expected yield shares");

        // Check balances
        assertEq(
            usds.balanceOf(yieldRecipient),
            recipientUsdsBefore,
            "USDS balance of yield recipient should be unchanged"
        );
        assertEq(
            sUsds.balanceOf(yieldRecipient),
            recipientSharesBefore + expectedYieldShares,
            "sUSDS balance of yield recipient should equal expected yield shares"
        );

        _assertSolvent();
    }

    function test_sweepYield_allOrdersFilled_fuzz(uint256 yieldAmount_) public {
        yieldAmount_ = bound(yieldAmount_, 1e18, 100_000e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Fill all orders
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 10_000e18);

        // Yield accrual
        _accrueYield(yieldAmount_);

        // Calculate expected yield
        uint256 sUsdsBalance = sUsds.balanceOf(address(limitOrders));
        uint256 usdsOwedShares = 0; // No USDS owed when all orders have been filled
        uint256 expectedYieldShares = sUsdsBalance - usdsOwedShares;
        uint256 expectedYield = sUsds.previewRedeem(expectedYieldShares);
        uint256 recipientUsdsBefore = usds.balanceOf(yieldRecipient);
        uint256 recipientSharesBefore = sUsds.balanceOf(yieldRecipient);

        // Check preview functions
        uint256 yield = limitOrders.getAccruedYield();
        assertEq(yield, expectedYield, "Yield should equal expected yield");

        uint256 yieldShares = limitOrders.getAccruedYieldShares();
        assertEq(
            yieldShares,
            expectedYieldShares,
            "Yield shares should equal expected yield shares"
        );

        // Perform sweep
        uint256 shares = limitOrders.sweepYield();
        assertEq(shares, expectedYieldShares, "Swept shares should equal expected yield shares");

        // Check balances
        assertEq(
            usds.balanceOf(yieldRecipient),
            recipientUsdsBefore,
            "USDS balance of yield recipient should be unchanged"
        );
        assertEq(
            sUsds.balanceOf(yieldRecipient),
            recipientSharesBefore + expectedYieldShares,
            "sUSDS balance of yield recipient should equal expected yield shares"
        );

        _assertSolvent();
    }

    // when the contract is disabled
    //  [X] it reverts
    function test_sweepYield_givenDisabled_reverts() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        vm.prank(filler);
        limitOrders.fillOrder(orderId, 10_000e18);

        // Disable
        _disableContract();

        // Expect revert
        vm.expectRevert(IEnabler.NotEnabled.selector);

        // Call function
        vm.prank(owner);
        limitOrders.sweepYield();
    }

    // ========== ADMIN TESTS ========== //

    // setYieldRecipient
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
            abi.encodeWithSelector(ILimitOrders.InvalidParam.selector, "yieldRecipient")
        );
        limitOrders.setYieldRecipient(address(0));
    }

    // when the contract is disabled
    //  [X] it reverts
    function test_setYieldRecipient_givenDisabled_reverts() public givenDisabled {
        address newRecipient = makeAddr("newRecipient");

        vm.prank(owner);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        limitOrders.setYieldRecipient(newRecipient);
    }

    // addDepositPeriod
    // when all parameters are valid
    //  [X] it adds deposit period successfully
    //  [X] it emits DepositPeriodAdded event
    function test_addDepositPeriod_success() public {
        cdAuctioneer.setDepositPeriodEnabled(PERIOD_12, true);
        cdAuctioneer.setReceiptToken(PERIOD_12, address(receiptToken12));

        vm.expectEmit(true, true, false, false);
        emit ILimitOrders.DepositPeriodAdded(PERIOD_12, address(receiptToken12));

        vm.prank(owner);
        limitOrders.addDepositPeriod(PERIOD_12, address(receiptToken12));

        assertEq(
            address(limitOrders.receiptTokens(PERIOD_12)),
            address(receiptToken12),
            "Receipt token should be set for PERIOD_12"
        );
    }

    // when caller is not owner
    //  [X] it reverts
    function test_addDepositPeriod_revert_notOwner() public {
        cdAuctioneer.setDepositPeriodEnabled(PERIOD_12, true);
        cdAuctioneer.setReceiptToken(PERIOD_12, address(receiptToken12));

        vm.prank(alice);
        vm.expectRevert();
        limitOrders.addDepositPeriod(PERIOD_12, address(receiptToken12));
    }

    // when contract is disabled
    //  [X] it reverts
    function test_addDepositPeriod_givenDisabled_reverts() public givenDisabled {
        cdAuctioneer.setDepositPeriodEnabled(PERIOD_12, true);
        cdAuctioneer.setReceiptToken(PERIOD_12, address(receiptToken12));

        vm.prank(owner);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        limitOrders.addDepositPeriod(PERIOD_12, address(receiptToken12));
    }

    // when depositPeriod is 0
    //  [X] it reverts
    function test_addDepositPeriod_revert_zeroDepositPeriod() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(ILimitOrders.InvalidParam.selector, "depositPeriod")
        );
        limitOrders.addDepositPeriod(0, address(receiptToken12));
    }

    // when receiptToken is address(0)
    //  [X] it reverts
    function test_addDepositPeriod_revert_zeroReceiptToken() public {
        cdAuctioneer.setDepositPeriodEnabled(PERIOD_12, true);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ILimitOrders.InvalidParam.selector, "receiptToken"));
        limitOrders.addDepositPeriod(PERIOD_12, address(0));
    }

    // when deposit period is already configured
    //  [X] it reverts
    function test_addDepositPeriod_revert_alreadyConfigured() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILimitOrders.InvalidParam.selector,
                "depositPeriod already configured"
            )
        );
        limitOrders.addDepositPeriod(PERIOD_3, address(receiptToken3));
    }

    // when deposit period is not enabled in auctioneer
    //  [X] it reverts
    function test_addDepositPeriod_revert_notEnabledInAuctioneer() public {
        cdAuctioneer.setDepositPeriodEnabled(PERIOD_12, false);

        vm.prank(owner);
        vm.expectRevert(ILimitOrders.DepositPeriodNotEnabled.selector);
        limitOrders.addDepositPeriod(PERIOD_12, address(receiptToken12));
    }

    // removeDepositPeriod
    // when all parameters are valid
    //  [X] it removes deposit period successfully
    //  [X] it emits DepositPeriodRemoved event
    function test_removeDepositPeriod_success() public {
        vm.expectEmit(true, false, false, false);
        emit ILimitOrders.DepositPeriodRemoved(PERIOD_3);

        vm.prank(owner);
        limitOrders.removeDepositPeriod(PERIOD_3);

        assertEq(
            address(limitOrders.receiptTokens(PERIOD_3)),
            address(0),
            "Receipt token should be removed for PERIOD_3"
        );
    }

    // when caller is not owner
    //  [X] it reverts
    function test_removeDepositPeriod_revert_notOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        limitOrders.removeDepositPeriod(PERIOD_3);
    }

    // when contract is disabled
    //  [X] it reverts
    function test_removeDepositPeriod_givenDisabled_reverts() public givenDisabled {
        vm.prank(owner);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        limitOrders.removeDepositPeriod(PERIOD_3);
    }

    // when deposit period is not configured
    //  [X] it reverts
    function test_removeDepositPeriod_revert_notConfigured() public {
        vm.prank(owner);
        vm.expectRevert(ILimitOrders.ReceiptTokenNotConfigured.selector);
        limitOrders.removeDepositPeriod(PERIOD_12);
    }

    // when there are active orders for the deposit period
    //  [X] it removes successfully (users can cancel orders)
    //  [X] active orders fail to fill after removal
    function test_removeDepositPeriod_withActiveOrders() public {
        // Create an order for PERIOD_3
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Remove the deposit period
        vm.prank(owner);
        limitOrders.removeDepositPeriod(PERIOD_3);

        // Verify order still exists
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertTrue(order.active, "Order should still be active");

        // Verify that order cannot be filled
        (bool canFill, string memory reason, ) = limitOrders.canFillOrder(
            orderId,
            DEFAULT_MIN_FILL_SIZE
        );
        assertFalse(canFill, "Order should not be fillable");
        assertEq(
            reason,
            "Receipt token not configured",
            "Reason should indicate receipt token is not configured"
        );

        // Expect revert
        vm.expectRevert(ILimitOrders.ReceiptTokenNotConfigured.selector);

        // Call function
        vm.prank(filler);
        limitOrders.fillOrder(orderId, DEFAULT_MIN_FILL_SIZE);
    }

    // when deposit period is removed and re-added
    //  [X] it allows creating and filling orders again
    function test_removeAndReaddDepositPeriod() public {
        // Remove PERIOD_3
        vm.prank(owner);
        limitOrders.removeDepositPeriod(PERIOD_3);

        // Verify it's removed
        assertEq(
            address(limitOrders.receiptTokens(PERIOD_3)),
            address(0),
            "Receipt token should be removed"
        );

        // Re-add PERIOD_3
        vm.expectEmit(true, true, false, false);
        emit ILimitOrders.DepositPeriodAdded(PERIOD_3, address(receiptToken3));

        vm.prank(owner);
        limitOrders.addDepositPeriod(PERIOD_3, address(receiptToken3));

        // Verify it's added back
        assertEq(
            address(limitOrders.receiptTokens(PERIOD_3)),
            address(receiptToken3),
            "Receipt token should be added back"
        );

        // Create and fill an order to verify it works
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

        // Fill the order
        vm.prank(filler);
        limitOrders.fillOrder(orderId, DEFAULT_MIN_FILL_SIZE);
    }

    // Constructor event emission
    //  [X] it emits DepositPeriodAdded for each deposit period
    function test_constructor_emitsDepositPeriodAdded() public {
        // Deploy a new contract to test constructor events
        uint8[] memory periods = new uint8[](2);
        periods[0] = PERIOD_3;
        periods[1] = PERIOD_6;

        address[] memory receiptTokens = new address[](2);
        receiptTokens[0] = address(receiptToken3);
        receiptTokens[1] = address(receiptToken6);

        vm.expectEmit(true, true, false, false);
        emit ILimitOrders.DepositPeriodAdded(PERIOD_3, address(receiptToken3));

        vm.expectEmit(true, true, false, false);
        emit ILimitOrders.DepositPeriodAdded(PERIOD_6, address(receiptToken6));

        new CDAuctioneerLimitOrders(
            owner,
            address(cdAuctioneer),
            address(usds),
            address(sUsds),
            address(positionNFT),
            yieldRecipient,
            periods,
            receiptTokens
        );
    }

    // transferOwnership
    // when caller is owner
    //  [X] it transfers ownership successfully
    function test_transferOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        limitOrders.transferOwnership(newOwner);

        assertEq(limitOrders.owner(), newOwner, "Contract owner should be updated to new owner");
    }

    // ========== VIEW FUNCTION TESTS ========== //

    // getRemaining
    //  [X] it returns correct remaining deposit and incentive
    function test_getRemainingDeposit() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        );

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
        limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        ); // Fillable
        limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            LOWER_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        ); // Price too high
        limitOrders.createOrder(
            PERIOD_6,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        ); // Different period
        vm.stopPrank();

        uint256[] memory fillable = limitOrders.getFillableOrders(PERIOD_3);

        assertEq(fillable.length, 1, "Should return 1 fillable order for PERIOD_3");
        assertEq(fillable[0], 0, "Fillable order should be order ID 0");
    }

    // when the contract is disabled
    //  [X] it returns empty array
    function test_getFillableOrders_givenDisabled_returnsEmptyArray() public {
        // Create multiple orders
        vm.startPrank(alice);
        limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        ); // Fillable
        limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            LOWER_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        ); // Price too high
        limitOrders.createOrder(
            PERIOD_6,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            DEFAULT_MIN_FILL_SIZE
        ); // Different period
        vm.stopPrank();

        // Disable
        _disableContract();

        // Get fillable orders
        uint256[] memory fillable = limitOrders.getFillableOrders(PERIOD_3);
        assertEq(fillable.length, 0, "Should return empty array when contract is disabled");
    }

    // ========== ERC721 RECEIVER TEST ========== //

    // [X] it returns correct selector
    function test_onERC721Received() public view {
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
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            SMALL_DEPOSIT_BUDGET,
            SMALL_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(
            orderId,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
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
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(
            orderId,
            SMALL_DEPOSIT_BUDGET,
            SMALL_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
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
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        // Partial fill: spends 3000 deposit + 15 incentive
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 3_000e18);

        // Check order status
        ILimitOrders.LimitOrder memory orderBefore = limitOrders.getOrder(orderId);
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
        limitOrders.changeOrder(
            orderId,
            SMALL_DEPOSIT_BUDGET,
            SMALL_INCENTIVE_BUDGET,
            32e18,
            SMALL_MIN_FILL_SIZE
        );

        // Check order status
        ILimitOrders.LimitOrder memory orderAfter = limitOrders.getOrder(orderId);
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
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        // Partial fill: spends 3000 deposit + 15 incentive
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 3_000e18);

        // Check order status
        ILimitOrders.LimitOrder memory orderBefore = limitOrders.getOrder(orderId);
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
        limitOrders.changeOrder(orderId, 11_000e18, 110e18, 32e18, SMALL_MIN_FILL_SIZE);

        // Check order status
        ILimitOrders.LimitOrder memory orderAfter = limitOrders.getOrder(orderId);
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
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        // Partial fill: spends 3000 deposit + 15 incentive
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 3_000e18);

        // Check order status
        ILimitOrders.LimitOrder memory orderBefore = limitOrders.getOrder(orderId);
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
        ILimitOrders.LimitOrder memory orderAfter = limitOrders.getOrder(orderId);
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
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            100e18,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        ); // 1% rate

        // Fill half
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 5_000e18); // Pays 50 incentive

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        // Remaining: 5000 + 50 = 5050
        // Can now set 0.1% rate - no problem since spent is reset
        vm.prank(alice);
        limitOrders.changeOrder(
            orderId,
            SMALL_DEPOSIT_BUDGET,
            5e18,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
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
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
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
        newMinFillSize_ = bound(newMinFillSize_, MIN_BID, DEFAULT_DEPOSIT_BUDGET);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(
            orderId,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            newMinFillSize_
        );

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, DEFAULT_DEPOSIT_BUDGET, "Deposit budget should be unchanged");
        assertEq(
            order.incentiveBudget,
            DEFAULT_INCENTIVE_BUDGET,
            "Incentive budget should be unchanged"
        );
        assertEq(order.depositSpent, 0, "Deposit spent should be reset to 0");
        assertEq(order.incentiveSpent, 0, "Incentive spent should be reset to 0");
        assertEq(order.maxPrice, DEFAULT_MAX_PRICE, "Max price should be unchanged");
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
            DEFAULT_DEPOSIT_BUDGET + DEFAULT_INCENTIVE_BUDGET,
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
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            SMALL_DEPOSIT_BUDGET,
            SMALL_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        // Completely fill the order
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 5_000e18);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        // Change order
        vm.prank(alice);
        limitOrders.changeOrder(
            orderId,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            32e18,
            499e18
        );

        // Check order status
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
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
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        vm.prank(bob);
        vm.expectRevert(ILimitOrders.NotOrderOwner.selector);
        limitOrders.changeOrder(
            orderId,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            40e18,
            SMALL_MIN_FILL_SIZE
        );
    }

    // when order is not active
    //  [X] it reverts
    function test_changeOrder_revert_orderNotActive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        vm.prank(alice);
        vm.expectRevert(ILimitOrders.OrderNotActive.selector);
        limitOrders.changeOrder(
            orderId,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            40e18,
            SMALL_MIN_FILL_SIZE
        );
    }

    // when newDepositBudget is zero
    //  [X] it reverts
    function test_changeOrder_revert_zeroDeposit() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ILimitOrders.InvalidParam.selector, "depositBudget")
        );
        limitOrders.changeOrder(
            orderId,
            0,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );
    }

    // when newMaxPrice is zero
    //  [X] it reverts
    function test_changeOrder_revert_zeroMaxPrice() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILimitOrders.InvalidParam.selector, "maxPrice"));
        limitOrders.changeOrder(
            orderId,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            0,
            SMALL_MIN_FILL_SIZE
        );
    }

    // when newMinFillSize is zero
    //  [X] it reverts
    function test_changeOrder_revert_zeroMinFill() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILimitOrders.InvalidParam.selector, "minFillSize"));
        limitOrders.changeOrder(
            orderId,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            0
        );
    }

    // when newMinFillSize exceeds newDepositBudget
    //  [X] it reverts
    function test_changeOrder_revert_minFillExceedsDeposit() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILimitOrders.InvalidParam.selector,
                "minFillSize > depositBudget"
            )
        );
        limitOrders.changeOrder(
            orderId,
            1_000e18,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            2_000e18
        );
    }

    // when newMinFillSize is below auctioneer minimum
    //  [X] it reverts
    function test_changeOrder_revert_minFillBelowAuctioneerMin() public {
        cdAuctioneer.setMinimumBid(500e18);

        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILimitOrders.InvalidParam.selector,
                "minFillSize < auctioneer minimum"
            )
        );
        limitOrders.changeOrder(
            orderId,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            100e18
        );
    }

    // when setting incentiveBudget to zero
    //  [X] it decreases budgets
    //  [X] it refunds the additional budget to the user
    //  [X] it reduces the USDS owed by the additional budget
    function test_changeOrder_zeroIncentive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            DEFAULT_DEPOSIT_BUDGET,
            DEFAULT_INCENTIVE_BUDGET,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(
            orderId,
            DEFAULT_DEPOSIT_BUDGET,
            0,
            DEFAULT_MAX_PRICE,
            SMALL_MIN_FILL_SIZE
        );

        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
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
/// forge-lint: disable-end(mixed-case-variable)
