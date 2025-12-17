// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IERC4626} from "src/interfaces/IERC4626.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";
import {ReentrancyGuard} from "@solmate-6.2.0/utils/ReentrancyGuard.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

/// @title  OlympusConvertibleERC20
/// @notice A convertible token that can be exchanged for OHM by paying a fixed price before expiration
contract OlympusConvertibleERC20 is ERC20, Policy, PolicyEnabler, ReentrancyGuard {
    using TransferHelper for ERC20;
    using FullMath for uint256;

    // ========== ERRORS ========== //

    error InvalidParam(string message);
    error Expired();
    error NotActive();

    // ========== EVENTS ========== //

    event Converted(
        address indexed user,
        uint256 amount,
        uint256 paid
    );

    event ActiveStateToggled(bool isActive);

    event Minted(address indexed to, uint256 amount);

    // ========== STATE VARIABLES ========== //

    /// @notice The MINTR module
    MINTRv1 public MINTR;

    /// @notice The TRSRY module
    TRSRYv1 public TRSRY;

    /// @notice The token used for payment
    ERC20 public immutable PAYMENT_TOKEN;

    /// @notice The ERC4626 vault for the payment token
    IERC4626 public immutable VAULT_PAYMENT_TOKEN;

    /// @notice The price in payment tokens per convertible token (scaled to payment token decimals)
    uint256 public immutable conversionPrice;

    /// @notice The timestamp after which conversion is no longer possible
    uint48 public immutable expirationTime;

    /// @notice Whether conversions are currently enabled
    bool public isActive;

    /// @notice Decimals of the payment token
    uint8 internal immutable _paymentTokenDecimals;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address kernel_,
        address paymentToken_,
        address vaultPaymentToken_,
        uint256 conversionPrice_,
        uint48 expirationTime_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_, 9) Policy(Kernel(kernel_)) {
        if (paymentToken_ == address(0)) revert InvalidParam("invalid payment token");
        if (vaultPaymentToken_ == address(0)) revert InvalidParam("invalid vault");
        if (conversionPrice_ == 0) revert InvalidParam("invalid conversion price");
        if (expirationTime_ <= block.timestamp) revert InvalidParam("invalid expiration time");

        PAYMENT_TOKEN = ERC20(paymentToken_);
        VAULT_PAYMENT_TOKEN = IERC4626(vaultPaymentToken_);
        conversionPrice = conversionPrice_;
        expirationTime = expirationTime_;
        _paymentTokenDecimals = ERC20(paymentToken_).decimals();

        isActive = true;

        // Approve vault to spend payment tokens for deposits
        ERC20(paymentToken_).approve(vaultPaymentToken_, type(uint256).max);
    }

    // ========== POLICY CONFIGURATION ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("TRSRY");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[2]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](1);
        permissions[0] = Permissions(toKeycode("MINTR"), MINTR.mintOhm.selector);
    }

    /// @notice Returns the version of this policy
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== MODIFIERS ========== //

    modifier onlyActive() {
        if (!isActive) revert NotActive();
        _;
    }

    modifier notExpired() {
        if (block.timestamp > expirationTime) revert Expired();
        _;
    }

    // ========== USER FUNCTIONS ========== //

    /// @notice         Convert convertible tokens to OHM by paying the conversion price
    /// @dev            Burns the caller's convertible tokens, takes payment, and mints OHM
    /// @param amount_  The amount of convertible tokens to convert
    function convert(
        uint256 amount_
    ) external nonReentrant onlyEnabled onlyActive notExpired {
        if (amount_ == 0) revert InvalidParam("zero amount");

        // Calculate payment required
        uint256 payment = previewConversion(amount_);

        // Transfer payment tokens from user
        PAYMENT_TOKEN.safeTransferFrom(msg.sender, address(this), payment);

        // Deposit payment tokens to vault, sending shares to TRSRY
        VAULT_PAYMENT_TOKEN.deposit(payment, address(TRSRY));

        // Burn convertible tokens from user
        _burn(msg.sender, amount_);

        // Mint OHM to user
        MINTR.mintOhm(msg.sender, amount_);

        emit Converted(msg.sender, amount_, payment);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice         Mint new convertible tokens
    /// @dev            Caller must have the manager role
    /// @param to_      The address to receive the tokens
    /// @param amount_  The amount of tokens to mint
    function mint(
        address to_,
        uint256 amount_
    ) external onlyManagerOrAdminRole {
        if (to_ == address(0)) revert InvalidParam("invalid recipient");
        if (amount_ == 0) revert InvalidParam("zero amount");

        _mint(to_, amount_);

        emit Minted(to_, amount_);
    }

    /// @notice         Toggle whether conversions are enabled
    /// @dev            Caller must have the manager role
    function toggleActiveState() external onlyManagerOrAdminRole {
        isActive = !isActive;

        emit ActiveStateToggled(isActive);
    }

    /// @notice Rescue tokens accidentally sent to this contract
    /// @dev    Cannot rescue the payment token (prevents draining)
    function rescueToken(
        ERC20 token_,
        address to_,
        uint256 amount_
    ) external onlyAdminRole {
        if (to_ == address(0)) revert InvalidParam("invalid recipient");
        token_.safeTransfer(to_, amount_);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice         Calculate the payment required to convert a given amount
    /// @param amount_  The amount of convertible tokens
    /// @return payment The amount of payment tokens required
    function previewConversion(uint256 amount_) public view returns (uint256 payment) {
        // conversionPrice is in payment token units per 1 convertible token (9 decimals)
        // Result should be in payment token decimals
        payment = amount_.mulDiv(conversionPrice, 10 ** decimals);
    }

    /// @notice         Check if the conversion period has expired
    /// @return         True if expired, false otherwise
    function isExpired() external view returns (bool) {
        return block.timestamp > expirationTime;
    }
}