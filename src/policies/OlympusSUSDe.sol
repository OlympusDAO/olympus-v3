// SPDX-License-Identifier: MIT
pragma solidity >=0.8.30;

// Interfaces
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-5.3.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin-5.3.0/interfaces/IERC4626.sol";
import {IOlympusSUSDe} from "src/policies/interfaces/IOlympusSUSDe.sol";
import {ISusdeSwapper} from "src/periphery/interfaces/ISusdeSwapper.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Libraries
import {Address} from "@openzeppelin-5.3.0/utils/Address.sol";
import {Math} from "@openzeppelin-5.3.0/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";
import {ERC7528Constants} from "src/libraries/ERC7528Constants.sol";
import {Errors} from "src/libraries/Errors.sol";

// Contracts
import {ERC20} from "@openzeppelin-5.3.0/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin-5.3.0/token/ERC20/extensions/ERC20Permit.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";
import {Rescueable} from "src/bases/Rescueable.sol";

// Modules
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @title OlympusSUSDe
/// @notice An ERC4626 wrapper over Ethena sUSDe with synchronous USDe redemption (osUSDe).
/// @dev The wrapper exists so that sUSDe, whose native redemption is asynchronous (the
///      Ethena cooldown), can be used across the protocol behind a standard ERC4626 face
///      that pays out USDe on demand. osUSDe shares are backed one-to-one by the sUSDe
///      shares the wrapper holds, tracked by `_stakedShares`:
///
///          totalSupply() (osUSDe) == _stakedShares == sUSDe shares held for holders.
///
///      The counter is maintained explicitly (rather than reading the sUSDe balance) so
///      that sUSDe donated to the wrapper cannot skew the accounting or the exchange rate.
///
///      Flows:
///      - `deposit` / `mint`: stake USDe into sUSDe and mint osUSDe one-to-one with the
///        sUSDe shares received. Lossless. Gated by `isEnabled`.
///      - `redeem`: burn osUSDe and sell the matching sUSDe for USDe through the swapper.
///        Lossy (swap slippage), bounded by `slippageCap`. Available while disabled.
///      - `redeemForUnderlyingShares`: burn osUSDe and return the matching sUSDe one-to-one.
///        Lossless, swapper-independent, and available while disabled, so holders always
///        retain an exit even if the swap route is unhealthy or the wrapper is paused.
///      - `withdraw`: disabled.
///
///      Conversion regimes:
///      - `convertToShares` / `convertToAssets` mirror the sUSDe value.
///      - `previewRedeem` / `previewWithdraw` / `maxRedeem` / `maxWithdraw` apply
///        the `slippageCap` haircut so they never overstate what an instant swap exit delivers.
///        `maxRedeem` / `maxWithdraw` are not capped by pool liquidity; on-chain consumers
///        that size against them, should guard its redemption.
///
///      All three tokens (osUSDe, sUSDe, USDe) use 18 decimals, so amounts pass through
///      without scaling.
contract OlympusSUSDe is
    Policy,
    PolicyEnablerV2,
    Rescueable,
    ReentrancyGuardTransient,
    ERC20Permit,
    IVersioned,
    IOlympusSUSDe
{
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC4626;

    // ========== CONSTANTS ========== //

    /// @notice Precision denominator for the slippage cap (`1e18` = 100%).
    uint256 private constant _ONE_HUNDRED_PERCENT = 1e18;

    /// @notice The maximum slippage cap an admin may set (`5e16` = 5%).
    /// @dev A hard ceiling, not the live value. Governance is expected to set a smaller cap;
    ///      the live cap is supplied on `enable` and adjustable through `setSlippageCap`.
    uint256 private constant _MAX_SLIPPAGE_CAP = 5e16;

    /// @notice The decimals required of the sUSDe and USDe tokens.
    uint8 private constant _REQUIRED_DECIMALS = 18;

    /// @notice Expected length of the `enable` payload (`abi.encode(EnableParams)`).
    /// @dev Two 32-byte words: `swapper` and `slippageCap`.
    uint256 private constant _ENABLE_PARAMS_LENGTH = 64;

    // ========== IMMUTABLES ========== //

    /// @notice The sUSDe vault backing the wrapper.
    IERC4626 private immutable _SUSDE;

    /// @notice The USDe token, the underlying asset of both sUSDe and this wrapper.
    IERC20 private immutable _USDE;

    // ========== STATE ========== //

    /// @inheritdoc IOlympusSUSDe
    address public override swapper;

    /// @inheritdoc IOlympusSUSDe
    uint256 public override slippageCap;

    /// @notice The sUSDe shares held on behalf of osUSDe holders.
    /// @dev Invariant: `_stakedShares == totalSupply()`. Used for donation-resistant valuation.
    uint256 internal _stakedShares;

    // ========== SETUP ========== //

    /// @notice Configures the wrapper.
    /// @dev Derives USDe from `susde_.asset()`, validates the 18-decimals assumption, and
    ///      grants a standing maximum USDe approval to sUSDe (used when staking on deposit).
    ///
    ///      Reverts if:
    ///      - `kernel_` or `susde_` is the zero address.
    ///      - sUSDe reports the zero address as its asset.
    ///      - sUSDe or USDe does not report 18 decimals.
    /// @param kernel_ The Olympus Kernel.
    /// @param susde_  The sUSDe vault to wrap.
    constructor(
        Kernel kernel_,
        address susde_
    ) Policy(kernel_) ERC20("Olympus Staked USDe", "osUSDe") ERC20Permit("Olympus Staked USDe") {
        if (address(kernel_) == address(0)) revert Errors.BadInput("kernel");
        if (susde_ == address(0)) revert Errors.BadInput("susde");

        address usde = IERC4626(susde_).asset();
        if (usde == address(0)) revert Errors.BadInput("susde");

        if (
            IERC20Metadata(susde_).decimals() != _REQUIRED_DECIMALS ||
            IERC20Metadata(usde).decimals() != _REQUIRED_DECIMALS
        ) revert IOlympusSUSDe_UnsupportedDecimals();

        _SUSDE = IERC4626(susde_);
        _USDE = IERC20(usde);

        // sUSDe pulls USDe from the wrapper when staking on deposit. The wrapper holds
        // no USDe between transactions.
        _USDE.forceApprove(susde_, type(uint256).max);
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        (uint8 rolesMajor, ) = ROLES.VERSION();
        if (rolesMajor != 1) revert Policy_WrongModuleVersion(abi.encode([1]));

        return dependencies;
    }

    /// @inheritdoc Policy
    /// @dev The wrapper requires no module write permissions.
    function requestPermissions() external pure override returns (Permissions[] memory) {}

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== ENABLE / DISABLE ========== //

    /// @inheritdoc EnablerV2
    /// @dev Decodes the `EnableParams` payload and sets the swapper and slippage cap,
    ///      overwriting any previous values. `disable` deliberately leaves them in place so
    ///      that `redeem` keeps working while the wrapper is disabled.
    ///
    ///      Reverts if:
    ///      - The payload length does not match `EnableParams`.
    ///      - The swapper is the zero address or does not reference this sUSDe and USDe.
    ///      - The slippage cap is zero or exceeds the maximum.
    function _beforeEnable(bytes calldata data_) internal override {
        if (data_.length != _ENABLE_PARAMS_LENGTH) revert Errors.BadInput("data");

        EnableParams memory params = abi.decode(data_, (EnableParams));
        _setSwapper(params.swapper);
        _setSlippageCap(params.slippageCap);
    }

    /// @inheritdoc EnablerV2
    /// @dev Disabling only blocks new deposits. The wrapper keeps backing existing osUSDe with
    ///      sUSDe, the swapper and slippage cap are retained, and `redeem` and
    ///      `redeemForUnderlyingShares` stay open so holders can always exit.
    function _beforeDisable(bytes calldata) internal override {}

    // ========== ERC4626: METADATA ========== //

    /// @inheritdoc IERC4626
    function asset() external view override returns (address) {
        return address(_USDE);
    }

    /// @inheritdoc IERC4626
    /// @dev The USDe value of the sUSDe held for holders, at the sUSDe value. Reads the
    ///      explicit `_stakedShares` counter, so sUSDe donated to the wrapper is excluded.
    function totalAssets() external view override returns (uint256) {
        return _SUSDE.convertToAssets(_stakedShares);
    }

    /// @inheritdoc IOlympusSUSDe
    function susde() external view override returns (address) {
        return address(_SUSDE);
    }

    // ========== ERC4626: CONVERSIONS ========== //

    /// @inheritdoc IERC4626
    /// @dev Mirrors the sUSDe value. osUSDe shares are one-to-one with sUSDe shares.
    function convertToShares(uint256 assets_) public view override returns (uint256) {
        return _SUSDE.convertToShares(assets_);
    }

    /// @inheritdoc IERC4626
    /// @dev Mirrors the sUSDe value. osUSDe shares are one-to-one with sUSDe shares.
    function convertToAssets(uint256 shares_) public view override returns (uint256) {
        return _SUSDE.convertToAssets(shares_);
    }

    // ========== ERC4626: DEPOSIT PREVIEWS ========== //

    /// @inheritdoc IERC4626
    /// @dev Staking USDe into sUSDe is lossless, so the deposit side mirrors sUSDe exactly.
    function previewDeposit(uint256 assets_) public view override returns (uint256) {
        return _SUSDE.previewDeposit(assets_);
    }

    /// @inheritdoc IERC4626
    function previewMint(uint256 shares_) public view override returns (uint256) {
        return _SUSDE.previewMint(shares_);
    }

    // ========== ERC4626: EXIT PREVIEWS ========== //

    /// @inheritdoc IERC4626
    /// @dev The sUSDe value less the slippage cap, rounded down. This is also the floor passed to the swap.
    function previewRedeem(uint256 shares_) public view override returns (uint256) {
        return
            Math.mulDiv(
                _SUSDE.convertToAssets(shares_),
                _ONE_HUNDRED_PERCENT - slippageCap,
                _ONE_HUNDRED_PERCENT
            );
    }

    /// @inheritdoc IERC4626
    /// @dev Inverse of `previewRedeem`: the shares needed so the swap exit yields at least `assets_`, rounded up.
    ///      Provided for share-sizing; the `withdraw` action itself is disabled (use `redeem` or `redeemForUnderlyingShares`).
    function previewWithdraw(uint256 assets_) public view override returns (uint256) {
        return
            Math.mulDiv(
                _SUSDE.convertToShares(assets_),
                _ONE_HUNDRED_PERCENT,
                _ONE_HUNDRED_PERCENT - slippageCap,
                Math.Rounding.Ceil
            );
    }

    // ========== ERC4626: LIMITS ========== //

    /// @inheritdoc IERC4626
    /// @dev Zero while disabled, since deposits are gated by `isEnabled`.
    function maxDeposit(address) external view override returns (uint256) {
        if (isEnabled) return _SUSDE.maxDeposit(address(this));
        return 0;
    }

    /// @inheritdoc IERC4626
    /// @dev Zero while disabled, since mints are gated by `isEnabled`.
    function maxMint(address) external view override returns (uint256) {
        if (isEnabled) return _SUSDE.maxMint(address(this));
        return 0;
    }

    /// @inheritdoc IERC4626
    /// @dev The USDe value of the owner's balance. Not capped by pool liquidity, so a swap exit at
    ///      this size may still revert if the pool cannot clear the floor.
    function maxWithdraw(address owner_) external view override returns (uint256) {
        return previewRedeem(balanceOf(owner_));
    }

    /// @inheritdoc IERC4626
    /// @dev The owner's full balance. Not capped by pool liquidity; a swap exit at this size may
    ///      revert. Exits are allowed while the wrapper is disabled, so this does not depend on
    ///      `isEnabled`.
    function maxRedeem(address owner_) external view override returns (uint256) {
        return balanceOf(owner_);
    }

    // ========== ERC4626: DEPOSIT / MINT ========== //

    /// @inheritdoc IERC4626
    /// @dev Pulls `assets_` USDe from the caller, stakes them into sUSDe, and mints osUSDe
    ///      one-to-one with the sUSDe shares received.
    ///
    ///      Reverts if:
    ///      - The wrapper is disabled.
    ///      - `assets_` is zero.
    ///      - `receiver_` is the zero address.
    function deposit(
        uint256 assets_,
        address receiver_
    ) external override nonReentrant returns (uint256 shares) {
        _requireEnabled();
        if (assets_ == 0) revert Errors.BadInput("assets");
        if (receiver_ == address(0)) revert Errors.InvalidRecipient();

        _USDE.safeTransferFrom(msg.sender, address(this), assets_);
        shares = _SUSDE.deposit(assets_, address(this));

        _stakedShares += shares;
        _mint(receiver_, shares);

        emit Deposit(msg.sender, receiver_, assets_, shares);
        return shares;
    }

    /// @inheritdoc IERC4626
    /// @dev Mints exactly `shares_` osUSDe, staking the USDe required to obtain `shares_` sUSDe.
    ///
    ///      Reverts if:
    ///      - The wrapper is disabled.
    ///      - `shares_` is zero.
    ///      - `receiver_` is the zero address.
    function mint(
        uint256 shares_,
        address receiver_
    ) external override nonReentrant returns (uint256 assets) {
        _requireEnabled();
        if (shares_ == 0) revert Errors.BadInput("shares");
        if (receiver_ == address(0)) revert Errors.InvalidRecipient();

        assets = _SUSDE.previewMint(shares_);
        _USDE.safeTransferFrom(msg.sender, address(this), assets);
        _SUSDE.mint(shares_, address(this));

        _stakedShares += shares_;
        _mint(receiver_, shares_);

        emit Deposit(msg.sender, receiver_, assets, shares_);
        return assets;
    }

    // ========== ERC4626: EXIT ========== //

    /// @inheritdoc IERC4626
    /// @dev Disabled. The swap delivers a variable amount of at least the floor, not exactly `assets`.
    ///      Use `redeem` (variable assets out) or `redeemForUnderlyingShares` (sUSDe out).
    function withdraw(uint256, address, address) external pure override returns (uint256) {
        revert IOlympusSUSDe_UseRedeem();
    }

    /// @inheritdoc IERC4626
    /// @dev Burns `shares_` osUSDe and sells the matching sUSDe for USDe through the swapper,
    ///      delivering the USDe to `receiver_`. The floor passed to the swap is `previewRedeem`
    ///      (the sUSDe value less the slippage cap), so the swap reverts rather than
    ///      delivering less. Available while the wrapper is disabled.
    ///
    ///      Reverts if:
    ///      - `shares_` is zero.
    ///      - `receiver_` is the zero address.
    ///      - The caller is not `owner_` and lacks sufficient allowance.
    ///      - The swap output is below the floor (for example a paused or too-illiquid pool).
    /// @return assets The USDe delivered to `receiver_`, at least `previewRedeem(shares_)`.
    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) external override nonReentrant returns (uint256 assets) {
        if (shares_ == 0) revert Errors.BadInput("shares");
        if (receiver_ == address(0)) revert Errors.InvalidRecipient();

        address swapper_ = swapper;
        if (swapper_ == address(0)) revert IOlympusSUSDe_SwapperNotSet();

        if (msg.sender != owner_) _spendAllowance(owner_, msg.sender, shares_);

        uint256 floor = previewRedeem(shares_);

        _burn(owner_, shares_);
        _stakedShares -= shares_;

        // The swapper pulls `shares_` sUSDe under the standing approval set in `_setSwapper`,
        // and sends the USDe directly to the receiver.
        assets = ISusdeSwapper(swapper_).swap(shares_, floor, receiver_);

        emit Withdraw(msg.sender, receiver_, owner_, assets, shares_);
        return assets;
    }

    /// @inheritdoc IOlympusSUSDe
    function redeemForUnderlyingShares(
        uint256 shares_,
        address receiver_,
        address owner_
    ) external override nonReentrant returns (uint256 susdeShares) {
        if (shares_ == 0) revert Errors.BadInput("shares");
        if (receiver_ == address(0)) revert Errors.InvalidRecipient();

        if (msg.sender != owner_) _spendAllowance(owner_, msg.sender, shares_);

        _burn(owner_, shares_);
        _stakedShares -= shares_;

        _SUSDE.safeTransfer(receiver_, shares_);

        emit RedeemedForUnderlyingShares(msg.sender, receiver_, owner_, shares_);
        return shares_;
    }

    /// @inheritdoc IOlympusSUSDe
    function previewRedeemForUnderlyingShares(
        uint256 shares_
    ) external pure override returns (uint256) {
        return shares_;
    }

    /// @inheritdoc IOlympusSUSDe
    function maxRedeemForUnderlyingShares(address owner_) external view override returns (uint256) {
        return balanceOf(owner_);
    }

    // ========== ADMIN ========== //

    /// @inheritdoc IOlympusSUSDe
    function setSwapper(address swapper_) external override onlyAdminRole {
        _setSwapper(swapper_);
    }

    /// @inheritdoc IOlympusSUSDe
    function setSlippageCap(uint256 slippageCap_) external override onlyAdminRole {
        _setSlippageCap(slippageCap_);
    }

    // ========== INTERNAL ========== //

    /// @notice Validates and sets the swapper, moving the standing sUSDe approval.
    /// @dev Revokes the previous swapper's sUSDe approval and grants the new one a maximum
    ///      approval, so `redeem` can let the swapper pull the sUSDe it sells.
    /// @param swapper_ The new swapper.
    function _setSwapper(address swapper_) internal {
        if (
            swapper_ == address(0) ||
            ISusdeSwapper(swapper_).susde() != address(_SUSDE) ||
            ISusdeSwapper(swapper_).usde() != address(_USDE)
        ) revert Errors.BadInput("swapper");

        address previous = swapper;
        if (previous != address(0)) IERC20(address(_SUSDE)).forceApprove(previous, 0);

        swapper = swapper_;
        IERC20(address(_SUSDE)).forceApprove(swapper_, type(uint256).max);

        emit SwapperSet(swapper_);
    }

    /// @notice Validates and sets the slippage cap.
    /// @param slippageCap_ The new slippage cap (`1e18` = 100%).
    function _setSlippageCap(uint256 slippageCap_) internal {
        if (slippageCap_ == 0 || slippageCap_ > _MAX_SLIPPAGE_CAP)
            revert Errors.BadInput("slippageCap");

        slippageCap = slippageCap_;
        emit SlippageCapSet(slippageCap_);
    }

    // ========== RESCUE ========== //

    /// @inheritdoc Rescueable
    /// @dev The sUSDe backing is tracked by `_stakedShares` and the USDe is only transiently
    ///      held during a deposit, so neither may be rescued.
    function rescue(address token_, address payable to_) public override {
        _authorizeRescue();

        if (to_ == address(0)) revert Errors.InvalidRecipient();

        if (token_ == ERC7528Constants.NATIVE_ASSET) {
            Address.sendValue(to_, address(this).balance);
        } else {
            uint256 bal = IERC20(token_).balanceOf(address(this));
            if (token_ != address(_SUSDE)) {
                IERC20(token_).safeTransfer(to_, bal);
            } else {
                // sUSDe.
                IERC20(token_).safeTransfer(to_, bal - _stakedShares);
            }
        }
    }

    /// @inheritdoc Rescueable
    function _authorizeRescue() internal view override onlyAdminRole {}

    // ========== ERC165 ========== //

    /// @inheritdoc EnablerV2
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, Rescueable) returns (bool) {
        return
            interfaceId_ == type(IOlympusSUSDe).interfaceId ||
            interfaceId_ == type(IERC4626).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
