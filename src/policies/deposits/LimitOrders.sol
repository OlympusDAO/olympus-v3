// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.24;

// Interfaces
import {IConvertibleDepositAuctioneer} from "../interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {ILimitOrders} from "../interfaces/deposits/ILimitOrders.sol";
import {IVersioned} from "../../interfaces/IVersioned.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC721Receiver} from "@openzeppelin-5.3.0/token/ERC721/IERC721Receiver.sol";

// Libraries
import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin-5.3.0/access/Ownable.sol";
import {ERC20} from "@openzeppelin-5.3.0/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin-5.3.0/token/ERC721/ERC721.sol";
import {ERC4626} from "@openzeppelin-5.3.0/token/ERC20/extensions/ERC4626.sol";
import {ERC721Utils} from "@openzeppelin-5.3.0/token/ERC721/utils/ERC721Utils.sol";
import {Math} from "@openzeppelin-5.3.0/utils/math/Math.sol";
import {PeripheryEnabler} from "src/periphery/PeripheryEnabler.sol";

/// @title  CDAuctioneer Limit Orders
/// @notice Enables limit order functionality for the Convertible Deposit Auctioneer
/// @dev    Users create orders specifying max price, MEV bots fill when price is favorable.
///         User deposits are held in sUSDS to generate yield, which accrues to a configurable recipient.
/// @author Zeus
contract CDAuctioneerLimitOrders is
    ILimitOrders,
    IVersioned,
    IERC721Receiver,
    ReentrancyGuardTransient,
    Ownable,
    PeripheryEnabler
{
    using SafeERC20 for ERC20;
    using Math for uint256;

    // ========== CONSTANTS ========== //

    uint256 internal constant OHM_SCALE = 1e9;

    // ========== IMMUTABLES ========== //

    /// @notice The Deposit Manager contract
    /// @dev    This variable is immutable
    address public immutable DEPOSIT_MANAGER;

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
    mapping(uint256 orderId => LimitOrder order) internal _orders;

    /// @notice Limit order IDs by user
    mapping(address => uint256[]) internal _ordersForUser;

    /// @notice Next order ID to be assigned
    uint256 public nextOrderId;

    /// @notice Total USDS owed to all order owners (principal tracking)
    uint256 public totalUsdsOwed;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address owner_,
        address depositManager_,
        address cdAuctioneer_,
        address usds_,
        address sUsds_,
        address positionNft_,
        address yieldRecipient_,
        uint8[] memory depositPeriods_,
        address[] memory receiptTokens_
    ) Ownable(owner_) {
        if (depositManager_ == address(0)) revert InvalidParam("depositManager");
        if (cdAuctioneer_ == address(0)) revert InvalidParam("cdAuctioneer");
        if (usds_ == address(0)) revert InvalidParam("usds");
        if (sUsds_ == address(0)) revert InvalidParam("sUsds");
        if (positionNft_ == address(0)) revert InvalidParam("positionNft");
        if (yieldRecipient_ == address(0)) revert InvalidParam("yieldRecipient");
        uint256 len = depositPeriods_.length;
        if (len != receiptTokens_.length) revert ArrayLengthMismatch();

        DEPOSIT_MANAGER = depositManager_;
        CD_AUCTIONEER = IConvertibleDepositAuctioneer(cdAuctioneer_);
        USDS = ERC20(usds_);
        SUSDS = ERC4626(sUsds_);
        POSITION_NFT = ERC721(positionNft_);
        yieldRecipient = yieldRecipient_;

        for (uint256 i = 0; i < len; i++) {
            _addDepositPeriod(depositPeriods_[i], receiptTokens_[i]);
        }

        USDS.approve(address(SUSDS), type(uint256).max);

        // Disabled by default
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
        return (major, minor);
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

    /// @notice Add a new deposit period and associated receipt token
    /// @dev    This function will revert if:
    ///         - The contract is not enabled
    ///         - The caller is not the owner
    ///         - The deposit period is 0
    ///         - The receipt token address is 0
    ///         - The deposit period is already configured
    ///         - The deposit period is not enabled in the auctioneer
    ///
    /// @param  depositPeriod_   The deposit period to add
    /// @param  receiptToken_   The receipt token address for the deposit period
    function addDepositPeriod(
        uint8 depositPeriod_,
        address receiptToken_
    ) external onlyOwner onlyEnabled {
        _addDepositPeriod(depositPeriod_, receiptToken_);
    }

    /// @notice Internal function to add a deposit period and associated receipt token
    /// @dev    This function will revert if:
    ///         - The deposit period is 0
    ///         - The receipt token address is 0
    ///         - The deposit period is already configured
    ///         - The deposit period is not enabled in the auctioneer
    ///
    /// @param  depositPeriod_   The deposit period to add
    /// @param  receiptToken_   The receipt token address for the deposit period
    function _addDepositPeriod(uint8 depositPeriod_, address receiptToken_) internal {
        // Validate deposit period is not 0
        if (depositPeriod_ == 0) revert InvalidParam("depositPeriod");

        // Validate receipt token is not address(0)
        if (receiptToken_ == address(0)) revert InvalidParam("receiptToken");

        // Check for duplicate entry
        if (address(receiptTokens[depositPeriod_]) != address(0)) {
            revert InvalidParam("depositPeriod already configured");
        }

        // Check if deposit period is enabled in auctioneer
        _requireEnabledDepositPeriod(depositPeriod_);

        // Set the receipt token
        receiptTokens[depositPeriod_] = ERC20(receiptToken_);

        // Emit event
        emit DepositPeriodAdded(depositPeriod_, receiptToken_);
    }

    /// @notice Remove a deposit period and associated receipt token
    /// @dev    This function will revert if:
    ///         - The contract is not enabled
    ///         - The caller is not the owner
    ///         - The deposit period is not configured
    ///
    ///         Note: Active orders for this deposit period will fail to fill until the deposit period
    ///         is re-added. Users can cancel their orders if needed.
    ///
    /// @param  depositPeriod_   The deposit period to remove
    function removeDepositPeriod(uint8 depositPeriod_) external onlyOwner onlyEnabled {
        // Check if deposit period is configured
        if (address(receiptTokens[depositPeriod_]) == address(0)) {
            revert ReceiptTokenNotConfigured();
        }

        // Remove the receipt token
        delete receiptTokens[depositPeriod_];

        // Emit event
        emit DepositPeriodRemoved(depositPeriod_);
    }

    // ========== ORDER MANAGEMENT ========== //

    /// @notice Internal function to deposit USDS into sUSDS and adjust the deposit and incentive budgets
    ///
    /// @param  depositBudget_          USDS budget for bids
    /// @param  incentiveBudget_        USDS budget for filler incentives (paid proportionally)
    /// @return actualDepositBudget     The actual deposit budget (may be less than the input)
    /// @return actualIncentiveBudget   The actual incentive budget (may be less than the input)
    function _deposit(
        uint256 depositBudget_,
        uint256 incentiveBudget_
    ) internal returns (uint256 actualDepositBudget, uint256 actualIncentiveBudget) {
        uint256 actualDeposit;
        {
            // Pull from caller
            uint256 totalDeposit = depositBudget_ + incentiveBudget_;
            USDS.safeTransferFrom(msg.sender, address(this), totalDeposit);

            // Check that the deposit will result in a non-zero amount of shares
            if (SUSDS.previewDeposit(totalDeposit) == 0) revert InvalidParam("zero shares");

            // Deposit into sUSDS
            uint256 depositedShares = SUSDS.deposit(totalDeposit, address(this));
            actualDeposit = SUSDS.previewRedeem(depositedShares);

            // Check that the withdrawable amount is not 0 (though this should never happen)
            if (actualDeposit == 0) revert InvalidParam("zero withdrawable amount");
        }

        // Adjust the deposit and incentive budgets, based on the withdrawable amount
        // If the amount withdrawable is less than the deposit budget, then the deposit budget is the actual deposit (and the incentive budget is 0)
        if (actualDeposit <= depositBudget_) {
            actualDepositBudget = actualDeposit;
        }
        // Otherwise, set the deposit budget to the input, and adjust the incentive budget to the difference
        else {
            actualDepositBudget = depositBudget_;
            actualIncentiveBudget = actualDeposit - depositBudget_;
        }

        return (actualDepositBudget, actualIncentiveBudget);
    }

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

        _requireEnabledDepositPeriod(depositPeriod_);

        // Verify that the caller/owner can receive ERC721 tokens
        ERC721Utils.checkOnERC721Received(msg.sender, address(this), msg.sender, 0, "");

        uint256 auctioneerMinBid = CD_AUCTIONEER.getMinimumBid();
        if (minFillSize_ < auctioneerMinBid)
            revert InvalidParam("minFillSize < auctioneer minimum");

        (uint256 actualDepositBudget, uint256 actualIncentiveBudget) = _deposit(
            depositBudget_,
            incentiveBudget_
        );
        totalUsdsOwed += actualDepositBudget + actualIncentiveBudget;

        unchecked {
            orderId = nextOrderId++;
        }

        _ordersForUser[msg.sender].push(orderId);

        _orders[orderId] = LimitOrder({
            owner: msg.sender,
            depositPeriod: depositPeriod_,
            active: true,
            depositBudget: actualDepositBudget,
            incentiveBudget: actualIncentiveBudget,
            depositSpent: 0,
            incentiveSpent: 0,
            maxPrice: maxPrice_,
            minFillSize: minFillSize_
        });

        emit OrderCreated(
            orderId,
            msg.sender,
            depositPeriod_,
            actualDepositBudget,
            actualIncentiveBudget,
            maxPrice_,
            minFillSize_
        );

        return orderId;
    }

    /// @notice Calculate capped fill amount and incentive for an order
    ///
    /// @param  order_           The limit order
    /// @param  fillAmount_      The requested fill amount
    /// @return cappedFill       The fill amount capped to remaining deposit
    /// @return incentive        The incentive amount (with final fill handling)
    /// @return remainingDeposit The remaining deposit budget
    function _calculateFillAndIncentive(
        LimitOrder storage order_,
        uint256 fillAmount_
    ) internal view returns (uint256 cappedFill, uint256 incentive, uint256 remainingDeposit) {
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
    ///         - The deposit period is not enabled
    ///         - The receipt token is not configured
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
        LimitOrder storage order = _orders[orderId_];

        if (!order.active) revert OrderNotActive();

        uint256 remainingDepositBefore;
        uint256 incentive;
        (fillAmount_, incentive, remainingDepositBefore) = _calculateFillAndIncentive(
            order,
            fillAmount_
        );

        if (remainingDepositBefore == 0) revert OrderFullySpent();

        // Check min fill (unless this is the final fill)
        if (remainingDepositBefore >= order.minFillSize && fillAmount_ < order.minFillSize) {
            revert FillBelowMinimum();
        }

        _requireEnabledDepositPeriod(order.depositPeriod);
        // Check that the receipt token is still configured
        if (address(receiptTokens[order.depositPeriod]) == address(0))
            revert ReceiptTokenNotConfigured();

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
        USDS.approve(address(DEPOSIT_MANAGER), fillAmount_);
        (uint256 ohmOut, uint256 positionId, , uint256 actualAmount) = CD_AUCTIONEER.bid(
            order.depositPeriod,
            fillAmount_,
            expectedOhmOut,
            true,
            true
        );

        // Transfer position NFT and receipt tokens to order owner
        POSITION_NFT.safeTransferFrom(address(this), order.owner, positionId);
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
        unchecked {
            // No underflow: fillAmount_ is capped to remainingDepositBefore in _calculateFillAndIncentive
            return (fillAmount_, incentive, remainingDepositBefore - fillAmount_);
        }
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
        LimitOrder storage order = _orders[orderId_];

        if (order.owner != msg.sender) revert NotOrderOwner();
        if (!order.active) revert OrderNotActive();
        uint256 depositBudget = order.depositBudget;
        uint256 depositSpent = order.depositSpent;
        if (depositSpent == depositBudget) revert OrderFullySpent();

        // Calculate remaining amounts (saturating subtraction ensures no underflow when cancelling)
        uint256 remainingDeposit = depositBudget.saturatingSub(depositSpent);
        uint256 remainingIncentive = order.incentiveBudget.saturatingSub(order.incentiveSpent);
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
    function getAccruedYield() external view returns (uint256) {
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

        return sUsdsBalance.saturatingSub(sharesRequired);
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
        return _orders[orderId_];
    }

    /// @notice Get limit order IDs by user
    ///
    /// @param  user_       The address of the user
    /// @return uint256[]   The IDs of the user's orders
    function getOrdersForUser(address user_) external view returns (uint256[] memory) {
        return _ordersForUser[user_];
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
        if (!isEnabled) return (0, 0);

        LimitOrder storage order = _orders[orderId_];
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
        if (!isEnabled) return (false, "Contract disabled", 0);

        LimitOrder storage order = _orders[orderId_];

        if (!order.active) return (false, "Order not active", 0);

        // Check that the deposit period is enabled
        uint8 depositPeriod = order.depositPeriod;
        {
            (bool isDepositPeriodEnabled, ) = CD_AUCTIONEER.isDepositPeriodEnabled(depositPeriod);
            if (!isDepositPeriodEnabled) return (false, "Deposit period not enabled", 0);
        }
        // Check that the receipt token is still configured
        if (address(receiptTokens[depositPeriod]) == address(0))
            return (false, "Receipt token not configured", 0);

        uint256 remainingDeposit = order.depositBudget - order.depositSpent;
        if (remainingDeposit == 0) return (false, "Order fully spent", 0);

        uint256 actualFill = fillAmount_ > remainingDeposit ? remainingDeposit : fillAmount_;

        if (remainingDeposit >= order.minFillSize && actualFill < order.minFillSize) {
            return (false, "Fill below minimum", 0);
        }

        uint256 expectedOhmOut = CD_AUCTIONEER.previewBid(depositPeriod, actualFill);
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
        LimitOrder storage order = _orders[orderId_];
        deposit = order.depositBudget.saturatingSub(order.depositSpent);
        incentive = order.incentiveBudget.saturatingSub(order.incentiveSpent);
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
        uint256[] memory tmp = new uint256[](index1 - index0);
        uint256 count = 0;
        for (uint256 i = index0; i < index1; i++) {
            if (_isOrderFillable(i, depositPeriod_)) {
                tmp[count++] = i;
            }
        }

        uint256[] memory fillable = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            fillable[i] = tmp[i];
        }
        return fillable;
    }

    /// @notice Check if an order is fillable
    ///
    /// @param  orderId_        The ID of the order
    /// @param  depositPeriod_  The deposit period
    /// @return bool            Whether the order is fillable
    function _isOrderFillable(uint256 orderId_, uint8 depositPeriod_) internal view returns (bool) {
        LimitOrder storage order = _orders[orderId_];

        // Early return if deposit period doesn't match
        if (order.depositPeriod != depositPeriod_) return false;

        // Calculate the fill amount to check (minFillSize or remaining deposit, whichever is smaller)
        uint256 remainingDeposit = order.depositBudget - order.depositSpent;
        uint256 checkAmount = remainingDeposit > order.minFillSize
            ? order.minFillSize
            : remainingDeposit;

        // Reuse canFillOrder to ensure consistency with fillOrder checks
        // This includes: contract enabled, order active, deposit period enabled,
        // receipt token configured, order not fully spent, min fill size, and price checks
        (bool canFill, , ) = canFillOrder(orderId_, checkAmount);
        return canFill;
    }

    // Requires that the deposit period be enabled in the auctioneer
    function _requireEnabledDepositPeriod(uint8 depositPeriod_) private view {
        (bool enabled, ) = CD_AUCTIONEER.isDepositPeriodEnabled(depositPeriod_);
        if (!enabled) revert DepositPeriodNotEnabled();
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
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // ========== ERC165 ========== //

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(ILimitOrders).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
/// forge-lint: disable-end(mixed-case-function)
