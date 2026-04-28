// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {ISubmodule} from "src/interfaces/ISubmodule.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Libraries
import {Deviation} from "src/libraries/Deviation.sol";
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {ensureContract, fromKeycode, Kernel, Keycode, toKeycode, Policy, Permissions, Module} from "src/Kernel.sol";
import {ensureValidSubKeycode, fromSubKeycode, ModuleWithSubmodules, SubKeycode, Submodule} from "src/Submodules.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @notice     Policy to configure PRICEv2
/// @dev        Some functions in this policy are gated to addresses with the "price_admin" or "admin" roles.
///             Timelocked actions assume an independent emergency role can cancel malicious or stale queued actions.
contract PriceConfigv2 is Policy, PolicyEnabler, IPriceConfigv2, IVersioned {
    using FullMath for uint256;

    // ========== STATE ========== //

    bytes5 internal constant _PRICE_KEYCODE = "PRICE";
    bytes5 internal constant _ROLES_KEYCODE = "ROLES";

    bytes32 internal constant _PRICE_ADMIN_ROLE = "price_admin";
    uint16 internal constant _BPS_MAX = 10_000;
    uint48 public constant MIN_TIMELOCK_DELAY = 1 days;
    uint48 public constant MAX_TIMELOCK_DELAY = 30 days;
    uint48 public constant EXECUTION_WINDOW = 7 days;

    // Modules
    PRICEv2 public PRICE;

    /// @notice Current timelock delay for queued configuration changes.
    uint48 public timelockDelay = MIN_TIMELOCK_DELAY;

    /// @notice Next queued action ID.
    uint256 public nextActionId = 1;

    /// @notice Queued configuration actions.
    mapping(uint256 => IPriceConfigv2.QueuedAction) internal _queuedActions;

    // ========== POLICY SETUP ========== //

    constructor(Kernel kernel_) Policy(kernel_) {
        // Unlike normal policies, we want this to be enabled by default
        // This allows the "price_admin" to configure assets in the same transaction batch as the module install/upgrade.
        isEnabled = true;
        emit Enabled();
    }

    /// @inheritdoc Policy
    /// @dev        Reverts if:
    ///             - The configured PRICE module version is unsupported
    ///             - The configured PRICE module does not implement IPRICEv2
    ///             - The configured ROLES module major version is unsupported
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode(_ROLES_KEYCODE);
        dependencies[1] = toKeycode(_PRICE_KEYCODE);

        address priceModule = getModuleAddress(dependencies[1]);

        // Require PRICE v1.2+ (major=1, minor>=2) or v2+ (major>=2)
        // Cast to Module to access VERSION() function
        (uint8 major, uint8 minor) = Module(priceModule).VERSION();
        if ((major == 1 && minor < 2) || major < 1)
            revert IPriceConfigv2_UnsupportedModuleVersion(_PRICE_KEYCODE, major, minor);

        // Verify the PRICE module supports IPRICEv2 interface
        if (!IERC165(priceModule).supportsInterface(type(IPRICEv2).interfaceId))
            revert IPriceConfigv2_UnsupportedModuleInterface(
                _PRICE_KEYCODE,
                type(IPRICEv2).interfaceId
            );

        // Set ROLES module (required by PolicyEnabler)
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        // Set PRICE module
        PRICE = PRICEv2(priceModule);

        // Ensure ROLES module is using the expected major version
        (uint8 rolesMajor, uint8 rolesMinor) = ROLES.VERSION();
        if (rolesMajor != 1)
            revert IPriceConfigv2_UnsupportedModuleVersion(_ROLES_KEYCODE, rolesMajor, rolesMinor);
    }

    /// @inheritdoc Policy
    /// @dev        Does not revert.
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode PRICE_KEYCODE = toKeycode("PRICE");

        requests = new Permissions[](8);
        // PRICE Permissions
        requests[0] = Permissions({keycode: PRICE_KEYCODE, funcSelector: PRICE.addAsset.selector});
        requests[1] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.removeAsset.selector
        });
        requests[2] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.updateAsset.selector
        });
        requests[3] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.installSubmodule.selector
        });
        requests[4] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.upgradeSubmodule.selector
        });
        requests[5] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.execOnSubmodule.selector
        });
        requests[6] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.storeObservation.selector
        });
        requests[7] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.storeObservations.selector
        });
    }

    /// @inheritdoc IVersioned
    /// @dev        Does not revert.
    function VERSION() external pure override returns (uint8, uint8) {
        return (2, 0);
    }

    // ========== MODIFIERS ========== //

    function _onlyPriceOrAdminRole() internal view {
        if (!ROLES.hasRole(msg.sender, _PRICE_ADMIN_ROLE) && !_isAdmin(msg.sender)) {
            revert NotAuthorised();
        }
    }

    /// @notice Modifier that reverts if the caller does not have the admin or price_admin role
    modifier onlyPriceOrAdminRole() {
        _onlyPriceOrAdminRole();
        _;
    }

    // ========== TIMELOCK MANAGEMENT ========== //

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The action does not exist
    function getQueuedAction(
        uint256 actionId_
    ) external view override returns (IPriceConfigv2.QueuedAction memory action_) {
        action_ = _queuedActions[actionId_];
        if (action_.queuedAt == 0) revert IPriceConfigv2_ActionNotFound(actionId_);
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller does not have the `admin` role
    ///             - The delay is outside the accepted range
    function queueTimelockDelay(
        uint48 delay_
    ) external override onlyEnabled onlyAdminRole returns (uint256 actionId_) {
        _validateTimelockDelay(delay_);
        return _queueAction(IPriceConfigv2.TimelockAction.SetTimelockDelay, abi.encode(delay_));
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Deliberately permissionless so any keeper or user can execute reviewed actions once ready.
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The action does not exist
    ///             - The action has already been executed
    ///             - The action has been cancelled
    ///             - The action is still timelocked
    ///             - The action has expired
    ///             - The queued action execution reverts
    function executeQueuedAction(uint256 actionId_) external override onlyEnabled {
        IPriceConfigv2.QueuedAction storage action = _queuedActions[actionId_];
        _validateActionExecutable(actionId_, action);

        action.executed = true;

        if (action.action == IPriceConfigv2.TimelockAction.UpdateAsset) {
            (
                address asset,
                IPRICEv2.UpdateAssetParams memory params,
                IPriceConfigv2.PriceFeedExpectation[] memory feedExpectations
            ) = abi.decode(
                    action.payload,
                    (address, IPRICEv2.UpdateAssetParams, IPriceConfigv2.PriceFeedExpectation[])
                );
            _executeUpdateAsset(asset, params, feedExpectations);
        } else if (action.action == IPriceConfigv2.TimelockAction.RemoveAsset) {
            address asset = abi.decode(action.payload, (address));
            PRICE.removeAsset(asset);
        } else if (action.action == IPriceConfigv2.TimelockAction.UpgradeSubmodule) {
            address submodule = abi.decode(action.payload, (address));
            PRICE.upgradeSubmodule(Submodule(submodule));
        } else if (action.action == IPriceConfigv2.TimelockAction.SetTimelockDelay) {
            uint48 delay = abi.decode(action.payload, (uint48));
            _validateTimelockDelay(delay);
            timelockDelay = delay;
            emit TimelockDelaySet(delay);
        }

        delete action.payload;

        emit PriceConfigActionExecuted(actionId_, action.action, msg.sender);
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        The emergency role is assumed to be independent from the admin authority that can queue actions.
    /// @dev        Reverts if:
    ///             - The caller does not have the `emergency` role
    ///             - The action does not exist
    ///             - The action has already been executed
    ///             - The action has been cancelled
    function cancelQueuedAction(uint256 actionId_) external override onlyEmergencyRole {
        IPriceConfigv2.QueuedAction storage action = _queuedActions[actionId_];
        _validateActionCancellable(actionId_, action);

        action.cancelled = true;
        delete action.payload;

        emit PriceConfigActionCancelled(actionId_, action.action, msg.sender);
    }

    function _queueAction(
        IPriceConfigv2.TimelockAction action_,
        bytes memory payload_
    ) internal returns (uint256 actionId_) {
        // Assumes callers already performed queue-time validation for the action-specific payload.
        uint48 queuedAt = uint48(block.timestamp);
        uint48 executableAt = queuedAt + timelockDelay;
        uint48 expiresAt = executableAt + EXECUTION_WINDOW;

        actionId_ = nextActionId;
        nextActionId = actionId_ + 1;

        _queuedActions[actionId_] = IPriceConfigv2.QueuedAction({
            action: action_,
            proposer: msg.sender,
            queuedAt: queuedAt,
            executableAt: executableAt,
            expiresAt: expiresAt,
            executed: false,
            cancelled: false,
            payload: payload_
        });

        emit PriceConfigActionQueued(
            actionId_,
            action_,
            msg.sender,
            keccak256(payload_),
            executableAt,
            expiresAt
        );
    }

    function _validateActionExecutable(
        uint256 actionId_,
        IPriceConfigv2.QueuedAction storage action_
    ) internal view {
        if (action_.queuedAt == 0) revert IPriceConfigv2_ActionNotFound(actionId_);
        if (action_.executed) revert IPriceConfigv2_ActionAlreadyExecuted(actionId_);
        if (action_.cancelled) revert IPriceConfigv2_ActionCancelled(actionId_);
        if (block.timestamp < action_.executableAt)
            revert IPriceConfigv2_ActionNotReady(actionId_, action_.executableAt);
        if (block.timestamp > action_.expiresAt)
            revert IPriceConfigv2_ActionExpired(actionId_, action_.expiresAt);
    }

    function _validateActionCancellable(
        uint256 actionId_,
        IPriceConfigv2.QueuedAction storage action_
    ) internal view {
        if (action_.queuedAt == 0) revert IPriceConfigv2_ActionNotFound(actionId_);
        if (action_.executed) revert IPriceConfigv2_ActionAlreadyExecuted(actionId_);
        if (action_.cancelled) revert IPriceConfigv2_ActionCancelled(actionId_);
    }

    function _validateTimelockDelay(uint48 delay_) internal pure {
        if (delay_ < MIN_TIMELOCK_DELAY || delay_ > MAX_TIMELOCK_DELAY)
            revert IPriceConfigv2_TimelockDelayInvalid(
                delay_,
                MIN_TIMELOCK_DELAY,
                MAX_TIMELOCK_DELAY
            );
    }

    function _validateRemoveAssetQueueParams(address asset_) internal view {
        if (asset_ == PRICE.unitOfAccount()) revert IPRICEv2.PRICE_AssetReserved(asset_);
        if (!PRICE.isAssetApproved(asset_)) revert IPRICEv2.PRICE_AssetNotApproved(asset_);
    }

    function _validateSubmoduleForQueue(
        Submodule submodule_
    ) internal view returns (SubKeycode subKeycode_) {
        ensureContract(address(submodule_));

        Keycode keycode = PRICE.KEYCODE();
        if (fromKeycode(submodule_.PARENT()) != fromKeycode(keycode))
            revert ModuleWithSubmodules.Module_InvalidSubmodule();

        subKeycode_ = submodule_.SUBKEYCODE();
        ensureValidSubKeycode(subKeycode_, keycode);

        (bool success, bytes memory data) = address(submodule_).staticcall(
            abi.encodeWithSelector(IERC165.supportsInterface.selector, type(ISubmodule).interfaceId)
        );

        if (!success || data.length != 32)
            revert ModuleWithSubmodules.Module_SubmoduleInterfaceNotImplemented(
                address(submodule_)
            );
        if (!abi.decode(data, (bool)))
            revert ModuleWithSubmodules.Module_SubmoduleInterfaceNotImplemented(
                address(submodule_)
            );
    }

    function _validateUpgradeSubmoduleQueueParams(address submodule_) internal view {
        Submodule newSubmodule = Submodule(submodule_);
        SubKeycode subKeycode = _validateSubmoduleForQueue(newSubmodule);

        Submodule oldSubmodule = PRICE.getSubmoduleForKeycode(subKeycode);
        if (oldSubmodule == Submodule(address(0)) || oldSubmodule == newSubmodule)
            revert ModuleWithSubmodules.Module_InvalidSubmoduleUpgrade(subKeycode);
    }

    /// @notice                         Validates each feed against its configured expected price
    /// @dev                            This is a configuration-time plausibility check only. It does
    ///                                 not prove feed identity, since another asset with a similar
    ///                                 price can still pass within tolerance.
    ///
    /// @param asset_                   The address of the asset being configured
    /// @param feeds_                   The feeds to validate
    /// @param feedExpectations_        The expected price and tolerance for each feed
    function _validatePriceFeedExpectations(
        address asset_,
        IPRICEv2.Component[] memory feeds_,
        PriceFeedExpectation[] memory feedExpectations_
    ) internal view {
        uint256 len = feeds_.length;
        if (feedExpectations_.length != len)
            revert IPriceConfigv2_FeedExpectationCountInvalid(
                asset_,
                feedExpectations_.length,
                len
            );

        uint8 priceDecimals = PRICE.decimals();
        for (uint256 i; i < len; ) {
            PriceFeedExpectation memory expectation = feedExpectations_[i];
            if (expectation.expectedPrice == 0 || expectation.toleranceBps > _BPS_MAX)
                revert IPriceConfigv2_FeedExpectationInvalid(asset_, i);

            (bool success, bytes memory data) = address(
                PRICE.getSubmoduleForKeycode(feeds_[i].target)
            ).staticcall(
                    abi.encodeWithSelector(
                        feeds_[i].selector,
                        asset_,
                        priceDecimals,
                        feeds_[i].params
                    )
                );

            if (!success || data.length != 32) revert IPriceConfigv2_PriceFeedCallFailed(asset_, i);

            uint256 price = abi.decode(data, (uint256));

            if (
                price == 0 ||
                Deviation.isDeviating(
                    price,
                    expectation.expectedPrice,
                    expectation.toleranceBps,
                    _BPS_MAX
                )
            ) {
                uint256 lowerBound = expectation.expectedPrice.mulDiv(
                    _BPS_MAX - expectation.toleranceBps,
                    _BPS_MAX
                );
                uint256 upperBound = expectation.expectedPrice.mulDivUp(
                    _BPS_MAX + expectation.toleranceBps,
                    _BPS_MAX
                );

                revert IPriceConfigv2_PriceFeedOutOfBounds(
                    asset_,
                    i,
                    price,
                    lowerBound,
                    upperBound
                );
            }

            unchecked {
                ++i;
            }
        }
    }

    function _validateAssetConfiguration(
        address asset_,
        IPRICEv2.Component memory strategy_,
        uint256 feedCount_,
        bool useMovingAverage_,
        bool storeMovingAverage_
    ) internal pure {
        if (useMovingAverage_ && !storeMovingAverage_)
            revert IPRICEv2.PRICE_ParamsStoreMovingAverageRequired(asset_);

        uint256 numFeeds = feedCount_ + (useMovingAverage_ ? 1 : 0);

        if (numFeeds > 1 && fromSubKeycode(strategy_.target) == bytes20(0))
            revert IPRICEv2.PRICE_ParamsStrategyInsufficient(
                asset_,
                abi.encode(strategy_),
                feedCount_,
                useMovingAverage_
            );

        if (numFeeds == 1 && fromSubKeycode(strategy_.target) != bytes20(0))
            revert IPRICEv2.PRICE_ParamsStrategyNotSupported(asset_);
    }

    function _validateMovingAverageParams(
        address asset_,
        IPRICEv2.UpdateAssetParams memory params_
    ) internal view {
        if (!params_.updateMovingAverage) return;

        if (!params_.storeMovingAverage) {
            if (params_.observations.length != 0)
                revert IPRICEv2.PRICE_ParamsInvalidObservationCount(
                    asset_,
                    params_.observations.length,
                    0,
                    0
                );

            if (params_.movingAverageDuration != 0)
                revert IPRICEv2.PRICE_ParamsMovingAverageDurationInvalid(
                    asset_,
                    params_.movingAverageDuration,
                    0
                );

            if (params_.lastObservationTime != 0)
                revert IPRICEv2.PRICE_ParamsLastObservationTimeInvalid(
                    asset_,
                    params_.lastObservationTime,
                    0,
                    0
                );

            return;
        }

        uint48 observationFrequency = PRICE.observationFrequency();
        if (
            params_.movingAverageDuration == 0 ||
            uint48(params_.movingAverageDuration) % observationFrequency != 0
        )
            revert IPRICEv2.PRICE_ParamsMovingAverageDurationInvalid(
                asset_,
                params_.movingAverageDuration,
                observationFrequency
            );

        uint256 numObservations = uint48(params_.movingAverageDuration) / observationFrequency;
        if (params_.observations.length != numObservations || numObservations < 2)
            revert IPRICEv2.PRICE_ParamsInvalidObservationCount(
                asset_,
                params_.observations.length,
                numObservations,
                numObservations
            );

        if (numObservations > type(uint16).max)
            revert IPRICEv2.PRICE_ParamsInvalidObservationCount(
                asset_,
                params_.observations.length,
                2,
                type(uint16).max
            );

        for (uint256 i; i < numObservations; ) {
            if (params_.observations[i] == 0)
                revert IPRICEv2.PRICE_ParamsObservationZero(asset_, i);

            unchecked {
                ++i;
            }
        }
    }

    function _validateUpdateComponentParams(
        address asset_,
        IPRICEv2.UpdateAssetParams memory params_
    ) internal view {
        if (params_.updateFeeds) {
            uint256 len = params_.feeds.length;
            bytes32[] memory hashes = new bytes32[](len);

            for (uint256 i; i < len; ) {
                if (address(PRICE.getSubmoduleForKeycode(params_.feeds[i].target)) == address(0))
                    revert IPRICEv2.PRICE_SubmoduleNotInstalled(
                        asset_,
                        abi.encode(params_.feeds[i].target)
                    );

                /// forge-lint: disable-start(asm-keccak256)
                bytes32 hash = keccak256(
                    abi.encode(
                        params_.feeds[i].target,
                        params_.feeds[i].selector,
                        params_.feeds[i].params
                    )
                );
                /// forge-lint: disable-end(asm-keccak256)

                for (uint256 j; j < i; ) {
                    if (hash == hashes[j]) revert IPRICEv2.PRICE_DuplicatePriceFeed(asset_, i);
                    unchecked {
                        ++j;
                    }
                }

                hashes[i] = hash;

                unchecked {
                    ++i;
                }
            }
        }

        if (
            params_.updateStrategy &&
            fromSubKeycode(params_.strategy.target) != bytes20(0) &&
            address(PRICE.getSubmoduleForKeycode(params_.strategy.target)) == address(0)
        ) revert IPRICEv2.PRICE_SubmoduleNotInstalled(asset_, abi.encode(params_.strategy.target));
    }

    function _validateUpdateAssetQueueParams(
        address asset_,
        IPRICEv2.UpdateAssetParams memory params_,
        PriceFeedExpectation[] memory feedExpectations_
    ) internal view {
        if (asset_ == PRICE.unitOfAccount()) revert IPRICEv2.PRICE_AssetReserved(asset_);

        if (!params_.updateFeeds && !params_.updateStrategy && !params_.updateMovingAverage)
            revert IPRICEv2.PRICE_NoUpdatesRequested(asset_);

        IPRICEv2.Asset memory asset = PRICE.getAssetData(asset_);
        if (!asset.approved) revert IPRICEv2.PRICE_AssetNotApproved(asset_);

        uint256 expectedCount = params_.updateFeeds ? params_.feeds.length : 0;
        if (feedExpectations_.length != expectedCount)
            revert IPriceConfigv2_FeedExpectationCountInvalid(
                asset_,
                feedExpectations_.length,
                expectedCount
            );

        if (params_.updateFeeds && params_.feeds.length == 0)
            revert IPRICEv2.PRICE_ParamsPriceFeedInsufficient(asset_, 0, 1);

        IPRICEv2.Component[] memory finalFeeds = params_.updateFeeds
            ? params_.feeds
            : abi.decode(asset.feeds, (IPRICEv2.Component[]));
        IPRICEv2.Component memory finalStrategy = params_.updateStrategy
            ? params_.strategy
            : abi.decode(asset.strategy, (IPRICEv2.Component));
        bool finalUseMA = params_.updateStrategy
            ? params_.useMovingAverage
            : asset.useMovingAverage;
        bool finalStoreMA = params_.updateMovingAverage
            ? params_.storeMovingAverage
            : asset.storeMovingAverage;

        _validateAssetConfiguration(
            asset_,
            finalStrategy,
            finalFeeds.length,
            finalUseMA,
            finalStoreMA
        );
        _validateMovingAverageParams(asset_, params_);
        _validateUpdateComponentParams(asset_, params_);
    }

    function _executeUpdateAsset(
        address asset_,
        IPRICEv2.UpdateAssetParams memory params_,
        PriceFeedExpectation[] memory feedExpectations_
    ) internal {
        uint256 expectedCount = params_.updateFeeds ? params_.feeds.length : 0;
        if (feedExpectations_.length != expectedCount)
            revert IPriceConfigv2_FeedExpectationCountInvalid(
                asset_,
                feedExpectations_.length,
                expectedCount
            );

        PRICE.updateAsset(asset_, params_);

        if (params_.updateFeeds)
            _validatePriceFeedExpectations(asset_, params_.feeds, feedExpectations_);
    }

    // ========== PRICE MANAGEMENT ========== //

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects the asset configuration
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
    ) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.addAsset(
            asset_,
            storeMovingAverage_,
            useMovingAverage_,
            movingAverageDuration_,
            lastObservationTime_,
            observations_,
            strategy_,
            feeds_
        );

        _validatePriceFeedExpectations(asset_, feeds_, feedExpectations_);
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - The removal queue parameters are invalid
    function queueRemoveAsset(
        address asset_
    ) external override onlyEnabled onlyPriceOrAdminRole returns (uint256 actionId_) {
        _validateRemoveAssetQueueParams(asset_);

        return _queueAction(IPriceConfigv2.TimelockAction.RemoveAsset, abi.encode(asset_));
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - The update queue parameters are invalid
    function queueUpdateAsset(
        address asset_,
        IPRICEv2.UpdateAssetParams memory params_,
        PriceFeedExpectation[] memory feedExpectations_
    ) external override onlyEnabled onlyPriceOrAdminRole returns (uint256 actionId_) {
        _validateUpdateAssetQueueParams(asset_, params_, feedExpectations_);

        return
            _queueAction(
                IPriceConfigv2.TimelockAction.UpdateAsset,
                abi.encode(asset_, params_, feedExpectations_)
            );
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects storing the observation
    function storeObservation(address asset_) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.storeObservation(asset_);
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects storing observations
    function storeObservations() external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.storeObservations();
    }

    // ========== SUBMODULE MANAGEMENT ========== //

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects submodule installation
    function installSubmodule(
        address submodule_
    ) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.installSubmodule(Submodule(submodule_));
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - The submodule upgrade queue parameters are invalid
    function queueUpgradeSubmodule(
        address submodule_
    ) external override onlyEnabled onlyPriceOrAdminRole returns (uint256 actionId_) {
        _validateUpgradeSubmoduleQueueParams(submodule_);

        return _queueAction(IPriceConfigv2.TimelockAction.UpgradeSubmodule, abi.encode(submodule_));
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects the submodule call
    function execOnSubmodule(
        SubKeycode subKeycode_,
        bytes calldata data_
    ) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.execOnSubmodule(subKeycode_, data_);
    }

    // ========== ERC165 ========== //

    /// @notice Query if a contract implements an interface
    /// @dev    Does not revert.
    ///
    /// @param  interfaceId The interface identifier, as specified in ERC-165
    /// @return bool        True if the contract implements `interfaceId`
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IPriceConfigv2).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
