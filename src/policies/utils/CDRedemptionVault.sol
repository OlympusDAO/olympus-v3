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
import {FullMath} from "src/libraries/FullMath.sol";

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
    using FullMath for uint256;

    // ========== CONSTANTS ========== //

    /// @notice The number representing 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    // ========== STATE VARIABLES ========== //

    /// @notice The TRSRY module.
    /// @dev    The inheriting contract must assign the CDEPO module address to this state variable using `configureDependencies()`
    TRSRYv1 public TRSRY;

    /// @notice The address of the CDEPO module
    /// @dev    The inheriting contract must assign the CDEPO module address to this state variable using `configureDependencies()`
    ///         The inheriting contract must also ensure that the following permissions are requested:
    ///         - `CDEPO.mintFor()`
    ///         - `CDEPO.burnFrom()`
    CDEPOv1 public CDEPO;

    /// @notice The number of commitments per user
    mapping(address => uint16) internal _userCommitmentCount;

    /// @notice The commitments for each user and commitment ID
    mapping(address => mapping(uint16 => UserCommitment)) internal _userCommitments;

    /// @notice Mapping of vault token to total shares
    /// @dev    This is used to track deposited vault shares for each vault token
    mapping(IERC4626 => uint256) private _totalShares;

    // ========== MODIFIERS ========== //

    modifier onlyCDToken(IConvertibleDepositERC20 cdToken_) {
        if (!CDEPO.isConvertibleDepositToken(address(cdToken_)))
            revert CDRedemptionVault_InvalidCDToken(address(cdToken_));
        _;
    }

    // ========== MINT/BURN ========== //

    /// @notice Mint CD tokens for `account_` in exchange for the deposit token
    function _mintFor(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) internal {
        // Validate that the amount is greater than 0
        if (amount_ == 0) revert CDRedemptionVault_ZeroAmount(account_);

        ERC20 asset = ERC20(address(cdToken_.asset()));
        IERC4626 vault = cdToken_.vault();

        // Transfer asset from account
        asset.safeTransferFrom(account_, address(this), amount_);

        // Deposit the underlying asset into the vault and update the total shares
        asset.safeApprove(address(vault), amount_);
        _totalShares[vault] += vault.deposit(amount_, address(this));

        // Mint the CD tokens (via CDEPO)
        // This will also validate that the CD token is supported
        CDEPO.mintFor(cdToken_, account_, amount_);
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    function burn(IConvertibleDepositERC20 cdToken_, uint256 amount_) external {
        burnFrom(cdToken_, msg.sender, amount_);
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    function burnFrom(IConvertibleDepositERC20 cdToken_, address account_, uint256 amount_) public {
        IERC4626 vault = cdToken_.vault();

        // Decrease the total shares
        uint256 sharesOut = vault.previewWithdraw(amount_);
        _totalShares[vault] -= sharesOut;

        // We want to avoid situations where the amount is low enough to be < 1 share, as that would enable users to manipulate the accounting with many small calls
        // Although the ERC4626 vault will typically round up the number of shares withdrawn, if `amount_` is low enough, it will round down to 0 and `sharesOut` will be 0
        if (sharesOut == 0) revert CDRedemptionVault_ZeroAmount(account_);

        // Burn the CD tokens (via CDEPO)
        // This will also validate that the CD token is supported
        CDEPO.burnFrom(cdToken_, account_, amount_);
    }

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
    ) external nonReentrant onlyEnabled onlyCDToken(cdToken_) returns (uint16 commitmentId) {
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
        _redeem(commitment.cdToken, msg.sender, commitmentAmount);

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
    )
        public
        view
        onlyEnabled
        onlyCDToken(cdToken_)
        returns (uint256 reclaimed, address cdTokenSpender)
    {
        // Validate that the amount is not 0
        if (amount_ == 0) revert CDRedemptionVault_ZeroAmount(msg.sender);

        // This is rounded down to keep assets in the vault, otherwise the contract may end up
        // in a state where there are not enough of the assets in the vault to redeem/reclaim
        reclaimed = amount_.mulDiv(CDEPO.reclaimRate(address(cdToken_)), ONE_HUNDRED_PERCENT);

        // If the reclaimed amount is 0, revert
        if (reclaimed == 0) revert CDRedemptionVault_ZeroAmount(msg.sender);

        return (reclaimed, address(CDEPO));
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The CD token is not supported
    ///             - The amount of CD tokens to reclaim is 0
    ///             - The reclaimed amount is 0
    function reclaimFor(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) public nonReentrant onlyEnabled onlyCDToken(cdToken_) returns (uint256 reclaimed) {
        // Calculate the quantity of deposit token to withdraw and return
        // This will create a difference between the quantity of deposit tokens and the vault shares, which will be swept as yield
        (uint256 discountedAssetsOut, ) = previewReclaim(cdToken_, amount_);

        // Redeem the CD tokens and transfer the underlying asset to `account_`
        // This also burns the CD tokens
        _redeem(cdToken_, account_, amount_);

        // Emit event
        emit Reclaimed(
            account_,
            address(cdToken_.asset()),
            discountedAssetsOut,
            amount_ - discountedAssetsOut
        );

        return discountedAssetsOut;
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    function reclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external returns (uint256 reclaimed) {
        reclaimed = reclaimFor(cdToken_, msg.sender, amount_);
    }

    // ========== HELPER FUNCTIONS ========== //

    function _withdraw(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) internal {
        cdToken_.vault().withdraw(amount_, account_, address(this));
    }

    function _redeem(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) internal {
        // Burn the CD tokens from `account_`
        burnFrom(cdToken_, account_, amount_);

        // Withdraw the underlying asset to the recipient
        _withdraw(cdToken_, account_, amount_);
    }
}
