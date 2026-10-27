// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IERC4626} from "@openzeppelin-5.3.0/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Steps} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Steps.sol";

// Libraries
import {Math} from "@openzeppelin-5.3.0/utils/math/Math.sol";
import {SafeCall} from "src/libraries/SafeCall.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";
import {YieldRepurchaseFacilityV2VaultLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2VaultLib.sol";

/// @title YieldRepurchaseFacilityV2BuybackPoolLib
/// @notice An external library that sizes the daily bid of a vault of the
///         YieldRepurchaseFacilityV2 from its buyback pool: the facility's balances of
///         the vault's shares and of its reserve token.
/// @dev The library is deployed separately and reached through `DELEGATECALL`, so the
///      facility is `address(this)`: the balances read here are the facility's, the
///      checked vault interactions (the wrap of the idle reserve and the redeem for a
///      deficit) run as calls to the facility's own `IYieldRepurchaseFacilityV2Steps`
///      functions, and the emitted events belong to the facility interface. The library
///      holds no state and never reads the treasury.
library YieldRepurchaseFacilityV2BuybackPoolLib {
    /// @notice Sizes the daily bid of a vault from the facility's balances and prepares
    ///         the payout for it.
    /// @dev The bid is the pool value divided by `daysRemaining_` (floor). For a
    ///      sell-shares asset the idle reserve balance is wrapped into vault shares
    ///      first, the pool value is the value of the held shares, and the capacity is
    ///      the smaller of the share amount covering the bid and the held shares,
    ///      denominated in shares; both conversions follow the redemption class of the
    ///      vault (`YieldRepurchaseFacilityV2VaultLib`). Otherwise the pool value is the
    ///      held reserve plus the redeemable value of the held shares, the reserve
    ///      shortfall of the bid is redeemed from the held shares, and the bid is clamped
    ///      to the reserve actually held when the redeem falls short. A zero bid or
    ///      capacity is returned as zero, and the caller opens no market.
    /// @param config_ The configuration storage of the vault.
    /// @param daysRemaining_ The number of daily cycles remaining in the week, including
    ///        this one; at least one.
    /// @return capacity The market capacity, in payout token units: the share amount for
    ///         a sell-shares asset, the reserve amount otherwise; zero when the day's
    ///         market is skipped.
    function dailyBid(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        uint256 daysRemaining_
    ) external returns (uint256 capacity) {
        address vault_ = config_.vault;
        address reserve_ = config_.reserve;
        address shareToken = config_.shareToken;

        if (config_.sellShares) {
            _wrapIdleReserve(vault_, reserve_);

            bool asyncRedeem = config_.asyncRedeem;
            uint256 heldShares = _selfBalance(shareToken);
            uint256 bidAmount = YieldRepurchaseFacilityV2VaultLib.sharesToAssets(
                vault_,
                asyncRedeem,
                heldShares
            ) / daysRemaining_;
            if (bidAmount == 0) return 0;

            return
                Math.min(
                    YieldRepurchaseFacilityV2VaultLib.assetsToShares(
                        vault_,
                        asyncRedeem,
                        bidAmount
                    ),
                    heldShares
                );
        }

        uint256 currentReserve = _selfBalance(reserve_);
        uint256 heldSharesReserveMode = _selfBalance(shareToken);

        uint256 bid = (currentReserve + IERC4626(vault_).previewRedeem(heldSharesReserveMode)) /
            daysRemaining_;
        if (bid == 0) return 0;

        if (currentReserve < bid) {
            uint256 deficit = bid - currentReserve;
            uint256 redeemed = _redeemForDeficit(vault_, deficit, heldSharesReserveMode);

            if (redeemed < deficit) {
                bid = currentReserve + redeemed;
            }
        }

        return bid;
    }

    /// @notice Wraps the facility's idle reserve balance into vault shares through the
    ///         checked self-call `selfWrapReserve`.
    /// @dev On a failed wrap the reserve is kept, `ReserveWrapFailed` is emitted, and
    ///      the wrap is retried at the following daily cycle. A dust balance that
    ///      previews to zero shares is skipped without an event and stays on the
    ///      facility until the balance grows past the vault's rounding threshold.
    function _wrapIdleReserve(address vault_, address reserve_) private {
        uint256 idleReserve = _selfBalance(reserve_);
        if (idleReserve == 0) return;
        if (IERC4626(vault_).previewDeposit(idleReserve) == 0) return;

        (bool success, bytes memory reason) = _selfCall(
            abi.encodeCall(IYieldRepurchaseFacilityV2Steps.selfWrapReserve, (vault_, idleReserve))
        );
        // The failed self-call rolled back the deposit, so the reserve is still held
        if (!success)
            emit IYieldRepurchaseFacilityV2.ReserveWrapFailed(vault_, idleReserve, reason);
    }

    /// @notice Redeems held shares to cover a reserve deficit of the daily bid.
    /// @dev The share amount is `previewWithdraw(deficit_)` (rounded up by the vault),
    ///      capped at the held shares.
    function _redeemForDeficit(
        address vault_,
        uint256 deficit_,
        uint256 heldShares_
    ) private returns (uint256 redeemed) {
        uint256 sharesNeeded = IERC4626(vault_).previewWithdraw(deficit_);
        uint256 sharesToRedeem = sharesNeeded > heldShares_ ? heldShares_ : sharesNeeded;

        redeemed = _redeemShares(vault_, sharesToRedeem);
    }

    /// @notice Redeems vault shares through the checked self-call `selfRedeemChecked`.
    /// @dev On a failed redeem the shares are kept, `RedeemFailed` is emitted, and zero
    ///      is reported as the received amount.
    /// @return received The reserve amount received.
    function _redeemShares(address vault_, uint256 shares_) private returns (uint256 received) {
        if (shares_ == 0) return 0;

        (bool success, bytes memory data) = _selfCall(
            abi.encodeCall(IYieldRepurchaseFacilityV2Steps.selfRedeemChecked, (vault_, shares_))
        );
        if (!success) {
            // The failed self-call rolled back the redeem, so all shares are still held
            emit IYieldRepurchaseFacilityV2.RedeemFailed(vault_, shares_, data);
            return 0;
        }
        // The success returndata is the one-word return of `selfRedeemChecked`, well
        // below the `MAX_RETURNDATA_LENGTH` cap
        return abi.decode(data, (uint256));
    }

    /// @notice Performs an isolated call to the facility itself that forwards the
    ///         remaining gas and no value, and captures the returndata truncated to
    ///         `MAX_RETURNDATA_LENGTH` bytes.
    /// @return success Whether the call succeeded.
    /// @return data The captured returndata, truncated to `MAX_RETURNDATA_LENGTH` bytes.
    function _selfCall(bytes memory callData_) private returns (bool success, bytes memory data) {
        return
            SafeCall.safeCall(
                address(this),
                gasleft(),
                0,
                YieldRepurchaseFacilityV2Constants.MAX_RETURNDATA_LENGTH,
                callData_
            );
    }

    /// @notice Returns the facility's own `token_` balance.
    function _selfBalance(address token_) private view returns (uint256) {
        return IERC20(token_).balanceOf(address(this));
    }
}
