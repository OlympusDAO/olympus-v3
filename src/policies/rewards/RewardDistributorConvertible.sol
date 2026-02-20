// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

// Base Contract
import {BaseRewardDistributor} from "src/policies/rewards/BaseRewardDistributor.sol";

// Interfaces
import {IRewardDistributor} from "src/policies/interfaces/rewards/IRewardDistributor.sol";
import {IRewardDistributorConvertible} from "src/policies/interfaces/rewards/IRewardDistributorConvertible.sol";
import {IConvertibleOHMTeller} from "src/policies/rewards/convertible/interfaces/IConvertibleOHMTeller.sol";
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";

// Bophades
import {Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @title Reward Distributor for Convertible OHM Tokens
/// @notice Distributes convertible OHM tokens to users based on Merkle proofs.
/// @dev Architecture:
///      - Rewards are calculated off-chain.
///      - Backend generates Merkle trees with accumulated rewards per user per epoch.
///      - Merkle roots are posted on-chain by the authorized role.
///      - Users submit proofs to claim their rewards in convertible tokens.
///
///      Tokens are deployed and minted via ConvertibleOHMTeller.
contract RewardDistributorConvertible is BaseRewardDistributor, IRewardDistributorConvertible {
    // ========== IMMUTABLES ========== //

    /// @notice The teller contract for deploying and minting convertible tokens
    IConvertibleOHMTeller public immutable TELLER;

    // ========== STATE VARIABLES ========== //

    /// @inheritdoc IRewardDistributorConvertible
    mapping(uint256 epochEndDate => address) public epochConvertibleTokens;

    // ========== CONSTRUCTOR ========== //

    /// @param kernel_ The kernel address
    /// @param lastEpochEndDate_ The end-of-day timestamp (23:59:59 UTC) of the day before the first epoch
    /// @param teller_ The address of the Convertible OHM Teller
    constructor(
        address kernel_,
        uint256 lastEpochEndDate_,
        address teller_
    ) BaseRewardDistributor(kernel_, lastEpochEndDate_) {
        if (teller_ == address(0)) revert RewardDistributor_InvalidAddress();
        TELLER = IConvertibleOHMTeller(teller_);
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        return dependencies;
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory) {}

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IRewardDistributor
    function endEpoch(
        uint40 epochEndDate_,
        bytes32 merkleRoot_,
        bytes calldata params_
    ) external onlyAuthorized(ROLE_REWARDS_MANAGER) onlyEnabled returns (address token) {
        IRewardDistributorConvertible.EndEpochParams memory p = abi.decode(
            params_,
            (IRewardDistributorConvertible.EndEpochParams)
        );

        // Validate that the token expires after the end of the epoch (users need time to claim their tokens)
        // Note: The teller rounds expiry_ to the nearest day at 0000 UTC, since
        // convertible tokens are only unique to a day, not a specific timestamp
        if (uint48(p.expiry / 1 days) * 1 days <= epochEndDate_)
            revert RewardDistributor_InvalidToken();

        // Set and validate the merkle root
        _setMerkleRoot(epochEndDate_, merkleRoot_);

        // Deploy the new convertible token via the teller
        token = TELLER.deploy(p.quoteToken, p.eligible, p.expiry, p.strikePrice);

        // Store the convertible token for this epoch
        epochConvertibleTokens[epochEndDate_] = token;

        emit EpochEnded(epochEndDate_, token, params_);
        return token;
    }

    // ========== USER FUNCTIONS ========== //

    /// @inheritdoc IRewardDistributorConvertible
    function claim(
        uint256[] calldata epochEndDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external onlyEnabled returns (address[] memory tokens, uint256[] memory mintedAmounts) {
        _validateClaimArrays(epochEndDates_, amounts_, proofs_);

        uint256 len = epochEndDates_.length;
        tokens = new address[](len);
        mintedAmounts = new uint256[](len);

        // Process claims for each epoch by verifying proofs, marking as claimed and minting convertible tokens
        bool hasMinted = false;
        for (uint256 i = 0; i < len; ++i) {
            // Get the convertible token for this epoch
            address convertibleToken = epochConvertibleTokens[epochEndDates_[i]];
            if (convertibleToken == address(0)) revert RewardDistributor_InvalidToken();

            // Validate preconditions, verify proof, and mark as claimed
            _validateAndMarkClaimed(msg.sender, epochEndDates_[i], amounts_[i], proofs_[i]);

            tokens[i] = convertibleToken;
            mintedAmounts[i] = amounts_[i];

            // Only mint tokens if amount != 0
            if (amounts_[i] != 0) {
                hasMinted = true;

                TELLER.create(convertibleToken, msg.sender, amounts_[i]);
                emit ConvertibleTokensClaimed(
                    msg.sender,
                    convertibleToken,
                    amounts_[i],
                    epochEndDates_[i]
                );
            }
        }

        // Revert if no tokens were actually minted
        if (!hasMinted) revert RewardDistributor_NothingToClaim();
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IRewardDistributorConvertible
    function previewClaim(
        address user_,
        uint256[] calldata epochEndDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external view returns (address[] memory tokens, uint256[] memory claimableAmounts) {
        uint256 len = epochEndDates_.length;
        if (len == 0 || len != amounts_.length || len != proofs_.length)
            return (tokens, claimableAmounts);

        tokens = new address[](len);
        claimableAmounts = new uint256[](len);

        for (uint256 i = 0; i < len; ++i) {
            // Get the convertible token for this epoch (may be the zero address if not set)
            tokens[i] = epochConvertibleTokens[epochEndDates_[i]];

            if (_isClaimable(user_, epochEndDates_[i], amounts_[i], proofs_[i]))
                claimableAmounts[i] = amounts_[i];
        }
    }

    // ========== ERC165 ========== //

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(BaseRewardDistributor, IERC165) returns (bool) {
        return
            interfaceId == type(IRewardDistributorConvertible).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
