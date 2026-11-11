// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.34;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IBurnerLoansAuthTarget} from "src/policies/interfaces/burnerloans/IBurnerLoansAuthTarget.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BL_ACTION_DEPOSIT, BL_ACTION_BORROW, BL_ACTION_WITHDRAW, BL_ACTION_EXTEND} from "src/policies/burnerloans/libraries/LoanActions.sol";

// Contracts
import {OperatorAuth} from "src/policies/utils/OperatorAuth.sol";

/// @notice Ordinary Core-bound operator grants; Core retains all custody and canonical settlement.
/// @dev Records the trusted Kernel to check Core's binding and readiness. It requests no module
///      permissions and uses no roles, so it does not need activation as a Kernel Policy.
///      It has no protocol configuration or independent lifecycle; Core selection controls availability.
///      Counters belong to this Auth instance. Core rotation invalidates old key namespaces; account
///      cancellation here deliberately does not cancel signatures targeting another Auth instance.
contract BurnerLoansAuth is OperatorAuth, IBurnerLoansAuth {
    /// @notice Trusted Kernel used to verify Core's binding and authoritative Policy readiness.
    address internal immutable _KERNEL;
    /// @notice Permanent Core whose selected verifier and installation epoch define grant validity.
    address internal immutable _CORE;

    /// @notice Binds the permanent Core identity without requiring prior selection or enablement.
    /// @dev Reverts if:
    ///      - Core does not advertise IBurnerLoansAuthTarget through ERC165.
    ///      - The independently supplied Kernel is the zero address.
    ///      - Core's Kernel getter fails, returns malformed data or reports a different Kernel.
    ///      Core validates the reverse binding when selecting Auth. Deploy Core before Auth;
    ///      Core Kernel migration requires selecting a new Auth bound to the new Kernel.
    /// @param kernel_ Trusted Kernel against which Core membership and binding are checked.
    /// @param core_ Deployed permanent Core implementing the authorization target interface.
    // ERC165 rejects a zero Core before storage; the Kernel has an explicit zero-address check.
    // forge-lint: disable-start(missing-zero-check)
    constructor(
        address kernel_,
        address core_
    ) OperatorAuth(BL_ACTION_DEPOSIT | BL_ACTION_BORROW | BL_ACTION_WITHDRAW | BL_ACTION_EXTEND) {
        if (!ERC165Checker.supportsInterface(core_, type(IBurnerLoansAuthTarget).interfaceId))
            revert BurnerLoansAuth_InvalidCore(core_);
        if (kernel_ == address(0)) revert BurnerLoansAuth_InvalidKernel(kernel_);
        PolicyDependency.requireSameKernel(core_, kernel_);
        _KERNEL = kernel_;
        _CORE = core_;
    }

    // forge-lint: disable-end(missing-zero-check)

    /// @inheritdoc IBurnerLoansCoreBound
    function core() external view returns (address) {
        return _CORE;
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8, uint8) {
        return (1, 0);
    }

    /// @inheritdoc IERC165
    /// @dev Advertises generic grants, lending constraints and immutable Core binding.
    function supportsInterface(bytes4 interfaceId_) public view override returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansAuth).interfaceId ||
            interfaceId_ == type(IBurnerLoansCoreBound).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @inheritdoc IBurnerLoansAuth
    /// @dev Reverts if:
    ///      - Core metadata is invalid, its Kernel differs from the trusted Kernel, or Core is inactive/disabled.
    ///      - Core has selected another Auth.
    ///      - The inherited identity, action, grant lifetime, epochs or original-stamp checks fail.
    ///      - The selected asset or required recipient differs from the grant's permission record.
    ///      Owner authority bypasses bounds after identity/action and original-stamp validation.
    ///      Core must compare the bound against canonical FLOAN after all effects under its guard.
    function validate(
        address account_,
        address operator_,
        uint8 action_,
        address asset_,
        address recipient_,
        bytes32 originalGrantStamp_
    ) external view returns (uint128) {
        Grant memory grant = _validateAuthorization(
            account_,
            operator_,
            action_,
            originalGrantStamp_
        );
        // Owners need no delegated bounds: zero removes the withdrawal floor; uint128.max removes
        // the deposit, debt and maturity ceilings. Core still enforces ordinary lending constraints.
        if (account_ == operator_) return action_ == BL_ACTION_WITHDRAW ? 0 : type(uint128).max;
        Permissions memory p = abi.decode(grant.permissions, (Permissions));
        if (action_ == BL_ACTION_DEPOSIT) {
            _matchAsset(p.depositAsset, asset_);
            return p.maxCollateral;
        }
        if (action_ == BL_ACTION_BORROW) {
            _matchAsset(p.borrowAsset, asset_);
            _matchRecipient(p.borrowRecipient, recipient_);
            return p.maxDebt;
        }
        if (action_ == BL_ACTION_WITHDRAW) {
            _matchAsset(p.withdrawAsset, asset_);
            _matchRecipient(p.withdrawRecipient, recipient_);
            return p.minCollateral;
        }
        _matchAsset(p.extendAsset, asset_);
        return p.maxMaturity;
    }

    /// @dev Auth's current namespace excludes signing-domain chain ID, so accepted grants retain
    ///      their acceptance-time signature semantics. Core's monotonic epoch prevents A->B->A revival.
    function _currentAuthorizationContext(
        address,
        address
    ) internal view override returns (bytes32) {
        // Selection is checked by the readiness hook; only the epoch defines this namespace.
        // forge-lint: disable-next-line(unused-return)
        (, uint256 epoch) = IBurnerLoansAuthTarget(_CORE).authConfig();
        return keccak256(abi.encode(_CORE, epoch));
    }

    /// @dev Grant creation requires selected Auth and active/enabled Core; cancellation intentionally
    ///      never calls this hook, including when retired or when Core is paused/inactive.
    function _beforeGrantCreation() internal view override {
        _requireOperationalCore();
    }

    /// @dev Operative grant views have the same direct service admission as actual authorization.
    function _beforeAuthorization() internal view override {
        _requireOperationalCore();
    }

    /// @dev Reverts for noncanonical size/padding or an unconfigured selected collateral asset.
    ///      Unselected records impose no constraint; their numeric padding must still be canonical.
    function _validatePermissions(Grant calldata grant_) internal view override {
        if (grant_.permissions.length != 320) revert BurnerLoansAuth_InvalidPermissions();
        uint256[10] memory words = abi.decode(grant_.permissions, (uint256[10]));
        if (
            words[0] > type(uint160).max ||
            words[1] > type(uint128).max ||
            words[2] > type(uint160).max ||
            words[3] > type(uint160).max ||
            words[4] > type(uint128).max ||
            words[5] > type(uint160).max ||
            words[6] > type(uint160).max ||
            words[7] > type(uint128).max ||
            words[8] > type(uint160).max ||
            words[9] > type(uint48).max
        ) revert BurnerLoansAuth_InvalidPermissions();
        Permissions memory p = abi.decode(grant_.permissions, (Permissions));
        if ((grant_.actions & BL_ACTION_DEPOSIT) != 0) _requireAsset(p.depositAsset);
        if ((grant_.actions & BL_ACTION_BORROW) != 0) _requireAsset(p.borrowAsset);
        if ((grant_.actions & BL_ACTION_WITHDRAW) != 0) _requireAsset(p.withdrawAsset);
        if ((grant_.actions & BL_ACTION_EXTEND) != 0) _requireAsset(p.extendAsset);
    }

    /// @notice Requires Core readiness in the independently trusted Kernel and this Auth's selection.
    /// @dev Reverts if:
    ///      - Core's Kernel/enabled getter fails or returns malformed data.
    ///      - Core reports another Kernel, is inactive in the trusted Kernel, or is disabled.
    ///      - Core has selected another Auth.
    ///      This runtime check is not used by construction, Core selection or Core enablement,
    ///      so it introduces no startup dependency cycle. Local cancellation bypasses it.
    function _requireOperationalCore() private view {
        PolicyDependency.requireActiveAndEnabled(_CORE, _KERNEL);
        IBurnerLoansAuthTarget target = IBurnerLoansAuthTarget(_CORE);
        // Selection is required here; the installation epoch defines the namespace separately.
        // forge-lint: disable-next-line(unused-return)
        (address selected, ) = target.authConfig();
        if (selected != address(this)) revert BurnerLoansAuth_NotSelected();
    }

    /// @notice Requires an explicit collateral asset registered by Core.
    /// @dev Reverts if the asset is zero/unregistered or Core's registration getter fails.
    /// @param asset_ Collateral asset selected by the grant's permission record.
    function _requireAsset(address asset_) private view {
        if (asset_ == address(0) || !IBurnerLoansAuthTarget(_CORE).isAssetRegistered(asset_))
            revert BurnerLoansAuth_InvalidAsset(asset_);
    }

    /// @notice Matches the selected permission record's asset to the operation.
    /// @dev Reverts if the actual asset differs from the required asset.
    /// @param expected_ Asset required by the selected grant record.
    /// @param actual_ Asset used by the operation.
    function _matchAsset(address expected_, address actual_) private pure {
        if (expected_ != actual_) revert BurnerLoansAuth_AssetMismatch(expected_, actual_);
    }

    /// @notice Matches a fixed recipient or accepts the grant's zero-address wildcard.
    /// @dev Reverts if a nonzero required recipient differs from the actual recipient.
    /// @param expected_ Required recipient, or zero for any otherwise-valid destination.
    /// @param actual_ Destination used by the operation.
    function _matchRecipient(address expected_, address actual_) private pure {
        if (expected_ != address(0) && expected_ != actual_)
            revert BurnerLoansAuth_RecipientMismatch(expected_, actual_);
    }
}
