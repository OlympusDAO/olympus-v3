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

    function mint(uint256 amount_) external virtual override {}

    function mintTo(address to_, uint256 amount_) external virtual override {}

    function previewMint(
        uint256 amount_
    ) external view virtual override returns (uint256 tokensOut) {}

    function burn(uint256 amount_) external virtual override {}

    function burnFrom(address from_, uint256 amount_) external virtual override {}

    function previewBurn(
        uint256 amount_
    ) external view virtual override returns (uint256 assetsOut) {}

    // ========== YIELD MANAGER ========== //

    /// @inheritdoc CDEPOv1
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
