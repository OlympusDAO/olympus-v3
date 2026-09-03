// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {ECDSA} from "@openzeppelin-5.3.0/utils/cryptography/ECDSA.sol";

/// @title OperatorAuth
/// @notice Reusable MonoCooler-style operator authorization for on-behalf-of actions.
abstract contract OperatorAuth is IOperatorAuth {
    // ========== CONSTANTS ========== //

    bytes32 internal constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 internal constant _AUTHORIZATION_TYPEHASH =
        keccak256(
            "Authorization(address account,address authorized,uint48 authorizationDeadline,uint256 nonce,uint48 signatureDeadline)"
        );

    // ========== IMMUTABLES ========== //

    /// @dev Chain identifier used to cache the deployment domain separator.
    uint256 internal immutable _INITIAL_CHAIN_ID;

    /// @dev Deployment domain separator reused while the chain identifier is unchanged.
    bytes32 internal immutable _INITIAL_DOMAIN_SEPARATOR;

    // ========== STATE ========== //

    /// @inheritdoc IOperatorAuth
    mapping(address account => mapping(address authorized => uint48 deadline))
        public
        override authorizationDeadlines;

    /// @inheritdoc IOperatorAuth
    mapping(address account => uint256 nonce) public override authorizationNonces;

    // ========== CONSTRUCTOR ========== //

    constructor() {
        _INITIAL_CHAIN_ID = block.chainid;
        _INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

    /// @inheritdoc IOperatorAuth
    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return
            block.chainid == _INITIAL_CHAIN_ID
                ? _INITIAL_DOMAIN_SEPARATOR
                : _computeDomainSeparator();
    }

    // ========== AUTHORIZATION ========== //

    /// @inheritdoc IOperatorAuth
    /// @dev Reverts with `OperatorAuth_ExpiredAuthorization` when `authorizationDeadline_` is
    ///      before the current block timestamp.
    ///      Reverts with `OperatorAuth_SelfAuthorization` when `authorized_` is the caller.
    ///      Invalidates authorization signatures prepared with the caller's current nonce.
    /// @param authorized_ Operator to authorize.
    /// @param authorizationDeadline_ Timestamp until which the operator is authorized, in seconds.
    function setAuthorization(
        address authorized_,
        uint48 authorizationDeadline_
    ) external override {
        // Condition: self-authorization is redundant because the account itself is always
        // authorized to act on its own behalf.
        if (authorized_ == msg.sender) {
            revert OperatorAuth_SelfAuthorization();
        }

        // Condition: the caller cannot create an already-expired authorization.
        _validateAuthorizationDeadline(authorizationDeadline_);

        // Condition: direct authorization is scoped to `msg.sender`; callers cannot set
        // authorization for any other account through this function. Incrementing the account
        // nonce prevents an earlier signature from overwriting this direct authorization.
        authorizationNonces[msg.sender]++;
        emit AuthorizationSet(msg.sender, msg.sender, authorized_, authorizationDeadline_);
        authorizationDeadlines[msg.sender][authorized_] = authorizationDeadline_;
    }

    /// @inheritdoc IOperatorAuth
    /// @dev Reverts if:
    ///      - The signature submission deadline has passed.
    ///      - The authorization deadline is before the current block timestamp.
    ///      - The signed account attempts to authorize itself as an operator.
    ///      - The signed nonce is not the account's current nonce.
    ///      - The signature is malformed or non-canonical according to `ECDSA.recover`.
    ///      - The signature does not recover `authorization_.account`.
    /// @param authorization_ Signed authorization payload.
    /// @param signature_ ECDSA signature over `authorization_`.
    function setAuthorizationWithSig(
        Authorization calldata authorization_,
        Signature calldata signature_
    ) external override {
        // Condition: the signature can only be submitted through its signed deadline.
        if (block.timestamp > authorization_.signatureDeadline) {
            revert OperatorAuth_ExpiredSignature(authorization_.signatureDeadline);
        }

        // Condition: the signed authorization cannot grant an already-expired permission.
        _validateAuthorizationDeadline(authorization_.authorizationDeadline);

        // Condition: self-authorization is redundant because the account itself is always
        // authorized to act on its own behalf.
        if (authorization_.authorized == authorization_.account) {
            revert OperatorAuth_SelfAuthorization();
        }

        // Condition: the nonce must match exactly; old, replayed, or skipped nonces fail.
        if (authorization_.nonce != authorizationNonces[authorization_.account]++) {
            revert OperatorAuth_InvalidNonce(authorization_.nonce);
        }

        // Condition: the recovered signer must be the signed account. The transaction caller
        // is only a relayer and cannot substitute themselves for the account.
        bytes32 structHash = keccak256(abi.encode(_AUTHORIZATION_TYPEHASH, authorization_));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        address signer = ECDSA.recover(digest, signature_.v, signature_.r, signature_.s);
        if (signer != authorization_.account) {
            revert OperatorAuth_InvalidSigner(signer, authorization_.account);
        }

        emit AuthorizationSet(
            msg.sender,
            authorization_.account,
            authorization_.authorized,
            authorization_.authorizationDeadline
        );
        authorizationDeadlines[authorization_.account][authorization_.authorized] = authorization_
            .authorizationDeadline;
    }

    /// @inheritdoc IOperatorAuth
    /// @dev Does not revert when the operator is already unauthorized. Invalidates authorization
    ///      signatures prepared with the caller's current nonce.
    /// @param authorized_ Operator whose authorization should be cancelled.
    function cancelAuthorization(address authorized_) external override {
        // Condition: cancellation is scoped to `msg.sender`; callers cannot clear
        // authorization for any other account through this function. Incrementing the account
        // nonce prevents an earlier signature from restoring the cancelled authorization.
        authorizationNonces[msg.sender]++;
        emit AuthorizationSet(msg.sender, msg.sender, authorized_, 0);
        authorizationDeadlines[msg.sender][authorized_] = 0;
    }

    /// @inheritdoc IOperatorAuth
    function isSenderAuthorized(
        address sender_,
        address onBehalfOf_
    ) public view override returns (bool) {
        return
            sender_ == onBehalfOf_ ||
            block.timestamp <= authorizationDeadlines[onBehalfOf_][sender_];
    }

    /// @notice Reverts if `sender_` is not authorized to act on behalf of `onBehalfOf_`.
    /// @dev Reverts with `OperatorAuth_UnauthorizedOnBehalfOf` unless `sender_` is the
    ///      account owner or has an unexpired authorization from `onBehalfOf_`.
    /// @param sender_ Caller or operator to check.
    /// @param onBehalfOf_ Account being acted for.
    function _requireSenderAuthorized(address sender_, address onBehalfOf_) internal view {
        if (!isSenderAuthorized(sender_, onBehalfOf_)) {
            revert OperatorAuth_UnauthorizedOnBehalfOf();
        }
    }

    /// @notice Reverts if an authorization deadline has already passed.
    /// @dev The deadline is inclusive: the current block timestamp is still valid.
    ///      Reverts with `OperatorAuth_ExpiredAuthorization` when `authorizationDeadline_`
    ///      is before the current block timestamp.
    /// @param authorizationDeadline_ Timestamp until which authorization is valid, in seconds.
    function _validateAuthorizationDeadline(uint48 authorizationDeadline_) internal view {
        if (block.timestamp > authorizationDeadline_) {
            revert OperatorAuth_ExpiredAuthorization(authorizationDeadline_);
        }
    }

    /// @notice Computes the EIP-712 domain separator for the current chain and contract.
    /// @return domainSeparator Current-chain domain separator.
    function _computeDomainSeparator() internal view returns (bytes32 domainSeparator) {
        return keccak256(abi.encode(_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }
}
