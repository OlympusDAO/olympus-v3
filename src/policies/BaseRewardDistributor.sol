// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";

// Libraries
import {MerkleProof} from "@openzeppelin-5.3.0/utils/cryptography/MerkleProof.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title  Base Reward Distributor
/// @notice Abstract base contract for merkle tree-based rewards distribution
/// @dev    This contract provides core functionality for merkle-based reward claims.
///         Implementations should override virtual functions to customize behavior.
///
///         Architecture:
///         - Rewards are calculated off-chain
///         - Backend generates weekly merkle trees with accumulated rewards per user
///         - Merkle roots are posted on-chain by authorized role
///         - Users submit proofs to claim their rewards
abstract contract BaseRewardDistributor is Policy, PolicyEnabler, IRewardDistributor {
    // ========== STATE VARIABLES ========== //

    /// @notice Role that can update merkle roots
    bytes32 public constant ROLE_MERKLE_UPDATER = "rewards_merkle_updater";

    /// @notice Minimum duration between week advances (7 days)
    uint256 public constant WEEK_DURATION = 7 days;

    /// @notice The TRSRY module
    TRSRYv1 internal TRSRY;

    /// @notice Mapping from week number => merkle root
    /// @dev    Week 0 is the first distribution week
    mapping(uint256 week => bytes32 merkleRoot) public weeklyMerkleRoots;

    /// @notice Mapping from user address => week number => claimed status
    mapping(address user => mapping(uint256 week => bool claimed)) public hasClaimed;

    /// @notice Timestamp when week 0 begins
    uint40 public immutable START_TIMESTAMP;

    // ========== MODIFIERS ========== //

    modifier onlyAuthorized(bytes32 role_) {
        ROLES.requireRole(role_, msg.sender);
        _;
    }

    // ========== CONSTRUCTOR ========== //

    /// @param kernel_          The Kernel address
    /// @param startTimestamp_  The timestamp when week 0 begins (typically midnight UTC of start date)
    constructor(address kernel_, uint256 startTimestamp_) Policy(Kernel(kernel_)) {
        if (startTimestamp_ == 0) revert DRD_InvalidAddress();
        START_TIMESTAMP = uint40(startTimestamp_);
        // Disabled by default by PolicyEnabler
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");

        // ROLES is inherited from PolicyEnabler
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[1]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        virtual
        override
        returns (Permissions[] memory permissions)
    {
        Keycode trsryKeycode = toKeycode("TRSRY");

        permissions = new Permissions[](2);
        permissions[0] = Permissions(trsryKeycode, TRSRY.increaseWithdrawApproval.selector);
        permissions[1] = Permissions(trsryKeycode, TRSRY.withdrawReserves.selector);
    }

    function VERSION() external pure virtual returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
        return (major, minor);
    }

    // ========== MERKLE ROOT MANAGEMENT ========== //

    /// @notice Set the merkle root for a week
    /// @dev    - Only callable by the ROLE_MERKLE_UPDATER role.
    ///         - Weeks can be set in any order.
    ///         - Calls are only allowed when the week deadline has been reached.
    ///         - Merkle tree cannot be updated once set.
    /// @param  week_          The week number being set
    /// @param  merkleRoot_     The merkle root for the week's distribution
    /// @return weekEndTime     The timestamp when the week ends
    function setMerkleRoot(
        uint40 week_,
        bytes32 merkleRoot_
    )
        external
        virtual
        onlyAuthorized(ROLE_MERKLE_UPDATER)
        onlyEnabled
        returns (uint256 weekEndTime)
    {
        // Validate input
        if (merkleRoot_ == bytes32(0)) revert DRD_InvalidProof();

        // Ensure the week hasn't already been set
        if (weeklyMerkleRoots[week_] != bytes32(0)) revert DRD_WeekAlreadySet(week_);

        // Calculate when this week should end based on start timestamp and week number
        weekEndTime = START_TIMESTAMP + (week_ + 1) * WEEK_DURATION;

        // Ensure the current time has reached or passed the week deadline
        if (block.timestamp < weekEndTime) {
            revert DRD_WeekTooEarly();
        }

        // Set the merkle root for this week
        weeklyMerkleRoots[week_] = merkleRoot_;

        _emitMerkleRootSet(week_, merkleRoot_);
    }

    // ========== CLAIM FUNCTIONS ========== //

    /// @notice Claim rewards for one or more weeks in a single transaction
    /// @param  weeks_          Array of week numbers to claim
    /// @param  amounts_        Array of amounts for each week (must match merkle leaves)
    /// @param  proofs_         Array of merkle proofs, one per week
    /// @param  asVaultToken_   If true, claim as vault token (e.g., sUSDS); if false, unwrap to underlying token (e.g., USDS)
    function claim(
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_,
        bool asVaultToken_
    ) external virtual onlyEnabled {
        _validateClaimArrays(weeks_, amounts_, proofs_);

        uint256 totalAmount = _processClaims(msg.sender, weeks_, amounts_, proofs_);

        _transferRewards(msg.sender, totalAmount, weeks_.length, asVaultToken_);
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Validate claim input arrays
    function _validateClaimArrays(
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) internal pure {
        if (weeks_.length == 0) revert DRD_NoWeeksSpecified();
        if (weeks_.length != amounts_.length || weeks_.length != proofs_.length) {
            revert DRD_ArrayLengthMismatch();
        }
    }

    /// @notice Process claims and return total amount
    function _processClaims(
        address user_,
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) internal returns (uint256 totalAmount) {
        for (uint256 i = 0; i < weeks_.length; ) {
            uint256 week = weeks_[i];
            uint256 amount = amounts_[i];

            // Verify merkle root is set for this week
            if (weeklyMerkleRoots[week] == bytes32(0)) revert DRD_MerkleRootNotSet(week);

            // Verify and mark as claimed
            _verifyAndMarkClaimed(user_, week, amount, proofs_[i]);

            totalAmount += amount;

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Verify merkle proof without modifying state
    /// @dev    Used for preview functionality
    function _verifyProof(
        address user_,
        uint256 week_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal view virtual {
        // Check if already claimed
        if (hasClaimed[user_][week_]) revert DRD_AlreadyClaimed(week_);

        // Construct the leaf node: keccak256(abi.encode(user, week, amount))
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user_, week_, amount_))));

        // Verify merkle proof
        if (!MerkleProof.verify(proof_, weeklyMerkleRoots[week_], leaf)) {
            revert DRD_InvalidProof();
        }
    }

    /// @notice Verify merkle proof and mark week as claimed for user
    function _verifyAndMarkClaimed(
        address user_,
        uint256 week_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal virtual {
        // Verify proof first
        _verifyProof(user_, week_, amount_, proof_);

        // Mark as claimed
        hasClaimed[user_][week_] = true;
    }

    /// @notice Internal function to transfer rewards from treasury
    /// @dev    Must be implemented by derived contracts
    /// @param  to_             Address to transfer rewards to
    /// @param  amount_         Amount to transfer
    /// @param  weekCount_      Number of weeks being claimed (for event)
    /// @param  asVaultToken_   If true, transfer as vault token; if false, unwrap first
    function _transferRewards(
        address to_,
        uint256 amount_,
        uint256 weekCount_,
        bool asVaultToken_
    ) internal virtual;

    /// @notice Emit merkle root set event
    /// @dev    Must be implemented by derived contracts to provide token address
    function _emitMerkleRootSet(uint256 week_, bytes32 merkleRoot_) internal virtual;

    // ========== ERC165 ========== //

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(PolicyEnabler, IERC165) returns (bool) {
        return
            interfaceId == type(IRewardDistributor).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}

