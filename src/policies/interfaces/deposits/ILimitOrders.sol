// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title  ILimitOrders
/// @notice Interface for limit order functionality for the Convertible Deposit Auctioneer
/// @dev    Users create orders specifying max price, MEV bots fill when price is favorable.
///         User deposits are held in sUSDS to generate yield, which accrues to a configurable recipient.
interface ILimitOrders {
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

    /// @notice Emitted when a deposit period and receipt token are added
    ///
    /// @param  depositPeriod   The deposit period that was added
    /// @param  receiptToken    The receipt token address for the deposit period
    event DepositPeriodAdded(uint8 indexed depositPeriod, address indexed receiptToken);

    /// @notice Emitted when a deposit period and receipt token are removed
    ///
    /// @param  depositPeriod   The deposit period that was removed
    event DepositPeriodRemoved(uint8 indexed depositPeriod);

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

    // ========== STATE ========== //

    /// @notice Recipient of accrued yield
    function yieldRecipient() external view returns (address);

    /// @notice Next order ID to be assigned
    function nextOrderId() external view returns (uint256);

    /// @notice Total USDS owed to all order owners (principal tracking)
    function totalUsdsOwed() external view returns (uint256);

    // ========== ADMIN ========== //

    /// @notice Update the yield recipient address
    ///
    /// @param  newRecipient_   The new yield recipient
    function setYieldRecipient(address newRecipient_) external;

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
    function addDepositPeriod(uint8 depositPeriod_, address receiptToken_) external;

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
    function removeDepositPeriod(uint8 depositPeriod_) external;

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
    ) external returns (uint256 orderId);

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
    ) external returns (uint256, uint256, uint256);

    /// @notice Cancel an active order and return remaining funds
    /// @dev    This function will revert if:
    ///         - The caller is not the order owner
    ///         - The order is not active
    ///         - The order is fully spent
    ///
    ///         Note that if the contract is disabled, this function will still operate in order to allow users to withdraw their deposited funds.
    ///
    /// @param  orderId_ The ID of the order to cancel
    function cancelOrder(uint256 orderId_) external;

    // ========== YIELD FUNCTIONS ========== //

    /// @notice Calculate current accrued yield in USDS terms
    ///
    /// @return uint256 The current accrued yield in USDS terms
    function getAccruedYield() external view returns (uint256);

    /// @notice Calculate accrued yield in sUSDS shares
    /// @dev    Uses previewWithdraw to safely account for rounding
    ///
    /// @return uint256 The current accrued yield in sUSDS terms
    function getAccruedYieldShares() external view returns (uint256);

    /// @notice Sweep all accrued yield to the yield recipient as sUSDS
    ///
    /// @return shares The amount of sUSDS swept to the yield recipient
    function sweepYield() external returns (uint256 shares);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Get a limit order by ID
    ///
    /// @param  orderId_    The ID of the order
    /// @return LimitOrder  The limit order
    function getOrder(uint256 orderId_) external view returns (LimitOrder memory);

    /// @notice Get limit order IDs by user
    ///
    /// @param  user_       The address of the user
    /// @return uint256[]   The IDs of the user's orders
    function getOrdersForUser(address user_) external view returns (uint256[] memory);

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
        returns (bool canFill, string memory reason, uint256 effectivePrice, uint256 incentive);

    /// @notice Calculate incentive and incentive rate for a given fill amount
    ///
    /// @param  orderId_        The ID of the order
    /// @param  fillAmount_     The amount of USDS to use for the bid
    /// @return incentive       The incentive amount for the fill
    /// @return incentiveRate   The incentive rate for the fill
    function calculateIncentive(
        uint256 orderId_,
        uint256 fillAmount_
    ) external view returns (uint256 incentive, uint256 incentiveRate);

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
    ) external view returns (bool canFill, string memory reason, uint256 effectivePrice);

    /// @notice Get remaining deposit and incentive budgets for order
    ///
    /// @param  orderId_    The ID of the order
    /// @return deposit     The remaining deposit budget
    /// @return incentive   The remaining incentive budget
    function getRemaining(
        uint256 orderId_
    ) external view returns (uint256 deposit, uint256 incentive);

    /// @notice Get current execution price for a fill amount
    ///
    /// @param  depositPeriod_  The deposit period
    /// @param  fillAmount_     The amount of USDS to use for the bid
    /// @return effectivePrice  The effective price of the fill
    function getExecutionPrice(
        uint8 depositPeriod_,
        uint256 fillAmount_
    ) external view returns (uint256);

    /// @notice Find fillable orders for a deposit period
    /// @dev    WARNING: Gas-intensive. Intended for off-chain use only.
    ///
    /// @param  depositPeriod_  The deposit period
    /// @return uint256[]       The IDs of the fillable orders
    function getFillableOrders(uint8 depositPeriod_) external view returns (uint256[] memory);

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
    ) external view returns (uint256[] memory);
}
