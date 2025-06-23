// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositRedemptionVault} from "src/bases/interfaces/IDepositRedemptionVault.sol";

// Libraries
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {ReentrancyGuard} from "@solmate-6.2.0/utils/ReentrancyGuard.sol";
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {DepositManager} from "src/policies/DepositManager.sol";

/// @title  BaseDepositRedemptionVault
/// @notice A contract that manages the redemption of receipt tokens
abstract contract BaseDepositRedemptionVault is
    IDepositRedemptionVault,
    PolicyEnabler,
    ReentrancyGuard
{
    using SafeTransferLib for ERC20;
    using FullMath for uint256;

    // Tasks
    // [ ] Consider if dependency on PolicyEnabler is needed

    // ========== CONSTANTS ========== //

    /// @notice The number representing 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    // ========== STATE VARIABLES ========== //

    /// @notice The address of the token manager
    DepositManager public immutable DEPOSIT_MANAGER;

    /// @notice The TRSRY module.
    /// @dev    The inheriting contract must assign the TRSRY module address to this state variable using `configureDependencies()`
    TRSRYv1 public TRSRY;

    /// @notice The number of commitments per user
    mapping(address => uint16) internal _userCommitmentCount;

    /// @notice The commitments for each user and commitment ID
    mapping(address => mapping(uint16 => UserCommitment)) internal _userCommitments;

    // ========== CONSTRUCTOR ========== //

    constructor(address depositManager_) {
        DEPOSIT_MANAGER = DepositManager(depositManager_);
    }

    /// @notice Pull the receipt tokens from the caller
    function _pullReceiptToken(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) internal {
        // Check that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // Validate that the asset is supported
        if (!DEPOSIT_MANAGER.isConfiguredDeposit(depositToken_, depositPeriod_))
            revert RedemptionVault_InvalidToken(address(depositToken_), depositPeriod_);

        // Transfer the receipt tokens from the caller to this contract
        DEPOSIT_MANAGER.transferFrom(
            msg.sender,
            address(this),
            DEPOSIT_MANAGER.getReceiptTokenId(depositToken_, depositPeriod_),
            amount_
        );
    }

    // ========== USER COMMITMENTS ========== //

    /// @inheritdoc IDepositRedemptionVault
    function getRedeemCommitmentCount(address user_) external view returns (uint16 count) {
        return _userCommitmentCount[user_];
    }

    /// @inheritdoc IDepositRedemptionVault
    function getRedeemCommitment(
        address user_,
        uint16 commitmentId_
    ) external view returns (UserCommitment memory commitment) {
        commitment = _userCommitments[user_][commitmentId_];
        // TODO should this be a revert?
        if (address(commitment.depositToken) == address(0))
            revert RedemptionVault_InvalidCommitmentId(user_, commitmentId_);

        return commitment;
    }

    // ========== REDEMPTION FLOW ========== //

    modifier onlyValidCommitmentId(address user_, uint16 commitmentId_) {
        // If the deposit token is the zero address, the commitment is invalid
        if (address(_userCommitments[user_][commitmentId_].depositToken) == address(0))
            revert RedemptionVault_InvalidCommitmentId(user_, commitmentId_);
        _;
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function performs the following:
    ///             - Creates a new commitment for the user
    ///             - Transfers the receipt tokens from the caller to this contract
    ///             - Emits the Committed event
    ///             - Returns the new commitment ID
    ///
    ///             The function will revert if:
    ///             - The deposit token and period are not supported
    ///             - The amount is 0
    ///             - The caller has not approved this contract to spend the receipt tokens
    ///             - The caller does not have enough receipt tokens
    function commitRedeem(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external nonReentrant onlyEnabled returns (uint16 commitmentId) {
        // Create a User Commitment
        commitmentId = _userCommitmentCount[msg.sender]++;
        _userCommitments[msg.sender][commitmentId] = UserCommitment({
            depositToken: depositToken_,
            depositPeriod: depositPeriod_,
            amount: amount_,
            redeemableAt: uint48(block.timestamp + uint48(depositPeriod_) * 30 days)
        });

        // Pull the receipt tokens from the caller
        // This will validate that the deposit token is supported
        _pullReceiptToken(depositToken_, depositPeriod_, amount_);

        // Return the new commitment ID
        emit Committed(msg.sender, commitmentId, address(depositToken_), depositPeriod_, amount_);
        return commitmentId;
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function performs the following:
    ///             - Checks that the commitment ID is valid
    ///             - Checks that the amount is not greater than the commitment
    ///             - Reduces the commitment amount
    ///             - Transfers the quantity of receipt tokens to the caller
    ///             - Emits the Uncommitted event
    ///
    ///             The function will revert if:
    ///             - The commitment ID is invalid
    ///             - The amount is 0
    ///             - The amount is greater than the committed amount
    function uncommitRedeem(
        uint16 commitmentId_,
        uint256 amount_
    ) external nonReentrant onlyEnabled onlyValidCommitmentId(msg.sender, commitmentId_) {
        // Get the commitment
        UserCommitment storage commitment = _userCommitments[msg.sender][commitmentId_];

        // Check that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // Check that the amount is not greater than the commitment
        if (amount_ > commitment.amount)
            revert RedemptionVault_InvalidAmount(msg.sender, commitmentId_, amount_);

        // Update the commitment
        commitment.amount -= amount_;

        // Transfer the quantity of receipt tokens to the caller
        DEPOSIT_MANAGER.transfer(
            msg.sender,
            DEPOSIT_MANAGER.getReceiptTokenId(commitment.depositToken, commitment.depositPeriod),
            amount_
        );

        // Emit the uncommitted event
        emit Uncommitted(
            msg.sender,
            commitmentId_,
            address(commitment.depositToken),
            commitment.depositPeriod,
            amount_
        );
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function performs the following:
    ///             - Checks that the commitment ID is valid
    ///             - Checks that the commitment is redeemable
    ///             - Updates the commitment
    ///             - Redeems the receipt tokens for the underlying asset
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
            revert RedemptionVault_AlreadyRedeemed(msg.sender, commitmentId_);

        // Check that the commitment is redeemable
        if (block.timestamp < commitment.redeemableAt)
            revert RedemptionVault_TooEarly(msg.sender, commitmentId_);

        // Update the commitment
        uint256 commitmentAmount = commitment.amount;
        commitment.amount = 0;

        // Withdraw the underlying asset from the deposit manager
        // This will burn the receipt tokens from this contract and send the released deposit tokens to the caller
        DEPOSIT_MANAGER.approve(
            address(DEPOSIT_MANAGER),
            DEPOSIT_MANAGER.getReceiptTokenId(commitment.depositToken, commitment.depositPeriod),
            commitmentAmount
        );
        DEPOSIT_MANAGER.withdraw(
            commitment.depositToken,
            commitment.depositPeriod,
            address(this),
            msg.sender,
            commitmentAmount,
            false
        );

        // Emit the redeemed event
        emit Redeemed(
            msg.sender,
            commitmentId_,
            address(commitment.depositToken),
            commitment.depositPeriod,
            commitmentAmount
        );
    }

    // ========== RECLAIM ========== //

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The amount of deposit tokens to reclaim is 0
    ///             - The reclaimed amount is 0
    function previewReclaim(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) public view onlyEnabled returns (uint256 reclaimed) {
        // Validate that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // This is rounded down to keep assets in the vault, otherwise the contract may end up
        // in a state where there are not enough of the assets in the vault to redeem/reclaim
        reclaimed = amount_.mulDiv(
            DEPOSIT_MANAGER.getDepositReclaimRate(depositToken_, depositPeriod_),
            ONE_HUNDRED_PERCENT
        );

        // If the reclaimed amount is 0, revert
        if (reclaimed == 0) revert RedemptionVault_ZeroAmount();

        return reclaimed;
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The deposit token is not supported
    ///             - The amount of receipt tokens to reclaim is 0
    ///             - The reclaimed amount is 0
    function reclaimFor(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        address recipient_,
        uint256 amount_
    ) public nonReentrant onlyEnabled returns (uint256 reclaimed) {
        // Calculate the quantity of deposit token to withdraw and return
        // This will create a difference between the quantity of deposit tokens and the vault shares, which will be swept as yield
        uint256 discountedAssetsOut = previewReclaim(depositToken_, depositPeriod_, amount_);

        // Withdraw the deposit tokens from the deposit manager
        // This will burn the receipt tokens from the caller and send the released deposit tokens to this contract
        DEPOSIT_MANAGER.withdraw(
            depositToken_,
            depositPeriod_,
            msg.sender,
            address(this),
            amount_,
            false
        );

        // Transfer discounted amount of the deposit token to the recipient
        ERC20(address(depositToken_)).safeTransfer(recipient_, discountedAssetsOut);

        // Transfer the remaining deposit tokens to the TRSRY
        ERC20(address(depositToken_)).safeTransfer(address(TRSRY), amount_ - discountedAssetsOut);

        // Emit event
        emit Reclaimed(
            recipient_,
            address(depositToken_),
            depositPeriod_,
            discountedAssetsOut,
            amount_ - discountedAssetsOut
        );

        return discountedAssetsOut;
    }

    /// @inheritdoc IDepositRedemptionVault
    function reclaim(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external returns (uint256 reclaimed) {
        reclaimed = reclaimFor(depositToken_, depositPeriod_, msg.sender, amount_);
    }
}
