// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";

/// @notice Exposes the readers and the lookups of `YieldRepurchaseFacilityV2ConfigLib` as
///         external calls, so that tests can match their reverts with `vm.expectRevert`.
contract YieldRepurchaseFacilityV2ConfigLibHarness {
    function desiredConfig(
        string memory env_,
        string memory chain_
    ) external view returns (YieldRepurchaseFacilityV2ConfigLib.DesiredConfig memory config) {
        return YieldRepurchaseFacilityV2ConfigLib.desiredConfig(env_, chain_);
    }

    function desiredParameters(
        string memory env_,
        string memory chain_
    )
        external
        view
        returns (YieldRepurchaseFacilityV2ConfigLib.DesiredParameters memory parameters)
    {
        return YieldRepurchaseFacilityV2ConfigLib.desiredParameters(env_, chain_);
    }

    function desiredAssets(
        string memory env_,
        string memory chain_
    )
        external
        view
        returns (
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets,
            address backingVault
        )
    {
        return YieldRepurchaseFacilityV2ConfigLib.desiredAssets(env_, chain_);
    }

    function desiredClearinghouses(
        string memory env_,
        string memory chain_
    )
        external
        view
        returns (YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[] memory clearinghouses)
    {
        return YieldRepurchaseFacilityV2ConfigLib.desiredClearinghouses(env_, chain_);
    }

    function usdeUsdPriceFeed(
        string memory env_,
        string memory chain_
    ) external view returns (address feed) {
        return YieldRepurchaseFacilityV2ConfigLib.usdeUsdPriceFeed(env_, chain_);
    }

    function findAsset(
        YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets_,
        address vault_
    )
        external
        pure
        returns (bool declared, YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset)
    {
        return YieldRepurchaseFacilityV2ConfigLib.findAsset(assets_, vault_);
    }

    function findAssetByName(
        YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets_,
        string memory name_
    )
        external
        pure
        returns (bool declared, YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset)
    {
        return YieldRepurchaseFacilityV2ConfigLib.findAssetByName(assets_, name_);
    }

    function findClearinghouse(
        YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[] memory clearinghouses_,
        address clearinghouse_
    )
        external
        pure
        returns (
            bool declared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse memory entry
        )
    {
        return YieldRepurchaseFacilityV2ConfigLib.findClearinghouse(clearinghouses_, clearinghouse_);
    }
}
