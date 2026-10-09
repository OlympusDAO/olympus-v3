// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Operator Authorization
/// @notice Reusable operator authorization surface for policies that support on-behalf-of actions.
interface IOperatorAuth {
    // ========== ERRORS ========== //

    error OperatorAuth_UnauthorizedOnBehalfOf();
    error OperatorAuth_ExpiredAuthorization(uint48 authorizationDeadline);
    error OperatorAuth_ExpiredSignature(uint48 signatureDeadline);
    error OperatorAuth_InvalidNonce(uint256 nonce);
    error OperatorAuth_InvalidSigner(address signer, address expectedSigner);
    error OperatorAuth_SelfAuthorization();

    // ========== STRUCTS ========== //

    /// @notice Signature authorization payload.
    /// @param account Account granting operator authorization.
    /// @param authorized Operator being authorized.
    /// @param authorizationDeadline Timestamp until which the operator is authorized, in seconds.
    /// @param nonce Account nonce consumed by the signature.
    /// @param signatureDeadline Timestamp until which the signature may be submitted, in seconds.
    struct Authorization {
        address account;
        address authorized;
        uint48 authorizationDeadline;
        uint256 nonce;
        uint48 signatureDeadline;
    }

    /// @notice ECDSA signature components.
    /// @param v Recovery identifier.
    /// @param r ECDSA r value.
    /// @param s ECDSA s value.
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    // ========== EVENTS ========== //

    event AuthorizationSet(
        address indexed caller,
        address indexed account,
        address indexed authorized,
        uint48 authorizationDeadline
    );

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the authorization deadline for an operator.
    /// @dev A sender is authorized while the stored deadline is greater than or equal to the current timestamp.
    /// @param account_ Account that granted authorization.
    /// @param authorized_ Operator account being checked.
    /// @return authorizationDeadline Timestamp until which `authorized_` may act for `account_`, in seconds.
    function authorizationDeadlines(
        address account_,
        address authorized_
    ) external view returns (uint48);

    /// @notice Returns the next signature nonce for an account.
    /// @dev A valid `setAuthorizationWithSig` call must include this exact nonce. The nonce
    ///      increments after every successful direct authorization, cancellation, or signature
    ///      authorization. Direct changes therefore invalidate signatures prepared with the
    ///      account's previous nonce.
    /// @param account_ Account whose nonce is queried.
    /// @return nonce Nonce that must be included in the next authorization signature.
    function authorizationNonces(address account_) external view returns (uint256);

    /// @notice Returns the EIP-712 domain separator used for authorization signatures.
    /// @return domainSeparator Domain separator for this contract and chain.
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice Returns whether a sender may act for an account.
    /// @dev The account itself is always authorized. Operators are authorized until their stored deadline expires.
    /// @param sender_ Caller or operator to check.
    /// @param onBehalfOf_ Account being acted for.
    /// @return True if `sender_` is `onBehalfOf_` or has an unexpired authorization.
    function isSenderAuthorized(address sender_, address onBehalfOf_) external view returns (bool);

    // ========== AUTHORIZATION FUNCTIONS ========== //

    /// @notice Sets or updates operator authorization for the caller.
    /// @dev Invalidates authorization signatures prepared with the caller's current nonce.
    ///      Reverts with `OperatorAuth_SelfAuthorization` when `authorized_` is the caller and
    ///      `OperatorAuth_ExpiredAuthorization` when `authorizationDeadline_` is in the past.
    /// @param authorized_ Operator to authorize.
    /// @param authorizationDeadline_ Timestamp until which the operator is authorized, in seconds.
    function setAuthorization(address authorized_, uint48 authorizationDeadline_) external;

    /// @notice Sets operator authorization using an EIP-712 signature from the account.
    /// @dev Reverts with `OperatorAuth_ExpiredSignature` when the signature deadline has passed,
    ///      `OperatorAuth_ExpiredAuthorization` when the authorization deadline has passed,
    ///      `OperatorAuth_InvalidNonce` when the signed nonce is not current,
    ///      `OperatorAuth_InvalidSigner` when the signature is not from the account, or
    ///      `OperatorAuth_SelfAuthorization` when the account authorizes itself.
    /// @param authorization_ Signed authorization payload.
    /// @param signature_ ECDSA signature over `authorization_`.
    function setAuthorizationWithSig(
        Authorization calldata authorization_,
        Signature calldata signature_
    ) external;

    /// @notice Clears operator authorization for the caller.
    /// @dev Invalidates authorization signatures prepared with the caller's current nonce.
    /// @param authorized_ Operator whose authorization should be cancelled.
    function cancelAuthorization(address authorized_) external;
}
