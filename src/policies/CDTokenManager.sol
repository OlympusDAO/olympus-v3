// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Interfaces
import {IConvertibleDepositTokenManager} from "src/policies/interfaces/IConvertibleDepositTokenManager.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {IPeriodicTask} from "src/policies/interfaces/IPeriodicTask.sol";

// Libraries
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title Convertible Deposit Token Manager
/// @notice This policy is used to manage convertible deposit ("CD") tokens
contract CDTokenManager is Policy, PolicyEnabler, ReentrancyGuard, IConvertibleDepositTokenManager, IPeriodicTask {
    using SafeTransferLib for ERC20;
    using FullMath for uint256;

    // ========== CONSTANTS ========== //

    /// @notice The number representing 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    // ========== STATE VARIABLES ========== //

    /// @notice The TRSRY module
    TRSRYv1 public TRSRY;

    /// @notice The CDEPO module
    CDEPOv1 public CDEPO;

    /// @notice The number of commitments per user
    mapping(address => uint16) internal _userRedeemCommitmentCount;

    /// @notice The commitments for each user and commitment ID
    mapping(address => mapping(uint16 => UserRedeemCommitment)) internal _userRedeemCommitments;

    /// @notice Mapping of vault token to total shares
    /// @dev    This is used to track deposited vault shares for each vault token
    mapping(IERC4626 => uint256) private _totalShares;

    // ========== MODIFIERS ========== //

    modifier onlyCDToken(IConvertibleDepositERC20 cdToken_) {
        if (!CDEPO.isConvertibleDepositToken(address(cdToken_)))
            revert CDRedemptionVault_InvalidCDToken(address(cdToken_));
        _;
    }

    modifier onlyValidRedeemCommitmentId(address user_, uint16 commitmentId_) {
        // If the CD token is the zero address, the commitment is invalid
        if (address(_userCommitments[user_][commitmentId_].cdToken) == address(0))
            revert CDRedemptionVault_InvalidCommitmentId(user_, commitmentId_);
        _;
    }

    // ========== CONSTRUCTOR ========== //

    constructor(Kernel kernel_) Policy(kernel_) {
        // Disabled by default by PolicyEnabler
    }

    // ========== Policy Configuration ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("CDEPO");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        CDEPO = CDEPOv1(getModuleAddress(dependencies[1]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode cdepoKeycode = toKeycode("CDEPO");

        permissions = new Permissions[](2);
        permissions[0] = Permissions(cdepoKeycode, CDEPO.create.selector);
        permissions[1] = Permissions(cdepoKeycode, CDEPO.setReclaimRate.selector);
    }

    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;

        return (major, minor);
    }

    // ========== MINT/BURN ========== //

    /// @inheritdoc IConvertibleDepositRedemptionVault
    function mintFor(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) external {
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

    // TODO mintFor/burnFrom should track amount of CD tokens minted/burned and allow for withdrawal of underlying assets. Should be permissioned?

    // ========== REDEMPTION FLOW ========== //

    /// @inheritdoc IConvertibleDepositRedemptionVault
    function getRedeemCommitmentCount(address user_) external view returns (uint16 count) {
        return _userRedeemCommitmentCount[user_];
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    function getRedeemCommitment(
        address user_,
        uint16 commitmentId_
    ) external view returns (UserRedeemCommitment memory commitment) {
        commitment = _userRedeemCommitments[user_][commitmentId_];
        if (commitment.cdToken == IConvertibleDepositERC20(address(0)))
            revert CDRedemptionVault_InvalidCommitmentId(user_, commitmentId_);

        return commitment;
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
    function commitRedeem(
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
    function uncommitRedeem(
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

    // ========== YIELD MANAGEMENT ========== //

    /// @inheritdoc IConvertibleDepositRedemptionVault
    function sweepAllYield() public {
        // Get all supported CD tokens
        IConvertibleDepositERC20[] memory cdTokens = CDEPO.getConvertibleDepositTokens();

        // Iterate over all supported CD tokens
        for (uint256 i; i < cdTokens.length; ++i) {
            sweepYield(cdTokens[i]);
        }
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    /// @dev        This function performs the following:
    ///             - Validates that the CD token is supported
    ///             - Validates that the caller is permissioned
    ///             - Computes the amount of yield that would be swept
    ///             - Reduces the shares tracked by the contract
    ///             - Transfers the yield to the recipient
    ///             - Emits an event
    ///
    ///             This function reverts if:
    ///             - The CD token is not supported
    ///             - The caller is not permissioned
    ///             - The recipient_ address is the zero address
    function sweepYield(
        IConvertibleDepositERC20 cdToken_
    ) public onlyCDToken(cdToken_) returns (uint256 yieldReserve, uint256 yieldSReserve) {
        (yieldReserve, yieldSReserve) = previewSweepYield(cdToken_);

        // Skip if there is no yield to sweep
        if (yieldSReserve == 0) return (0, 0);

        // Reduce the shares tracked by the contract
        IERC4626 vaultToken = cdToken_.vault();
        _totalShares[vaultToken] -= yieldSReserve;

        // Transfer the yield to the TRSRY
        address recipient = address(TRSRY);
        ERC20(address(vaultToken)).safeTransfer(recipient, yieldSReserve);

        // Emit the event
        emit YieldSwept(address(vaultToken), recipient, yieldReserve, yieldSReserve);

        return (yieldReserve, yieldSReserve);
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    /// @dev        This function reverts if:
    ///             - The CD token is not supported
    function previewSweepYield(
        IConvertibleDepositERC20 cdToken_
    ) public view onlyCDToken(cdToken_) returns (uint256 yieldReserve, uint256 yieldSReserve) {
        IERC4626 vaultToken = cdToken_.vault();

        // The yield is the difference between the quantity of underlying assets in the vault and the quantity of CD tokens issued
        yieldReserve = vaultToken.previewRedeem(_totalShares[vaultToken]) - cdToken_.totalSupply();

        // The yield in sReserve terms is the quantity of vault shares that would be burnt if yieldReserve was redeemed
        if (yieldReserve > 0) {
            yieldSReserve = vaultToken.previewWithdraw(yieldReserve);
        }

        return (yieldReserve, yieldSReserve);
    }

    // ========== PERIODIC TASK ========== //

    /// @notice Performs periodic tasks relevant to the redemption vault
    /// @dev    This function performs the following:
    ///         - Sweeps all yield from the CD tokens to the TRSRY module
    ///
    ///         This function has the following assumptions:
    ///         - The calling function has already checked that the caller has the HEART_ROLE
    function _execute() internal {
        // If the contract is disabled, do nothing
        if (!isEnabled) return;

        sweepAllYield();
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepositTokenConfig
    function create(
        IERC4626 vault_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyAdminRole returns (IConvertibleDepositERC20 cdToken) {
        cdToken = CDEPO.create(vault_, periodMonths_, reclaimRate_);
    }

    /// @inheritdoc IConvertibleDepositTokenConfig
    function setReclaimRate(
        IConvertibleDepositERC20 cdToken_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyAdminRole {
        CDEPO.setReclaimRate(cdToken_, reclaimRate_);
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    ///
    /// @return     shares The amount of vault shares deposited for the CD token, or 0
    function getVaultShares(
        IConvertibleDepositERC20 cdToken_
    ) public view returns (uint256 shares) {
        return _totalShares[cdToken_.vault()];
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
