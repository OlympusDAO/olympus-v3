// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {ITimelockQueue} from "src/policies/interfaces/utils/ITimelockQueue.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Libraries
import {Deviation} from "src/libraries/Deviation.sol";
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {Kernel, Keycode, toKeycode, Policy, Permissions, Module} from "src/Kernel.sol";
import {SubKeycode, Submodule} from "src/Submodules.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {TimelockQueue} from "src/policies/utils/TimelockQueue.sol";

/// @notice     Policy to configure PRICEv2
/// @dev        Some functions in this policy are gated to addresses with the "price_admin" or "admin" roles.
///             Timelocked actions assume an independent emergency role can cancel malicious or stale queued actions.
contract PriceConfigv2 is Policy, PolicyEnabler, TimelockQueue, IPriceConfigv2, IVersioned {
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

    // ========== POLICY SETUP ========== //

    constructor(Kernel kernel_) Policy(kernel_) TimelockQueue(MIN_TIMELOCK_DELAY) {
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

        requests = new Permissions[](10);
        // PRICE Permissions
        requests[0] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.registerNonContractAsset.selector
        });
        requests[1] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.unregisterNonContractAsset.selector
        });
        requests[2] = Permissions({keycode: PRICE_KEYCODE, funcSelector: PRICE.addAsset.selector});
        requests[3] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.removeAsset.selector
        });
        requests[4] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.updateAsset.selector
        });
        requests[5] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.installSubmodule.selector
        });
        requests[6] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.upgradeSubmodule.selector
        });
        requests[7] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.execOnSubmodule.selector
        });
        requests[8] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.storeObservation.selector
        });
        requests[9] = Permissions({
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
    ///             - The policy is disabled
    ///             - The caller does not have the `admin` role
    ///             - The delay is outside the accepted range
    function queueTimelockDelay(uint48 delay_) external override returns (uint64 actionId_) {
        return _queueAction(address(this), this.queueTimelockDelay.selector, abi.encode(delay_));
    }

    /// @inheritdoc TimelockQueue
    /// @dev        Called by `executeQueuedAction` after the standard timelock state checks and
    ///             `_validateExecution` pass. Dispatches the queued target/selector to the
    ///             corresponding PRICE or local operation.
    /// @dev        Reverts if:
    ///             - The queued target and selector pair is not supported
    ///             - The queued payload cannot be decoded for the supported action
    ///             - PRICE rejects the queued operation at execution time
    ///             - An execOnSubmodule action no longer points to the submodule implementation
    ///               that was installed when it was queued
    function _executeAction(uint64, ITimelockQueue.QueuedAction memory action_) internal override {
        if (action_.target == address(PRICE) && action_.selector == PRICE.updateAsset.selector) {
            (
                address asset,
                IPRICEv2.UpdateAssetParams memory params,
                IPriceConfigv2.PriceFeedExpectation[] memory feedExpectations
            ) = abi.decode(
                    action_.payload,
                    (address, IPRICEv2.UpdateAssetParams, IPriceConfigv2.PriceFeedExpectation[])
                );
            _executeUpdateAsset(asset, params, feedExpectations);
        } else if (
            action_.target == address(PRICE) && action_.selector == PRICE.removeAsset.selector
        ) {
            address asset = abi.decode(action_.payload, (address));
            PRICE.removeAsset(asset);
        } else if (
            action_.target == address(PRICE) && action_.selector == PRICE.upgradeSubmodule.selector
        ) {
            address submodule = abi.decode(action_.payload, (address));
            PRICE.upgradeSubmodule(Submodule(submodule));
        } else if (
            action_.target == address(PRICE) && action_.selector == PRICE.execOnSubmodule.selector
        ) {
            (SubKeycode subKeycode, address queuedSubmodule, bytes memory data) = abi.decode(
                action_.payload,
                (SubKeycode, address, bytes)
            );
            address currentSubmodule = address(PRICE.getSubmoduleForKeycode(subKeycode));
            if (currentSubmodule != queuedSubmodule)
                revert IPriceConfigv2_SubmoduleImplementationChanged(
                    SubKeycode.unwrap(subKeycode),
                    queuedSubmodule,
                    currentSubmodule
                );
            PRICE.execOnSubmodule(subKeycode, data);
        } else if (
            action_.target == address(this) && action_.selector == this.queueTimelockDelay.selector
        ) {
            uint48 delay = abi.decode(action_.payload, (uint48));
            _setTimelockDelay(delay);
        } else {
            revert ITimelockQueue_ActionInvalid(action_.target, action_.selector);
        }
    }

    /// @inheritdoc TimelockQueue
    /// @dev        Called by `_queueAction` before a queued action is stored. This is the queue-time
    ///             gate for PriceConfig actions: it checks enabled status, queue authorization,
    ///             supported target/selector pairs, and action-specific PRICE validation.
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller cannot queue the requested action
    ///             - The target/selector pair is not supported
    ///             - The payload cannot be decoded for the action
    ///             - PRICE rejects the action-specific queue parameters
    ///             - An execOnSubmodule payload does not match the currently installed submodule
    ///               implementation
    function _validateQueue(
        address caller_,
        address target_,
        bytes4 selector_,
        bytes memory payload_
    ) internal view override {
        _onlyEnabled();

        if (target_ == address(this)) {
            if (selector_ == this.queueTimelockDelay.selector) {
                // Timelock delay changes affect future queue semantics, so only admin can propose.
                if (!_isAdmin(caller_)) revert ROLESv1.ROLES_RequireRole(ADMIN_ROLE);
                _validateTimelockDelayPayload(target_, selector_, payload_);
                return;
            }
        } else if (target_ == address(PRICE)) {
            // Queue authorization happens here because execution is intentionally permissionless.
            if (!(ROLES.hasRole(caller_, _PRICE_ADMIN_ROLE) || _isAdmin(caller_)))
                revert NotAuthorised();

            if (selector_ == PRICE.removeAsset.selector) {
                _validateRemoveAssetPayload(target_, selector_, payload_);
                return;
            } else if (selector_ == PRICE.updateAsset.selector) {
                _validateUpdateAssetPayload(target_, selector_, payload_);
                return;
            } else if (selector_ == PRICE.upgradeSubmodule.selector) {
                _validateUpgradeSubmodulePayload(target_, selector_, payload_);
                return;
            } else if (selector_ == PRICE.execOnSubmodule.selector) {
                _validateExecOnSubmodulePayload(target_, selector_, payload_);
                return;
            }
        }

        revert ITimelockQueue_ActionInvalid(target_, selector_);
    }

    /// @inheritdoc TimelockQueue
    /// @dev        Called by `executeQueuedAction` after the standard timelock state checks pass
    ///             and before `_executeAction` runs. Execution is deliberately permissionless; this
    ///             hook only enforces enabled status and rejects unknown action targets/selectors.
    /// @dev        Authorization is not repeated here because the proposer was checked by
    ///             `_validateQueue`. Requiring an execution role would let an unavailable or
    ///             compromised executor block already-approved timelocked changes.
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The queued target/selector pair is not supported
    function _validateExecution(
        address,
        uint64,
        ITimelockQueue.QueuedAction memory action_
    ) internal view override {
        _onlyEnabled();

        if (action_.target == address(this)) {
            if (action_.selector == this.queueTimelockDelay.selector) return;
        } else if (action_.target == address(PRICE)) {
            if (
                action_.selector == PRICE.removeAsset.selector ||
                action_.selector == PRICE.updateAsset.selector ||
                action_.selector == PRICE.upgradeSubmodule.selector ||
                action_.selector == PRICE.execOnSubmodule.selector
            ) {
                return;
            }
        }

        revert ITimelockQueue_ActionInvalid(action_.target, action_.selector);
    }

    /// @inheritdoc TimelockQueue
    /// @dev        Called by `cancelQueuedAction` after the standard cancellable-state checks pass.
    ///             Cancellation is intentionally allowed while the policy is disabled so the
    ///             emergency role can clear malicious or stale queued actions.
    /// @dev        The emergency role is separate from the roles that can queue actions. This gives
    ///             emergency operators a narrow veto path without granting them PRICE configuration
    ///             authority or timelock-delay authority.
    /// @dev        Reverts if:
    ///             - The caller does not have the emergency role
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockQueue.QueuedAction memory
    ) internal view override {
        if (!_isEmergency(caller_)) revert ROLESv1.ROLES_RequireRole(EMERGENCY_ROLE);
    }

    /// @inheritdoc TimelockQueue
    function _validateTimelockDelay(uint48 delay_) internal pure override {
        if (delay_ < MIN_TIMELOCK_DELAY || delay_ > MAX_TIMELOCK_DELAY)
            revert ITimelockQueue_TimelockDelayInvalid(
                delay_,
                MIN_TIMELOCK_DELAY,
                MAX_TIMELOCK_DELAY
            );
    }

    /// @inheritdoc TimelockQueue
    function _executionWindow() internal pure override returns (uint48 executionWindow_) {
        return EXECUTION_WINDOW;
    }

    /// @notice Validate a queued removeAsset payload before it is stored.
    /// @dev    Called from `_validateQueue` after the caller has been authorized to queue PRICE
    ///         mutations. Uses PRICE's view validator so queue-time checks match PRICE mutation-time
    ///         invariants.
    /// @dev    Reverts if the payload cannot be decoded as an address or PRICE rejects removing
    ///         the decoded asset.
    function _validateRemoveAssetPayload(address, bytes4, bytes memory payload_) internal view {
        address asset = abi.decode(payload_, (address));
        PRICE.validateRemoveAsset(asset);
    }

    /// @notice Validate a queued updateAsset payload before it is stored.
    /// @dev    Called from `_validateQueue` after the caller has been authorized to queue PRICE
    ///         mutations. Keeps feed expectation count validation in this policy because feed
    ///         expectations are a PriceConfig safety check, then uses PRICE's view validator for
    ///         PRICE-owned invariants.
    /// @dev    Reverts if the payload cannot be decoded as updateAsset parameters, has an invalid
    ///         feed expectation count, or PRICE rejects the decoded update parameters.
    function _validateUpdateAssetPayload(address, bytes4, bytes memory payload_) internal view {
        (
            address asset,
            IPRICEv2.UpdateAssetParams memory params,
            IPriceConfigv2.PriceFeedExpectation[] memory feedExpectations
        ) = abi.decode(
                payload_,
                (address, IPRICEv2.UpdateAssetParams, IPriceConfigv2.PriceFeedExpectation[])
            );
        _validateUpdateFeedExpectationCount(
            asset,
            params.updateFeeds ? params.feeds.length : 0,
            feedExpectations
        );
        PRICE.validateUpdateAsset(asset, params);
    }

    /// @notice Validate a queued upgradeSubmodule payload before it is stored.
    /// @dev    Called from `_validateQueue` after the caller has been authorized to queue PRICE
    ///         mutations. Uses PRICE's view validator so queue-time checks match PRICE submodule
    ///         upgrade invariants.
    /// @dev    Reverts if the payload cannot be decoded as an address or PRICE rejects upgrading
    ///         to the decoded submodule.
    function _validateUpgradeSubmodulePayload(
        address,
        bytes4,
        bytes memory payload_
    ) internal view {
        address submodule = abi.decode(payload_, (address));
        PRICE.validateUpgradeSubmodule(submodule);
    }

    /// @notice Validate a queued execOnSubmodule payload before it is stored.
    /// @dev    Called from `_validateQueue` after the caller has been authorized to queue PRICE
    ///         mutations. Binds the queued call to the current submodule implementation so a later
    ///         submodule upgrade cannot silently redirect already-reviewed calldata to different
    ///         code.
    /// @dev    Reverts if the payload cannot be decoded as execOnSubmodule parameters, PRICE
    ///         rejects the decoded subkeycode, or the decoded submodule implementation does not
    ///         match the currently installed submodule.
    function _validateExecOnSubmodulePayload(address, bytes4, bytes memory payload_) internal view {
        SubKeycode subKeycode;
        address queuedSubmodule;
        (subKeycode, queuedSubmodule, ) = abi.decode(payload_, (SubKeycode, address, bytes));

        PRICE.validateExecOnSubmodule(SubKeycode.unwrap(subKeycode));
        address currentSubmodule = address(PRICE.getSubmoduleForKeycode(subKeycode));
        if (currentSubmodule != queuedSubmodule)
            revert IPriceConfigv2_SubmoduleImplementationChanged(
                SubKeycode.unwrap(subKeycode),
                queuedSubmodule,
                currentSubmodule
            );
    }

    /// @notice Validate a queued timelock delay payload before it is stored.
    /// @dev    Called by `_validateQueue` for local timelock delay updates after the caller has
    ///         been authorized as admin. Delay updates affect all future queued actions, so invalid
    ///         delays are rejected before the action is stored.
    /// @dev    Reverts if the payload cannot be decoded as a `uint48`, or the decoded delay is
    ///         outside the accepted range.
    ///
    /// @param payload_  The encoded queued action payload.
    function _validateTimelockDelayPayload(address, bytes4, bytes memory payload_) internal pure {
        uint48 delay = abi.decode(payload_, (uint48));
        _validateTimelockDelay(delay);
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

    function _validateUpdateFeedExpectationCount(
        address asset_,
        uint256 expectedCount_,
        PriceFeedExpectation[] memory feedExpectations_
    ) internal pure {
        if (feedExpectations_.length != expectedCount_)
            revert IPriceConfigv2_FeedExpectationCountInvalid(
                asset_,
                feedExpectations_.length,
                expectedCount_
            );
    }

    function _executeUpdateAsset(
        address asset_,
        IPRICEv2.UpdateAssetParams memory params_,
        PriceFeedExpectation[] memory feedExpectations_
    ) internal {
        _validateUpdateFeedExpectationCount(
            asset_,
            params_.updateFeeds ? params_.feeds.length : 0,
            feedExpectations_
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
    ///             - `asset_` is the zero address
    ///             - `asset_` is a contract
    ///             - `asset_` is reserved or otherwise invalid under PRICE rules
    ///             - `asset_` is already registered as a non-contract asset
    ///             - PRICE rejects the registration
    function registerNonContractAsset(
        address asset_
    ) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.registerNonContractAsset(asset_);
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects the deregistration
    function unregisterNonContractAsset(
        address asset_
    ) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.unregisterNonContractAsset(asset_);
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects the asset configuration
    ///             - Any feed expectation is invalid or outside the accepted tolerance
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
    function queueRemoveAsset(address asset_) external override returns (uint64 actionId_) {
        return _queueAction(address(PRICE), PRICE.removeAsset.selector, abi.encode(asset_));
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
    ) external override returns (uint64 actionId_) {
        return
            _queueAction(
                address(PRICE),
                PRICE.updateAsset.selector,
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
        PRICE.validateInstallSubmodule(submodule_);

        PRICE.installSubmodule(Submodule(submodule_));
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - The submodule upgrade queue parameters are invalid
    function queueUpgradeSubmodule(
        address submodule_
    ) external override returns (uint64 actionId_) {
        return
            _queueAction(address(PRICE), PRICE.upgradeSubmodule.selector, abi.encode(submodule_));
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - The submodule execution queue parameters are invalid
    function queueExecOnSubmodule(
        bytes20 subKeycode_,
        bytes calldata data_
    ) external override returns (uint64 actionId_) {
        SubKeycode subKeycode = SubKeycode.wrap(subKeycode_);
        address submodule = address(PRICE.getSubmoduleForKeycode(subKeycode));

        return
            _queueAction(
                address(PRICE),
                PRICE.execOnSubmodule.selector,
                abi.encode(subKeycode, submodule, data_)
            );
    }

    // ========== ERC165 ========== //

    /// @notice Query if a contract implements an interface
    /// @dev    Does not revert.
    ///
    /// @param  interfaceId The interface identifier, as specified in ERC-165
    /// @return bool        True if the contract implements `interfaceId`
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(PolicyEnabler, TimelockQueue) returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IPriceConfigv2).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            PolicyEnabler.supportsInterface(interfaceId) ||
            TimelockQueue.supportsInterface(interfaceId);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
