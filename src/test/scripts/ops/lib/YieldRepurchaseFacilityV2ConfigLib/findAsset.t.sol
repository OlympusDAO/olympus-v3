// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";
import {YieldRepurchaseFacilityV2ConfigLibTest} from "src/test/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib/YieldRepurchaseFacilityV2ConfigLibTest.sol";

contract YieldRepurchaseFacilityV2ConfigLibTests_findAsset is
    YieldRepurchaseFacilityV2ConfigLibTest
{
    // ========== HELPERS ========== //

    function _assets()
        internal
        view
        returns (YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets)
    {
        (assets, ) = harness.desiredAssets(_validEnv(), CHAIN);
    }

    // ========== TESTS ========== //

    // when no asset is declared
    //   [X] it reports the vault as not declared
    function test_whenAssetsAreEmpty(address vault_) public view {
        (bool declared, YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset) = harness
            .findAsset(new YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[](0), vault_);

        assertFalse(declared, "declared");
        assertEq(asset.vault, address(0), "asset.vault");
    }

    // when the vault is not the vault of a declared asset
    //   [X] it reports the vault as not declared
    //   [X] it returns an empty asset
    function test_whenVaultIsNotDeclared(address vault_) public view {
        vm.assume(vault_ != susds);
        vm.assume(vault_ != susde);

        (bool declared, YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset) = harness
            .findAsset(_assets(), vault_);

        assertFalse(declared, "declared");
        _assertAsset(asset, "", address(0), false, false, 0, "asset");
    }

    // when the vault is the vault of the first declared asset
    //   [X] it returns that asset
    function test_whenVaultIsFirstAsset() public view {
        (bool declared, YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset) = harness
            .findAsset(_assets(), susds);

        assertTrue(declared, "declared");
        _assertAsset(asset, SUSDS, susds, true, false, ONE_HUNDRED_PERCENT, "asset");
    }

    // when the vault is the vault of the last declared asset
    //   [X] it returns that asset
    function test_whenVaultIsLastAsset() public view {
        (bool declared, YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset) = harness
            .findAsset(_assets(), susde);

        assertTrue(declared, "declared");
        _assertAsset(asset, SUSDE, susde, true, true, ONE_HUNDRED_PERCENT, "asset");
    }
}
