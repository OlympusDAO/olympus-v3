// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorRescue} from "src/policies/interfaces/IRevenueDistributorRescue.sol";
import {IYieldRepurchaseRecipient} from "src/policies/interfaces/IYieldRepurchaseRecipient.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {Math} from "@openzeppelin-5.7.0/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin-5.7.0/utils/structs/EnumerableSet.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeCall} from "src/libraries/SafeCall.sol";

// Contracts
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {ConfigOperatorSingleStep} from "src/policies/utils/ConfigOperatorSingleStep.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Revenue Distributor
/// @notice Holds received ERC-20 assets and settles each managed asset under one distribution.
/// @dev Incoming ERC-20 transfers require no call to this policy. Source contracts can continue
///      sending during local disablement or Kernel deactivation; settlement is paused then.
contract RevenueDistributor is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigOperatorSingleStep,
    ReentrancyGuard,
    IRevenueDistributor,
    IRevenueDistributorRescue,
    IVersioned
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for ERC20;
    using SafeCall for address;

    /// @dev Basis-point denominator for each distribution route.
    uint256 internal constant _BPS = 10_000;
    /// @dev VaultConfig returns four ABI words: vault, share token, underlying asset, and enabled.
    uint16 internal constant _VAULT_CONFIG_RETURN_SIZE = 128;
    /// @dev Copy one extra byte so oversized responses fail the exact-length check.
    uint16 internal constant _MAX_VAULT_CONFIG_RETURN_SIZE = _VAULT_CONFIG_RETURN_SIZE + 1;
    /// @dev Time after disablement in which the policy may be re-enabled.
    uint32 internal constant _REENABLE_GRACE_PERIOD = 7 days;

    /// @dev Stored allocation for an active asset.
    struct StoredRoute {
        uint16 repurchaseBps;
        AssetRoute[] routes;
    }

    /// @dev Current Treasury module, refreshed when Kernel dependencies are configured.
    TRSRYv1 internal _TRSRY;
    /// @dev Current recipient of repurchase shares, or zero to route them to Treasury.
    address internal _yieldRecipient;
    /// @dev Historical management state of each asset.
    mapping(address asset => AssetState state) internal _assetStates;
    /// @dev Current allocation route for each active asset.
    mapping(address asset => StoredRoute route) internal _routes;
    /// @dev Assets currently eligible for distribution.
    EnumerableSet.AddressSet internal _activeAssets;
    /// @dev Assets with at least one unpaid distribution.
    EnumerableSet.AddressSet internal _pendingAssets;
    /// @dev Sum of all unpaid shares for an asset. Subtracting it from custody prevents a later
    ///      distribution or rescue from spending tokens already owed to any recipient.
    mapping(address asset => uint256 amount) internal _totalPending;
    /// @dev Treasury liability for each asset, following the current Treasury module.
    mapping(address asset => uint256 amount) internal _pendingTreasury;
    /// @dev Repurchase liability for each asset, following the current yield recipient.
    mapping(address asset => uint256 amount) internal _pendingYieldRecipient;
    /// @dev Liabilities to configured recipients, fixed to their original addresses.
    mapping(address asset => mapping(address recipient => uint256 amount))
        internal _pendingConfiguredDistributions;
    /// @dev Configured recipient addresses with unpaid distributions, including former routes.
    mapping(address asset => EnumerableSet.AddressSet recipients)
        internal _pendingConfiguredRecipients;

    constructor(Kernel kernel_) Policy(kernel_) ReEnablerGracePeriod(_REENABLE_GRACE_PERIOD) {}

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - The ROLES or TRSRY module has an incompatible major version.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        _TRSRY = TRSRYv1(getModuleAddress(dependencies[1]));

        // The two module dependencies are compatible across minor versions.
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = Module(address(ROLES)).VERSION();
        // forge-lint: disable-next-line(unused-return)
        (uint8 treasuryMajor, ) = Module(address(_TRSRY)).VERSION();
        if (rolesMajor != 1 || treasuryMajor != 1) {
            revert Policy_WrongModuleVersion(abi.encode([1]));
        }
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @inheritdoc IRevenueDistributor
    /// @dev Reverts if:
    ///      - The caller is neither admin nor the selected operator, or the policy is inactive or disabled.
    ///      - The asset or any route entry is invalid or duplicated.
    ///      - The basis-point total exceeds 10,000 or the repurchase recipient cannot accept the asset.
    function setAssetRoutes(
        address asset_,
        uint16 repurchaseBps_,
        AssetRoute[] calldata routes_
    ) external override nonReentrant {
        _requireActiveAndEnabled();
        _requireConfigOperatorOrAdmin();
        _validateAssetRoutes(asset_, repurchaseBps_, routes_);

        if (_assetStates[asset_] != AssetState.Active) {
            _activeAssets.add(asset_);
            _assetStates[asset_] = AssetState.Active;
        }
        // Replace the route for future receipts. Existing configured liabilities retain their
        // original recipients, so route changes never redirect an unpaid share.
        _routes[asset_].repurchaseBps = repurchaseBps_;
        delete _routes[asset_].routes;
        for (uint256 i; i < routes_.length; ++i) {
            _routes[asset_].routes.push(routes_[i]);
        }
        emit AssetDistributionSet(asset_, repurchaseBps_, routes_);
    }

    /// @inheritdoc IRevenueDistributor
    /// @dev Reverts if:
    ///      - The policy is Kernel-inactive or locally disabled.
    ///      - The asset or any route entry is invalid or duplicated.
    ///      - The basis-point total exceeds 10,000 or the yield recipient cannot accept the asset.
    function validateSetAssetRoutes(
        address asset_,
        uint16 repurchaseBps_,
        AssetRoute[] calldata routes_
    ) external view override {
        _requireActiveAndEnabled();
        _validateAssetRoutes(asset_, repurchaseBps_, routes_);
    }

    function _validateAssetRoutes(
        address asset_,
        uint16 repurchaseBps_,
        AssetRoute[] calldata routes_
    ) internal view {
        if (asset_ == address(0) || asset_.code.length == 0) {
            revert RevenueDistributor_InvalidAsset(asset_);
        }
        if (repurchaseBps_ != 0) _requireYieldRecipientForAsset(_yieldRecipient, asset_);

        // Use a wide accumulator so an invalid sum cannot overflow before the bounds check.
        uint256 totalBps = repurchaseBps_;
        address treasury_ = address(_TRSRY);
        // Each invalid route entry must be rejected before storing the route.
        // forge-lint: disable-start(require-revert-in-loop)
        for (uint256 i; i < routes_.length; ++i) {
            AssetRoute calldata share = routes_[i];
            if (_isInvalidConfiguredRecipient(share.recipient, treasury_)) {
                revert RevenueDistributor_InvalidRecipient(share.recipient);
            }
            if (share.bps == 0) {
                revert RevenueDistributor_ZeroRecipientBasisPoints(share.recipient);
            }
            for (uint256 j; j < i; ++j) {
                if (routes_[j].recipient == share.recipient) {
                    revert RevenueDistributor_DuplicateRecipient(share.recipient);
                }
            }
            totalBps += share.bps;
        }
        // forge-lint: disable-end(require-revert-in-loop)
        if (totalBps > _BPS) revert RevenueDistributor_InvalidBasisPoints(totalBps);
    }

    /// @inheritdoc IRevenueDistributor
    /// @dev Reverts if:
    ///      - The caller is neither admin nor the selected operator, or the policy is inactive or disabled.
    ///      - The asset has no active distribution.
    ///      Its managed identity persists after disablement.
    function disableAssetRoutes(address asset_) external override nonReentrant {
        _requireActiveAndEnabled();
        _requireConfigOperatorOrAdmin();
        _validateDisableAssetRoutes(asset_);
        _activeAssets.remove(asset_);
        _assetStates[asset_] = AssetState.Retired;
        delete _routes[asset_];
        emit AssetDistributionDisabled(asset_);
    }

    /// @inheritdoc IRevenueDistributor
    /// @dev Reverts if:
    ///      - The policy is Kernel-inactive or locally disabled.
    ///      - The asset has no active distribution.
    function validateDisableAssetRoutes(address asset_) external view override {
        _requireActiveAndEnabled();
        _validateDisableAssetRoutes(asset_);
    }

    function _validateDisableAssetRoutes(address asset_) internal view {
        if (_assetStates[asset_] != AssetState.Active) {
            revert RevenueDistributor_AssetNotActive(asset_);
        }
    }

    /// @inheritdoc IRevenueDistributor
    /// @dev Reverts if:
    ///      - The caller is neither admin nor the selected operator, or the policy is inactive or disabled.
    ///      - The pointer is unchanged, or the recipient is invalid, duplicates a configured recipient, or cannot accept an
    ///        asset with an active route or a pending repurchase share.
    // Zero deliberately clears the optional role destination; _validateYieldRecipient checks every active route.
    // forge-lint: disable-next-line(missing-zero-check)
    function setYieldRecipient(address recipient_) external override nonReentrant {
        _requireActiveAndEnabled();
        _requireConfigOperatorOrAdmin();
        _validateYieldRecipient(recipient_);
        _yieldRecipient = recipient_;
        emit YieldRecipientSet(recipient_);
    }

    /// @inheritdoc IRevenueDistributor
    /// @dev Reverts if:
    ///      - The policy is Kernel-inactive or locally disabled.
    ///      - The pointer is unchanged, or the recipient is invalid, duplicates a configured recipient, or cannot accept an
    ///        asset with an active route or pending yield share.
    function validateSetYieldRecipient(address recipient_) external view override {
        _requireActiveAndEnabled();
        _validateYieldRecipient(recipient_);
    }

    function _validateYieldRecipient(address recipient_) internal view {
        if (recipient_ == _yieldRecipient) revert RevenueDistributor_SameAddress(recipient_);
        // A role destination must not also be configured as an ordinary recipient. Treasury
        // receives every route's residual, so selecting it as the yield recipient would merge
        // two independently accounted shares.
        if (recipient_ == address(_TRSRY)) {
            revert RevenueDistributor_InvalidYieldRecipient(recipient_);
        }
        if (recipient_ != address(0)) _requireYieldRecipientPolicy(recipient_);
        // Future repurchase shares must be deliverable under every active route. A nonzero
        // recipient also cannot overlap a configured recipient on any active route.
        uint256 count = _activeAssets.length();
        for (uint256 i; i < count; ++i) {
            address asset_ = _activeAssets.at(i);
            if (_routes[asset_].repurchaseBps != 0) {
                _requireYieldRecipientForAsset(recipient_, asset_);
            }
            // Routes keep shares in an array so each address stays paired with its bps and order.
            // A second stored set would duplicate route state for this configuration-time scan.
            if (recipient_ != address(0)) {
                for (uint256 j; j < _routes[asset_].routes.length; ++j) {
                    if (_routes[asset_].routes[j].recipient == recipient_) {
                        // Reject a role destination that duplicates a configured recipient.
                        // forge-lint: disable-next-line(require-revert-in-loop)
                        revert RevenueDistributor_DuplicateRecipient(recipient_);
                    }
                }
            }
        }
        // Retired routes are gone, but their unpaid repurchase shares follow the current yield
        // recipient. Validate those assets before redirecting an existing obligation.
        if (recipient_ != address(0)) {
            uint256 pendingCount = _pendingAssets.length();
            for (uint256 i; i < pendingCount; ++i) {
                address asset_ = _pendingAssets.at(i);
                if (_pendingYieldRecipient[asset_] != 0) {
                    _requireYieldRecipientForAsset(recipient_, asset_);
                }
            }
        }
    }

    /// @inheritdoc IRevenueDistributor
    /// @dev Reverts if:
    ///      - The policy is disabled or Kernel-inactive.
    ///      - The asset has no active distribution.
    ///      - Custody is below reserved payouts.
    ///      - A Treasury upgrade made a configured recipient equal to the current Treasury.
    ///      A failed individual transfer leaves only that recipient's share pending.
    function distribute(address asset_) external override nonReentrant {
        _requireActiveAndEnabled();
        if (_assetStates[asset_] != AssetState.Active) {
            revert RevenueDistributor_AssetNotActive(asset_);
        }

        ERC20 token = ERC20(asset_);
        uint256 balance = token.balanceOf(address(this));
        if (balance < _totalPending[asset_]) {
            revert RevenueDistributor_InsufficientPayoutBalance(asset_);
        }
        // The live balance includes earlier failed payouts. Only receipts above that reserved
        // liability may be allocated again.
        uint256 newReceipts = balance - _totalPending[asset_];

        StoredRoute storage route = _routes[asset_];
        if (newReceipts != 0) {
            uint256 newAllocated;
            // Reserve every share before attempting transfers. A failed recipient therefore stays
            // owed, and later distribute calls cannot allocate its tokens a second time.
            if (route.repurchaseBps != 0) {
                // newReceipts (token units) * BPS / 10_000 (BPS) = token units, rounded down.
                uint256 repurchaseAmount = FullMath.mulDiv(newReceipts, route.repurchaseBps, _BPS);
                _pendingYieldRecipient[asset_] += repurchaseAmount;
                newAllocated = repurchaseAmount;
            }
            for (uint256 i; i < route.routes.length; ++i) {
                AssetRoute storage share = route.routes[i];
                // A route was valid when stored, but a later module upgrade can make a configured
                // recipient the current Treasury. Reject new allocations: otherwise that address
                // would receive both a configured share and the implicit Treasury remainder.
                // Previously reserved shares keep their original accounting and can be retried.
                if (share.recipient == address(_TRSRY)) {
                    // Route entries must be checked while traversing the configured recipients.
                    // forge-lint: disable-next-line(require-revert-in-loop)
                    revert RevenueDistributor_InvalidRecipient(share.recipient);
                }
                // Each independent share rounds down so all dust remains with Treasury.
                uint256 amount = FullMath.mulDiv(newReceipts, share.bps, _BPS);
                if (amount != 0) {
                    // Each recipient's unpaid share must be reserved separately.
                    // forge-lint: disable-next-line(costly-loop)
                    _pendingConfiguredDistributions[asset_][share.recipient] += amount;
                    _pendingConfiguredRecipients[asset_].add(share.recipient);
                    newAllocated += amount;
                }
            }
            // Treasury receives the unallocated residual, including per-recipient rounding dust.
            // The total reserve grows by exactly the receipts allocated in this call.
            _pendingTreasury[asset_] += newReceipts - newAllocated;
            _totalPending[asset_] += newReceipts;
            _pendingAssets.add(asset_);
        }

        // Without new receipts, this only retries historical liabilities; no route validation or
        // allocation is needed. Try destinations on the current route. Former configured recipients
        // remain available for direct retry through the pending-recipient view.
        _transferCurrentPayouts(asset_, route);
    }

    /// @inheritdoc IRevenueDistributor
    /// @dev Reverts if:
    ///      - The policy is Kernel-inactive or locally disabled.
    ///      Asset retirement does not block a retry while the policy is enabled.
    function transferPendingPayout(
        address asset_,
        address recipient_
    ) external override nonReentrant {
        _requirePolicyActive();
        _requireEnabled();
        _transferPendingPayout(asset_, recipient_);
    }

    /// @inheritdoc IRevenueDistributor
    function pendingPayout(
        address asset_,
        address recipient_
    ) external view override returns (uint256) {
        return _pendingAmount(asset_, recipient_);
    }

    /// @inheritdoc IRevenueDistributor
    function getPendingPayoutAssets() external view override returns (address[] memory) {
        return _pendingAssets.values();
    }

    /// @inheritdoc IRevenueDistributor
    function getPendingPayoutRecipients(
        address asset_
    ) external view override returns (address[] memory recipients) {
        EnumerableSet.AddressSet storage configuredSet = _pendingConfiguredRecipients[asset_];
        address[] memory configured = configuredSet.values();
        // The stored set contains only fixed-address liabilities, which can outlive their routes.
        // Yield and Treasury destinations can change without touching those liabilities, so add
        // them at read time only when owed and absent from the stored set.
        address[] memory found = new address[](configured.length + 2);
        uint256 length;
        for (uint256 i; i < configured.length; ++i) {
            found[length++] = configured[i];
        }
        address yieldRecipient_ = _yieldPayoutRecipient();
        bool includeYield = _pendingYieldRecipient[asset_] != 0 &&
            !configuredSet.contains(yieldRecipient_);
        if (includeYield) found[length++] = yieldRecipient_;
        address treasury_ = address(_TRSRY);
        // Yield falls back to Treasury when unset, and a Treasury upgrade can overlap a
        // historical configured recipient. The caller should see each address only once.
        if (
            _pendingTreasury[asset_] != 0 &&
            treasury_ != address(0) &&
            !configuredSet.contains(treasury_) &&
            !(includeYield && treasury_ == yieldRecipient_)
        ) found[length++] = treasury_;
        recipients = new address[](length);
        for (uint256 i; i < length; ++i) {
            recipients[i] = found[i];
        }
    }

    /// @inheritdoc IRevenueDistributorRescue
    /// @dev Reverts if:
    ///      - The caller is neither admin nor the selected config operator, or the policy is Kernel-inactive.
    ///      - A guarded operation is already in progress.
    ///      - The asset was ever managed, has no code, or cannot report its balance.
    ///      - The destination is zero, the Kernel, this policy, or the asset, or custody is below reserved payouts.
    ///      - The token transfer to the specified destination fails.
    ///      Callable while locally disabled.
    function rescue(address asset_, address destination_) external override nonReentrant {
        _requirePolicyActive();
        _requireConfigOperatorOrAdmin();
        uint256 amount = _previewRescue(asset_, destination_);
        if (amount == 0) return;
        ERC20(asset_).safeTransfer(destination_, amount);
        emit AssetRescued(asset_, destination_, amount);
    }

    /// @inheritdoc IRevenueDistributorRescue
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - The asset is managed or has no token code.
    ///      - The destination is zero, the Kernel, this policy, or the asset, or custody is below reserved payouts.
    function previewRescue(
        address asset_,
        address destination_
    ) external view override returns (uint256) {
        _requirePolicyActive();
        return _previewRescue(asset_, destination_);
    }

    /// @inheritdoc IRevenueDistributorRescue
    /// @dev Callable while locally disabled; resolves role recipients at execution.
    ///      Debits asset route, repurchase, then Treasury.
    ///      Emits one per-kind event for each nonzero debit and transfers the total once.
    ///      Reverts if:
    ///      - The caller is neither admin nor the selected config operator.
    ///      - This policy is Kernel-inactive or a guarded operation is in progress.
    ///      - The asset has no code, or the recipient or destination is zero.
    ///      - The destination is the Kernel, this policy, or the asset.
    ///      - The amount is zero or exceeds the recipient's current combined entitlement.
    ///      - The token transfer fails.
    /// @param asset_ Token owed.
    /// @param recipient_ Recipient currently owed the pending payout.
    /// @param destination_ Recipient of the rescued tokens.
    /// @param amount_ Exact positive amount, at most pendingPayout(asset_, recipient_).
    function rescuePendingPayout(
        address asset_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) external override nonReentrant {
        _requirePolicyActive();
        _requireConfigOperatorOrAdmin();
        // Validates that amount_ is positive and fits the recipient's combined pending payout.
        _previewRescuePendingPayout(asset_, recipient_, destination_, amount_);
        uint256 assetRoute = Math.min(amount_, _pendingConfiguredDistributions[asset_][recipient_]);
        uint256 repurchase;
        if (recipient_ == _yieldPayoutRecipient()) {
            repurchase = Math.min(amount_ - assetRoute, _pendingYieldRecipient[asset_]);
        }
        uint256 treasuryPayout = amount_ - assetRoute - repurchase;

        if (assetRoute != 0) {
            _pendingConfiguredDistributions[asset_][recipient_] -= assetRoute;
            if (_pendingConfiguredDistributions[asset_][recipient_] == 0) {
                _pendingConfiguredRecipients[asset_].remove(recipient_);
            }
            emit PendingAssetRouteRescued(asset_, recipient_, destination_, assetRoute);
        }
        if (repurchase != 0) {
            _pendingYieldRecipient[asset_] -= repurchase;
            emit PendingRepurchaseRescued(asset_, destination_, repurchase);
        }
        if (treasuryPayout != 0) {
            // The validated entitlement includes this liability only for the current Treasury.
            _pendingTreasury[asset_] -= treasuryPayout;
            emit PendingTreasuryRescued(asset_, destination_, treasuryPayout);
        }
        _decreasePending(asset_, amount_);
        ERC20(asset_).safeTransfer(destination_, amount_);
    }

    /// @inheritdoc IRevenueDistributorRescue
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - The asset has no code, or recipient or destination is zero.
    ///      - The destination is the Kernel, this policy, or the asset.
    ///      - The amount is zero or exceeds the recipient's current combined entitlement.
    function previewRescuePendingPayout(
        address asset_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) external view override returns (uint256) {
        _requirePolicyActive();
        return _previewRescuePendingPayout(asset_, recipient_, destination_, amount_);
    }

    /// @inheritdoc IRevenueDistributor
    function assetState(address asset_) external view override returns (AssetState) {
        return _assetStates[asset_];
    }

    /// @inheritdoc IRevenueDistributor
    function getActiveAssets() external view override returns (address[] memory) {
        return _activeAssets.values();
    }

    /// @inheritdoc IRevenueDistributor
    function getActiveAssetCount() external view override returns (uint256) {
        return _activeAssets.length();
    }

    /// @inheritdoc IRevenueDistributor
    /// @dev Reverts if:
    ///      - The index is outside the current active asset set.
    function getActiveAssetAt(uint256 index_) external view override returns (address) {
        return _activeAssets.at(index_);
    }

    /// @inheritdoc IRevenueDistributor
    function getAssetDistribution(
        address asset_
    ) external view override returns (uint16 repurchaseBps, AssetRoute[] memory routes) {
        StoredRoute storage route = _routes[asset_];
        return (route.repurchaseBps, route.routes);
    }

    /// @inheritdoc IRevenueDistributor
    function assetDistributionHash(address asset_) external view override returns (bytes32) {
        StoredRoute storage route = _routes[asset_];
        AssetRoute[] memory routes = route.routes;
        return
            keccak256(
                abi.encode(_assetStates[asset_], route.repurchaseBps, routes, _yieldRecipient)
            );
    }

    /// @inheritdoc IRevenueDistributor
    function yieldRecipient() external view override returns (address) {
        return _yieldRecipient;
    }

    /// @inheritdoc IRevenueDistributor
    function treasury() external view override returns (address) {
        return address(_TRSRY);
    }

    /// @dev Restricts config-operator rotation to admin while this policy is Kernel-active.
    function _authorizeSetConfigOperator() internal view override returns (bool) {
        _requirePolicyActive();
        if (!_isAdmin(msg.sender)) return false;
        return true;
    }

    /// @dev Reverts if:
    ///      - The caller lacks admin and revenue_distributor_admin roles.
    function _authorizeReEnable() internal view override {
        _requireAuthorized(
            !_isAdmin(msg.sender) && !_hasRole(msg.sender, REVENUE_DISTRIBUTOR_ADMIN_ROLE)
        );
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - This policy is locally disabled.
    ///      - The caller lacks ADMIN.
    ///      - The requested period is zero.
    function setGracePeriod(uint32 period_) public override {
        _requirePolicyActive();
        super.setGracePeriod(period_);
    }

    /// @dev Reverts if:
    ///      - The caller lacks the admin role.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @dev Reverts if:
    ///      - The caller is neither admin nor the selected config operator.
    function _requireConfigOperatorOrAdmin() internal view {
        if (!_isAdmin(msg.sender) && !_isConfigOperator(msg.sender)) {
            revert RevenueDistributor_UnauthorizedConfigOperator(msg.sender);
        }
    }

    /// @dev Reverts if:
    ///      - This policy is disabled or Kernel-inactive.
    function _requireActiveAndEnabled() internal view {
        _requirePolicyActive();
        _requireEnabled();
    }

    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      Activation refreshes cached modules.
    function _requirePolicyActive() internal view {
        if (!kernel.isPolicyActive(Policy(address(this)))) {
            revert RevenueDistributor_PolicyNotActive(address(this));
        }
    }

    // Active-asset route validation must query each candidate policy and reject incompatible ones.
    // forge-lint: disable-start(calls-loop,require-revert-in-loop)
    /// @dev Reverts if:
    ///      - The candidate lacks a required interface, reports incompatible metadata, or is not active/enabled.
    function _requireYieldRecipientPolicy(address recipient_) internal view {
        if (
            !ERC165Checker.supportsInterface(
                recipient_,
                type(IYieldRepurchaseRecipient).interfaceId
            ) || !ERC165Checker.supportsInterface(recipient_, type(IEnabler).interfaceId)
        ) revert RevenueDistributor_InvalidYieldRecipient(recipient_);
        PolicyDependency.requireActiveAndEnabled(recipient_, address(kernel));
    }

    /// @dev Reverts if:
    ///      - The recipient is zero or lacks the required active, enabled policy state.
    ///      - No enabled vault accepts the asset as its shares or underlying.
    function _requireYieldRecipientForAsset(address recipient_, address asset_) internal view {
        if (recipient_ == address(0)) {
            revert RevenueDistributor_YieldRecipientUnavailable(recipient_, asset_);
        }
        _requireYieldRecipientPolicy(recipient_);
        // Some recipients hold vault shares directly; others accept the vault's underlying
        // asset. Try the direct share match first, then inspect registered vaults for an
        // enabled share or underlying match. A failed or malformed lookup cannot establish compatibility.
        if (_yieldVaultMatches(recipient_, asset_, asset_)) return;
        // Decode words first: typed try/catch does not catch malformed return-data decoding.
        (bool success, bytes memory data) = recipient_.staticcall(
            abi.encodeCall(IYieldRepurchaseRecipient.getVaults, ())
        );
        if (success && data.length >= 64) {
            (uint256 offset, uint256 length) = abi.decode(data, (uint256, uint256));
            if (offset == 32 && length == (data.length - 64) / 32 && data.length % 32 == 0) {
                uint256[] memory vaults = abi.decode(data, (uint256[]));
                for (uint256 i; i < vaults.length; ++i) {
                    if (vaults[i] > type(uint160).max) {
                        revert RevenueDistributor_YieldRecipientUnavailable(recipient_, asset_);
                    }
                }
                for (uint256 i; i < vaults.length; ++i) {
                    // Every word was checked above; narrowing cannot truncate an address.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    if (_yieldVaultMatches(recipient_, address(uint160(vaults[i])), asset_)) return;
                }
            }
        }
        revert RevenueDistributor_YieldRecipientUnavailable(recipient_, asset_);
    }

    /// @dev Safely checks one canonical four-word VaultConfig, without bubbling getter failures.
    function _yieldVaultMatches(
        address recipient_,
        address vault_,
        address asset_
    ) internal view returns (bool) {
        (bool success, bytes memory data) = recipient_.safeStaticCall(
            gasleft(),
            _MAX_VAULT_CONFIG_RETURN_SIZE,
            abi.encodeCall(IYieldRepurchaseRecipient.getVaultConfig, (vault_))
        );
        if (!success || data.length != _VAULT_CONFIG_RETURN_SIZE) return false;
        (uint256 returnedVault, uint256 shareToken, uint256 underlying, uint256 enabled) = abi
            .decode(data, (uint256, uint256, uint256, uint256));
        return
            returnedVault == uint256(uint160(vault_)) &&
            shareToken <= type(uint160).max &&
            underlying <= type(uint160).max &&
            enabled == 1 &&
            (shareToken == uint256(uint160(asset_)) || underlying == uint256(uint160(asset_)));
    }

    // forge-lint: disable-end(calls-loop,require-revert-in-loop)

    /// @dev Rejects empty, protocol control, Treasury, and yield-recipient addresses for an ordinary share.
    function _isInvalidConfiguredRecipient(
        address recipient_,
        address treasury_
    ) internal view returns (bool) {
        return
            recipient_ == address(0) ||
            recipient_ == address(this) ||
            recipient_ == address(kernel) ||
            recipient_ == treasury_ ||
            recipient_ == _yieldRecipient;
    }

    /// @dev Returns the combined configured and role-based liability to a recipient.
    ///      Reverts if:
    ///      - The sum of liabilities to the same current address overflows.
    function _pendingAmount(
        address asset_,
        address recipient_
    ) internal view returns (uint256 amount) {
        // A Treasury upgrade can make an old configured recipient the current Treasury. The
        // configured share remains owed to that fixed address; the remainder follows TRSRY.
        // Their overlap is one transfer amount, backed by two separate liability buckets.
        amount = _pendingConfiguredDistributions[asset_][recipient_];
        if (recipient_ == _yieldPayoutRecipient()) {
            amount += _pendingYieldRecipient[asset_];
        }
        if (recipient_ == address(_TRSRY)) amount += _pendingTreasury[asset_];
    }

    /// @dev Attempts each current route destination, leaving failed shares reserved. If a
    ///      configured recipient became Treasury, the first attempt pays both buckets and the
    ///      later attempt is a no-op because the buckets are already cleared.
    function _transferCurrentPayouts(address asset_, StoredRoute storage route_) internal {
        if (_pendingYieldRecipient[asset_] != 0) {
            _transferPendingPayout(asset_, _yieldPayoutRecipient());
        }
        for (uint256 i; i < route_.routes.length; ++i) {
            _transferPendingPayout(asset_, route_.routes[i].recipient);
        }
        if (_pendingTreasury[asset_] != 0) {
            _transferPendingPayout(asset_, address(_TRSRY));
        }
    }

    /// @dev Attempts one recipient's full pending amount and clears its liabilities on success.
    function _transferPendingPayout(address asset_, address recipient_) internal {
        if (recipient_ == address(0)) return;
        uint256 amount = _pendingAmount(asset_, recipient_);
        if (amount == 0) return;
        if (!ERC20(asset_).trySafeTransfer(recipient_, amount)) {
            emit DistributionDeferred(asset_, recipient_, amount);
            return;
        }
        // A successful transfer settles every debt bucket represented by this address. The
        // aggregate reserve decreases by the same amount, so future receipts stay distinct.
        if (_pendingConfiguredDistributions[asset_][recipient_] != 0) {
            delete _pendingConfiguredDistributions[asset_][recipient_];
            _pendingConfiguredRecipients[asset_].remove(recipient_);
        }
        if (recipient_ == _yieldPayoutRecipient()) delete _pendingYieldRecipient[asset_];
        if (recipient_ == address(_TRSRY)) delete _pendingTreasury[asset_];
        _totalPending[asset_] -= amount;
        if (_totalPending[asset_] == 0) _pendingAssets.remove(asset_);
        emit Distributed(asset_, recipient_, amount);
    }

    /// @dev Reverts if:
    ///      - The token has no code, is managed, or the destination is zero.
    ///      - The destination is the Kernel, this policy, or the asset.
    ///      - Custody is below reserved distributions.
    /// @param asset_ Token to inspect.
    /// @param destination_ Proposed rescue recipient.
    /// @return Full unreserved token balance.
    function _previewRescue(address asset_, address destination_) internal view returns (uint256) {
        _validateRescueAddresses(asset_, destination_);
        if (_assetStates[asset_] != AssetState.NeverListed) {
            revert RevenueDistributor_AssetManaged(asset_);
        }
        uint256 balance = ERC20(asset_).balanceOf(address(this));
        uint256 reserved = _totalPending[asset_];
        if (balance < reserved) revert RevenueDistributor_InsufficientPayoutBalance(asset_);
        return balance - reserved;
    }

    /// @dev Reverts if:
    ///      - The asset has no code, or recipient or destination is zero.
    ///      - The destination is the Kernel, this policy, or the asset.
    ///      - The amount is zero or exceeds the recipient's current combined entitlement.
    function _previewRescuePendingPayout(
        address asset_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) internal view returns (uint256 available) {
        _validateRescueAddresses(asset_, destination_);
        if (recipient_ == address(0)) revert RevenueDistributor_InvalidRecipient(recipient_);
        if (amount_ == 0) revert RevenueDistributor_InvalidRescueAmount();
        available = _pendingAmount(asset_, recipient_);
        if (amount_ > available) {
            revert RevenueDistributor_InsufficientPendingDistribution(asset_, amount_, available);
        }
    }

    /// @dev Reverts if:
    ///      - The token has no code or the rescue destination is zero.
    ///      - The destination is the Kernel, this policy, or the asset.
    /// @param asset_ Token to check.
    /// @param destination_ Proposed rescue recipient.
    function _validateRescueAddresses(address asset_, address destination_) internal view {
        if (asset_ == address(0) || asset_.code.length == 0) {
            revert RevenueDistributor_InvalidAsset(asset_);
        }
        if (
            destination_ == address(0) ||
            destination_ == address(kernel) ||
            destination_ == address(this) ||
            destination_ == asset_
        ) {
            revert RevenueDistributor_InvalidRescueDestination(destination_);
        }
    }

    /// @dev Removes a rescued liability from the asset reserve and enumeration.
    ///      Reverts if:
    ///      - the decrease exceeds the aggregate reserve.
    /// @param asset_ Token whose reserve decreases.
    /// @param amount_ Amount paid from the reserve.
    function _decreasePending(address asset_, uint256 amount_) internal {
        _totalPending[asset_] -= amount_;
        if (_totalPending[asset_] == 0) _pendingAssets.remove(asset_);
    }

    /// @dev Falls back to current Treasury when no yield recipient is configured.
    function _yieldPayoutRecipient() internal view returns (address) {
        return _yieldRecipient == address(0) ? address(_TRSRY) : _yieldRecipient;
    }

    /// @inheritdoc EnablerV2
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(EnablerV2, ReEnablerGracePeriod) returns (bool) {
        return
            interfaceId_ == type(IRevenueDistributor).interfaceId ||
            interfaceId_ == type(IRevenueDistributorRescue).interfaceId ||
            interfaceId_ == type(IConfigOperator).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty.
    ///      - This policy is inactive or a required operational dependency is unavailable.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert RevenueDistributor_InvalidData();
        _requirePolicyActive();
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty.
    ///
    /// @dev Kernel inactivity does not prevent disable.
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert RevenueDistributor_InvalidData();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The shared re-enable grace checks fail.
    ///      - The enable prerequisites fail.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requirePolicyActive();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The grace deadline does not fit uint48 (SafeCastOverflowedUintDowncast).
    ///      - The inclusive grace window has expired (GracePeriod_Expired).
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }
}
