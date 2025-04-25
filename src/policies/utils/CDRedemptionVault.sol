// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Interfaces
import {IConvertibleDepositRedemptionVault} from "../interfaces/IConvertibleDepositRedemptionVault.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

// Libraries
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

// Bophades
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title  CDRedemptionVault
/// @notice A contract that manages the redemption of convertible deposit (CD) tokens
abstract contract CDRedemptionVault is
    IConvertibleDepositRedemptionVault,
    PolicyEnabler,
    ReentrancyGuard
{
    using SafeTransferLib for ERC20;

    // ========== STATE VARIABLES ========== //

    /// @notice The number of commitments per user
    mapping(address => uint16) internal _userCommitmentCount;

    /// @notice The commitments for each user and commitment ID
    mapping(address => mapping(uint16 => UserCommitment)) internal _userCommitments;

    /// @notice The TRSRY module.
    /// @dev    The inheriting contract must assign the CDEPO module address to this state variable using `configureDependencies()`
    TRSRYv1 public TRSRY;

    /// @notice The address of the CDEPO module
    /// @dev    The inheriting contract must assign the CDEPO module address to this state variable using `configureDependencies()`
    ///         The inheriting contract must also ensure that the following permissions are requested:
    ///         - `CDEPO.redeemFor()`
    ///         - `CDEPO.reclaimFor()`
    ///         - `CDEPO.setReclaimRate()`
    CDEPOv1 public CDEPO;

    // ========== USER COMMITMENTS ========== //

    /// @inheritdoc IConvertibleDepositRedemptionVault
    function getUserCommitmentCount(address user_) external view returns (uint16 count) {
        return _userCommitmentCount[user_];
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    function getUserCommitment(
        address user_,
        uint16 commitmentId_
    ) external view returns (UserCommitment memory commitment) {
        commitment = _userCommitments[user_][commitmentId_];
        if (commitment.cdToken == IConvertibleDepositERC20(address(0)))
            revert CDRedemptionVault_InvalidCommitmentId(user_, commitmentId_);

        return commitment;
    }

    // ========== REDEMPTION FLOW ========== //

    modifier onlyValidCommitmentId(address user_, uint16 commitmentId_) {
        // If the CD token is the zero address, the commitment is invalid
        if (address(_userCommitments[user_][commitmentId_].cdToken) == address(0))
            revert CDRedemptionVault_InvalidCommitmentId(user_, commitmentId_);
        _;
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    /// @dev        This function performs the following:
    ///             - Checks that the CD token is configured in the CDEPO module
    ///             - Creates a new commitment for the user
    ///             - Transfers the CD tokens from the caller to this contract
    ///             - Emits the Committed event
    ///             - Returns the new commitment ID
    ///
    ///             The function will revert if:
    ///             - The CD token is not configured in the CDEPO module
    ///             - The amount is 0
    ///             - The caller has not approved this contract to spend the CD tokens
    ///             - The caller does not have enough CD tokens
    function commit(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external nonReentrant onlyEnabled returns (uint16 commitmentId) {
        // Check that the CD token is valid
        if (!CDEPO.isConvertibleDepositToken(address(cdToken_)))
            revert CDRedemptionVault_InvalidCDToken(address(cdToken_));

        // Check that the amount is not 0
        if (amount_ == 0) revert CDRedemptionVault_ZeroAmount(msg.sender);

        // Create a User Commitment
        commitmentId = _userCommitmentCount[msg.sender]++;
        _userCommitments[msg.sender][commitmentId] = UserCommitment({
            cdToken: cdToken_,
            amount: amount_,
            redeemableAt: uint48(block.timestamp + cdToken_.periodMonths() * 30 days)
        });

        // Transfer the CD tokens from the caller to this contract
        ERC20(address(cdToken_)).safeTransferFrom(msg.sender, address(this), amount_);

        // Return the new commitment ID
        emit Committed(msg.sender, commitmentId, address(cdToken_), amount_);
        return commitmentId;
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    /// @dev        This function performs the following:
    ///             - Checks that the commitment ID is valid
    ///             - Checks that the amount is not greater than the commitment
    ///             - Reduces the commitment amount
    ///             - Transfers the quantity of CD tokens to the caller
    ///             - Emits the Uncommitted event
    ///
    ///             The function will revert if:
    ///             - The commitment ID is invalid
    ///             - The amount is 0
    ///             - The amount is greater than the committed amount
    function uncommit(
        uint16 commitmentId_,
        uint256 amount_
    ) external nonReentrant onlyEnabled onlyValidCommitmentId(msg.sender, commitmentId_) {
        // Get the commitment
        UserCommitment storage commitment = _userCommitments[msg.sender][commitmentId_];

        // Check that the amount is not 0
        if (amount_ == 0) revert CDRedemptionVault_ZeroAmount(msg.sender);

        // Check that the amount is not greater than the commitment
        if (amount_ > commitment.amount)
            revert CDRedemptionVault_InvalidAmount(msg.sender, commitmentId_, amount_);

        // Update the commitment
        commitment.amount -= amount_;

        // Transfer the quantity of CD tokens to the caller
        ERC20(address(commitment.cdToken)).safeTransfer(msg.sender, amount_);

        // Emit the uncommitted event
        emit Uncommitted(msg.sender, commitmentId_, address(commitment.cdToken), amount_);
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    /// @dev        This function performs the following:
    ///             - Checks that the commitment ID is valid
    ///             - Checks that the commitment is redeemable
    ///             - Updates the commitment
    ///             - Redeems the CD tokens for the underlying asset
    ///             - Transfers the underlying asset to the caller
    ///             - Emits the Redeemed event
    ///
    ///             The function will revert if:
    ///             - The commitment ID is invalid
    ///             - The commitment is not yet redeemable
    function redeem(
        uint16 commitmentId_
    ) external nonReentrant onlyEnabled onlyValidCommitmentId(msg.sender, commitmentId_) {
        // Get the commitment
        UserCommitment storage commitment = _userCommitments[msg.sender][commitmentId_];

        // Check that the commitment is not already redeemed
        if (commitment.amount == 0)
            revert CDRedemptionVault_AlreadyRedeemed(msg.sender, commitmentId_);

        // Check that the commitment is redeemable
        if (block.timestamp < commitment.redeemableAt)
            revert CDRedemptionVault_TooEarly(msg.sender, commitmentId_);

        // Update the commitment
        uint256 commitmentAmount = commitment.amount;
        commitment.amount = 0;

        // Redeem the CD tokens for the underlying asset
        // This also burns the CD tokens
        ERC20(address(commitment.cdToken)).safeApprove(address(CDEPO), commitmentAmount);
        CDEPO.redeemFor(commitment.cdToken, address(this), commitmentAmount);

        // Transfer the underlying asset to the caller
        ERC20(address(commitment.cdToken.asset())).safeTransfer(msg.sender, commitmentAmount);

        // Emit the redeemed event
        emit Redeemed(msg.sender, commitmentId_, address(commitment.cdToken), commitmentAmount);
    }

    // ========== RECLAIM ========== //

    /// @inheritdoc IConvertibleDepositRedemptionVault
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The amount of CD tokens to reclaim is 0
    ///             - The reclaimed amount is 0
    function previewReclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external view onlyEnabled returns (uint256 reclaimed, address cdTokenSpender) {
        // Preview reclaiming the amount
        // This will revert if the amount or reclaimed amount is 0
        reclaimed = CDEPO.previewReclaim(cdToken_, amount_);

        return (reclaimed, address(CDEPO));
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The amount of CD tokens to reclaim is 0
    ///             - The reclaimed amount is 0
    function reclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external nonReentrant onlyEnabled returns (uint256 reclaimed) {
        // Reclaim the CD deposit
        // This will revert if the amount or reclaimed amount is 0
        // It will return the discount quantity of underlying asset to this contract
        reclaimed = CDEPO.reclaimFor(cdToken_, msg.sender, amount_);

        // Transfer the tokens to the caller
        ERC20 depositToken = ERC20(address(cdToken_.asset()));
        depositToken.safeTransfer(msg.sender, reclaimed);

        // Wrap any remaining tokens and transfer to the TRSRY
        uint256 remainingTokens = depositToken.balanceOf(address(this));
        if (remainingTokens > 0) {
            IERC4626 vault = cdToken_.vault();
            depositToken.safeApprove(address(vault), remainingTokens);
            vault.deposit(remainingTokens, address(TRSRY));
        }

        // Emit event
        emit Reclaimed(msg.sender, address(depositToken), reclaimed, amount_ - reclaimed);

        return reclaimed;
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    /// @dev    This function will revert if:
    ///         - The caller is not an admin
    ///         - CDEPO reverts
    ///
    /// @param  cdToken_      The address of the CD token
    /// @param  reclaimRate_  The new reclaim rate to set
    function setReclaimRate(
        IConvertibleDepositERC20 cdToken_,
        uint16 reclaimRate_
    ) external onlyAdminRole {
        // CDEPO will handle validation
        CDEPO.setReclaimRate(cdToken_, reclaimRate_);
    }
}
