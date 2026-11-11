// SPDX-License-Identifier: MIT
pragma solidity >=0.8.34;

/// @title Scoped operator authorization
/// @notice Instance-scoped grants with unordered actions, transaction-local or reusable lifetimes,
///         and consumer-defined permissions and authorization contexts.
interface IOperatorAuth {
    /// @notice A required account/operator identity is zero or the submitter cannot approve it.
    error OperatorAuth_InvalidIdentity();
    /// @notice An account attempted to grant or cancel delegated authority to itself.
    error OperatorAuth_SelfGrant();
    /// @notice A grant's action mask is empty or contains unsupported bits.
    /// @param actions Rejected action mask.
    error OperatorAuth_InvalidActions(uint8 actions);
    /// @notice An authority check did not select exactly one supported action.
    /// @param action Rejected action value.
    error OperatorAuth_InvalidAction(uint8 action);
    /// @notice The grant's inclusive deadline has passed.
    /// @param deadline Expired grant deadline, in absolute seconds.
    error OperatorAuth_ExpiredGrant(uint48 deadline);
    /// @notice Acceptance supplied stale account or pair epochs.
    error OperatorAuth_InvalidEpoch();
    /// @notice An epoch cannot be advanced without wrapping uint256.
    error OperatorAuth_EpochExhausted();
    /// @notice The account did not authenticate the complete signed grant payload.
    error OperatorAuth_InvalidSignature();
    /// @notice The namespace, live grant, selected action permission or original stamp is stale/invalid.
    error OperatorAuth_InvalidContext();
    /// @notice Acceptance-only signature data is unsupported by the consumer.
    error OperatorAuth_UnsupportedSignatureData();

    /// @notice Complete authority accepted for one account/operator pair.
    /// @param account Position owner granting authority.
    /// @param operator Operator allowed to act for the account.
    /// @param accountEpoch Account cancellation epoch expected at acceptance.
    /// @param pairEpoch Pair acceptance/cancellation epoch expected at acceptance.
    /// @param deadline Inclusive grant deadline, compared to the full-width timestamp.
    /// @param multiple False restricts authority to the accepting transaction; true permits later transactions.
    /// @param actions Unordered bit mask of the consumer's supported actions.
    /// @param context Consumer-defined live namespace authenticated by direct/signed acceptance.
    /// @param permissions Canonical, consumer-bounded permission data.
    struct Grant {
        address account;
        address operator;
        uint256 accountEpoch;
        uint256 pairEpoch;
        uint48 deadline;
        bool multiple;
        uint8 actions;
        bytes32 context;
        bytes permissions;
    }

    /// @notice Accepted grant metadata; permissionsHash fingerprints the acceptance calldata bytes.
    /// @dev Epoch fields are the pre-acceptance expected epochs, not the incremented pair counter.
    /// @param caller Account or designated operator submitting acceptance.
    /// @param account Account granting authority.
    /// @param operator Designated operator.
    /// @param accountEpoch Account epoch authenticated at acceptance.
    /// @param pairEpoch Pair epoch authenticated before acceptance advances it.
    /// @param deadline Inclusive grant deadline, in absolute seconds.
    /// @param multiple Whether authority survives the accepting transaction.
    /// @param actions Accepted unordered action mask.
    /// @param context Accepted consumer namespace.
    /// @param permissionsHash Keccak256 hash of the exact accepted permission bytes.
    event GrantAccepted(
        address indexed caller,
        address indexed account,
        address indexed operator,
        uint256 accountEpoch,
        uint256 pairEpoch,
        uint48 deadline,
        bool multiple,
        uint8 actions,
        bytes32 context,
        bytes32 permissionsHash
    );
    /// @notice Records pair cancellation in this Auth instance.
    /// @param account Account cancelling authority.
    /// @param operator Operator whose pair epoch advanced.
    /// @param nextPairEpoch Pair epoch after cancellation.
    event GrantCancelled(address indexed account, address indexed operator, uint256 nextPairEpoch);
    /// @notice Records account-wide cancellation in this Auth instance.
    /// @param account Account cancelling all its operators.
    /// @param nextAccountEpoch Account epoch after cancellation.
    event AllGrantsCancelled(address indexed account, uint256 nextAccountEpoch);

    /// @notice Grants authority through an account transaction, including a Safe transaction.
    /// @param grant Complete grant to accept in the caller's own account namespace.
    function approveGrant(Grant calldata grant) external;

    /// @notice Accepts account-signed authority submitted by the designated operator.
    /// @param grant Complete grant to accept.
    /// @param signatureData Consumer-defined acceptance-only data, authenticated by the signature.
    /// @param signature EOA or ERC-1271 signature over this Auth's current-chain typed payload.
    function acceptGrant(
        Grant calldata grant,
        bytes calldata signatureData,
        bytes calldata signature
    ) external;

    /// @notice Advances the caller's pair epoch without deleting historical permissions.
    /// @param operator Operator whose authority is cancelled in this Auth instance.
    function cancelGrant(address operator) external;

    /// @notice Advances the caller's account epoch without enumerating or resetting pair counters.
    function cancelAllGrants() external;

    /// @notice Returns the account cancellation epoch local to this Auth instance.
    /// @param account Account whose epoch is requested.
    /// @return Current account cancellation epoch.
    function accountEpochs(address account) external view returns (uint256);

    /// @notice Returns the next pair acceptance/cancellation epoch, independent of context namespaces.
    /// @param account Account granting authority.
    /// @param operator Designated operator.
    /// @return Current pair epoch expected by a fresh acceptance or cancellation.
    function pairEpochs(address account, address operator) external view returns (uint256);

    /// @notice Returns a live grant in the current namespace, or an entirely empty grant.
    /// @dev Absent, expired, cancelled and replaced records return empty; deadline equality is live.
    ///      Capture and revalidation are still required around effects.
    /// @param account Account granting authority.
    /// @param operator Designated operator.
    /// @return Current live accepted grant, or an empty record when none exists.
    function getGrant(address account, address operator) external view returns (Grant memory);

    /// @notice Returns the consumer's current live namespace; zero is a real default namespace.
    /// @param account Account granting authority.
    /// @param operator Designated operator.
    /// @return Consumer-defined current authorization namespace.
    function authorizationContext(
        address account,
        address operator
    ) external view returns (bytes32);

    /// @notice Captures the original authority for an individual supported action.
    /// @dev A returned stamp is not bearer authority; consumers must supply the actual operator.
    /// @param account Account on whose behalf the action executes.
    /// @param operator Actual action caller whose authority is checked.
    /// @param action Exactly one supported action bit.
    /// @return Original delegated-grant stamp, or zero for intrinsic owner authority.
    function captureAuthorization(
        address account,
        address operator,
        uint8 action
    ) external view returns (bytes32);

    /// @notice Revalidates the original authority and returns its permission data.
    /// @param account Account on whose behalf the action executes.
    /// @param operator Actual action caller whose authority is checked.
    /// @param action Exactly one supported action bit.
    /// @param originalStamp Stamp captured before external preparation or effects.
    /// @return Authenticated delegated permissions, or empty bytes for intrinsic owner authority.
    function validateAuthorization(
        address account,
        address operator,
        uint8 action,
        bytes32 originalStamp
    ) external view returns (bytes memory);

    /// @notice Returns this Auth instance's current-chain EIP-712 domain separator.
    /// @return Domain separator committing to the chain ID and this Auth address.
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
