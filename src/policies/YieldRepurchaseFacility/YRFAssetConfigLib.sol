// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC4626} from "@openzeppelin-5.3.0/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-5.3.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";

// Modules
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";

/// @title YRFAssetConfigLib
/// @notice An external library that validates and maintains the per-asset registry and
///         the yield snapshots of the YieldRepurchaseFacilityV2.
/// @dev The library is deployed separately and reached through `DELEGATECALL`, so the
///      storage parameters reference the calling facility's storage, the facility is
///      `address(this)`, and the emitted events and the errors belong to the facility
///      interface.
library YRFAssetConfigLib {
    /// @notice Maximum reserve token decimals supported when adding a vault.
    uint8 internal constant MAX_RESERVE_DECIMALS = 18;

    /// @notice Precision denominator of the yield buyback share (`1e18` = 100%).
    uint256 internal constant ONE_HUNDRED_PERCENT = 1e18;

    /// @notice The registration inputs of `addAsset`.
    /// @param vault The ERC4626 vault to register.
    /// @param yieldBuybackShare The share of the yield routed to buybacks (`1e18` =
    ///        100%).
    /// @param initialReserveBalance The initial `lastReserveBalance` snapshot, in
    ///        reserve units.
    /// @param initialConversionRate The initial `lastConversionRate` snapshot: the
    ///        reserve amount redeemable for one whole share.
    /// @param nextYield The initial stored next yield, in reserve units.
    /// @param sellShares Whether bond markets pay out the vault shares instead of the
    ///        reserve.
    struct AddAssetParams {
        address vault;
        uint256 yieldBuybackShare;
        uint256 initialReserveBalance;
        uint256 initialConversionRate;
        uint256 nextYield;
        bool sellShares;
    }

    /// @notice Validates and registers an ERC4626 vault as a reserve asset of the
    ///         calling facility.
    /// @dev The asset is registered in the enabled state. Emits `AssetAdded` and
    ///      `NextYieldSet` for the facility.
    ///
    ///      Reverts if:
    ///      - The vault address is the zero address.
    ///      - The yield buyback share exceeds 100% (`1e18`).
    ///      - The vault is already registered.
    ///      - The vault reports the zero address as its underlying asset.
    ///      - The vault's underlying asset decimals exceed 18.
    ///      - The vault's share decimals do not match its reserve decimals.
    ///      - The vault or its reserve token is OHM, the vault equals its own reserve,
    ///        or the vault or the reserve collides with the vault or the reserve of a
    ///        registered asset.
    ///      - The `price_.getPriceIn(ohm_, reserve)` probe reverts or returns zero.
    /// @param assetConfigs_ The facility's per-vault configuration storage.
    /// @param vaults_ The facility's registered vault list storage.
    /// @param price_ The PRICE module used for the reserve price probe.
    /// @param ohm_ The OHM token address.
    /// @param params_ The registration inputs.
    function addAsset(
        mapping(address => IYieldRepurchaseFacilityV2.ReserveAsset) storage assetConfigs_,
        address[] storage vaults_,
        PRICEv2 price_,
        address ohm_,
        AddAssetParams memory params_
    ) external {
        address vault_ = params_.vault;
        if (vault_ == address(0)) revert Errors.BadInput("vault");
        if (params_.yieldBuybackShare > ONE_HUNDRED_PERCENT)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_YieldBuybackShareTooHigh();
        if (assetConfigs_[vault_].vault != address(0))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetAlreadyRegistered();

        address reserve_ = IERC4626(vault_).asset();
        if (reserve_ == address(0)) revert Errors.BadInput("vault.asset");

        uint8 reserveDecimals = IERC20Metadata(reserve_).decimals();
        if (reserveDecimals > MAX_RESERVE_DECIMALS)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_UnsupportedDecimals();

        // The conversion rate probe and the sell-shares market pricing both treat
        // `10 ** reserveDecimals` as one whole share.
        if (IERC20Metadata(vault_).decimals() != reserveDecimals)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_VaultDecimalsMismatch();

        // Every token balance held by the facility belongs to exactly one pool: the OHM
        // balance backs the purchased-OHM counter, and each registered vault or reserve
        // balance backs its own asset, so any collision between them is rejected.
        if (vault_ == ohm_ || reserve_ == ohm_)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_TokenPoolConflict(ohm_);
        if (vault_ == reserve_)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_TokenPoolConflict(vault_);

        uint256 vaultsLength = vaults_.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address registeredVault = vaults_[i];
            address registeredReserve = assetConfigs_[registeredVault].reserve;
            if (registeredReserve == reserve_ || registeredVault == reserve_)
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_TokenPoolConflict(
                    reserve_
                );
            if (registeredReserve == vault_)
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_TokenPoolConflict(
                    vault_
                );
        }

        // The daily cycles price the vault's markets through `PRICE.getPriceIn`, so the
        // reserve must resolve against OHM at registration; a PRICE revert (for example
        // an unregistered reserve) bubbles up.
        if (price_.getPriceIn(ohm_, reserve_) == 0)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_ReserveNotPriceable(
                reserve_
            );

        assetConfigs_[vault_] = IYieldRepurchaseFacilityV2.ReserveAsset({
            vault: vault_,
            reserve: reserve_,
            reserveDecimals: reserveDecimals,
            sellShares: params_.sellShares,
            isAssetEnabled: true,
            yieldBuybackShare: params_.yieldBuybackShare,
            lastReserveBalance: params_.initialReserveBalance,
            lastConversionRate: params_.initialConversionRate,
            nextYield: params_.nextYield,
            unfundedYield: 0
        });
        vaults_.push(vault_);

        emit IYieldRepurchaseFacilityV2.AssetAdded(vault_, reserve_, params_.yieldBuybackShare);
        emit IYieldRepurchaseFacilityV2.NextYieldSet(reserve_, params_.nextYield);
    }

    /// @notice Restarts the weekly cycle of the enabled assets: zeroes their yields and
    ///         unfunded carries, applies the supplied next-yield seeds, and refreshes
    ///         their yield snapshots.
    /// @dev Disabled assets are not touched and are not seedable. A single
    ///      `NextYieldSet` event with the resulting value is emitted per enabled vault;
    ///      when the seed array contains duplicates, the last entry wins. The epoch
    ///      counter and the seeding window of the facility are not written here.
    ///
    ///      Reverts if a seed references an unregistered or disabled vault.
    /// @param assetConfigs_ The facility's per-vault configuration storage.
    /// @param vaults_ The facility's registered vault list storage.
    /// @param nextYieldSeeds_ The per-vault `nextYield` values to apply after the reset.
    /// @param chreg_ The Clearinghouse registry module, read for the balance snapshots.
    /// @param trsry_ The treasury address, read for the balance snapshots.
    /// @param backingVault_ The backing vault, or the zero address when none is
    ///        designated.
    function resetCycle(
        mapping(address => IYieldRepurchaseFacilityV2.ReserveAsset) storage assetConfigs_,
        address[] storage vaults_,
        IYieldRepurchaseFacilityV2.NextYieldSeed[] memory nextYieldSeeds_,
        CHREGv1 chreg_,
        address trsry_,
        address backingVault_
    ) external {
        uint256 vaultsLength = vaults_.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            IYieldRepurchaseFacilityV2.ReserveAsset storage config = assetConfigs_[vaults_[i]];
            if (!config.isAssetEnabled) continue;

            config.nextYield = 0;
            config.unfundedYield = 0;
            _refreshSnapshots(config, chreg_, trsry_, backingVault_);
        }

        uint256 seedsLength = nextYieldSeeds_.length;
        for (uint256 i = 0; i < seedsLength; ++i) {
            IYieldRepurchaseFacilityV2.NextYieldSeed memory seed = nextYieldSeeds_[i];
            IYieldRepurchaseFacilityV2.ReserveAsset storage config = assetConfigs_[seed.vault];
            if (config.vault == address(0))
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered(
                    seed.vault
                );
            if (!config.isAssetEnabled)
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetDisabled();
            config.nextYield = seed.nextYield;
        }

        for (uint256 i = 0; i < vaultsLength; ++i) {
            IYieldRepurchaseFacilityV2.ReserveAsset storage config = assetConfigs_[vaults_[i]];
            if (!config.isAssetEnabled) continue;
            emit IYieldRepurchaseFacilityV2.NextYieldSet(config.reserve, config.nextYield);
        }
    }

    /// @notice Refreshes the vault's conversion-rate and reserve-balance snapshots.
    /// @param config_ The vault's configuration storage.
    /// @param chreg_ The Clearinghouse registry module.
    /// @param trsry_ The treasury address.
    /// @param backingVault_ The backing vault, or the zero address when none is
    ///        designated.
    function refreshSnapshots(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        CHREGv1 chreg_,
        address trsry_,
        address backingVault_
    ) external {
        _refreshSnapshots(config_, chreg_, trsry_, backingVault_);
    }

    /// @notice Returns the reserve value of the protocol-held shares of a vault.
    /// @dev Counts the treasury balance, and for the backing vault also the balances of
    ///      the active Clearinghouses, valued through `previewRedeem` (floor).
    /// @param vault_ The vault to value.
    /// @param chreg_ The Clearinghouse registry module.
    /// @param trsry_ The treasury address.
    /// @param backingVault_ The backing vault, or the zero address when none is
    ///        designated.
    /// @return balance The reserve value, in reserve units.
    function protocolReserveBalance(
        address vault_,
        CHREGv1 chreg_,
        address trsry_,
        address backingVault_
    ) external view returns (uint256 balance) {
        return _protocolReserveBalance(vault_, chreg_, trsry_, backingVault_);
    }

    /// @notice Returns the amount of `token_` the facility can rescue to the treasury.
    /// @dev Only the OHM excess above the purchased accumulator and the full balance of
    ///      unregistered tokens are rescuable; the share and reserve tokens of the
    ///      registered assets are their buyback pools and are rejected.
    ///
    ///      Reverts if `token_` is the share or the reserve token of a registered
    ///      asset.
    /// @param assetConfigs_ The facility's per-vault configuration storage.
    /// @param vaults_ The facility's registered vault list storage.
    /// @param token_ The token to rescue.
    /// @param ohm_ The OHM token address.
    /// @param ohmPurchased_ The purchased-OHM accumulator backing the burn accounting.
    /// @return rescuable The rescuable amount.
    function rescuableAmount(
        mapping(address => IYieldRepurchaseFacilityV2.ReserveAsset) storage assetConfigs_,
        address[] storage vaults_,
        address token_,
        address ohm_,
        uint256 ohmPurchased_
    ) external view returns (uint256 rescuable) {
        uint256 balance = IERC20(token_).balanceOf(address(this));
        if (token_ == ohm_) {
            // The purchased OHM backs the burn accounting and must stay on the facility
            return balance > ohmPurchased_ ? balance - ohmPurchased_ : 0;
        }

        uint256 vaultsLength = vaults_.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address vault = vaults_[i];
            if (token_ == vault || token_ == assetConfigs_[vault].reserve)
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_TokenNotRescuable(
                    token_
                );
        }
        return balance;
    }

    /// @notice Refreshes the snapshots of a vault configuration in place.
    function _refreshSnapshots(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        CHREGv1 chreg_,
        address trsry_,
        address backingVault_
    ) private {
        address vault_ = config_.vault;
        // One whole share: `addAsset` requires the share decimals to equal the reserve
        // decimals
        config_.lastConversionRate = IERC4626(vault_).previewRedeem(10 ** config_.reserveDecimals);
        config_.lastReserveBalance = _protocolReserveBalance(vault_, chreg_, trsry_, backingVault_);
    }

    /// @notice Returns the reserve value of the protocol-held shares of a vault.
    function _protocolReserveBalance(
        address vault_,
        CHREGv1 chreg_,
        address trsry_,
        address backingVault_
    ) private view returns (uint256 balance) {
        uint256 totalShares = IERC20(vault_).balanceOf(trsry_);

        if (vault_ == backingVault_) {
            uint256 activeCount = chreg_.activeCount();
            for (uint256 i = 0; i < activeCount; ++i) {
                totalShares += IERC20(vault_).balanceOf(chreg_.active(i));
            }
        }

        balance = IERC4626(vault_).previewRedeem(totalShares);
    }
}
