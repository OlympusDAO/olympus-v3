// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositRedemptionVault} from "src/bases/interfaces/IDepositRedemptionVault.sol";
import {IDepositManager} from "src/policies/interfaces/IDepositManager.sol";

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
/// @dev    This currently inherits from PolicyEnabler, and thus assumes that the inheriting contract is a Policy.
///         It could be refactored to inherit from IEnabler instead.
abstract contract BaseDepositRedemptionVault is
    IDepositRedemptionVault,
    PolicyEnabler,
    ReentrancyGuard
{
    using SafeTransferLib for ERC20;
    using FullMath for uint256;

    // ========== CONSTANTS ========== //

    /// @notice The number representing 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    // ========== STATE VARIABLES ========== //

    /// @notice The address of the token manager
    DepositManager public immutable DEPOSIT_MANAGER;

    /// @notice The TRSRY module.
    /// @dev    The inheriting contract must assign the TRSRY module address to this state variable using `configureDependencies()`
    TRSRYv1 public TRSRY;

    /// @notice The number of redemptions per user
    mapping(address => uint16) internal _userRedemptionCount;

    /// @notice The redemption for each user and redemption ID
    /// @dev    Use `_getUserRedemptionKey()` to calculate the key for the mapping.
    ///         A complex key is used to save gas compared to a nested mapping.
    mapping(bytes32 => UserRedemption) internal _userRedemptions;

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
        (bool isConfigured, ) = DEPOSIT_MANAGER.isAssetPeriod(depositToken_, depositPeriod_);
        if (!isConfigured)
            revert RedemptionVault_InvalidToken(address(depositToken_), depositPeriod_);

        // Transfer the receipt tokens from the caller to this contract
        DEPOSIT_MANAGER.transferFrom(
            msg.sender,
            address(this),
            DEPOSIT_MANAGER.getReceiptTokenId(depositToken_, depositPeriod_),
            amount_
        );
    }

    // ========== USER REDEMPTIONS ========== //

    function _getUserRedemptionKey(
        address user_,
        uint16 redemptionId_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(user_, redemptionId_));
    }

    /// @inheritdoc IDepositRedemptionVault
    function getUserRedemptionCount(address user_) external view returns (uint16 count) {
        return _userRedemptionCount[user_];
    }

    /// @inheritdoc IDepositRedemptionVault
    function getUserRedemption(
        address user_,
        uint16 redemptionId_
    ) external view returns (UserRedemption memory redemption) {
        redemption = _userRedemptions[_getUserRedemptionKey(user_, redemptionId_)];
        // TODO should this be a revert?
        if (redemption.depositToken == address(0))
            revert RedemptionVault_InvalidRedemptionId(user_, redemptionId_);

        return redemption;
    }

    // ========== REDEMPTION FLOW ========== //

    modifier onlyValidRedemptionId(address user_, uint16 redemptionId_) {
        // If the deposit token is the zero address, the redemption is invalid
        if (
            _userRedemptions[_getUserRedemptionKey(user_, redemptionId_)].depositToken == address(0)
        ) revert RedemptionVault_InvalidRedemptionId(user_, redemptionId_);
        _;
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function performs the following:
    ///             - Creates a new redemption for the user
    ///             - Transfers the receipt tokens from the caller to this contract
    ///             - Emits the RedemptionStarted event
    ///             - Returns the new redemption ID
    ///
    ///             The function will revert if:
    ///             - The deposit token and period are not supported
    ///             - The amount is 0
    ///             - The caller has not approved this contract to spend the receipt tokens
    ///             - The caller does not have enough receipt tokens
    function startRedemption(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external nonReentrant onlyEnabled returns (uint16 redemptionId) {
        // Create a User Commitment
        redemptionId = _userRedemptionCount[msg.sender]++;
        _userRedemptions[_getUserRedemptionKey(msg.sender, redemptionId)] = UserRedemption({
            depositToken: address(depositToken_),
            depositPeriod: depositPeriod_,
            redeemableAt: uint48(block.timestamp + uint48(depositPeriod_) * 30 days),
            amount: amount_
        });

        // Pull the receipt tokens from the caller
        // This will validate that the deposit token is supported
        _pullReceiptToken(depositToken_, depositPeriod_, amount_);

        // Return the new redemption ID
        emit RedemptionStarted(
            msg.sender,
            redemptionId,
            address(depositToken_),
            depositPeriod_,
            amount_
        );
        return redemptionId;
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function performs the following:
    ///             - Checks that the redemption ID is valid
    ///             - Checks that the amount is not greater than the redemption
    ///             - Reduces the redemption amount
    ///             - Transfers the quantity of receipt tokens to the caller
    ///             - Emits the RedemptionCancelled event
    ///
    ///             The function will revert if:
    ///             - The redemption ID is invalid
    ///             - The amount is 0
    ///             - The amount is greater than the redemption amount
    function cancelRedemption(
        uint16 redemptionId_,
        uint256 amount_
    ) external nonReentrant onlyEnabled onlyValidRedemptionId(msg.sender, redemptionId_) {
        // Get the redemption
        UserRedemption storage redemption = _userRedemptions[
            _getUserRedemptionKey(msg.sender, redemptionId_)
        ];

        // Check that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // Check that the amount is not greater than the redemption
        if (amount_ > redemption.amount)
            revert RedemptionVault_InvalidAmount(msg.sender, redemptionId_, amount_);

        // Update the redemption
        redemption.amount -= amount_;

        // Transfer the quantity of receipt tokens to the caller
        DEPOSIT_MANAGER.transfer(
            msg.sender,
            DEPOSIT_MANAGER.getReceiptTokenId(
                IERC20(redemption.depositToken),
                redemption.depositPeriod
            ),
            amount_
        );

        // Emit the cancelled event
        emit RedemptionCancelled(
            msg.sender,
            redemptionId_,
            redemption.depositToken,
            redemption.depositPeriod,
            amount_
        );
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function performs the following:
    ///             - Checks that the redemption ID is valid
    ///             - Checks that the redemption is redeemable
    ///             - Updates the redemption
    ///             - Redeems the receipt tokens for the underlying asset
    ///             - Transfers the underlying asset to the caller
    ///             - Emits the RedemptionFinished event
    ///
    ///             The function will revert if:
    ///             - The redemption ID is invalid
    ///             - The redemption is not yet redeemable
    function finishRedemption(
        uint16 redemptionId_
    ) external nonReentrant onlyEnabled onlyValidRedemptionId(msg.sender, redemptionId_) {
        // Get the redemption
        UserRedemption storage redemption = _userRedemptions[
            _getUserRedemptionKey(msg.sender, redemptionId_)
        ];

        // Check that the redemption is not already redeemed
        if (redemption.amount == 0)
            revert RedemptionVault_AlreadyRedeemed(msg.sender, redemptionId_);

        // Check that the redemption is redeemable
        if (block.timestamp < redemption.redeemableAt)
            revert RedemptionVault_TooEarly(msg.sender, redemptionId_);

        // Update the redemption
        uint256 redemptionAmount = redemption.amount;
        redemption.amount = 0;

        // Withdraw the underlying asset from the deposit manager
        // This will burn the receipt tokens from this contract and send the released deposit tokens to the caller
        DEPOSIT_MANAGER.approve(
            address(DEPOSIT_MANAGER),
            DEPOSIT_MANAGER.getReceiptTokenId(
                IERC20(redemption.depositToken),
                redemption.depositPeriod
            ),
            redemptionAmount
        );
        DEPOSIT_MANAGER.withdraw(
            IDepositManager.WithdrawParams({
                asset: IERC20(redemption.depositToken),
                depositPeriod: redemption.depositPeriod,
                depositor: address(this),
                recipient: msg.sender,
                amount: redemptionAmount,
                isWrapped: false
            })
        );

        // Emit the redeemed event
        emit RedemptionFinished(
            msg.sender,
            redemptionId_,
            redemption.depositToken,
            redemption.depositPeriod,
            redemptionAmount
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
            DEPOSIT_MANAGER.getAssetPeriodReclaimRate(depositToken_, depositPeriod_),
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
            IDepositManager.WithdrawParams({
                asset: depositToken_,
                depositPeriod: depositPeriod_,
                depositor: msg.sender,
                recipient: address(this),
                amount: amount_,
                isWrapped: false
            })
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

    // ========== ERC165 ========== //

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IDepositRedemptionVault).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
