// SPDX-License-Identifier: AGPL-3.0
// Transient-storage clearing fixes require Solidity 0.8.34 or newer.
pragma solidity >=0.8.34;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {Bytes} from "@openzeppelin-5.7.0/utils/Bytes.sol";
import {SlotDerivation} from "@openzeppelin-5.7.0/utils/SlotDerivation.sol";
import {TransientSlot} from "@openzeppelin-5.7.0/utils/TransientSlot.sol";
import {SignatureChecker} from "@openzeppelin-5.7.0/utils/cryptography/SignatureChecker.sol";

/// @title Scoped operator authorization
/// @notice Generic local grants with consumer-defined permissions and optional live/signature data.
/// @dev Consumers capture before preparation and validate the SAME stamp after effects. Returning
///      authenticated permissions does not enforce their meaning; the consumer owns result checks.
abstract contract OperatorAuth is IOperatorAuth, IERC165 {
    using Bytes for bytes;
    using SlotDerivation for bytes32;
    using TransientSlot for *;

    uint256 internal constant _ABI_WORD_SIZE = 32;
    bytes32 internal constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 public constant GRANT_TYPEHASH =
        keccak256(
            "Grant(address account,address operator,uint256 accountEpoch,uint256 pairEpoch,uint48 deadline,bool multiple,uint8 actions,bytes32 context,bytes32 permissionsHash,bytes32 signatureDataHash)"
        );
    bytes32 internal constant _RECORD_NAMESPACE = keccak256("olympus.operator-auth.record.v2");
    bytes32 internal constant _TRANSIENT_NAMESPACE =
        keccak256("olympus.operator-auth.temporary.v2");
    bytes32 internal constant _STAMP_NAMESPACE = keccak256("olympus.operator-auth.stamp.v2");
    uint8 internal immutable _SUPPORTED_ACTIONS;
    /// @dev Account/operator/context identity is committed by the canonical mapping key.
    struct StoredGrant {
        uint256 accountEpoch;
        uint256 pairEpoch;
        uint48 deadline;
        bool multiple;
        uint8 actions;
        bytes permissions;
    }
    mapping(address => uint256) public override accountEpochs;
    mapping(address => mapping(address => uint256)) public override pairEpochs;
    mapping(bytes32 => StoredGrant) private _grants;

    /// @notice Selects the unordered action bits understood by the consumer.
    /// @dev Reverts if the supported action mask is empty.
    /// @param supportedActions_ Nonzero mask of supported action bits.
    constructor(uint8 supportedActions_) {
        if (supportedActions_ == 0) revert OperatorAuth_InvalidActions(0);
        _SUPPORTED_ACTIONS = supportedActions_;
    }

    /// @inheritdoc IOperatorAuth
    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return keccak256(abi.encode(_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 id_) public view virtual returns (bool) {
        return id_ == type(IOperatorAuth).interfaceId || id_ == type(IERC165).interfaceId;
    }

    /// @inheritdoc IOperatorAuth
    /// @dev Reverts if:
    ///      - Consumer-specific creation admission fails.
    ///      - The caller is not the grant's account, either identity is zero, or the grant is a self-grant.
    ///      - The action mask is empty/unsupported or the inclusive deadline has passed.
    ///      - Expected account/pair epochs are stale or the pair epoch is exhausted.
    ///      - The live namespace differs or consumer-specific permission validation fails.
    function approveGrant(Grant calldata grant_) external override {
        _beforeGrantCreation();
        if (msg.sender != grant_.account) revert OperatorAuth_InvalidIdentity();
        _validateGrant(grant_);
        _install(grant_);
    }

    /// @inheritdoc IOperatorAuth
    /// @dev EOA/ERC1271 verification and signature-only validation precede every state write.
    ///      Reverts if:
    ///      - Consumer-specific creation admission fails.
    ///      - The caller is not the designated operator, either identity is zero, or the grant is a self-grant.
    ///      - The action mask is empty/unsupported or the inclusive deadline has passed.
    ///      - Expected account/pair epochs are stale or the pair epoch is exhausted.
    ///      - The live namespace differs or consumer-specific permission/signature-data validation fails.
    ///      - The account's EOA or ERC1271 signature does not authenticate the complete payload.
    function acceptGrant(
        Grant calldata grant_,
        bytes calldata signatureData_,
        bytes calldata signature_
    ) external override {
        _beforeGrantCreation();
        if (msg.sender != grant_.operator) revert OperatorAuth_InvalidIdentity();
        _validateGrant(grant_);
        _validateSignatureData(grant_, signatureData_);
        bytes32 structHash = keccak256(
            abi.encode(
                GRANT_TYPEHASH,
                grant_.account,
                grant_.operator,
                grant_.accountEpoch,
                grant_.pairEpoch,
                grant_.deadline,
                grant_.multiple,
                grant_.actions,
                grant_.context,
                keccak256(grant_.permissions),
                keccak256(signatureData_)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        if (!SignatureChecker.isValidSignatureNow(grant_.account, digest, signature_))
            revert OperatorAuth_InvalidSignature();
        _install(grant_);
    }

    /// @inheritdoc IOperatorAuth
    /// @dev Bypasses admission/context hooks. Reverts if:
    ///      - The operator is zero or the calling account itself.
    ///      - The pair epoch is exhausted.
    function cancelGrant(address operator_) external override {
        if (operator_ == address(0)) revert OperatorAuth_InvalidIdentity();
        if (operator_ == msg.sender) revert OperatorAuth_SelfGrant();
        uint256 epoch = pairEpochs[msg.sender][operator_];
        if (epoch == type(uint256).max) revert OperatorAuth_EpochExhausted();
        pairEpochs[msg.sender][operator_] = epoch + 1;
        emit GrantCancelled(msg.sender, operator_, epoch + 1);
    }

    /// @inheritdoc IOperatorAuth
    /// @dev Never enumerates namespaces or resets pairs. Reverts if:
    ///      - The calling account's cancellation epoch equals uint256.max.
    function cancelAllGrants() external override {
        uint256 epoch = accountEpochs[msg.sender];
        if (epoch == type(uint256).max) revert OperatorAuth_EpochExhausted();
        accountEpochs[msg.sender] = epoch + 1;
        emit AllGrantsCancelled(msg.sender, epoch + 1);
    }

    /// @inheritdoc IOperatorAuth
    function authorizationContext(
        address account_,
        address operator_
    ) public view override returns (bytes32) {
        return _currentAuthorizationContext(account_, operator_);
    }

    /// @inheritdoc IOperatorAuth
    function getGrant(
        address account_,
        address operator_
    ) public view override returns (Grant memory grant) {
        grant = _getGrant(account_, operator_, _currentAuthorizationContext(account_, operator_));
        // Grant deadlines use block time and include the exact deadline.
        // forge-lint: disable-next-line(block-timestamp)
        if (!_hasCurrentEpochs(grant) || block.timestamp > grant.deadline) {
            Grant memory empty;
            return empty;
        }
    }

    /// @inheritdoc IOperatorAuth
    /// @dev Reverts if:
    ///      - The action is zero, unsupported or composite, or either identity is zero.
    ///      - Consumer-specific operative admission fails.
    ///      - Delegated authority is absent, cancelled, replaced, outside this namespace or missing the action.
    ///      - The delegated grant's inclusive deadline has passed.
    ///      Intrinsic owner authority bypasses only the delegated-record checks.
    function captureAuthorization(
        address account_,
        address operator_,
        uint8 action_
    ) public view override returns (bytes32) {
        _checkAuthorityInput(account_, operator_, action_);
        if (account_ == operator_) return bytes32(0);
        Grant memory grant = _getGrant(
            account_,
            operator_,
            _currentAuthorizationContext(account_, operator_)
        );
        _requireLive(grant, action_);
        return _stamp(grant);
    }

    /// @inheritdoc IOperatorAuth
    /// @dev Reverts if:
    ///      - The action is zero, unsupported or composite, or either identity is zero.
    ///      - Consumer-specific operative admission fails.
    ///      - Delegated authority is absent/stale, lacks the action or has passed its inclusive deadline.
    ///      - The current delegated stamp differs from the original, or an owner supplies a nonzero stamp.
    function validateAuthorization(
        address account_,
        address operator_,
        uint8 action_,
        bytes32 originalStamp_
    ) external view override returns (bytes memory) {
        return _validateAuthorization(account_, operator_, action_, originalStamp_).permissions;
    }

    /// @notice Returns original authenticated permission data for concrete checks.
    /// @dev Owner's empty record follows mandatory identity/action/admission/stamp checks.
    function _validateAuthorization(
        address account_,
        address operator_,
        uint8 action_,
        bytes32 originalStamp_
    ) internal view returns (Grant memory grant) {
        _checkAuthorityInput(account_, operator_, action_);
        if (account_ == operator_) {
            if (originalStamp_ != bytes32(0)) revert OperatorAuth_InvalidContext();
            grant.account = account_;
            grant.operator = operator_;
            return grant;
        }
        grant = _getGrant(account_, operator_, _currentAuthorizationContext(account_, operator_));
        _requireLive(grant, action_);
        if (_stamp(grant) != originalStamp_) revert OperatorAuth_InvalidContext();
    }

    function _validateGrant(Grant calldata grant_) private view {
        if (grant_.account == address(0) || grant_.operator == address(0))
            revert OperatorAuth_InvalidIdentity();
        if (grant_.account == grant_.operator) revert OperatorAuth_SelfGrant();
        if (grant_.actions == 0 || (grant_.actions & ~_SUPPORTED_ACTIONS) != 0)
            revert OperatorAuth_InvalidActions(grant_.actions);
        // Grant deadlines use block time and include the exact deadline.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > grant_.deadline) revert OperatorAuth_ExpiredGrant(grant_.deadline);
        if (
            grant_.accountEpoch != accountEpochs[grant_.account] ||
            grant_.pairEpoch != pairEpochs[grant_.account][grant_.operator]
        ) revert OperatorAuth_InvalidEpoch();
        if (grant_.pairEpoch == type(uint256).max) revert OperatorAuth_EpochExhausted();
        if (grant_.context != _currentAuthorizationContext(grant_.account, grant_.operator))
            revert OperatorAuth_InvalidContext();
        _validatePermissions(grant_);
    }

    function _install(Grant calldata grant_) private {
        // Reuse authenticated context verbatim; no mutable hook or fresh context read follows.
        bytes32 key = _recordKey(grant_.account, grant_.operator, grant_.context);
        StoredGrant memory record = StoredGrant(
            grant_.accountEpoch,
            grant_.pairEpoch,
            grant_.deadline,
            grant_.multiple,
            grant_.actions,
            grant_.permissions
        );
        pairEpochs[grant_.account][grant_.operator] = grant_.pairEpoch + 1;
        if (grant_.multiple) _grants[key] = record;
        else {
            bytes memory data = abi.encode(record);
            bytes32 slot = keccak256(abi.encode(_TRANSIENT_NAMESPACE, key));
            slot.asUint256().tstore(data.length);
            for (uint256 offset; offset < data.length; offset += _ABI_WORD_SIZE) {
                // ABI encoding is word-aligned, so each slice contains exactly one complete word.
                // forge-lint: disable-next-line(unsafe-typecast)
                bytes32 word = bytes32(data.slice(offset, offset + _ABI_WORD_SIZE));
                slot.offset(1 + offset / _ABI_WORD_SIZE).asBytes32().tstore(word);
            }
        }
        emit GrantAccepted(
            msg.sender,
            grant_.account,
            grant_.operator,
            grant_.accountEpoch,
            grant_.pairEpoch,
            grant_.deadline,
            grant_.multiple,
            grant_.actions,
            grant_.context,
            keccak256(grant_.permissions)
        );
    }

    function _getGrant(
        address account_,
        address operator_,
        bytes32 context_
    ) private view returns (Grant memory grant) {
        bytes32 key = _recordKey(account_, operator_, context_);
        StoredGrant memory record;
        bytes32 slot = keccak256(abi.encode(_TRANSIENT_NAMESPACE, key));
        uint256 length = slot.asUint256().tload();
        if (length != 0) {
            bytes32[] memory words = new bytes32[](length / _ABI_WORD_SIZE);
            for (uint256 i; i < words.length; ++i) {
                words[i] = slot.offset(i + 1).asBytes32().tload();
            }
            // ABI records are word-aligned; packing bytes32[] preserves those words without a length prefix.
            record = abi.decode(abi.encodePacked(words), (StoredGrant));
        }
        // Pair epochs choose a new reusable replacement over a prior temporary record. When
        // transient state expires, historical persistent bytes still fail the same epoch checks.
        if (
            length == 0 ||
            record.pairEpoch == type(uint256).max ||
            record.pairEpoch + 1 != pairEpochs[account_][operator_]
        ) record = _grants[key];
        grant = Grant(
            account_,
            operator_,
            record.accountEpoch,
            record.pairEpoch,
            record.deadline,
            record.multiple,
            record.actions,
            context_,
            record.permissions
        );
    }

    function _recordKey(
        address account_,
        address operator_,
        bytes32 context_
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(_RECORD_NAMESPACE, account_, operator_, context_));
    }

    function _checkAuthorityInput(address account_, address operator_, uint8 action_) private view {
        if (action_ == 0 || (action_ & ~_SUPPORTED_ACTIONS) != 0 || (action_ & (action_ - 1)) != 0)
            revert OperatorAuth_InvalidAction(action_);
        if (account_ == address(0) || operator_ == address(0))
            revert OperatorAuth_InvalidIdentity();
        _beforeAuthorization();
    }

    /// @dev Shared current-record predicate; historical bytes are never deleted for filtering.
    function _hasCurrentEpochs(Grant memory grant_) private view returns (bool) {
        return
            grant_.actions != 0 &&
            grant_.accountEpoch == accountEpochs[grant_.account] &&
            grant_.pairEpoch != type(uint256).max &&
            grant_.pairEpoch + 1 == pairEpochs[grant_.account][grant_.operator];
    }

    function _requireLive(Grant memory grant_, uint8 action_) private view {
        if (!_hasCurrentEpochs(grant_) || (grant_.actions & action_) == 0)
            revert OperatorAuth_InvalidContext();
        // Grant deadlines use block time and include the exact deadline.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > grant_.deadline) revert OperatorAuth_ExpiredGrant(grant_.deadline);
    }

    function _stamp(Grant memory grant_) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _STAMP_NAMESPACE,
                    grant_.account,
                    grant_.operator,
                    grant_.accountEpoch,
                    grant_.pairEpoch,
                    grant_.context,
                    grant_.deadline,
                    grant_.multiple,
                    grant_.actions,
                    keccak256(grant_.permissions)
                )
            );
    }

    /// @notice Required consumer schema and length validation for direct/signed approval.
    function _validatePermissions(Grant calldata grant_) internal view virtual;

    /// @notice Optional live namespace; zero is real. Recurring context may revive current epochs.
    function _currentAuthorizationContext(
        address,
        address
    ) internal view virtual returns (bytes32) {
        return bytes32(0);
    }

    /// @notice Optional acceptance-only schema/conditions; base hashing authenticates every byte.
    /// @dev Default empty-only; consumers must canonically bound custom data before installation.
    function _validateSignatureData(Grant calldata, bytes calldata data_) internal view virtual {
        if (data_.length != 0) revert OperatorAuth_UnsupportedSignatureData();
    }

    /// @notice Optional creation admission; cancellation never executes this hook.
    function _beforeGrantCreation() internal view virtual {}

    /// @notice Optional operative admission; cancellation/getters bypass this hook.
    function _beforeAuthorization() internal view virtual {}
}
