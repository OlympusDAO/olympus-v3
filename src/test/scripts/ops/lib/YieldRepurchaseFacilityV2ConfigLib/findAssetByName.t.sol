// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";
import {YieldRepurchaseFacilityV2ConfigLibTest} from "src/test/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib/YieldRepurchaseFacilityV2ConfigLibTest.sol";

contract YieldRepurchaseFacilityV2ConfigLibTests_findAssetByName is
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
    //   [X] it reports the name as not declared
    function test_whenAssetsAreEmpty() public view {
        (bool declared, YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset) = harness
            .findAssetByName(new YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[](0), SUSDS);

        assertFalse(declared, "declared");
        assertEq(asset.vault, address(0), "asset.vault");
    }

    // when the name is not the name of a declared asset
    //   [X] it reports the name as not declared
    //   [X] it returns an empty asset
    function test_whenNameIsNotDeclared(string memory name_) public view {
        vm.assume(keccak256(bytes(name_)) != keccak256(bytes(SUSDS)));
        vm.assume(keccak256(bytes(name_)) != keccak256(bytes(SUSDE)));

        (bool declared, YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset) = harness
            .findAssetByName(_assets(), name_);

        assertFalse(declared, "declared");
        _assertAsset(asset, "", address(0), false, false, 0, "asset");
    }

    // when the name differs from a declared name by letter case only
    //   [X] it reports the name as not declared
    function test_whenNameDiffersByCase() public view {
        (bool declared, ) = harness.findAssetByName(_assets(), "susds");

        assertFalse(declared, "declared");
    }

    // when the name is the name of the first declared asset
    //   [X] it returns that asset
    function test_whenNameIsFirstAsset() public view {
        (bool declared, YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset) = harness
            .findAssetByName(_assets(), SUSDS);

        assertTrue(declared, "declared");
        _assertAsset(asset, SUSDS, susds, true, false, ONE_HUNDRED_PERCENT, "asset");
    }

    // when the name is the name of the last declared asset
    //   [X] it returns that asset
    function test_whenNameIsLastAsset() public view {
        (bool declared, YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset) = harness
            .findAssetByName(_assets(), SUSDE);

        assertTrue(declared, "declared");
        _assertAsset(asset, SUSDE, susde, true, true, ONE_HUNDRED_PERCENT, "asset");
    }
}
