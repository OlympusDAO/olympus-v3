// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

interface ICDAuctioneer {
    struct Tick {
        uint256 price;
        uint256 capacity;
        uint48 lastUpdate;
    }

    function previewBid(
        uint8 depositPeriod,
        uint256 bidAmount
    ) external view returns (uint256 ohmOut);

    function bid(
        uint8 depositPeriod,
        uint256 depositAmount,
        uint256 minOhmOut,
        bool wrapPosition,
        bool wrapReceipt
    ) external returns (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId, uint256 actualAmount);

    function getCurrentTick(uint8 depositPeriod) external view returns (Tick memory);

    function isDepositPeriodEnabled(uint8 depositPeriod) external view returns (bool isEnabled, bool isPendingEnabled);

    function getMinimumBid() external view returns (uint256);
}

/// @title  CDAuctioneer Limit Orders
/// @notice Enables limit order functionality for the Convertible Deposit Auctioneer
/// @dev    Users create orders specifying max price, MEV bots fill when price is favorable.
///         User deposits are held in sUSDS to generate yield, which accrues to a configurable recipient.
contract CDAuctioneerLimitOrders is ReentrancyGuardTransient, Ownable {
    using SafeERC20 for ERC20;

    // ========== ERRORS ========== //

    error InvalidParam(string param);
    error OrderNotActive();
    error OrderFullySpent();
    error FillBelowMinimum();
    error PriceAboveMax();
    error NotOrderOwner();
    error DepositPeriodNotEnabled();
    error ReceiptTokenNotConfigured();
    error NoYieldToSweep();
    error ArrayLengthMismatch();
    error ZeroOhmOut();

    // ========== EVENTS ========== //

    event OrderCreated(
        uint256 indexed orderId,
        address indexed owner,
        uint8 depositPeriod,
        uint256 depositBudget,
        uint256 incentiveBudget,
        uint256 maxPrice,
        uint256 minFillSize
    );

    event OrderFilled(
        uint256 indexed orderId,
        address indexed filler,
        uint256 fillAmount,
        uint256 incentivePaid,
        uint256 ohmOut,
        uint256 positionId
    );

    event OrderCancelled(uint256 indexed orderId, uint256 usdsReturned);

    event YieldSwept(address indexed recipient, uint256 sUsdsAmount);

    event YieldRecipientUpdated(address indexed newRecipient);

    // ========== CONSTANTS ========== //

    uint256 internal constant OHM_SCALE = 1e9;

    // ========== IMMUTABLES ========== //

    ICDAuctioneer public immutable CD_AUCTIONEER;
    ERC20 public immutable USDS;
    ERC4626 public immutable SUSDS;
    ERC721 public immutable POSITION_NFT;

    // ========== STATE ========== //

    /// @notice Recipient of accrued yield
    address public yieldRecipient;

    /// @notice Receipt token address for each deposit period
    mapping(uint8 depositPeriod => ERC20 receiptToken) public receiptTokens;

    /// @notice Limit orders by ID
    mapping(uint256 orderId => LimitOrder order) public orders;

    /// @notice Next order ID to be assigned
    uint256 public nextOrderId;

    /// @notice Total USDS owed to all order owners (principal tracking)
    uint256 public totalUsdsOwed;

    // ========== STRUCTS ========== //

    struct LimitOrder {
        address owner;
        uint8 depositPeriod;
        uint256 depositBudget;
        uint256 incentiveBudget;
        uint256 depositSpent;
        uint256 incentiveSpent;
        uint256 maxPrice;
        uint256 minFillSize;
        bool active;
    }

    // ========== CONSTRUCTOR ========== //

    constructor(
        address owner_,
        address cdAuctioneer_,
        address usds_,
        address sUsds_,
        address positionNft_,
        address yieldRecipient_,
        uint8[] memory depositPeriods_,
        address[] memory receiptTokens_
    ) Ownable(owner_) {
        if (cdAuctioneer_ == address(0)) revert InvalidParam("cdAuctioneer");
        if (usds_ == address(0)) revert InvalidParam("usds");
        if (sUsds_ == address(0)) revert InvalidParam("sUsds");
        if (positionNft_ == address(0)) revert InvalidParam("positionNft");
        if (yieldRecipient_ == address(0)) revert InvalidParam("yieldRecipient");
        if (depositPeriods_.length != receiptTokens_.length) revert ArrayLengthMismatch();

        CD_AUCTIONEER = ICDAuctioneer(cdAuctioneer_);
        USDS = ERC20(usds_);
        SUSDS = ERC4626(sUsds_);
        POSITION_NFT = ERC721(positionNft_);
        yieldRecipient = yieldRecipient_;

        for (uint256 i = 0; i < depositPeriods_.length; i++) {
            if (receiptTokens_[i] == address(0)) revert InvalidParam("receiptToken");
            receiptTokens[depositPeriods_[i]] = ERC20(receiptTokens_[i]);
        }

        USDS.approve(address(SUSDS), type(uint256).max);
    }

    // ========== ADMIN ========== //

    /// @notice Update the yield recipient address
    /// @param  newRecipient_ The new yield recipient
    function setYieldRecipient(address newRecipient_) external onlyOwner {
        if (newRecipient_ == address(0)) revert InvalidParam("yieldRecipient");
        yieldRecipient = newRecipient_;
        emit YieldRecipientUpdated(newRecipient_);
    }

    // ========== ORDER MANAGEMENT ========== //

    /// @notice Create a new limit order
    /// @param  depositPeriod_   The deposit period for the CD position
    /// @param  depositBudget_   USDS budget for bids
    /// @param  incentiveBudget_ USDS budget for filler incentives (paid proportionally)
    /// @param  maxPrice_        Maximum execution price (USDS per OHM)
    /// @param  minFillSize_     Minimum USDS per fill (except final fill)
    /// @return orderId          The ID of the created order
    function createOrder(
        uint8 depositPeriod_,
        uint256 depositBudget_,
        uint256 incentiveBudget_,
        uint256 maxPrice_,
        uint256 minFillSize_
    ) external nonReentrant returns (uint256 orderId) {
        if (depositBudget_ == 0) revert InvalidParam("depositBudget");
        if (maxPrice_ == 0) revert InvalidParam("maxPrice");
        if (minFillSize_ == 0) revert InvalidParam("minFillSize");
        if (minFillSize_ > depositBudget_) revert InvalidParam("minFillSize > depositBudget");

        if (address(receiptTokens[depositPeriod_]) == address(0)) {
            revert ReceiptTokenNotConfigured();
        }

        (bool isEnabled, ) = CD_AUCTIONEER.isDepositPeriodEnabled(depositPeriod_);
        if (!isEnabled) revert DepositPeriodNotEnabled();

        uint256 auctioneerMinBid = CD_AUCTIONEER.getMinimumBid();
        if (minFillSize_ < auctioneerMinBid) revert InvalidParam("minFillSize < auctioneer minimum");

        uint256 totalDeposit = depositBudget_ + incentiveBudget_;
        USDS.safeTransferFrom(msg.sender, address(this), totalDeposit);
        SUSDS.deposit(totalDeposit, address(this));
        totalUsdsOwed += totalDeposit;

        orderId = nextOrderId++;

        orders[orderId] = LimitOrder({
            owner: msg.sender,
            depositPeriod: depositPeriod_,
            depositBudget: depositBudget_,
            incentiveBudget: incentiveBudget_,
            depositSpent: 0,
            incentiveSpent: 0,
            maxPrice: maxPrice_,
            minFillSize: minFillSize_,
            active: true
        });

        emit OrderCreated(
            orderId,
            msg.sender,
            depositPeriod_,
            depositBudget_,
            incentiveBudget_,
            maxPrice_,
            minFillSize_
        );

        return orderId;
    }

    /// @notice Fill a limit order (called by MEV bots)
    /// @param  orderId_    The ID of the order to fill
    /// @param  fillAmount_ The amount of USDS to use for the bid
    function fillOrder(uint256 orderId_, uint256 fillAmount_) external nonReentrant {
        LimitOrder storage order = orders[orderId_];

        if (!order.active) revert OrderNotActive();

        uint256 remainingDeposit = order.depositBudget - order.depositSpent;
        if (remainingDeposit == 0) revert OrderFullySpent();

        // Cap fill to remaining deposit budget
        if (fillAmount_ > remainingDeposit) {
            fillAmount_ = remainingDeposit;
        }

        // Check min fill (unless this is the final fill)
        if (remainingDeposit > order.minFillSize && fillAmount_ < order.minFillSize) {
            revert FillBelowMinimum();
        }

        // Calculate proportional incentive
        // Final fill gets all remaining incentive (avoids rounding dust)
        uint256 remainingIncentive = order.incentiveBudget - order.incentiveSpent;
        uint256 incentive;
        if (fillAmount_ == remainingDeposit) {
            incentive = remainingIncentive;
        } else {
            incentive = (fillAmount_ * order.incentiveBudget) / order.depositBudget;
        }

        // Check execution price via previewBid
        uint256 expectedOhmOut = CD_AUCTIONEER.previewBid(order.depositPeriod, fillAmount_);
        if (expectedOhmOut == 0) revert ZeroOhmOut();

        uint256 effectivePrice = (fillAmount_ * OHM_SCALE) / expectedOhmOut;
        if (effectivePrice > order.maxPrice) revert PriceAboveMax();

        // Withdraw USDS from sUSDS
        uint256 usdsNeeded = fillAmount_ + incentive;
        SUSDS.withdraw(usdsNeeded, address(this), address(this));

        // Update accounting
        order.depositSpent += fillAmount_;
        order.incentiveSpent += incentive;
        totalUsdsOwed -= usdsNeeded;

        // Approve and execute bid
        USDS.approve(address(CD_AUCTIONEER), fillAmount_);

        (uint256 ohmOut, uint256 positionId, , ) = CD_AUCTIONEER.bid(
            order.depositPeriod,
            fillAmount_,
            expectedOhmOut,
            true,
            true
        );

        // Transfer position NFT to order owner
        POSITION_NFT.transferFrom(address(this), order.owner, positionId);

        // Transfer receipt tokens to order owner
        ERC20 receiptToken = receiptTokens[order.depositPeriod];
        uint256 receiptBalance = receiptToken.balanceOf(address(this));
        if (receiptBalance > 0) {
            receiptToken.safeTransfer(order.owner, receiptBalance);
        }

        // Transfer incentive to filler
        if (incentive > 0) {
            USDS.safeTransfer(msg.sender, incentive);
        }

        emit OrderFilled(
            orderId_, 
            msg.sender, 
            fillAmount_, 
            incentive, 
            ohmOut, 
            positionId
        );
    }

    /// @notice Cancel an active order and return remaining funds
    /// @param  orderId_ The ID of the order to cancel
    function cancelOrder(uint256 orderId_) external nonReentrant {
        LimitOrder storage order = orders[orderId_];

        if (order.owner != msg.sender) revert NotOrderOwner();
        if (!order.active) revert OrderNotActive();

        uint256 remainingDeposit = order.depositBudget - order.depositSpent;
        uint256 remainingIncentive = order.incentiveBudget - order.incentiveSpent;
        uint256 totalRemaining = remainingDeposit + remainingIncentive;

        order.active = false;
        totalUsdsOwed -= totalRemaining;

        if (totalRemaining > 0) {
            SUSDS.withdraw(totalRemaining, order.owner, address(this));
        }

        emit OrderCancelled(orderId_, totalRemaining);
    }

    // ========== YIELD FUNCTIONS ========== //

    /// @notice Calculate current accrued yield in USDS terms
    function getAccruedYield() public view returns (uint256) {
        return SUSDS.convertToAssets(getAccruedYieldShares());
    }

    /// @notice Calculate accrued yield in sUSDS shares
    /// @dev    Uses previewWithdraw to safely account for rounding
    function getAccruedYieldShares() public view returns (uint256) {
        uint256 sUsdsBalance = SUSDS.balanceOf(address(this));

        // previewWithdraw rounds UP, giving us the max shares needed to cover obligations
        uint256 sharesRequired = SUSDS.previewWithdraw(totalUsdsOwed);

        if (sUsdsBalance <= sharesRequired) return 0;

        return sUsdsBalance - sharesRequired;
    }

    /// @notice Sweep all accrued yield to the yield recipient as sUSDS
    /// @return shares The amount of sUSDS swept
    function sweepYield() external nonReentrant returns (uint256 shares) {
        shares = getAccruedYieldShares();
        if (shares == 0) revert NoYieldToSweep();

        ERC20(address(SUSDS)).safeTransfer(yieldRecipient, shares);

        emit YieldSwept(yieldRecipient, shares);

        return shares;
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Calculate incentive and incentive rate for a given fill amount
    function calculateIncentive(
        uint256 orderId_,
        uint256 fillAmount_
    ) external view returns (uint256 incentive, uint256 incentiveRate) {
        LimitOrder memory order = orders[orderId_];
        if (order.depositBudget == 0) return (0, 0);
        incentive = (fillAmount_ * order.incentiveBudget) / order.depositBudget;
        incentiveRate = (order.incentiveBudget * 10_000) / order.depositBudget;
    }

    /// @notice Check if an order can be filled at a given size
    function canFillOrder(
        uint256 orderId_,
        uint256 fillAmount_
    ) external view returns (bool canFill, string memory reason, uint256 effectivePrice) {
        LimitOrder memory order = orders[orderId_];

        if (!order.active) return (false, "Order not active", 0);

        uint256 remainingDeposit = order.depositBudget - order.depositSpent;
        if (remainingDeposit == 0) return (false, "Order fully spent", 0);

        uint256 actualFill = fillAmount_ > remainingDeposit ? remainingDeposit : fillAmount_;

        if (remainingDeposit > order.minFillSize && actualFill < order.minFillSize) {
            return (false, "Fill below minimum", 0);
        }

        uint256 expectedOhmOut = CD_AUCTIONEER.previewBid(order.depositPeriod, actualFill);
        if (expectedOhmOut == 0) return (false, "Zero OHM output", 0);

        effectivePrice = (actualFill * OHM_SCALE) / expectedOhmOut;
        if (effectivePrice > order.maxPrice) {
            return (false, "Price above max", effectivePrice);
        }

        return (true, "", effectivePrice);
    }

    /// @notice Get remaining deposit and incentive budgets for order
    function getRemaining(uint256 orderId_) external view returns (uint256 deposit, uint256 incentive) {
        LimitOrder memory order = orders[orderId_];
        deposit = order.depositBudget - order.depositSpent;
        incentive = order.incentiveBudget - order.incentiveSpent;
    }

    /// @notice Get current execution price for a fill amount
    function getExecutionPrice(
        uint8 depositPeriod_,
        uint256 fillAmount_
    ) external view returns (uint256) {
        uint256 ohmOut = CD_AUCTIONEER.previewBid(depositPeriod_, fillAmount_);
        if (ohmOut == 0) return 0;
        return (fillAmount_ * OHM_SCALE) / ohmOut;
    }

    /// @notice Find fillable orders for a deposit period
    /// @dev    WARNING: Gas-intensive. Intended for off-chain use only.
    function getFillableOrders(uint8 depositPeriod_) external view returns (uint256[] memory) {
        return _getFillableOrders(depositPeriod_, 0, nextOrderId);
    }

    /// @notice Find fillable orders for a deposit period between given order IDs
    /// @dev    For use if getFillableOrders(uint8 depositPeriod_) exceeds limit
    /// @dev    WARNING: Gas-intensive. Intended for off-chain use only.
    function getFillableOrders(uint8 depositPeriod_, uint256 index0, uint256 index1) external view returns (uint256[] memory) {
        return _getFillableOrders(depositPeriod_, index0, index1);
    }

    function _getFillableOrders(uint8 depositPeriod_, uint256 index0, uint256 index1) internal view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = index0; i < index1; i++) {
            if (_isOrderFillable(i, depositPeriod_)) {
                count++;
            }
        }

        uint256[] memory fillable = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = index0; i < index1; i++) {
            if (_isOrderFillable(i, depositPeriod_)) {
                fillable[index++] = i;
            }
        }

        return fillable;
    }

    function _isOrderFillable(
        uint256 orderId_,
        uint8 depositPeriod_
    ) internal view returns (bool) {
        LimitOrder memory order = orders[orderId_];

        if (!order.active) return false;
        if (order.depositPeriod != depositPeriod_) return false;
        
        uint256 remainingDeposit = order.depositBudget - order.depositSpent;
        if (remainingDeposit == 0) return false;

        uint256 checkAmount = remainingDeposit > order.minFillSize 
            ? order.minFillSize 
            : remainingDeposit;

        uint256 expectedOhmOut = CD_AUCTIONEER.previewBid(depositPeriod_, checkAmount);
        if (expectedOhmOut == 0) return false;

        uint256 effectivePrice = (checkAmount * OHM_SCALE) / expectedOhmOut;
        if (effectivePrice > order.maxPrice) return false;

        return true;
    }

    // ========== ERC721 RECEIVER ========== //

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}