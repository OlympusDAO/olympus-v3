// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.15;

import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {SubKeycode} from "src/Submodules.sol";

/// @notice     Interface for PriceConfigv2 policy
/// @dev        Policy to configure PRICEv2
interface IPriceConfigv2 {
    // ========== EVENTS ========== //

    /// @notice Emitted when a PRICE configuration action is queued
    ///
    /// @param actionId     The queued action ID
    /// @param action       The type of action queued
    /// @param proposer     The account that queued the action
    /// @param payloadHash  Hash of the encoded action payload
    /// @param executableAt Timestamp at which the action can first be executed
    /// @param expiresAt    Timestamp after which the action can no longer be executed
    event PriceConfigActionQueued(
        uint256 indexed actionId,
        TimelockAction indexed action,
        address indexed proposer,
        bytes32 payloadHash,
        uint48 executableAt,
        uint48 expiresAt
    );

    /// @notice Emitted when a queued PRICE configuration action is executed
    ///
    /// @param actionId The queued action ID
    /// @param action   The type of action executed
    /// @param executor The account that executed the action
    event PriceConfigActionExecuted(
        uint256 indexed actionId,
        TimelockAction indexed action,
        address indexed executor
    );

    /// @notice Emitted when a queued PRICE configuration action is cancelled
    ///
    /// @param actionId  The queued action ID
    /// @param action    The type of action cancelled
    /// @param canceller The account that cancelled the action
    event PriceConfigActionCancelled(
        uint256 indexed actionId,
        TimelockAction indexed action,
        address indexed canceller
    );

    /// @notice Emitted when the configuration timelock delay is changed
    ///
    /// @param delay The new timelock delay in seconds
    event TimelockDelaySet(uint48 delay);

    // ========== ERRORS ========== //

    /// @notice Thrown when module does not support interface
    ///
    /// @param  keycode     The keycode of the module
    /// @param  interfaceId The interface identifier, as specified in ERC-165
    error IPriceConfigv2_UnsupportedModuleInterface(bytes5 keycode, bytes4 interfaceId);

    /// @notice Thrown when module version is not supported
    ///
    /// @param  keycode The keycode of the module
    /// @param  major   The major version of the module
    /// @param  minor   The minor version of the module
    error IPriceConfigv2_UnsupportedModuleVersion(bytes5 keycode, uint8 major, uint8 minor);

    /// @notice Thrown when the number of feed expectations does not match the number of feeds
    ///
    /// @param  asset_            The address of the asset being configured
    /// @param  expectationCount_ The number of expectations provided
    /// @param  feedCount_        The number of feeds expected
    error IPriceConfigv2_FeedExpectationCountInvalid(
        address asset_,
        uint256 expectationCount_,
        uint256 feedCount_
    );

    /// @notice Thrown when a feed expectation is invalid
    ///
    /// @param  asset_ The address of the asset being configured
    /// @param  index_ The index of the invalid expectation
    error IPriceConfigv2_FeedExpectationInvalid(address asset_, uint256 index_);

    /// @notice Thrown when a feed cannot be queried for expectation validation
    ///
    /// @param  asset_ The address of the asset being configured
    /// @param  index_ The index of the feed that failed
    error IPriceConfigv2_PriceFeedCallFailed(address asset_, uint256 index_);

    /// @notice Thrown when a feed price is outside the configured expectation range
    ///
    /// @param  asset_      The address of the asset being configured
    /// @param  index_      The index of the feed that returned an out-of-bounds price
    /// @param  price_      The price returned by the feed
    /// @param  lowerBound_ The minimum accepted price
    /// @param  upperBound_ The maximum accepted price
    error IPriceConfigv2_PriceFeedOutOfBounds(
        address asset_,
        uint256 index_,
        uint256 price_,
        uint256 lowerBound_,
        uint256 upperBound_
    );

    /// @notice Thrown when a queued action does not exist
    ///
    /// @param actionId The queued action ID
    error IPriceConfigv2_ActionNotFound(uint256 actionId);

    /// @notice Thrown when a queued action has already been executed
    ///
    /// @param actionId The queued action ID
    error IPriceConfigv2_ActionAlreadyExecuted(uint256 actionId);

    /// @notice Thrown when a queued action has been cancelled
    ///
    /// @param actionId The queued action ID
    error IPriceConfigv2_ActionCancelled(uint256 actionId);

    /// @notice Thrown when a queued action is executed before its timelock has elapsed
    ///
    /// @param actionId     The queued action ID
    /// @param executableAt Timestamp at which the action can first be executed
    error IPriceConfigv2_ActionNotReady(uint256 actionId, uint48 executableAt);

    /// @notice Thrown when a queued action is executed after its execution window
    ///
    /// @param actionId  The queued action ID
    /// @param expiresAt Timestamp after which the action can no longer be executed
    error IPriceConfigv2_ActionExpired(uint256 actionId, uint48 expiresAt);

    /// @notice Thrown when a proposed timelock delay is outside the accepted range
    ///
    /// @param delay   The proposed delay
    /// @param minimum The minimum accepted delay
    /// @param maximum The maximum accepted delay
    error IPriceConfigv2_TimelockDelayInvalid(uint48 delay, uint48 minimum, uint48 maximum);

    // ========== DATA STRUCTURES ========== //

    /// @notice                     Expected price and tolerance for a configured feed
    /// @dev                        Used as a configuration-time plausibility check only. This
    ///                             does not prove feed identity; a different asset with a similar
    ///                             price can still pass within tolerance.
    ///
    /// @param expectedPrice        Expected feed price in PRICE output decimals
    /// @param toleranceBps         Allowed deviation from expected price, in basis points
    struct PriceFeedExpectation {
        uint256 expectedPrice;
        uint16 toleranceBps;
    }

    /// @notice Queued timelock action type
    enum TimelockAction {
        UpdateAsset,
        RemoveAsset,
        UpgradeSubmodule,
        SetTimelockDelay
    }

    /// @notice Queued PRICE configuration action
    ///
    /// @param action       The type of action queued
    /// @param proposer     The account that queued the action
    /// @param queuedAt     Timestamp at which the action was queued
    /// @param executableAt Timestamp at which the action can first be executed
    /// @param expiresAt    Timestamp after which the action can no longer be executed
    /// @param executed     Whether the action has been executed
    /// @param cancelled    Whether the action has been cancelled
    /// @param payload      Encoded parameters for the action
    struct QueuedAction {
        TimelockAction action;
        address proposer;
        uint48 queuedAt;
        uint48 executableAt;
        uint48 expiresAt;
        bool executed;
        bool cancelled;
        bytes payload;
    }

    // ========================= //
    // TIMELOCK MANAGEMENT       //
    // ========================= //

    /// @notice Execute a queued PRICE configuration action
    /// @dev    Deliberately permissionless; the timelock and emergency cancellation are the authorization boundaries.
    ///
    /// @param  actionId_ The queued action ID
    function executeQueuedAction(uint256 actionId_) external;

    /// @notice Cancel a queued PRICE configuration action
    /// @dev    Intended to be callable only by an independent emergency role.
    ///
    /// @param  actionId_ The queued action ID
    function cancelQueuedAction(uint256 actionId_) external;

    /// @notice Queue a timelocked change to the timelock delay
    /// @dev    The delay update is not applied until the queued action is executed. Intended to be callable only by `admin`.
    ///
    /// @param  delay_    The new timelock delay in seconds
    /// @return actionId_ The queued action ID
    function queueTimelockDelay(uint48 delay_) external returns (uint256 actionId_);

    /// @notice Get a queued PRICE configuration action
    ///
    /// @param  actionId_ The queued action ID
    /// @return action_   The queued action
    function getQueuedAction(uint256 actionId_) external view returns (QueuedAction memory action_);

    // ========================= //
    // PRICE MANAGEMENT          //
    // ========================= //

    /// @notice Configure a new asset on the PRICE module
    /// @dev    See PRICEv2 for more details on caching behavior when no moving average is stored and component interface
    ///
    /// @param  asset_                  The address of the asset to add
    /// @param  storeMovingAverage_     Whether to store the moving average for this asset
    /// @param  useMovingAverage_       Whether to use the moving average as part of the price resolution strategy for this asset
    /// @param  movingAverageDuration_  The duration of the moving average in seconds, only used if `storeMovingAverage_` is true
    /// @param  lastObservationTime_    The timestamp of the last observation
    /// @param  observations_           The array of observations to add - the number of observations must match the moving average duration divided by the PRICEv2 observation frequency
    /// @param  strategy_               The price resolution strategy to use for this asset
    /// @param  feeds_                  The array of price feeds to use for this asset
    /// @param  feedExpectations_       Expected price and tolerance for each feed, aligned by index with `feeds_`
    function addAsset(
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        IPRICEv2.Component memory strategy_,
        IPRICEv2.Component[] memory feeds_,
        PriceFeedExpectation[] memory feedExpectations_
    ) external;

    /// @notice Queue removal of an asset from the PRICE module
    /// @dev    After execution, calls to PRICEv2 for the asset's price will revert.
    ///
    /// @param  asset_    The address of the asset to remove
    /// @return actionId_ The queued action ID
    function queueRemoveAsset(address asset_) external returns (uint256 actionId_);

    /// @notice Queue an atomic asset configuration update
    /// @dev    Only updates components flagged in params_ after the queued action is executed.
    /// @dev    See PRICEv2 for more details on the UpdateAssetParams struct
    ///
    /// @param  asset_            The address of the asset to update
    /// @param  params_           Update parameters with flags indicating which components to update
    /// @param  feedExpectations_ Expected price and tolerance for each feed when `params_.updateFeeds` is true. Must be empty otherwise.
    /// @return actionId_         The queued action ID
    function queueUpdateAsset(
        address asset_,
        IPRICEv2.UpdateAssetParams memory params_,
        PriceFeedExpectation[] memory feedExpectations_
    ) external returns (uint256 actionId_);

    /// @notice Store a price observation for an asset
    /// @dev    Calls PRICE.storeObservation(asset_) to calculate and store current price
    ///
    /// @param  asset_  The address of asset
    function storeObservation(address asset_) external;

    /// @notice Store the current price of all assets that track a moving average
    /// @dev    Calls PRICE.storeObservations() to calculate and store observations
    function storeObservations() external;

    // ========================= //
    // SUBMODULE MANAGEMENT      //
    // ========================= //

    /// @notice Install a new submodule on the designated module
    ///
    /// @param  submodule_  The address of the submodule to install
    function installSubmodule(address submodule_) external;

    /// @notice Queue an upgrade of a submodule on the PRICE module
    /// @dev    The upgraded submodule must have the same SubKeycode as an existing submodule that it is replacing, otherwise use installSubmodule.
    ///
    /// @param  submodule_  The address of the submodule to upgrade to
    /// @return actionId_   The queued action ID
    function queueUpgradeSubmodule(address submodule_) external returns (uint256 actionId_);

    /// @notice Perform a view/staticcall-only action on a submodule
    /// @dev    This function is intentionally not timelocked because it is reserved for read-only
    ///         submodule interactions. Mutable submodule configuration must be exposed through an
    ///         explicit PriceConfigv2 function and timelocked if it can affect live price resolution.
    /// @dev    This function reverts if:
    /// @dev    - PRICE.execOnSubmodule() reverts
    ///
    /// @param  subKeycode_ The SubKeycode of the submodule to call
    /// @param  data_       The calldata to send to the submodule
    function execOnSubmodule(SubKeycode subKeycode_, bytes calldata data_) external;
}
/// forge-lint: disable-end(mixed-case-function)
