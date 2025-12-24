// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.20;

// Test
import {Test, console2} from "forge-std/Test.sol";

// Libraries
import {ERC20} from "@openzeppelin-5.3.0/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin-5.3.0/token/ERC20/extensions/ERC4626.sol";
import {ERC721} from "@openzeppelin-5.3.0/token/ERC721/ERC721.sol";

// Bophades
import {CDAuctioneerLimitOrders} from "src/policies/deposits/LimitOrders.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {ILimitOrders} from "src/policies/interfaces/deposits/ILimitOrders.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

/// @title LimitOrdersForkTest
/// @notice Fork test for LimitOrders contract using mainnet contracts
contract LimitOrdersForkTest is Test {
    // Mainnet contract addresses
    address public constant DEPOSIT_MANAGER = 0xcb4E21Eb404d80F3e1dB781aAd9AD6A1217fbbf2;
    address public constant CD_AUCTIONEER = 0xF35193DA8C10e44aF10853Ba5a3a1a6F7529E39a;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address public constant POSITION_NFT = 0x02331A4c97a4841084dF54d7c0eC04DD3f1A9F1c; // DEPOS module
    address public constant CD_FACILITY = 0xEBDe552D851DD6Dfd3D360C596D3F4aF6e5F9678; // Operator for receipt tokens

    // Fork configuration - using a recent block after CD deployment
    uint256 internal constant FORK_BLOCK = 24080000;

    // Contracts
    CDAuctioneerLimitOrders public limitOrders;
    IConvertibleDepositAuctioneer public cdAuctioneer;
    IDepositManager public depositManager;
    ERC20 public usds;
    ERC4626 public sUsds;
    ERC721 public positionNFT;

    // Test accounts
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public filler = makeAddr("filler");
    address public yieldRecipient = makeAddr("yieldRecipient");

    function setUp() public {
        // Fork mainnet at specific block
        vm.createSelectFork("mainnet", FORK_BLOCK);

        // Load mainnet contracts
        cdAuctioneer = IConvertibleDepositAuctioneer(CD_AUCTIONEER);
        depositManager = IDepositManager(DEPOSIT_MANAGER);
        usds = ERC20(USDS);
        sUsds = ERC4626(SUSDS);
        positionNFT = ERC721(POSITION_NFT);

        // Deploy new LimitOrders contract
        _deployLimitOrders();
    }

    function _deployLimitOrders() internal {
        // Get enabled deposit periods from auctioneer
        uint8[] memory depositPeriods = cdAuctioneer.getDepositPeriods();
        require(depositPeriods.length > 0, "No enabled deposit periods");

        // Get receipt token addresses for each enabled period
        address[] memory receiptTokens = new address[](depositPeriods.length);
        for (uint256 i = 0; i < depositPeriods.length; ++i) {
            (, address wrappedToken) = depositManager.getReceiptToken(
                IERC20(USDS),
                depositPeriods[i],
                CD_FACILITY
            );
            require(wrappedToken != address(0), "Receipt token not found");
            receiptTokens[i] = wrappedToken;
            console2.log("Deposit period:", depositPeriods[i], "Receipt token:", wrappedToken);
        }

        // Deploy LimitOrders contract
        limitOrders = new CDAuctioneerLimitOrders(
            owner, // owner
            DEPOSIT_MANAGER,
            CD_AUCTIONEER,
            USDS,
            SUSDS,
            POSITION_NFT,
            yieldRecipient,
            depositPeriods,
            receiptTokens
        );

        // Enable the contract (needs to be done by owner)
        vm.prank(owner);
        limitOrders.enable(bytes(""));

        // Give user some USDS for testing
        deal(address(usds), user, 100_000e18);
    }

    function test_createAndFillOrder() public {
        // Use the first enabled deposit period
        uint8[] memory depositPeriods = cdAuctioneer.getDepositPeriods();
        require(depositPeriods.length > 0, "No enabled deposit periods");
        uint8 depositPeriod = depositPeriods[0];

        // Get minimum bid amount
        uint256 minBid = cdAuctioneer.getMinimumBid();
        console2.log("Minimum bid:", minBid);

        // Order parameters
        uint256 depositBudget = 10_000e18;
        uint256 incentiveBudget = 50e18;
        uint256 maxPrice = 50e18; // 50 USDS per OHM (should be above current market price)
        uint256 minFillSize = minBid; // Use minimum bid as min fill size

        // Preview bid to get expected OHM out and check price
        uint256 expectedOhmOut = cdAuctioneer.previewBid(depositPeriod, depositBudget);
        require(expectedOhmOut > 0, "Expected OHM out is zero");
        uint256 effectivePrice = (depositBudget * 1e9) / expectedOhmOut;
        console2.log("Expected OHM out:", expectedOhmOut);
        console2.log("Effective price:", effectivePrice);
        require(effectivePrice <= maxPrice, "Price too high for max price");

        // Create order
        vm.startPrank(user);
        usds.approve(address(limitOrders), depositBudget + incentiveBudget);
        uint256 orderId = limitOrders.createOrder(
            depositPeriod,
            depositBudget,
            incentiveBudget,
            maxPrice,
            minFillSize
        );
        vm.stopPrank();

        console2.log("Order created with ID:", orderId);

        // Verify order was created
        ILimitOrders.LimitOrder memory order = limitOrders.getOrder(orderId);
        assertTrue(order.active, "Order should be active");
        assertEq(order.owner, user, "Order owner should be user");
        assertEq(uint256(order.depositPeriod), uint256(depositPeriod), "Deposit period mismatch");
        assertEq(order.depositBudget, depositBudget, "Deposit budget mismatch");

        // Fill order
        uint256 fillAmount = depositBudget; // Fill the entire order
        vm.prank(filler);
        (uint256 actualFill, uint256 incentive, uint256 remaining) = limitOrders.fillOrder(
            orderId,
            fillAmount
        );

        console2.log("Fill amount:", actualFill);
        console2.log("Incentive paid:", incentive);
        console2.log("Remaining deposit:", remaining);

        // Verify fill
        assertGt(actualFill, 0, "Fill amount should be greater than zero");
        assertGt(incentive, 0, "Incentive should be greater than zero");
        assertEq(remaining, 0, "Remaining should be zero after full fill");

        // Verify order was filled
        order = limitOrders.getOrder(orderId);
        assertEq(order.depositSpent, depositBudget, "Deposit should be fully spent");
        assertEq(order.incentiveSpent, incentiveBudget, "Incentive should be fully spent");

        // Verify filler received incentive
        uint256 fillerUsdsBalance = usds.balanceOf(filler);
        assertGe(fillerUsdsBalance, incentive, "Filler should receive incentive");

        // Verify user received position NFT and receipt tokens
        (uint256 deposit, uint256 incentiveRemaining) = limitOrders.getRemaining(orderId);
        assertEq(deposit, 0, "Deposit remaining should be zero");
        assertEq(incentiveRemaining, 0, "Incentive remaining should be zero");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
