// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";
import {YieldRepurchaseFacilityV2ConfigLibTest} from "src/test/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib/YieldRepurchaseFacilityV2ConfigLibTest.sol";

contract YieldRepurchaseFacilityV2ConfigLibTests_desiredConfig is
    YieldRepurchaseFacilityV2ConfigLibTest
{
    // ========== HELPERS ========== //

    function _read(
        string memory config_
    ) internal view returns (YieldRepurchaseFacilityV2ConfigLib.DesiredConfig memory) {
        return harness.desiredConfig(_envWithConfig(config_), CHAIN);
    }

    // ========== DEFECTS OF ONE BLOCK ========== //

    // when the scalar parameters are missing
    //   [X] it reverts naming the first parameter key
    function test_whenParametersAreMissing_reverts() public {
        _expectRevertMissingKey(string.concat(CONFIG_PATH, ".gracePeriod"));
        _read(_join(_validAssetMembers(), _validClearinghouseMember()));
    }

    // when the assets are missing
    //   [X] it reverts naming the assets key
    function test_whenAssetsAreMissing_reverts() public {
        _expectRevertMissingKey(ASSETS_PATH);
        _read(_join(_validParameterMembers(), _validClearinghouseMember()));
    }

    // when the clearinghouses are missing
    //   [X] it reverts naming the clearinghouses key
    function test_whenClearinghousesAreMissing_reverts() public {
        _expectRevertMissingKey(CLEARINGHOUSES_PATH);
        _read(_join(_validParameterMembers(), _validAssetMembers()));
    }

    // ========== SUCCESS ========== //

    // when every block is valid
    //   [X] it reads the scalar parameters
    //   [X] it reads the assets and the backing vault
    //   [X] it reads the clearinghouses
    function test_whenEveryBlockIsValid() public view {
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig memory config = harness.desiredConfig(
            _validEnv(),
            CHAIN
        );

        assertEq(config.parameters.gracePeriod, GRACE_PERIOD, "parameters.gracePeriod");
        assertEq(config.parameters.stepGasLimit, STEP_GAS_LIMIT, "parameters.stepGasLimit");
        assertEq(config.parameters.timelockDelay, TIMELOCK_DELAY, "parameters.timelockDelay");
        assertEq(
            config.parameters.initialDiscount,
            INITIAL_DISCOUNT,
            "parameters.initialDiscount"
        );
        assertEq(
            config.parameters.maxPricePremium,
            MAX_PRICE_PREMIUM,
            "parameters.maxPricePremium"
        );

        assertEq(config.backingVault, susds, "backingVault");
        assertEq(config.assets.length, 2, "assets.length");
        _assertAsset(config.assets[0], SUSDS, susds, true, false, ONE_HUNDRED_PERCENT, "assets[0]");
        _assertAsset(config.assets[1], SUSDE, susde, true, true, ONE_HUNDRED_PERCENT, "assets[1]");

        assertEq(config.clearinghouses.length, 3, "clearinghouses.length");
        _assertClearinghouse(
            config.clearinghouses[0],
            clearinghouseA,
            true,
            0,
            "clearinghouses[0]"
        );
        _assertClearinghouse(
            config.clearinghouses[1],
            clearinghouseB,
            true,
            2_000_000e18,
            "clearinghouses[1]"
        );
        _assertClearinghouse(
            config.clearinghouses[2],
            clearinghouseC,
            false,
            5,
            "clearinghouses[2]"
        );
    }

    // when the chain is another chain of the same file
    //   [X] it reverts naming the key under that chain
    function test_whenChainHasNoConfig_reverts() public {
        _expectRevertMissingKey(
            ".current.other.olympus.config.YieldRepurchaseFacilityV2.gracePeriod"
        );
        harness.desiredConfig(_validEnv(), "other");
    }

    // given the env.json of the repository
    //   when the chain is mainnet
    //     [X] it reads the desired state
    //     [X] the backing vault is one of the declared assets, enabled and not selling shares
    function test_givenRepositoryEnv_whenChainIsMainnet() public view {
        string memory env = vm.readFile("./src/scripts/env.json");

        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig memory config = harness.desiredConfig(
            env,
            "mainnet"
        );

        (
            bool declared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory backingAsset
        ) = harness.findAsset(config.assets, config.backingVault);
        assertTrue(declared, "the backing vault is a declared asset");
        assertTrue(backingAsset.enabled, "the backing vault is enabled");
        assertFalse(backingAsset.sellShares, "the backing vault does not sell shares");
    }
}
