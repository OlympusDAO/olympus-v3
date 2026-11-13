// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {YieldRepurchaseFacilityV2ValidationLib} from "src/policies/YieldRepurchaseFacility/libraries/internal/YieldRepurchaseFacilityV2ValidationLib.sol";

/// @notice Exposes the value rules of `YieldRepurchaseFacilityV2ValidationLib`, which the
///         facility setters and the validation functions of the configuration policy apply, as
///         external calls, so that tests can compare them with the bounds the desired-state
///         reader declares.
contract YieldRepurchaseFacilityV2ValidationLibHarness {
    function requireValidYieldBuybackShare(uint256 share_) external pure {
        YieldRepurchaseFacilityV2ValidationLib.requireValidYieldBuybackShare(share_);
    }

    function requireValidInitialDiscount(uint256 initialDiscount_) external pure {
        YieldRepurchaseFacilityV2ValidationLib.requireValidInitialDiscount(initialDiscount_);
    }

    function requireValidMaxPricePremium(uint256 maxPricePremium_) external pure {
        YieldRepurchaseFacilityV2ValidationLib.requireValidMaxPricePremium(maxPricePremium_);
    }
}
