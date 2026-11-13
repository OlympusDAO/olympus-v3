// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";
import {YieldRepurchaseFacilityV2ConfigLibTest} from "src/test/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib/YieldRepurchaseFacilityV2ConfigLibTest.sol";

contract YieldRepurchaseFacilityV2ConfigLibTests_desiredAssets is
    YieldRepurchaseFacilityV2ConfigLibTest
{
    // ========== HELPERS ========== //

    /// @notice Reads the assets of an `env.json` whose facility config object holds `config_`
    ///         and whose `external.tokens` object holds `tokens_`.
    function _read(
        string memory config_,
        string memory tokens_
    )
        internal
        view
        returns (
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets,
            address backingVault
        )
    {
        return harness.desiredAssets(_env(config_, tokens_, ""), CHAIN);
    }

    /// @notice The asset members of the rig with `share_` as the yield buyback share of sUSDe.
    function _withSusdeShare(uint256 share_) internal pure returns (string memory members) {
        return
            _assetMembers(
                _join(
                    _asset(SUSDS, true, false, ONE_HUNDRED_PERCENT),
                    _asset(SUSDE, true, true, share_)
                ),
                SUSDS
            );
    }

    /// @notice The asset members with sUSDS, declared with the given flags, as the only asset
    ///         and as the backing vault.
    function _withBackingVaultFlags(
        bool enabled_,
        bool sellShares_
    ) internal pure returns (string memory members) {
        return _assetMembers(_asset(SUSDS, enabled_, sellShares_, ONE_HUNDRED_PERCENT), SUSDS);
    }

    function _expectRevertShare(uint256 value_) internal {
        _expectRevertOutOfBound(
            string.concat(ASSETS_PATH, ".sUSDe.yieldBuybackShare"),
            value_,
            string.concat(
                "a yield buyback share is at most ",
                vm.toString(ONE_HUNDRED_PERCENT),
                " (100%)"
            )
        );
    }

    function _expectRevertShareTooHigh() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_YieldBuybackShareTooHigh
                    .selector
            )
        );
    }

    // ========== MISSING KEYS ========== //

    // when the assets object is missing
    //   [X] it reverts naming the key
    function test_whenAssetsAreMissing_reverts() public {
        _expectRevertMissingKey(ASSETS_PATH);
        _read(_member("backingVault", _quoted(SUSDS)), _validTokens());
    }

    // when the backing vault is missing
    //   [X] it reverts naming the key
    function test_whenBackingVaultIsMissing_reverts() public {
        _expectRevertMissingKey(string.concat(CONFIG_PATH, ".backingVault"));
        _read(
            _member(
                "assets",
                string.concat("{", _asset(SUSDS, true, false, ONE_HUNDRED_PERCENT), "}")
            ),
            _validTokens()
        );
    }

    // when an asset lacks the enabled flag
    //   [X] it reverts naming the key
    function test_whenEnabledIsMissing_reverts() public {
        string memory entry = _member(
            SUSDS,
            string.concat(
                "{",
                _member("sellShares", "false"),
                ",",
                _member("yieldBuybackShare", _quoted(ONE_HUNDRED_PERCENT)),
                "}"
            )
        );

        _expectRevertMissingKey(string.concat(ASSETS_PATH, ".sUSDS.enabled"));
        _read(_assetMembers(entry, SUSDS), _validTokens());
    }

    // when an asset lacks the sell shares flag
    //   [X] it reverts naming the key
    function test_whenSellSharesIsMissing_reverts() public {
        string memory entry = _member(
            SUSDS,
            string.concat(
                "{",
                _member("enabled", "true"),
                ",",
                _member("yieldBuybackShare", _quoted(ONE_HUNDRED_PERCENT)),
                "}"
            )
        );

        _expectRevertMissingKey(string.concat(ASSETS_PATH, ".sUSDS.sellShares"));
        _read(_assetMembers(entry, SUSDS), _validTokens());
    }

    // when an asset lacks the yield buyback share
    //   [X] it reverts naming the key
    function test_whenYieldBuybackShareIsMissing_reverts() public {
        string memory entry = _member(
            SUSDS,
            string.concat("{", _member("enabled", "true"), ",", _member("sellShares", "false"), "}")
        );

        _expectRevertMissingKey(string.concat(ASSETS_PATH, ".sUSDS.yieldBuybackShare"));
        _read(_assetMembers(entry, SUSDS), _validTokens());
    }

    // ========== YIELD BUYBACK SHARE ========== //

    // when a yield buyback share is one above 100%
    //   [X] it reverts naming the key and the bound
    //   [X] the facility rule rejects the same value
    function test_whenYieldBuybackShareIsAboveOneHundredPercent_reverts() public {
        _expectRevertShareTooHigh();
        validation.requireValidYieldBuybackShare(ONE_HUNDRED_PERCENT + 1);

        _expectRevertShare(ONE_HUNDRED_PERCENT + 1);
        _read(_withSusdeShare(ONE_HUNDRED_PERCENT + 1), _validTokens());
    }

    // when a yield buyback share is anywhere above 100%
    //   [X] it reverts naming the key and the bound
    //   [X] the facility rule rejects the same value
    function test_whenYieldBuybackShareIsInInvalidInterval_reverts(uint256 share_) public {
        // The invalid interval is [ONE_HUNDRED_PERCENT + 1, type(uint256).max]
        uint256 share = bound(share_, ONE_HUNDRED_PERCENT + 1, type(uint256).max);

        _expectRevertShareTooHigh();
        validation.requireValidYieldBuybackShare(share);

        _expectRevertShare(share);
        _read(_withSusdeShare(share), _validTokens());
    }

    // when a yield buyback share is the largest uint256
    //   [X] it reverts naming the key and the bound
    function test_whenYieldBuybackShareIsMaxUint256_reverts() public {
        _expectRevertShare(type(uint256).max);
        _read(_withSusdeShare(type(uint256).max), _validTokens());
    }

    // when a yield buyback share is zero
    //   [X] it reads the share
    function test_whenYieldBuybackShareIsZero() public view {
        (YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets, ) = _read(
            _withSusdeShare(0),
            _validTokens()
        );

        assertEq(assets[1].yieldBuybackShare, 0, "sUSDe.yieldBuybackShare");
    }

    // when a yield buyback share is 100%
    //   [X] it reads the share
    //   [X] the facility rule accepts the same value
    function test_whenYieldBuybackShareIsOneHundredPercent() public view {
        validation.requireValidYieldBuybackShare(ONE_HUNDRED_PERCENT);

        (YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets, ) = _read(
            _withSusdeShare(ONE_HUNDRED_PERCENT),
            _validTokens()
        );

        assertEq(assets[1].yieldBuybackShare, ONE_HUNDRED_PERCENT, "sUSDe.yieldBuybackShare");
    }

    // when a yield buyback share is anywhere up to 100%
    //   [X] it reads the share
    //   [X] the facility rule accepts the same value
    function test_whenYieldBuybackShareIsInValidInterval(uint256 share_) public view {
        // The valid interval is [0, ONE_HUNDRED_PERCENT]
        uint256 share = bound(share_, 0, ONE_HUNDRED_PERCENT);

        validation.requireValidYieldBuybackShare(share);

        (YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets, ) = _read(
            _withSusdeShare(share),
            _validTokens()
        );

        assertEq(assets[1].yieldBuybackShare, share, "sUSDe.yieldBuybackShare");
    }

    // ========== VAULT ADDRESSES ========== //

    // when an asset name has no key under the tokens
    //   [X] it reverts naming the asset and the token key
    function test_whenAssetHasNoTokenKey_reverts() public {
        _expectRevertMessage(
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: asset sUSDe of ",
                ASSETS_PATH,
                " has no vault address: missing env.json key ",
                TOKENS_PATH,
                ".sUSDe"
            )
        );
        _read(_validAssetMembers(), _member(SUSDS, _quoted(susds)));
    }

    // when the token key of an asset holds the zero address
    //   [X] it reverts naming the asset and the token key
    function test_whenAssetTokenIsZeroAddress_reverts() public {
        _expectRevertMessage(
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: asset sUSDe of ",
                ASSETS_PATH,
                " has no vault address: zero address for ",
                TOKENS_PATH,
                ".sUSDe"
            )
        );
        _read(
            _validAssetMembers(),
            _join(_member(SUSDS, _quoted(susds)), _member(SUSDE, _quoted(address(0))))
        );
    }

    // when two assets resolve to one vault address
    //   [X] it reverts naming both assets and the address
    function test_whenTwoAssetsShareVault_reverts() public {
        _expectRevertMessage(
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: assets sUSDS and sUSDe of ",
                ASSETS_PATH,
                " resolve to one vault address ",
                vm.toString(susds)
            )
        );
        _read(
            _validAssetMembers(),
            _join(_member(SUSDS, _quoted(susds)), _member(SUSDE, _quoted(susds)))
        );
    }

    // ========== BACKING VAULT ========== //

    // when the backing vault names an asset that is not declared
    //   [X] it reverts naming the key, the name and the assets object
    function test_whenBackingVaultIsNotDeclared_reverts() public {
        _expectRevertMessage(
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: ",
                CONFIG_PATH,
                ".backingVault names sDAI, which is not declared under ",
                ASSETS_PATH
            )
        );
        _read(
            _assetMembers(_asset(SUSDS, true, false, ONE_HUNDRED_PERCENT), "sDAI"),
            _validTokens()
        );
    }

    // when no asset is declared
    //   [X] it reverts, since the backing vault names no declared asset
    function test_whenAssetsAreEmpty_reverts() public {
        _expectRevertMessage(
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: ",
                CONFIG_PATH,
                ".backingVault names sUSDS, which is not declared under ",
                ASSETS_PATH
            )
        );
        _read(_assetMembers("", SUSDS), _validTokens());
    }

    // when the backing vault is declared with enabled: false
    //   [X] it reverts naming the asset and both keys
    function test_whenBackingVaultIsDisabled_reverts() public {
        _expectRevertMessage(
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: the backing vault sUSDS (",
                CONFIG_PATH,
                ".backingVault) is declared with enabled: false under ",
                ASSETS_PATH,
                "; the facility cannot disable the backing vault"
            )
        );
        _read(_withBackingVaultFlags(false, false), _validTokens());
    }

    // when the backing vault is declared with sellShares: true
    //   [X] it reverts naming the asset and both keys
    function test_whenBackingVaultSellsShares_reverts() public {
        _expectRevertMessage(
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: the backing vault sUSDS (",
                CONFIG_PATH,
                ".backingVault) is declared with sellShares: true under ",
                ASSETS_PATH,
                "; the backing vault cannot sell shares"
            )
        );
        _read(_withBackingVaultFlags(true, true), _validTokens());
    }

    // when the backing vault is declared with enabled: false and sellShares: true
    //   [X] it reverts on the enabled flag first
    function test_whenBackingVaultIsDisabledAndSellsShares_reverts() public {
        _expectRevertMessage(
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: the backing vault sUSDS (",
                CONFIG_PATH,
                ".backingVault) is declared with enabled: false under ",
                ASSETS_PATH,
                "; the facility cannot disable the backing vault"
            )
        );
        _read(_withBackingVaultFlags(false, true), _validTokens());
    }

    // ========== SUCCESS ========== //

    // when one asset is declared and named as the backing vault
    //   [X] it reads the asset
    //   [X] it returns its vault as the backing vault
    function test_whenOneAsset() public view {
        (
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets,
            address backingVault
        ) = _read(_withBackingVaultFlags(true, false), _validTokens());

        assertEq(assets.length, 1, "assets.length");
        _assertAsset(assets[0], SUSDS, susds, true, false, ONE_HUNDRED_PERCENT, "assets[0]");
        assertEq(backingVault, susds, "backingVault");
    }

    // when two assets are declared
    //   [X] it reads both assets with their own fields
    //   [X] it returns the vault of the named asset as the backing vault
    function test_whenTwoAssets() public view {
        string memory members = _assetMembers(
            _join(_asset(SUSDS, true, false, ONE_HUNDRED_PERCENT), _asset(SUSDE, true, true, 5e17)),
            SUSDS
        );

        (
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets,
            address backingVault
        ) = _read(members, _validTokens());

        assertEq(assets.length, 2, "assets.length");
        _assertAsset(assets[0], SUSDS, susds, true, false, ONE_HUNDRED_PERCENT, "assets[0]");
        _assertAsset(assets[1], SUSDE, susde, true, true, 5e17, "assets[1]");
        assertEq(backingVault, susds, "backingVault");
    }

    // when an asset other than the backing vault is declared with enabled: false
    //   [X] it reads the asset as disabled
    function test_whenOtherAssetIsDisabled() public view {
        string memory members = _assetMembers(
            _join(
                _asset(SUSDS, true, false, ONE_HUNDRED_PERCENT),
                _asset(SUSDE, false, true, ONE_HUNDRED_PERCENT)
            ),
            SUSDS
        );

        (YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets, ) = _read(
            members,
            _validTokens()
        );

        _assertAsset(assets[1], SUSDE, susde, false, true, ONE_HUNDRED_PERCENT, "assets[1]");
    }

    // when the assets are declared out of name order
    //   [X] it returns them sorted by name, byte-wise
    function test_whenAssetsAreOutOfOrder() public {
        address sdai = makeAddr("sDAI");
        address weth = makeAddr("WETH");
        // Byte-wise order: "WETH" < "sDAI" < "sUSDS" < "sUSDe", an upper-case letter sorting
        // before every lower-case one
        string memory entries = _asset(SUSDE, true, true, 1);
        entries = _join(entries, _asset("sDAI", false, false, 2));
        entries = _join(entries, _asset(SUSDS, true, false, 3));
        entries = _join(entries, _asset("WETH", true, true, 4));
        string memory tokens = _join(_validTokens(), _member("sDAI", _quoted(sdai)));
        tokens = _join(tokens, _member("WETH", _quoted(weth)));

        (
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets,
            address backingVault
        ) = _read(_assetMembers(entries, SUSDS), tokens);

        assertEq(assets.length, 4, "assets.length");
        _assertAsset(assets[0], "WETH", weth, true, true, 4, "assets[0]");
        _assertAsset(assets[1], "sDAI", sdai, false, false, 2, "assets[1]");
        _assertAsset(assets[2], SUSDS, susds, true, false, 3, "assets[2]");
        _assertAsset(assets[3], SUSDE, susde, true, true, 1, "assets[3]");
        assertEq(backingVault, susds, "backingVault");
    }

    // when the tokens object holds addresses of names that are not assets
    //   [X] it reads the declared assets only
    function test_whenTokensHoldOtherNames() public {
        string memory tokens = _join(_validTokens(), _member("DAI", _quoted(makeAddr("DAI"))));

        (YieldRepurchaseFacilityV2ConfigLib.DesiredAsset[] memory assets, ) = _read(
            _validAssetMembers(),
            tokens
        );

        assertEq(assets.length, 2, "assets.length");
    }
}
