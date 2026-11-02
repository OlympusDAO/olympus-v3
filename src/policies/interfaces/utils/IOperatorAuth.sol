// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Operator Authorization
/// @notice Reusable operator authorization surface for policies that support on-behalf-of actions.
interface IOperatorAuth {
    // ========== EVENTS ========== //

    /// @notice Emitted when an operator grant is set, updated or cancelled.
    /// @param caller Account submitting the direct change or relaying the signed authorization.
    /// @param account Account whose operator authorization changed.
    /// @param authorized Operator receiving or losing authority.
    /// @param authorizationDeadline Inclusive grant deadline in seconds; zero denotes cancellation.
    event AuthorizationSet(
        address indexed caller,
        address indexed account,
        address indexed authorized,
        uint48 authorizationDeadline
    );

    // ========== ERRORS ========== //

    /// @notice The caller has no valid authorization to act for the requested account.
    error OperatorAuth_UnauthorizedOnBehalfOf();

    /// @notice The proposed operator authorization deadline has passed.
    /// @param authorizationDeadline Expired inclusive authorization deadline, in seconds.
    error OperatorAuth_ExpiredAuthorization(uint48 authorizationDeadline);

    /// @notice The deadline for submitting the signed authorization has passed.
    /// @param signatureDeadline Expired inclusive signature submission deadline, in seconds.
    error OperatorAuth_ExpiredSignature(uint48 signatureDeadline);

    /// @notice A signed authorization uses a nonce other than the account's current nonce.
    /// @param nonce Nonce supplied in the signed authorization.
    error OperatorAuth_InvalidNonce(uint256 nonce);

    /// @notice The account cannot consume another authorization nonce.
    /// @param account Account whose nonce reached uint256.max.
    error OperatorAuth_NonceExhausted(address account);

    /// @notice The recovered signer differs from the account granting authorization.
    /// @param signer Address recovered from the authorization signature.
    /// @param expectedSigner Account whose signature is required.
    error OperatorAuth_InvalidSigner(address signer, address expectedSigner);

    /// @notice An account attempted to grant an operator authorization to itself.
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
    /// @param authorized_ Operator to authorize.
    /// @param authorizationDeadline_ Timestamp until which the operator is authorized, in seconds.
    function setAuthorization(address authorized_, uint48 authorizationDeadline_) external;

    /// @notice Sets operator authorization using an EIP-712 signature from the account.
    /// @dev Any relayer may submit the payload; the account's signature grants authority and consumes
    ///      its current nonce. The authorization and signature deadlines are independently inclusive.
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
