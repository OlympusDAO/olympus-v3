// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {CDEPOv1} from "./CDEPO.v1.sol";
import {Kernel, Module} from "src/Kernel.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

contract OlympusConvertibleDepository is CDEPOv1 {
    // ========== STATE VARIABLES ========== //

    /// @inheritdoc CDEPOv1
    ERC4626 public immutable override vault;

    /// @inheritdoc CDEPOv1
    ERC20 public immutable override asset;

    /// @inheritdoc CDEPOv1
    uint16 public override burnRate;

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

    // ========== ERC20 OVERRIDES ========== //

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Calls `mintTo` with the caller as the recipient
    function mint(uint256 amount_) external virtual override {
        mintTo(msg.sender, amount_);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Transfers the underlying asset from `to_` to the contract
    ///             - Deposits the underlying asset into the ERC4626 vault
    ///             - Mints the corresponding amount of convertible deposit tokens to `to_`
    ///             - Emits a `Transfer` event
    ///
    /// @param  to_       The address to mint the tokens to
    /// @param  amount_   The amount of underlying asset to transfer
    function mintTo(address to_, uint256 amount_) public virtual override {
        // Transfer the underlying asset to the contract
        asset.transferFrom(to_, address(this), amount_);

        // Deposit the underlying asset into the vault and update the total shares
        totalShares += vault.deposit(amount_, to_);

        // Mint the CD tokens to the caller
        _mint(to_, amount_);
    }

    /// @inheritdoc CDEPOv1
    /// @dev        CD tokens are minted 1:1 with underlying asset, so this function returns the amount of underlying asset
    function previewMint(
        uint256 amount_
    ) external view virtual override returns (uint256 tokensOut) {
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
    ///             - Emits a `Transfer` event
    ///
    /// @param  to_       The address to reclaim the tokens to
    /// @param  amount_   The amount of CD tokens to burn
    function reclaimTo(address to_, uint256 amount_) public virtual override {
        // Burn the CD tokens from `from_`
        _burn(msg.sender, amount_);

        // Calculate the quantity of underlying asset to withdraw and return
        // This will create a difference between the quantity of underlying assets and the vault shares, which will be swept as yield
        // TODO make sure there are no shares left over if all CD tokens are burned
        uint256 discountedAssetsOut = previewReclaim(amount_);
        uint256 shares = vault.previewWithdraw(discountedAssetsOut);
        totalShares -= shares;

        // Return the underlying asset to `to_`
        vault.redeem(shares, to_, address(this));
    }

    /// @inheritdoc CDEPOv1
    function previewReclaim(
        uint256 amount_
    ) public view virtual override returns (uint256 assetsOut) {
        assetsOut = (amount_ * burnRate) / ONE_HUNDRED_PERCENT;
    }

    /// @inheritdoc CDEPOv1
    /// @dev        This function performs the following:
    ///             - Validates that the caller is permissioned
    ///             - Burns the CD tokens from the caller
    ///             - Calculates the quantity of underlying asset to withdraw and return
    ///             - Returns the underlying asset to the caller
    ///
    /// @param  amount_   The amount of CD tokens to burn
    function redeem(uint256 amount_) external override permissioned returns (uint256 sharesOut) {
        // Burn the CD tokens from the caller
        _burn(msg.sender, amount_);

        // Calculate the quantity of shares to transfer
        sharesOut = vault.previewWithdraw(amount_);
        totalShares -= sharesOut;

        // Transfer the shares to the caller
        vault.transfer(msg.sender, sharesOut);
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
        vault.transfer(msg.sender, yieldSReserve);

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
    ///             - The new burn rate is not within bounds
    function setBurnRate(uint16 newBurnRate_) external virtual override permissioned {
        // Validate that the burn rate is within bounds
        if (newBurnRate_ > ONE_HUNDRED_PERCENT) revert CDEPO_InvalidArgs("Greater than 100%");

        // Update the burn rate
        burnRate = newBurnRate_;

        // Emit the event
        emit BurnRateUpdated(newBurnRate_);
    }
}
