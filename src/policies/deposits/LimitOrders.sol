// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IConvertibleDepositAuctioneer} from "../interfaces/deposits/IConvertibleDepositAuctioneer.sol";

// Libraries
import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin-5.3.0/access/Ownable.sol";
import {ERC20} from "@openzeppelin-5.3.0/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin-5.3.0/token/ERC721/ERC721.sol";
import {ERC4626} from "@openzeppelin-5.3.0/token/ERC20/extensions/ERC4626.sol";
import {ERC721Utils} from "@openzeppelin-5.3.0/token/ERC721/utils/ERC721Utils.sol";
import {PeripheryEnabler} from "src/periphery/PeripheryEnabler.sol";

/// @title  CDAuctioneer Limit Orders
/// @notice Enables limit order functionality for the Convertible Deposit Auctioneer
/// @dev    Users create orders specifying max price, MEV bots fill when price is favorable.
///         User deposits are held in sUSDS to generate yield, which accrues to a configurable recipient.
contract CDAuctioneerLimitOrders is ReentrancyGuardTransient, Ownable, PeripheryEnabler {
    using SafeERC20 for ERC20;

    // ========== ERRORS ========== //

    /// @notice Used when a function parameter is invalid
    error InvalidParam(string param);

    /// @notice Used when an order is not active
    error OrderNotActive();

    /// @notice Used when an order is fully spent
    error OrderFullySpent();

    /// @notice Used when a fill amount is below the minimum fill size
    error FillBelowMinimum();

    /// @notice Used when a fill amount is above the maximum price
    error PriceAboveMax();

    /// @notice Used when the caller is not the order owner
    error NotOrderOwner();

    /// @notice Used when a deposit period is not enabled
    error DepositPeriodNotEnabled();

    /// @notice Used when a receipt token is not configured
    error ReceiptTokenNotConfigured();

    /// @notice Used when an array length mismatch is detected
    error ArrayLengthMismatch();

    /// @notice Used when the previewBid function returns zero OHM output
    error ZeroOhmOut();

    // ========== EVENTS ========== //

    /// @notice Emitted when a new order is created
    ///
    /// @param  orderId         The ID of the created order
    /// @param  owner           The owner of the order
    /// @param  depositPeriod   The deposit period for the CD position
    /// @param  depositBudget   The USDS budget for bids
    /// @param  incentiveBudget The USDS budget for filler incentives (paid proportionally)
    /// @param  maxPrice        The maximum execution price (USDS per OHM)
    /// @param  minFillSize     The minimum USDS per fill (except final fill)
    event OrderCreated(
        uint256 indexed orderId,
        address indexed owner,
        uint8 depositPeriod,
        uint256 depositBudget,
        uint256 incentiveBudget,
        uint256 maxPrice,
        uint256 minFillSize
    );

    /// @notice Emitted when an order is filled
    ///
    /// @param  orderId         The ID of the filled order
    /// @param  filler          The address of the filler
    /// @param  fillAmount      The amount of USDS used for the bid
    /// @param  incentivePaid   The amount of USDS paid as incentive
    /// @param  ohmOut          The amount of OHM output
    /// @param  positionId      The ID of the filled position
    event OrderFilled(
        uint256 indexed orderId,
        address indexed filler,
        uint256 fillAmount,
        uint256 incentivePaid,
        uint256 ohmOut,
        uint256 positionId
    );

    /// @notice Emitted when an order is changed
    ///
    /// @param  orderId         The ID of the changed order
    /// @param  depositBudget   The new USDS budget for bids
    /// @param  incentiveBudget The new USDS budget for filler incentives (paid proportionally)
    /// @param  maxPrice        The new maximum execution price (USDS per OHM)
    /// @param  minFillSize     The new minimum USDS per fill (except final fill)
    event OrderChanged(
        uint256 indexed orderId,
        uint256 depositBudget,
        uint256 incentiveBudget,
        uint256 maxPrice,
        uint256 minFillSize
    );

    /// @notice Emitted when an order is cancelled
    ///
    /// @param  orderId         The ID of the cancelled order
    /// @param  usdsReturned    The amount of USDS returned to the order owner
    event OrderCancelled(uint256 indexed orderId, uint256 usdsReturned);

    /// @notice Emitted when yield is swept
    ///
    /// @param  recipient       The address of the recipient
    /// @param  sUsdsAmount     The amount of sUSDS swept
    event YieldSwept(address indexed recipient, uint256 sUsdsAmount);

    /// @notice Emitted when the yield recipient is updated
    ///
    /// @param  newRecipient    The new address of the recipient
    event YieldRecipientUpdated(address indexed newRecipient);

    // ========== CONSTANTS ========== //

    uint256 internal constant OHM_SCALE = 1e9;

    // ========== IMMUTABLES ========== //

    /// @notice The Convertible Deposit Auctioneer contract
    /// @dev    This variable is immutable
    IConvertibleDepositAuctioneer public immutable CD_AUCTIONEER;

    /// @notice The USDS contract
    /// @dev    This variable is immutable
    ERC20 public immutable USDS;

    /// @notice The sUSDS contract
    /// @dev    This variable is immutable
    ERC4626 public immutable SUSDS;

    /// @notice The Position NFT contract
    /// @dev    This variable is immutable
    ERC721 public immutable POSITION_NFT;

    // ========== STATE ========== //

    /// @notice Recipient of accrued yield
    address public yieldRecipient;

    /// @notice Receipt token address for each deposit period
    mapping(uint8 depositPeriod => ERC20 receiptToken) public receiptTokens;

    /// @notice Limit orders by ID
    mapping(uint256 orderId => LimitOrder order) public orders;

    /// @notice Limit order IDs by user
    mapping(address => uint256[]) public ordersForUser;

    /// @notice Next order ID to be assigned
    uint256 public nextOrderId;

    /// @notice Total USDS owed to all order owners (principal tracking)
    uint256 public totalUsdsOwed;

    // ========== STRUCTS ========== //

    /// @notice Limit order struct
    /// @dev    This struct is used to store limit order information
    ///
    /// @param  owner           The owner of the order
    /// @param  depositPeriod   The deposit period for the CD position
    /// @param  active          Whether the order is active
    /// @param  depositBudget   The USDS budget for bids
    /// @param  incentiveBudget The USDS budget for filler incentives (paid proportionally)
    /// @param  depositSpent    The amount of USDS spent on the deposit
    /// @param  incentiveSpent  The amount of USDS spent on the incentive
    /// @param  maxPrice        The maximum execution price (USDS per OHM)
    /// @param  minFillSize     The minimum USDS per fill (except final fill)
    struct LimitOrder {
        address owner;
        uint8 depositPeriod;
        bool active;
        uint256 depositBudget;
        uint256 incentiveBudget;
        uint256 depositSpent;
        uint256 incentiveSpent;
        uint256 maxPrice;
        uint256 minFillSize;
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

        CD_AUCTIONEER = IConvertibleDepositAuctioneer(cdAuctioneer_);
        USDS = ERC20(usds_);
        SUSDS = ERC4626(sUsds_);
        POSITION_NFT = ERC721(positionNft_);
        yieldRecipient = yieldRecipient_;

        for (uint256 i = 0; i < depositPeriods_.length; i++) {
            if (receiptTokens_[i] == address(0)) revert InvalidParam("receiptToken");
            receiptTokens[depositPeriods_[i]] = ERC20(receiptTokens_[i]);
        }

        USDS.approve(address(SUSDS), type(uint256).max);

        // Disabled by default
    }

    // ========== ADMIN ========== //

    /// @notice Update the yield recipient address
    ///
    /// @param  newRecipient_   The new yield recipient
    function setYieldRecipient(address newRecipient_) external onlyOwner onlyEnabled {
        if (newRecipient_ == address(0)) revert InvalidParam("yieldRecipient");
        yieldRecipient = newRecipient_;
        emit YieldRecipientUpdated(newRecipient_);
    }

    // ========== ORDER MANAGEMENT ========== //

    /// @notice Create a new limit order
    /// @dev    This function will revert if:
    ///         - The contract is not enabled
    ///         - The deposit budget, max price, or min fill size is invalid
    ///         - The receipt token is not configured in this contract
    ///         - The deposit period is not enabled in the auctioneer
    ///         - The caller cannot receive ERC721 tokens
    ///         - The min fill size is below the auctioneer minimum bid
    ///
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
    ) external nonReentrant onlyEnabled returns (uint256 orderId) {
        if (depositBudget_ == 0) revert InvalidParam("depositBudget");
        if (maxPrice_ == 0) revert InvalidParam("maxPrice");
        if (minFillSize_ == 0) revert InvalidParam("minFillSize");
        if (minFillSize_ > depositBudget_) revert InvalidParam("minFillSize > depositBudget");

        if (address(receiptTokens[depositPeriod_]) == address(0)) {
            revert ReceiptTokenNotConfigured();
        }

        (bool isEnabled, ) = CD_AUCTIONEER.isDepositPeriodEnabled(depositPeriod_);
        if (!isEnabled) revert DepositPeriodNotEnabled();

        // Verify that the caller/owner can receive ERC721 tokens
        ERC721Utils.checkOnERC721Received(msg.sender, address(this), msg.sender, 0, "");

        uint256 auctioneerMinBid = CD_AUCTIONEER.getMinimumBid();
        if (minFillSize_ < auctioneerMinBid)
            revert InvalidParam("minFillSize < auctioneer minimum");

        uint256 totalDeposit = depositBudget_ + incentiveBudget_;
        USDS.safeTransferFrom(msg.sender, address(this), totalDeposit);
        SUSDS.deposit(totalDeposit, address(this));
        totalUsdsOwed += totalDeposit;

        orderId = nextOrderId++;

        ordersForUser[msg.sender].push(orderId);

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

    /// @notice Modify an existing limit order (resets spent amounts)
    /// @dev    Functionally equivalent to cancel + create but preserves order ID
    ///
    ///         This function will revert if:
    ///         - The contract is not enabled
    ///         - The caller is not the order owner
    ///         - The order is not active
    ///         - The new deposit budget, max price, or min fill size is invalid
    ///         - The new min fill size is below the auctioneer minimum bid
    ///
    /// @param  orderId_            The ID of the order to modify
    /// @param  newDepositBudget_   New deposit budget
    /// @param  newIncentiveBudget_ New incentive budget
    /// @param  newMaxPrice_        New max price
    /// @param  newMinFillSize_     New min fill size
    function changeOrder(
        uint256 orderId_,
        uint256 newDepositBudget_,
        uint256 newIncentiveBudget_,
        uint256 newMaxPrice_,
        uint256 newMinFillSize_
    ) external nonReentrant onlyEnabled {
        LimitOrder storage order = orders[orderId_];

        if (order.owner != msg.sender) revert NotOrderOwner();
        if (!order.active) revert OrderNotActive();

        // Validate new params (same as createOrder)
        if (newDepositBudget_ == 0) revert InvalidParam("depositBudget");
        if (newMaxPrice_ == 0) revert InvalidParam("maxPrice");
        if (newMinFillSize_ == 0) revert InvalidParam("minFillSize");
        if (newMinFillSize_ > newDepositBudget_) revert InvalidParam("minFillSize > depositBudget");
        if (newMinFillSize_ < CD_AUCTIONEER.getMinimumBid())
            revert InvalidParam("minFillSize < auctioneer minimum");

        // Calculate old remaining (what's left to work with)
        uint256 oldRemaining = (order.depositBudget - order.depositSpent) +
            (order.incentiveBudget - order.incentiveSpent);

        uint256 newTotal = newDepositBudget_ + newIncentiveBudget_;

        if (newTotal > oldRemaining) {
            // Need more funds from user
            uint256 increase = newTotal - oldRemaining;
            totalUsdsOwed += increase;
            USDS.safeTransferFrom(msg.sender, address(this), increase);
            SUSDS.deposit(increase, address(this));
        } else if (newTotal < oldRemaining) {
            // Return excess to user
            uint256 decrease = oldRemaining - newTotal;
            totalUsdsOwed -= decrease;
            SUSDS.withdraw(decrease, msg.sender, address(this));
        }

        // Reset order with fresh values
        order.depositBudget = newDepositBudget_;
        order.incentiveBudget = newIncentiveBudget_;
        order.depositSpent = 0;
        order.incentiveSpent = 0;
        order.maxPrice = newMaxPrice_;
        order.minFillSize = newMinFillSize_;

        emit OrderChanged(
            orderId_,
            newDepositBudget_,
            newIncentiveBudget_,
            newMaxPrice_,
            newMinFillSize_
        );
    }

    /// @notice Calculate capped fill amount and incentive for an order
    ///
    /// @param  order_           The limit order
    /// @param  fillAmount_      The requested fill amount
    /// @return cappedFill       The fill amount capped to remaining deposit
    /// @return incentive        The incentive amount (with final fill handling)
    /// @return remainingDeposit The remaining deposit budget
    function _calculateFillAndIncentive(
        LimitOrder memory order_,
        uint256 fillAmount_
    ) internal pure returns (uint256 cappedFill, uint256 incentive, uint256 remainingDeposit) {
        remainingDeposit = order_.depositBudget - order_.depositSpent;

        // Cap fill to remaining deposit budget
        cappedFill = fillAmount_ > remainingDeposit ? remainingDeposit : fillAmount_;

        // Calculate proportional incentive
        // Final fill gets all remaining incentive (avoids rounding dust)
        uint256 remainingIncentive = order_.incentiveBudget - order_.incentiveSpent;
        if (cappedFill == remainingDeposit) {
            incentive = remainingIncentive;
        } else {
            incentive = (cappedFill * order_.incentiveBudget) / order_.depositBudget;
        }
    }

    /// @notice Fill a limit order
    /// @dev    This function will revert if:
    ///         - The contract is not enabled
    ///         - The order is not active
    ///         - The order budget has been fully spent
    ///         - The fill amount is below the minimum fill size (unless this is the final fill)
    ///         - The execution price is above the maximum price
    ///         - The previewBid function returns zero OHM output
    ///
    /// @param  orderId_    The ID of the order to fill
    /// @param  fillAmount_ The amount of USDS to use for the bid
    /// @return uint256     The actual fill amount (may be capped to remaining deposit)
    /// @return uint256     The incentive amount paid to the filler
    /// @return uint256     The remaining deposit budget after the fill
    function fillOrder(
        uint256 orderId_,
        uint256 fillAmount_
    ) external nonReentrant onlyEnabled returns (uint256, uint256, uint256) {
        LimitOrder storage order = orders[orderId_];

        if (!order.active) revert OrderNotActive();

        uint256 remainingDepositBefore;
        uint256 incentive;
        (fillAmount_, incentive, remainingDepositBefore) = _calculateFillAndIncentive(
            order,
            fillAmount_
        );

        if (remainingDepositBefore == 0) revert OrderFullySpent();

        // Check min fill (unless this is the final fill)
        if (remainingDepositBefore > order.minFillSize && fillAmount_ < order.minFillSize) {
            revert FillBelowMinimum();
        }

        // Check execution price via previewBid
        uint256 expectedOhmOut = CD_AUCTIONEER.previewBid(order.depositPeriod, fillAmount_);
        if (expectedOhmOut == 0) revert ZeroOhmOut();
        if ((fillAmount_ * OHM_SCALE) / expectedOhmOut > order.maxPrice) revert PriceAboveMax();

        // Withdraw USDS from sUSDS and update accounting
        uint256 usdsNeeded = fillAmount_ + incentive;
        SUSDS.withdraw(usdsNeeded, address(this), address(this));
        order.depositSpent += fillAmount_;
        order.incentiveSpent += incentive;
        totalUsdsOwed -= usdsNeeded;

        // Approve and execute bid
        // The fill amount is the amount of USDS that will be used for the bid, and so is used for incentive and subsequent calculations.
        // The actual amount is the quantity of receipt tokens that will be received.
        USDS.approve(address(CD_AUCTIONEER), fillAmount_);
        (uint256 ohmOut, uint256 positionId, , uint256 actualAmount) = CD_AUCTIONEER.bid(
            order.depositPeriod,
            fillAmount_,
            expectedOhmOut,
            true,
            true
        );

        // Transfer position NFT and receipt tokens to order owner
        POSITION_NFT.transferFrom(address(this), order.owner, positionId);
        if (actualAmount > 0) {
            receiptTokens[order.depositPeriod].safeTransfer(order.owner, actualAmount);
        }

        // Transfer incentive to filler
        if (incentive > 0) USDS.safeTransfer(msg.sender, incentive);
        // Transfer any remaining USDS to sUSDS (but only if it would be >= 1 share)
        uint256 remainingBalance = USDS.balanceOf(address(this));
        if (remainingBalance > 0 && SUSDS.previewDeposit(remainingBalance) > 0)
            SUSDS.deposit(remainingBalance, address(this));

        emit OrderFilled(orderId_, msg.sender, fillAmount_, incentive, ohmOut, positionId);

        // Calculate remaining deposit after fill and return
        return (fillAmount_, incentive, remainingDepositBefore - fillAmount_);
    }

    /// @notice Cancel an active order and return remaining funds
    /// @dev    This function will revert if:
    ///         - The caller is not the order owner
    ///         - The order is not active
    ///         - The order is fully spent
    ///
    ///         Note that if the contract is disabled, this function will still operate in order to allow users to withdraw their deposited funds.
    ///
    /// @param  orderId_ The ID of the order to cancel
    function cancelOrder(uint256 orderId_) external nonReentrant {
        LimitOrder storage order = orders[orderId_];

        if (order.owner != msg.sender) revert NotOrderOwner();
        if (!order.active) revert OrderNotActive();
        if (order.depositSpent == order.depositBudget) revert OrderFullySpent();

        // Ternaries to ensure against underflow when cancelling
        uint256 remainingDeposit = order.depositBudget > order.depositSpent
            ? order.depositBudget - order.depositSpent
            : 0;
        uint256 remainingIncentive = order.incentiveBudget > order.incentiveSpent
            ? order.incentiveBudget - order.incentiveSpent
            : 0;
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
    ///
    /// @return uint256 The current accrued yield in USDS terms
    function getAccruedYield() public view returns (uint256) {
        return SUSDS.convertToAssets(getAccruedYieldShares());
    }

    /// @notice Calculate accrued yield in sUSDS shares
    /// @dev    Uses previewWithdraw to safely account for rounding
    ///
    /// @return uint256 The current accrued yield in sUSDS terms
    function getAccruedYieldShares() public view returns (uint256) {
        uint256 sUsdsBalance = SUSDS.balanceOf(address(this));

        // previewWithdraw rounds UP, giving us the max shares needed to cover obligations
        uint256 sharesRequired = SUSDS.previewWithdraw(totalUsdsOwed);

        if (sUsdsBalance <= sharesRequired) return 0;

        return sUsdsBalance - sharesRequired;
    }

    /// @notice Sweep all accrued yield to the yield recipient as sUSDS
    ///
    /// @return shares The amount of sUSDS swept to the yield recipient
    function sweepYield() external nonReentrant onlyEnabled returns (uint256 shares) {
        shares = getAccruedYieldShares();
        if (shares == 0) return 0;

        ERC20(address(SUSDS)).safeTransfer(yieldRecipient, shares);

        emit YieldSwept(yieldRecipient, shares);

        return shares;
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Get a limit order by ID
    ///
    /// @param  orderId_    The ID of the order
    /// @return LimitOrder  The limit order
    function getOrder(uint256 orderId_) external view returns (LimitOrder memory) {
        return orders[orderId_];
    }

    /// @notice Preview a fill order
    ///
    /// @param  orderId_        The ID of the order
    /// @param  fillAmount_     The amount of USDS to use for the bid
    /// @return canFill         Whether the order can be filled
    /// @return reason          The reason the order cannot be filled
    /// @return effectivePrice  The effective price of the fill
    /// @return incentive       The incentive amount for the fill
    function previewFillOrder(
        uint256 orderId_,
        uint256 fillAmount_
    )
        external
        view
        returns (bool canFill, string memory reason, uint256 effectivePrice, uint256 incentive)
    {
        (canFill, reason, effectivePrice) = canFillOrder(orderId_, fillAmount_);
        (incentive, ) = calculateIncentive(orderId_, fillAmount_);
    }

    /// @notice Calculate incentive and incentive rate for a given fill amount
    ///
    /// @param  orderId_        The ID of the order
    /// @param  fillAmount_     The amount of USDS to use for the bid
    /// @return incentive       The incentive amount for the fill
    /// @return incentiveRate   The incentive rate for the fill
    function calculateIncentive(
        uint256 orderId_,
        uint256 fillAmount_
    ) public view returns (uint256 incentive, uint256 incentiveRate) {
        LimitOrder memory order = orders[orderId_];
        if (order.depositBudget == 0) return (0, 0);

        (, incentive, ) = _calculateFillAndIncentive(order, fillAmount_);
        incentiveRate = (order.incentiveBudget * 10_000) / order.depositBudget;
    }

    /// @notice Check if an order can be filled at a given size
    ///
    /// @param  orderId_        The ID of the order
    /// @param  fillAmount_     The amount of USDS to use for the bid
    /// @return canFill         Whether the order can be filled
    /// @return reason          The reason the order cannot be filled
    /// @return effectivePrice  The effective price of the fill
    function canFillOrder(
        uint256 orderId_,
        uint256 fillAmount_
    ) public view returns (bool canFill, string memory reason, uint256 effectivePrice) {
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
    ///
    /// @param  orderId_    The ID of the order
    /// @return deposit     The remaining deposit budget
    /// @return incentive   The remaining incentive budget
    function getRemaining(
        uint256 orderId_
    ) external view returns (uint256 deposit, uint256 incentive) {
        LimitOrder memory order = orders[orderId_];
        deposit = order.depositBudget - order.depositSpent;
        incentive = order.incentiveBudget - order.incentiveSpent;
    }

    /// @notice Get current execution price for a fill amount
    ///
    /// @param  depositPeriod_  The deposit period
    /// @param  fillAmount_     The amount of USDS to use for the bid
    /// @return effectivePrice  The effective price of the fill
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
    ///
    /// @param  depositPeriod_  The deposit period
    /// @return uint256[]       The IDs of the fillable orders
    function getFillableOrders(uint8 depositPeriod_) external view returns (uint256[] memory) {
        return _getFillableOrders(depositPeriod_, 0, nextOrderId);
    }

    /// @notice Find fillable orders for a deposit period between given order IDs
    /// @dev    For use if getFillableOrders(uint8 depositPeriod_) exceeds limit
    /// @dev    WARNING: Gas-intensive. Intended for off-chain use only.
    ///
    /// @param  depositPeriod_  The deposit period
    /// @param  index0          The starting order ID
    /// @param  index1          The ending order ID
    /// @return uint256[]       The IDs of the fillable orders
    function getFillableOrders(
        uint8 depositPeriod_,
        uint256 index0,
        uint256 index1
    ) external view returns (uint256[] memory) {
        return _getFillableOrders(depositPeriod_, index0, index1);
    }

    /// @notice Find fillable orders for a deposit period between given order IDs
    /// @dev    For use if getFillableOrders(uint8 depositPeriod_) exceeds limit
    /// @dev    WARNING: Gas-intensive. Intended for off-chain use only.
    ///
    /// @param  depositPeriod_  The deposit period
    /// @param  index0          The starting order ID
    /// @param  index1          The ending order ID
    /// @return uint256[]       The IDs of the fillable orders
    function _getFillableOrders(
        uint8 depositPeriod_,
        uint256 index0,
        uint256 index1
    ) internal view returns (uint256[] memory) {
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

    /// @notice Check if an order is fillable
    ///
    /// @param  orderId_        The ID of the order
    /// @param  depositPeriod_  The deposit period
    /// @return bool            Whether the order is fillable
    function _isOrderFillable(uint256 orderId_, uint8 depositPeriod_) internal view returns (bool) {
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

    // ========== ENABLER FUNCTIONS ========== //

    /// @inheritdoc PeripheryEnabler
    /// @dev        Calls Ownable's _checkOwner()
    function _onlyOwner() internal view override {
        _checkOwner();
    }

    /// @inheritdoc PeripheryEnabler
    /// @dev        No-op
    function _enable(bytes calldata enableData_) internal override {
        // No-op
    }

    /// @inheritdoc PeripheryEnabler
    /// @dev        No-op
    function _disable(bytes calldata disableData_) internal override {
        // No-op
    }

    // ========== ERC721 RECEIVER ========== //

    /// @notice ERC721 receiver function
    ///
    /// @return bytes4  The selector of the function
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
