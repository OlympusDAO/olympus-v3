// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @title Price Cacher Task
/// @notice Heart task that refreshes an admin-configured set of PriceCache pairs.
/// @dev Pair configuration is independent from every cache consumer.
///      Calls are not gas bounded. A cache call that consumes nearly all available gas can prevent
///      later pairs, later Heart tasks, or Heart finalization despite ordinary revert isolation.
contract PriceCacherTask is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    IPriceCacherTask,
    IVersioned,
    IPeriodicTask
{
    /// @notice Initial window, in seconds, for re-enablement after a lifecycle transition.
    uint32 internal constant _INITIAL_REENABLE_GRACE_PERIOD = 7 days;

    /// @notice Delegated role permitted to manage the configured pair set alongside admin.
    bytes32 internal constant _PRICE_ADMIN_ROLE = "price_admin";

    /// @notice PriceCache used to validate configured pairs and refresh their cached prices.
    IPriceCache internal _PRICE_CACHE;

    /// @notice Configured pairs in traversal order; removal may reorder the remaining pairs.
    AssetPair[] internal _assetPairs;

    /// @notice Binds a compatible cache without requiring it to be operational during deployment.
    /// @dev Reverts if:
    ///      - The cache is zero (PriceCacherTask_ZeroAddress).
    ///      - The cache lacks IPriceCache or IEnabler (PriceCacherTask_InvalidPriceCache).
    ///      - The cache's Kernel getter fails or returns malformed data (PolicyDependency_InvalidDependency).
    ///      - The cache reports another Kernel (PolicyDependency_KernelMismatch).
    ///
    /// @param kernel_ Kernel supplying this task's roles.
    /// @param priceCache_ Initial pair cache, which may be inactive or disabled until activation.
    constructor(
        Kernel kernel_,
        IPriceCache priceCache_
    ) Policy(kernel_) ReEnablerGracePeriod(_INITIAL_REENABLE_GRACE_PERIOD) {
        _requireCacheInterfaces(address(priceCache_));
        PolicyDependency.requireSameKernel(address(priceCache_), address(kernel_));
        _PRICE_CACHE = priceCache_;
    }

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - The Kernel has no ROLES module (Policy_ModuleDoesNotExist).
    ///      - The ROLES version getter reverts or returns malformed data.
    ///      - The ROLES major version is not 1 (Policy_WrongModuleVersion).
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        // ROLES compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = Module(address(ROLES)).VERSION();
        if (rolesMajor != 1) revert Policy_WrongModuleVersion(abi.encode([1]));
    }

    /// @inheritdoc Policy
    /// @dev Revert conditions: none.
    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    /// @dev Revert conditions: none.
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @inheritdoc IPeriodicTask
    /// @dev Authorization and Kernel activity are checked before the disabled no-op.
    ///      Self-call failures emit ExecutionFailed; calls are not gas bounded.
    ///      Reverts if:
    ///      - The caller lacks HEART_ROLE (ROLES_RequireRole).
    ///      - This task is Kernel-inactive (PriceCacherTask_PolicyInactive).
    ///      - The unbounded self-call or revert-data handling leaves insufficient gas to finish.
    function execute() external override {
        _requireOwnPolicyActive();
        _requireRole(msg.sender, HEART_ROLE);
        if (!isEnabled) return;

        try this.selfExecuteTask() {} catch (bytes memory reason) {
            // forge-lint: disable-next-line(unsafe-typecast)
            emit ExecutionFailed(bytes4(reason));
        }
    }

    /// @notice Runs cache maintenance through an external self-call.
    /// @dev Reverts if:
    ///      - The caller is not this contract (PriceCacherTask_OnlySelf).
    ///      - The cache is Kernel-inactive or disabled (PolicyDependency_NotActive).
    ///      - The active cache's enabled-state getter reverts or returns malformed data.
    ///      - Unbounded cache calls or failure reporting exhaust the available gas.
    ///      execute catches and reports these failures to Heart; pair failures are caught separately.
    function selfExecuteTask() external {
        if (msg.sender != address(this)) revert PriceCacherTask_OnlySelf();

        address priceCache_ = address(_PRICE_CACHE);
        if (!kernel.isPolicyActive(Policy(priceCache_)) || !IEnabler(priceCache_).isEnabled())
            revert PolicyDependency.PolicyDependency_NotActive(priceCache_);

        uint256 length = _assetPairs.length;
        for (uint256 i; i < length; ++i) {
            _cachePair(priceCache_, _assetPairs[i]);
        }
    }

    /// @inheritdoc IPriceCacherTask
    /// @dev Callable while locally enabled or disabled. The unchanged check precedes compatibility probes.
    ///      Reverts if:
    ///      - The caller lacks ADMIN_ROLE (ROLES_RequireRole).
    ///      - This task is Kernel-inactive (PriceCacherTask_PolicyInactive).
    ///      - The candidate is already selected (PriceCacherTask_UnchangedAddress).
    ///      - The candidate is zero (PriceCacherTask_ZeroAddress).
    ///      - The candidate lacks IPriceCache or IEnabler (PriceCacherTask_InvalidPriceCache).
    ///      - The candidate's Kernel getter fails or returns malformed data (PolicyDependency_InvalidDependency).
    ///      - The candidate reports another Kernel (PolicyDependency_KernelMismatch).
    ///      - The candidate rejects any configured pair; its validation error is propagated.
    function setPriceCache(address priceCache_) external override {
        _requireOwnPolicyActive();
        _requireRole(msg.sender, ADMIN_ROLE);
        if (priceCache_ == address(_PRICE_CACHE))
            revert PriceCacherTask_UnchangedAddress(priceCache_);
        _requireCacheInterfaces(priceCache_);
        PolicyDependency.requireSameKernel(priceCache_, address(kernel));
        IPriceCache candidate = IPriceCache(priceCache_);
        uint256 length = _assetPairs.length;
        for (uint256 i; i < length; ++i) {
            AssetPair memory pair = _assetPairs[i];
            // Each configured pair must remain valid on cache rotation.
            // forge-lint: disable-next-line(calls-loop)
            candidate.validateAssetPair(pair.asset, pair.quote);
        }
        _PRICE_CACHE = IPriceCache(priceCache_);
        emit PriceCacheSet(priceCache_);
    }

    /// @inheritdoc IPriceCacherTask
    /// @dev Callable while locally enabled or disabled. Reverts if:
    ///      - The caller holds neither price_admin nor admin (NotAuthorised).
    ///      - This task is Kernel-inactive (PriceCacherTask_PolicyInactive).
    ///      - Either leg is zero or the legs are identical (PriceCacherTask_InvalidAssetPair).
    ///      - The pair is already configured in either orientation (PriceCacherTask_AssetPairAlreadyAdded).
    ///      - The cache rejects the pair; its validation error is propagated.
    function addAssetPair(address asset_, address quote_) external override {
        _requireOwnPolicyActive();
        _requirePriceOrAdminRole();
        _validateAssetPair(asset_, quote_);
        if (_findAssetPair(asset_, quote_) != type(uint256).max) {
            revert PriceCacherTask_AssetPairAlreadyAdded(asset_, quote_);
        }
        _PRICE_CACHE.validateAssetPair(asset_, quote_);

        _assetPairs.push(AssetPair({asset: asset_, quote: quote_}));
        emit AssetPairAdded(asset_, quote_);
    }

    /// @inheritdoc IPriceCacherTask
    /// @dev Callable while locally enabled or disabled, without consulting the cache. Reverts if:
    ///      - The caller holds neither price_admin nor admin (NotAuthorised).
    ///      - This task is Kernel-inactive (PriceCacherTask_PolicyInactive).
    ///      - Either leg is zero or the legs are identical (PriceCacherTask_InvalidAssetPair).
    ///      - Neither orientation of the pair is configured (PriceCacherTask_AssetPairNotFound).
    function removeAssetPair(address asset_, address quote_) external override {
        _requireOwnPolicyActive();
        _requirePriceOrAdminRole();
        _validateAssetPair(asset_, quote_);
        uint256 index = _findAssetPair(asset_, quote_);
        if (index == type(uint256).max) revert PriceCacherTask_AssetPairNotFound(asset_, quote_);

        AssetPair memory removedPair = _assetPairs[index];
        uint256 lastIndex = _assetPairs.length - 1;
        if (index != lastIndex) _assetPairs[index] = _assetPairs[lastIndex];
        _assetPairs.pop();
        emit AssetPairRemoved(removedPair.asset, removedPair.quote);
    }

    /// @inheritdoc IPriceCacherTask
    /// @dev Revert conditions: none.
    function priceCache() external view override returns (address priceCache_) {
        return address(_PRICE_CACHE);
    }

    /// @inheritdoc IPriceCacherTask
    /// @dev Revert conditions: none.
    function getAssetPairs() external view override returns (AssetPair[] memory pairs) {
        return _assetPairs;
    }

    /// @notice Authorizes fast re-enablement by price admin or governance.
    /// @dev Reverts if:
    ///      - The caller holds neither price_admin nor admin (NotAuthorised).
    function _authorizeReEnable() internal view override {
        _requirePriceOrAdminRole();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - This policy is locally disabled.
    ///      - The caller lacks ADMIN.
    ///      - The requested period is zero.
    function setGracePeriod(uint32 period_) public override {
        _requireOwnPolicyActive();
        super.setGracePeriod(period_);
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The caller lacks ADMIN_ROLE (ROLES_RequireRole).
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @inheritdoc IPeriodicTask
    /// @dev Revert conditions: none.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(EnablerV2, ReEnablerGracePeriod, IPeriodicTask) returns (bool) {
        return
            interfaceId_ == type(IPeriodicTask).interfaceId ||
            interfaceId_ == type(IPriceCacherTask).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @notice Requires price administration or governance authority.
    /// @dev Reverts if:
    ///      - The caller holds neither price_admin nor admin (NotAuthorised).
    function _requirePriceOrAdminRole() private view {
        if (!ROLES.hasRole(msg.sender, _PRICE_ADMIN_ROLE) && !_isAdmin(msg.sender))
            revert NotAuthorised();
    }

    /// @notice Requires a nonzero cache with the interfaces consumed by this task.
    /// @dev Callers check Kernel compatibility or operational readiness through PolicyDependency.
    ///      Reverts if:
    ///      - The cache is zero (PriceCacherTask_ZeroAddress).
    ///      - The cache lacks IPriceCache or IEnabler (PriceCacherTask_InvalidPriceCache).
    ///
    /// @param priceCache_ Candidate cache.
    function _requireCacheInterfaces(address priceCache_) private view {
        if (priceCache_ == address(0)) revert PriceCacherTask_ZeroAddress();
        bytes4[] memory interfaceIds = new bytes4[](2);
        interfaceIds[0] = type(IPriceCache).interfaceId;
        interfaceIds[1] = type(IEnabler).interfaceId;
        if (!ERC165Checker.supportsAllInterfaces(priceCache_, interfaceIds))
            revert PriceCacherTask_InvalidPriceCache(priceCache_);
    }

    /// @notice Checks only the pair's address shape, without consulting the selected cache.
    /// @dev Cache support is checked separately when adding or rotating pairs. Removal must remain
    ///      possible after a pair becomes unsupported or its cache becomes unavailable. Reverts if:
    ///      - Either leg is zero or both legs identify the same asset (PriceCacherTask_InvalidAssetPair).
    ///
    /// @param asset_ Asset leg.
    /// @param quote_ Quote leg.
    function _validateAssetPair(address asset_, address quote_) private pure {
        if (asset_ == address(0) || quote_ == address(0) || asset_ == quote_) {
            revert PriceCacherTask_InvalidAssetPair();
        }
    }

    /// @notice Finds a configured pair in either asset/quote orientation.
    /// @dev Revert conditions: none.
    ///
    /// @param asset_ First pair leg.
    /// @param quote_ Second pair leg.
    /// @return index Pair index, or uint256.max when neither orientation is configured.
    function _findAssetPair(address asset_, address quote_) private view returns (uint256 index) {
        uint256 length = _assetPairs.length;
        for (uint256 i; i < length; ++i) {
            AssetPair memory pair = _assetPairs[i];
            // PriceCache keys pairs independently of request direction, so reversed semantic
            // requests share one snapshot and must not be configured twice.
            if (
                (pair.asset == asset_ && pair.quote == quote_) ||
                (pair.asset == quote_ && pair.quote == asset_)
            ) return i;
        }
        return type(uint256).max;
    }

    /// @notice Attempts one pair refresh and reports failure while allowing later pairs to run.
    /// @dev Letting a pair failure reach execute's self-call catch would roll back earlier pairs
    ///      and skip the rest of the batch. This catch emits PairCacheFailed without rethrowing.
    ///      Reverts if:
    ///      - The unbounded cache call or revert-data handling leaves insufficient gas to report failure.
    ///
    /// @param priceCache_ Cache used for this execution.
    /// @param pair_ Configured pair to refresh.
    function _cachePair(address priceCache_, AssetPair memory pair_) private {
        // External calls are the purpose of this governance-configured pair iteration.
        // forge-lint: disable-next-line(calls-loop)
        try IPriceCache(priceCache_).cachePriceIfNecessary(pair_.asset, pair_.quote, 0) returns (
            IPriceCache.CachedPrice memory
        ) {} catch (bytes memory reason) {
            // forge-lint: disable-next-line(unsafe-typecast)
            emit PairCacheFailed(priceCache_, pair_.asset, pair_.quote, bytes4(reason));
        }
    }

    /// @notice Requires this task to remain installed in its Kernel.
    /// @dev Reverts if:
    ///      - This task is Kernel-inactive (PriceCacherTask_PolicyInactive).
    function _requireOwnPolicyActive() private view {
        if (!kernel.isPolicyActive(this)) revert PriceCacherTask_PolicyInactive(address(this));
    }

    /// @notice Requires a compatible cache that is active in this task's Kernel and enabled.
    /// @dev Compatibility precedes readiness; malformed status is not a pause. Reverts if:
    ///      - The cache is zero (PriceCacherTask_ZeroAddress).
    ///      - The cache lacks IPriceCache or IEnabler (PriceCacherTask_InvalidPriceCache).
    ///      - Kernel or enabled-state metadata fails or is malformed (PolicyDependency_InvalidDependency).
    ///      - The cache reports another Kernel (PolicyDependency_KernelMismatch).
    ///      - The cache is Kernel-inactive or disabled (PolicyDependency_NotActive).
    function _requireCacheReady() private view {
        address cache = address(_PRICE_CACHE);
        _requireCacheInterfaces(cache);
        PolicyDependency.requireActiveAndEnabled(cache, address(kernel));
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty (PriceCacherTask_InvalidData).
    ///      - This task is Kernel-inactive (PriceCacherTask_PolicyInactive).
    ///      - The cache fails any interface, metadata, Kernel or readiness check in _requireCacheReady.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert PriceCacherTask_InvalidData();
        _requireOwnPolicyActive();
        _requireCacheReady();
    }

    /// @inheritdoc EnablerV2
    /// @dev Kernel inactivity does not prevent disable. Reverts if:
    ///      - The unused lifecycle data is nonempty (PriceCacherTask_InvalidData).
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert PriceCacherTask_InvalidData();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The grace deadline exceeds uint48 (SafeCastOverflowedUintDowncast).
    ///      - The current timestamp exceeds the inclusive grace deadline (GracePeriod_Expired).
    ///      - This task is Kernel-inactive (PriceCacherTask_PolicyInactive).
    ///      - The cache fails any interface, metadata, Kernel or readiness check in _requireCacheReady.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireOwnPolicyActive();
        _requireCacheReady();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The widened deadline exceeds uint48 (SafeCastOverflowedUintDowncast).
    ///      - The current timestamp exceeds the inclusive deadline (GracePeriod_Expired).
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }
}
