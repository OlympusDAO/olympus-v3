// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {CDEPOv1} from "./CDEPO.v1.sol";
import {Kernel, Module, Keycode, toKeycode} from "src/Kernel.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract OlympusConvertibleDepository is CDEPOv1 {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for ERC4626;

    // ========== STATE VARIABLES ========== //

    /// @inheritdoc CDEPOv1
    ERC4626 public immutable override vault;

    /// @inheritdoc CDEPOv1
    ERC20 public immutable override asset;

    /// @inheritdoc CDEPOv1
    uint16 public override reclaimRate;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address kernel_,
        address erc4626Vault_
    )
        Module(Kernel(kernel_))
        ERC20(
            string.concat("cd", ERC20(ERC4626(erc4626Vault_).asset()).symbol()),
            string.concat("cd", ERC20(ERC4626(erc4626Vault_).asset()).symbol()),
            ERC4626(erc4626Vault_).decimals()
        )
    {
        // Store the vault and asset
        vault = ERC4626(erc4626Vault_);
        asset = ERC20(vault.asset());
    }

    // ========== MODULE FUNCTIONS ========== //

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("CDEPO");
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== ERC20 OVERRIDES ========== //

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Calls `mintTo` with the caller as the recipient
    function mint(uint256 amount_) external virtual override {
        mintTo(msg.sender, amount_);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Transfers the underlying asset from the caller to the contract
    ///             - Deposits the underlying asset into the ERC4626 vault
    ///             - Mints the corresponding amount of convertible deposit tokens to `to_`
    ///             - Emits a `Transfer` event
    ///
    ///             This function reverts if:
    ///             - The amount is zero
    ///             - The caller has not approved this contract to spend `asset`
    ///
    /// @param  to_       The address to mint the tokens to
    /// @param  amount_   The amount of underlying asset to transfer
    function mintTo(address to_, uint256 amount_) public virtual override {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // Transfer the underlying asset to the contract
        asset.safeTransferFrom(msg.sender, address(this), amount_);

        // Deposit the underlying asset into the vault and update the total shares
        asset.safeApprove(address(vault), amount_);
        totalShares += vault.deposit(amount_, address(this));

        // Mint the CD tokens to the caller
        _mint(to_, amount_);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        CD tokens are minted 1:1 with underlying asset, so this function returns the amount of underlying asset
    function previewMint(
        uint256 amount_
    ) external view virtual override returns (uint256 tokensOut) {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // Return the same amount of CD tokens
        return amount_;
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Calls `reclaimTo` with the caller as the address to reclaim the tokens to
    function reclaim(uint256 amount_) external virtual override {
        reclaimTo(msg.sender, amount_);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Burns the CD tokens from the caller
    ///             - Calculates the quantity of underlying asset to withdraw and return
    ///             - Returns the underlying asset to `to_`
    ///
    ///             This function reverts if:
    ///             - The amount is zero
    ///             - The quantity of vault shares for the amount is zero
    ///
    /// @param  to_       The address to reclaim the tokens to
    /// @param  amount_   The amount of CD tokens to burn
    function reclaimTo(address to_, uint256 amount_) public virtual override {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // Calculate the quantity of underlying asset to withdraw and return
        // This will create a difference between the quantity of underlying assets and the vault shares, which will be swept as yield
        uint256 discountedAssetsOut = previewReclaim(amount_);
        uint256 sharesOut = vault.previewWithdraw(discountedAssetsOut);
        totalShares -= sharesOut;

        // We want to avoid situations where the amount is low enough to be < 1 share, as that would enable users to manipulate the accounting with many small calls
        // Although the ERC4626 vault will typically round up the number of shares withdrawn, if `discountedAssetsOut` is low enough, it will round down to 0 and `sharesOut` will be 0
        if (sharesOut == 0) revert CDEPO_InvalidArgs("shares");

        // Burn the CD tokens from `from_`
        // This uses the standard ERC20 implementation from solmate
        // It will revert if the caller does not have enough CD tokens
        // Allowance is not checked, because the CD tokens belonging to the caller
        // will be burned, and this function cannot be called on behalf of another address
        _burn(msg.sender, amount_);

        // Return the underlying asset to `to_`
        vault.withdraw(discountedAssetsOut, to_, address(this));
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function reverts if:
    ///             - The amount is zero
    function previewReclaim(
        uint256 amount_
    ) public view virtual override returns (uint256 assetsOut) {
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // This is rounded down to keep assets in the vault, otherwise the contract may end up
        // in a state where there are not enough of the assets in the vault to redeem/reclaim
        assetsOut = FullMath.mulDiv(amount_, reclaimRate, ONE_HUNDRED_PERCENT);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Validates that the caller is permissioned
    ///             - Burns the CD tokens from the caller
    ///             - Calculates the quantity of underlying asset to withdraw and return
    ///             - Returns the underlying asset to the caller
    ///
    ///             This function reverts if:
    ///             - The amount is zero
    ///             - The quantity of vault shares for the amount is zero
    ///
    /// @param  amount_   The amount of CD tokens to burn
    function redeem(uint256 amount_) external override permissioned returns (uint256 sharesOut) {
        // Validate that the amount is greater than zero
        if (amount_ == 0) revert CDEPO_InvalidArgs("amount");

        // Calculate the quantity of shares to transfer
        sharesOut = vault.previewWithdraw(amount_);
        totalShares -= sharesOut;

        // We want to avoid situations where the amount is low enough to be < 1 share, as that would enable users to manipulate the accounting with many small calls
        // This is unlikely to happen, as the vault will typically round up the number of shares withdrawn
        // However a different ERC4626 vault implementation may trigger the condition
        if (sharesOut == 0) revert CDEPO_InvalidArgs("shares");

        // Burn the CD tokens from the caller
        _burn(msg.sender, amount_);

        // Transfer the assets to the caller
        vault.withdraw(amount_, msg.sender, address(this));
    }

    // ========== YIELD MANAGER ========== //

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Validates that the caller has the correct role
    ///             - Computes the amount of yield that would be swept
    ///             - Reduces the shares tracked by the contract
    ///             - Transfers the yield to the caller
    ///             - Emits an event
    ///
    ///             This function reverts if:
    ///             - The caller is not permissioned
    ///
    /// @return yieldReserve  The amount of reserve token that was swept
    /// @return yieldSReserve The amount of sReserve token that was swept
    function sweepYield()
        external
        virtual
        override
        permissioned
        returns (uint256 yieldReserve, uint256 yieldSReserve)
    {
        (yieldReserve, yieldSReserve) = previewSweepYield();

        // Reduce the shares tracked by the contract
        totalShares -= yieldSReserve;

        // Transfer the yield to the permissioned caller
        vault.safeTransfer(msg.sender, yieldSReserve);

        // Emit the event
        emit YieldSwept(msg.sender, yieldReserve, yieldSReserve);

        return (yieldReserve, yieldSReserve);
    }

    /// @inheritdoc CDEPOv1
    function previewSweepYield()
        public
        view
        virtual
        override
        returns (uint256 yieldReserve, uint256 yieldSReserve)
    {
        // The yield is the difference between the quantity of underlying assets in the vault and the quantity CD tokens issued
        yieldReserve = vault.previewRedeem(totalShares) - totalSupply;

        // The yield in sReserve terms is the quantity of vault shares that would be burnt if yieldReserve was redeemed
        yieldSReserve = vault.previewWithdraw(yieldReserve);

        return (yieldReserve, yieldSReserve);
    }

    // ========== ADMIN ========== //

    /// @inheritdoc CDEPOv1
    /// @dev        This function reverts if:
    ///             - The caller is not permissioned
    ///             - The new reclaim rate is not within bounds
    function setReclaimRate(uint16 newReclaimRate_) external virtual override permissioned {
        // Validate that the reclaim rate is within bounds
        if (newReclaimRate_ > ONE_HUNDRED_PERCENT) revert CDEPO_InvalidArgs("Greater than 100%");

        // Update the reclaim rate
        reclaimRate = newReclaimRate_;

        // Emit the event
        emit ReclaimRateUpdated(newReclaimRate_);
    }
}
