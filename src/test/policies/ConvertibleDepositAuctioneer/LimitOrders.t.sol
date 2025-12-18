// SPDX-License-Identifier: AGPL-3.0
// solhint-disable use-natspec
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
        cdAuctioneer.setMinimumBid(100e18);
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

    // ========== CREATE ORDER TESTS ========== //

    // when all parameters are valid
    //  [X] it creates order successfully
    function test_createOrder_success() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(
            PERIOD_3,
            10_000e18, // depositBudget
            50e18, // incentiveBudget
            35e18, // maxPrice
            1_000e18 // minFillSize
        );

        assertEq(orderId, 0);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.owner, alice);
        assertEq(order.depositPeriod, PERIOD_3);
        assertEq(order.depositBudget, 10_000e18);
        assertEq(order.incentiveBudget, 50e18);
        assertEq(order.depositSpent, 0);
        assertEq(order.incentiveSpent, 0);
        assertEq(order.maxPrice, 35e18);
        assertEq(order.minFillSize, 1_000e18);
        assertTrue(order.active);

        // Check sUSDS balance
        // TODO restore this
        // assertEq(limitOrders.getSUsdsBalance(), 10_050e18);
        assertEq(limitOrders.totalUsdsOwed(), 10_050e18);
    }

    // when there are multiple orders
    //  [X] it creates multiple orders with sequential IDs
    function test_createOrder_multipleOrders() public {
        vm.startPrank(alice);
        uint256 orderId1 = limitOrders.createOrder(PERIOD_3, 5_000e18, 25e18, 35e18, 500e18);
        uint256 orderId2 = limitOrders.createOrder(PERIOD_6, 3_000e18, 15e18, 32e18, 300e18);
        vm.stopPrank();

        assertEq(orderId1, 0);
        assertEq(orderId2, 1);
        assertEq(limitOrders.totalUsdsOwed(), 8_040e18);
    }

    // when multiple users create orders
    //  [X] it tracks orders correctly per user
    function test_createOrder_multipleUsers() public {
        vm.prank(alice);
        uint256 aliceOrder = limitOrders.createOrder(PERIOD_3, 5_000e18, 25e18, 35e18, 500e18);

        vm.prank(bob);
        uint256 bobOrder = limitOrders.createOrder(PERIOD_3, 3_000e18, 15e18, 32e18, 300e18);

        assertEq(aliceOrder, 0);
        assertEq(bobOrder, 1);

        CDAuctioneerLimitOrders.LimitOrder memory aliceOrderData = limitOrders.getOrder(aliceOrder);
        CDAuctioneerLimitOrders.LimitOrder memory bobOrderData = limitOrders.getOrder(bobOrder);

        assertEq(aliceOrderData.owner, alice);
        assertEq(bobOrderData.owner, bob);
    }

    // when the incentive budget is zero
    //  [X] it creates the order successfully
    function test_createOrder_zeroIncentive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 0, 35e18, 1_000e18);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.incentiveBudget, 0);
    }

    // when the recipient cannot receive ERC721 tokens
    //  [ ] it reverts

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

    // when depositPeriod is not enabled
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

    // given the auctioneer deposit period has been disabled
    //  [ ] it reverts

    // given the auctioneer despoit period has been enabled
    //  [ ] it creates an order with the new deposit period

    // TODO fuzz tests

    // ========== FILL ORDER TESTS ========== //

    // when order is active and price is below max
    //  [X] it fills order successfully
    //  [ ] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_success() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        vm.prank(filler);
        limitOrders.fillOrder(orderId, 1_000e18);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, 1_000e18);
        assertEq(order.incentiveSpent, 5e18); // 1000 * 50 / 10000 = 5

        // Check filler received incentive
        assertEq(usds.balanceOf(filler), 5e18);

        // Check alice received NFT
        assertEq(positionNFT.ownerOf(1), alice);

        // Check alice received receipt tokens
        assertEq(receiptToken3.balanceOf(alice), 1_000e18);
    }

    // when order is active and price is below max
    //  [X] it handles multiple fills correctly
    //  [ ] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_multipleFills() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        // First fill
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 2_000e18);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, 2_000e18);
        assertEq(order.incentiveSpent, 10e18);

        // Second fill
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 3_000e18);

        order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, 5_000e18);
        assertEq(order.incentiveSpent, 25e18);

        // Check totals
        assertEq(usds.balanceOf(filler), 25e18);
        assertEq(positionNFT.balanceOf(alice), 2);
    }

    // when the remaining deposit is less than the fill amount
    //  [X] it caps fill to remaining deposit
    //  [ ] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_capToRemainingDeposit() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 5_000e18, 25e18, 35e18, 1_000e18);

        // Try to fill more than remaining
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 10_000e18);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, 5_000e18); // Capped to max
        assertEq(order.incentiveSpent, 25e18); // All incentive paid
    }

    // when there have been previous fills
    //  when the fill amount completes the order
    //   when the remaining deposit is less than the minFillSize
    //    [X] it allows fill below minFillSize if final fill
    //    [ ] it reduces the USDS owed by the amount of deposit and incentive spent
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

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, 2_500e18);
    }

    //   [X] it gives final fill all remaining incentive
    //   [ ] the deposit spent is the total deposit budget
    //   [ ] the incentive spent is the total incentive budget
    //   [ ] the USDS owed is 0
    function test_fillOrder_finalFillGetsAllRemainingIncentive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        // Fill most of the order
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 9_000e18);

        uint256 fillerBalanceBefore = usds.balanceOf(filler);

        // Final fill - should get all remaining incentive (avoids dust)
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 1_000e18);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, 10_000e18);
        assertEq(order.incentiveSpent, 50e18);

        // Final fill got remaining 5e18 incentive
        assertEq(usds.balanceOf(filler) - fillerBalanceBefore, 5e18);
    }

    // when filling order with zero incentive
    //  [X] it fills without paying incentive
    function test_fillOrder_zeroIncentive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 0, 35e18, 1_000e18);

        uint256 fillerBalanceBefore = usds.balanceOf(filler);

        vm.prank(filler);
        limitOrders.fillOrder(orderId, 1_000e18);

        assertEq(usds.balanceOf(filler), fillerBalanceBefore);
    }

    // when minFillSize equals remaining deposit
    //  [X] it allows fill
    //  [ ] the deposit spent is the fill amount
    //  [ ] it reduces the USDS owed by the amount of deposit and incentive spent
    function test_fillOrder_exactMinFillEqualsRemaining() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 1_000e18, 5e18, 35e18, 1_000e18);

        // minFillSize == depositBudget == 1000
        // This should work as it's both the min and final fill
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 1_000e18);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, 1_000e18);
    }

    // when different fillers fill same order
    //  [X] it distributes incentives correctly
    function test_fillOrder_differentFillers() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        address filler2 = makeAddr("filler2");

        vm.prank(filler);
        limitOrders.fillOrder(orderId, 2_000e18);

        vm.prank(filler2);
        limitOrders.fillOrder(orderId, 3_000e18);

        assertEq(usds.balanceOf(filler), 10e18); // 2000 * 50 / 10000
        assertEq(usds.balanceOf(filler2), 15e18); // 3000 * 50 / 10000
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
        assertFalse(order.active);

        // Alice should receive full refund
        assertEq(usds.balanceOf(alice) - aliceBalanceBefore, 10_050e18);
        assertEq(limitOrders.totalUsdsOwed(), 0);
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
        assertEq(usds.balanceOf(alice) - aliceBalanceBefore, expectedRefund);
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

    // ========== YIELD TESTS ========== //

    // when yield has accrued
    //  [X] it sweeps yield successfully
    function test_sweepYield_success() public {
        vm.prank(alice);
        limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        // Simulate yield by increasing exchange rate
        sUsds.setExchangeRate(1.1e18); // 10% yield

        uint256 yield = limitOrders.getAccruedYield();
        assertApproxEqRel(yield, 1_005e18, 0.01e18); // ~10% of 10_050

        uint256 recipientSharesBefore = sUsds.balanceOf(yieldRecipient);

        limitOrders.sweepYield();

        assertGt(sUsds.balanceOf(yieldRecipient), recipientSharesBefore);
    }

    // when yield has accrued
    //  [X] it transfers shares to recipient
    function test_sweepYield_transfersShares() public {
        vm.prank(alice);
        limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        sUsds.setExchangeRate(1.1e18);

        uint256 expectedShares = limitOrders.getAccruedYieldShares();

        uint256 shares = limitOrders.sweepYield();

        assertEq(shares, expectedShares);
        assertEq(sUsds.balanceOf(yieldRecipient), shares);
    }

    // when no yield has accrued
    //  [X] it returns zero shares
    function test_sweepYield_revert_noYield() public {
        vm.prank(alice);
        limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        uint256 shares = limitOrders.sweepYield();
        assertEq(shares, 0);
    }

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
        assertGt(yield, 0);
    }

    // ========== ADMIN TESTS ========== //

    // when caller is owner
    //  [X] it sets yield recipient successfully
    function test_setYieldRecipient_success() public {
        address newRecipient = makeAddr("newRecipient");

        vm.prank(owner);
        limitOrders.setYieldRecipient(newRecipient);

        assertEq(limitOrders.yieldRecipient(), newRecipient);
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

        assertEq(limitOrders.owner(), newOwner);
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

        assertTrue(canFill);
        assertEq(bytes(reason).length, 0);
        assertEq(effectivePrice, 30e18); // Mock price
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

        assertFalse(canFill);
        assertEq(reason, "Price above max");
        assertEq(effectivePrice, 30e18);
    }

    // when order is not active
    //  [X] it returns false with reason
    function test_canFillOrder_orderNotActive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        vm.prank(alice);
        limitOrders.cancelOrder(orderId);

        (bool canFill, string memory reason, ) = limitOrders.canFillOrder(orderId, 1_000e18);

        assertFalse(canFill);
        assertEq(reason, "Order not active");
    }

    // TODO shift canFillOrder tests to fillOrder tests

    // calculateIncentive
    //  [X] it calculates incentive and rate correctly
    function test_calculateIncentive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        (uint256 incentive, uint256 rate) = limitOrders.calculateIncentive(orderId, 2_000e18);
        assertEq(incentive, 10e18); // 2000 * 50 / 10000
        assertEq(rate, 50); // 50 bps = 0.5%
    }

    // TODO shift calculateIncentive tests to fillOrder tests

    // TODO fuzz test

    // getRemaining
    //  [X] it returns correct remaining deposit and incentive
    function test_getRemainingDeposit() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 1_000e18);

        (uint256 deposit, uint256 incentive) = limitOrders.getRemaining(orderId);

        assertEq(deposit, 10_000e18);
        assertEq(incentive, 50e18);

        vm.prank(filler);
        limitOrders.fillOrder(orderId, 2_000e18);

        (deposit, incentive) = limitOrders.getRemaining(orderId);

        assertEq(deposit, 8_000e18);
        assertEq(incentive, 40e18);
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

        assertEq(fillable.length, 1);
        assertEq(fillable[0], 0);
    }

    // ========== ERC721 RECEIVER TEST ========== //

    // [X] it returns correct selector
    function test_onERC721Received() public {
        bytes4 selector = limitOrders.onERC721Received(address(0), address(0), 0, "");
        assertEq(selector, limitOrders.onERC721Received.selector);
    }

    // ========== CHANGE ORDER TESTS ========== //

    // changeOrder
    // when increasing the deposit and incentive budgets
    //  [X] it transfers additional budget from the user
    //  [X] it increases budgets
    //  [ ] it increases the USDS owed by the additional budget
    function test_changeOrder_increaseBudgets() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 5_000e18, 25e18, 35e18, 500e18);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 10_000e18, 50e18, 35e18, 500e18);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, 10_000e18);
        assertEq(order.incentiveBudget, 50e18);
        assertEq(order.depositSpent, 0);
        assertEq(order.incentiveSpent, 0);

        // Alice paid additional 5025
        assertEq(aliceBalanceBefore - usds.balanceOf(alice), 5_025e18);
    }

    // when decreasing the deposit and incentive budgets
    //  [X] it decreases budgets
    //  [ ] it refunds the additional budget to the user
    //  [ ] it reduces the USDS owed by the additional budget
    function test_changeOrder_decreaseBudgets() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 5_000e18, 25e18, 35e18, 500e18);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, 5_000e18);
        assertEq(order.incentiveBudget, 25e18);

        // Alice received 5025 back
        assertEq(usds.balanceOf(alice) - aliceBalanceBefore, 5_025e18);
    }

    // given there has been a partial fill
    //  when decreasing the deposit and incentive budgets
    //   [X] it resets spent amounts
    //   [ ] it refunds the additional budget to the user
    //   [ ] it reduces the USDS owed by the additional budget
    function test_changeOrder_afterPartialFill_resetsSpent() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        // Partial fill: spends 3000 deposit + 15 incentive
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 3_000e18);

        CDAuctioneerLimitOrders.LimitOrder memory orderBefore = limitOrders.getOrder(orderId);
        assertEq(orderBefore.depositSpent, 3_000e18);
        assertEq(orderBefore.incentiveSpent, 15e18);

        // Remaining: 7000 + 35 = 7035
        // New total: 5000 + 25 = 5025
        // User receives: 7035 - 5025 = 2010

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 5_000e18, 25e18, 32e18, 500e18);

        CDAuctioneerLimitOrders.LimitOrder memory orderAfter = limitOrders.getOrder(orderId);
        assertEq(orderAfter.depositBudget, 5_000e18);
        assertEq(orderAfter.incentiveBudget, 25e18);
        assertEq(orderAfter.depositSpent, 0); // Reset!
        assertEq(orderAfter.incentiveSpent, 0); // Reset!
        assertEq(orderAfter.maxPrice, 32e18);

        assertEq(usds.balanceOf(alice) - aliceBalanceBefore, 2_010e18);
    }

    //  when increasing the deposit and incentive budgets
    //   [ ] it transfers additional budget from the user
    //   [ ] it increases budgets
    //   [ ] it increases the USDS owed by the additional budget

    //  [X] it allows changing incentive rate freely
    function test_changeOrder_afterPartialFill_canChangeIncentiveRateFreely() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 100e18, 35e18, 500e18); // 1% rate

        // Fill half
        vm.prank(filler);
        limitOrders.fillOrder(orderId, 5_000e18); // Pays 50 incentive

        // Remaining: 5000 + 50 = 5050
        // Can now set 0.1% rate - no problem since spent is reset
        vm.prank(alice);
        limitOrders.changeOrder(orderId, 5_000e18, 5e18, 35e18, 500e18);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.depositBudget, 5_000e18);
        assertEq(order.incentiveBudget, 5e18);
        assertEq(order.depositSpent, 0);
        assertEq(order.incentiveSpent, 0);

        // User received excess: 5050 - 5005 = 45
    }

    // when the budget is the same
    //  given there has been a partial fill
    //   [ ] it changes the max price
    //   [ ] it changes the min fill size
    //   [ ] it makes no transfer
    //   [ ] it resets the spent amounts
    //  when only the maxPrice is changed
    //   [ ] it changes the max price
    //   [ ] it makes no transfer
    //   [ ] it resets the spent amounts
    //  when only the minFillSize is changed
    //   [ ] it changes the min fill size
    //   [ ] it makes no transfer
    //   [ ] it resets the spent amounts
    function test_changeOrder_sameValues_noTransfer() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        uint256 aliceBalanceBefore = usds.balanceOf(alice);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 10_000e18, 50e18, 35e18, 500e18);

        assertEq(usds.balanceOf(alice), aliceBalanceBefore);
    }

    // when only changing maxPrice
    //  [X] it updates maxPrice only
    function test_changeOrder_onlyMaxPrice() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 10_000e18, 50e18, 40e18, 500e18);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.maxPrice, 40e18);
        // TODO check other values
    }

    // when the order has been completely filled
    //  [ ] it reverts

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
    //  [X] it updates successfully
    function test_changeOrder_zeroIncentive() public {
        vm.prank(alice);
        uint256 orderId = limitOrders.createOrder(PERIOD_3, 10_000e18, 50e18, 35e18, 500e18);

        vm.prank(alice);
        limitOrders.changeOrder(orderId, 10_000e18, 0, 35e18, 500e18);

        CDAuctioneerLimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertEq(order.incentiveBudget, 0);
        // TODO check other values
    }
}
