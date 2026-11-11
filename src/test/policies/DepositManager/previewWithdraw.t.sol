// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Test contracts
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

contract DepositManagerPreviewWithdrawTest is DepositManagerTest {
    function test_givenThreeAssetsPerShare_whenShareOutputRounding()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        asset.mint(address(vault), 190e18);
        // 100e18 shares / 300e18 assets, both 18 decimals: floor(request / 3).
        // One whole asset yields 0.333333333333333333 shares; two yield
        // 0.666666666666666666 shares. Three assets yield exactly one share.
        _assertPreview(1, true, address(iVault), 0);
        _assertPreview(2, true, address(iVault), 0);
        _assertPreview(3, true, address(iVault), 1);
        _assertPreview(4, true, address(iVault), 1);
        _assertPreview(1e18, true, address(iVault), 333_333_333_333_333_333);
        _assertPreview(2e18, true, address(iVault), 666_666_666_666_666_666);
        _assertPreview(3e18, true, address(iVault), 1e18);
    }

    function test_givenThreeAssetsPerShare_whenUnderlyingOutputRounding()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        asset.mint(address(vault), 190e18);
        // Floor the request / 3 to raw shares, then multiply by 3 to redeem.
        // 1e18 leaves one raw asset unit behind; 2e18 leaves two; 3e18 is exact.
        _assertPreview(1, false, address(iAsset), 0);
        _assertPreview(2, false, address(iAsset), 0);
        _assertPreview(3, false, address(iAsset), 3);
        _assertPreview(4, false, address(iAsset), 3);
        _assertPreview(1e18, false, address(iAsset), 999_999_999_999_999_999);
        _assertPreview(2e18, false, address(iAsset), 1_999_999_999_999_999_998);
        _assertPreview(3e18, false, address(iAsset), 3e18);
    }

    function test_givenThreeFifthsAssetPerShare_whenShareOutputRounding()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        asset.burn(address(vault), 50e18);
        // 100e18 shares / 60e18 assets: floor(request * 5 / 3).
        // Whole-asset requests of one and two produce repeating fractional shares;
        // three assets convert exactly to five shares.
        _assertPreview(1, true, address(iVault), 1);
        _assertPreview(2, true, address(iVault), 3);
        _assertPreview(3, true, address(iVault), 5);
        _assertPreview(4, true, address(iVault), 6);
        _assertPreview(1e18, true, address(iVault), 1_666_666_666_666_666_666);
        _assertPreview(2e18, true, address(iVault), 3_333_333_333_333_333_333);
        _assertPreview(3e18, true, address(iVault), 5e18);
    }

    function test_givenThreeFifthsAssetPerShare_whenUnderlyingOutputRounding()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        asset.burn(address(vault), 50e18);
        // Floor(request * 5 / 3) shares, then floor(shares * 3 / 5) assets.
        // One raw asset buys one raw share, which redeems to zero raw assets.
        // For 1e18: 1_666_666_666_666_666_666 shares redeem to
        // floor(999_999_999_999_999_999.6) = 999_999_999_999_999_999 assets.
        _assertPreview(1, false, address(iAsset), 0);
        _assertPreview(2, false, address(iAsset), 1);
        _assertPreview(3, false, address(iAsset), 3);
        _assertPreview(4, false, address(iAsset), 3);
        _assertPreview(1e18, false, address(iAsset), 999_999_999_999_999_999);
        _assertPreview(2e18, false, address(iAsset), 1_999_999_999_999_999_999);
        _assertPreview(3e18, false, address(iAsset), 3e18);
    }

    function test_givenSharePriceBelowOne_whenUnderlyingOutputBoundaries()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        asset.burn(address(vault), 60e18);
        // 100e18 shares / 50e18 assets: one raw asset unit buys two raw shares.
        // Redeeming those shares returns the requested asset units exactly.
        _assertPreview(0, false, address(iAsset), 0);
        _assertPreview(1, false, address(iAsset), 1);
        _assertPreview(2, false, address(iAsset), 2);
        _assertPreview(3, false, address(iAsset), 3);
    }

    function test_givenSharePriceBelowOne_whenShareOutputBoundaries()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        asset.burn(address(vault), 60e18);
        // Both tokens use 18 decimals. At 0.5 assets/share, raw requests 0, 1, 2, 3
        // yield exactly 0, 2, 4, 6 raw shares, with no rounding loss.
        _assertPreview(0, true, address(iVault), 0);
        _assertPreview(1, true, address(iVault), 2);
        _assertPreview(2, true, address(iVault), 4);
        _assertPreview(3, true, address(iVault), 6);
    }

    function test_givenSharePriceAboveOne_whenUnderlyingOutputBoundaries()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        asset.mint(address(vault), 90e18);
        // 100e18 shares / 200e18 assets: the first raw share costs two raw asset units.
        // Requests 0 and 1 produce no shares. Requests 2 and 3 both redeem one share
        // for two raw asset units; request 3 loses one unit to the initial floor.
        _assertPreview(0, false, address(iAsset), 0);
        _assertPreview(1, false, address(iAsset), 0);
        _assertPreview(2, false, address(iAsset), 2);
        _assertPreview(3, false, address(iAsset), 2);
    }

    function test_givenSharePriceAboveOne_whenShareOutputBoundaries()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        asset.mint(address(vault), 90e18);
        // Both tokens use 18 decimals. At two assets/share, requests 0, 1, 2, 3
        // produce 0, 0, 1, 1 raw shares: below, at, and just above one-share cost.
        _assertPreview(0, true, address(iVault), 0);
        _assertPreview(1, true, address(iVault), 0);
        _assertPreview(2, true, address(iVault), 1);
        _assertPreview(3, true, address(iVault), 1);
    }

    function _assertPreview(
        uint256 requestedAssets_,
        bool asShares_,
        address expectedToken_,
        uint256 expectedOutput_
    ) internal view {
        (IERC20 token, uint256 output) = IDepositManagerV1_1(address(depositManager))
            .previewWithdraw(iAsset, requestedAssets_, asShares_);
        assertEq(address(token), expectedToken_, "boundary output token");
        assertEq(output, expectedOutput_, "hard-coded boundary output");
    }

    function test_givenSharePriceBelowOne_whenUnderlyingOutput(
        uint96 amount_
    ) public givenIsEnabled givenAssetIsAdded {
        asset.burn(address(vault), 60e18);
        // Raw 18-decimal units: 100e18 shares represent 50e18 assets.
        // Shares = amount * 2; assets = shares / 2 = amount, exactly.
        (IERC20 token, uint256 output) = IDepositManagerV1_1(address(depositManager))
            .previewWithdraw(iAsset, amount_, false);
        assertEq(address(token), address(iAsset), "selected output token");
        assertEq(output, uint256(amount_), "non-unit withdrawal output");
    }

    function test_givenSharePriceBelowOne_whenShareOutput(
        uint96 amount_
    ) public givenIsEnabled givenAssetIsAdded {
        asset.burn(address(vault), 60e18);
        // Raw 18-decimal units: 100e18 shares represent 50e18 assets.
        // Shares = amount * 2, exactly.
        (IERC20 token, uint256 output) = IDepositManagerV1_1(address(depositManager))
            .previewWithdraw(iAsset, amount_, true);
        assertEq(address(token), address(iVault), "selected output token");
        assertEq(output, uint256(amount_) * 2, "non-unit withdrawal output");
    }

    function test_givenSharePriceAboveOne_whenUnderlyingOutput(
        uint96 amount_
    ) public givenIsEnabled givenAssetIsAdded {
        asset.mint(address(vault), 90e18);
        // Raw 18-decimal units: 100e18 shares represent 200e18 assets.
        // Shares = floor(amount / 2); assets = shares * 2, losing one unit for odd amounts.
        (IERC20 token, uint256 output) = IDepositManagerV1_1(address(depositManager))
            .previewWithdraw(iAsset, amount_, false);
        assertEq(address(token), address(iAsset), "selected output token");
        assertEq(output, uint256(amount_) - (uint256(amount_) % 2), "non-unit withdrawal output");
    }

    function test_givenSharePriceAboveOne_whenShareOutput(
        uint96 amount_
    ) public givenIsEnabled givenAssetIsAdded {
        asset.mint(address(vault), 90e18);
        // Raw 18-decimal units: 100e18 shares represent 200e18 assets.
        // Shares = floor(amount / 2), rounded down.
        (IERC20 token, uint256 output) = IDepositManagerV1_1(address(depositManager))
            .previewWithdraw(iAsset, amount_, true);
        assertEq(address(token), address(iVault), "selected output token");
        assertEq(output, uint256(amount_) / 2, "non-unit withdrawal output");
    }

    function test_givenVault_whenUnderlyingOutput_whenCallerIsFuzzed(
        address caller_
    ) public givenIsEnabled givenAssetIsAdded {
        uint256 requestedAssets = 10e18;

        // Vault state: 100e18 shares represent 110e18 assets.
        // Shares = floor(10e18 assets * 100e18 shares / 110e18 assets)
        //        = 9_090_909_090_909_090_909 shares (18 decimals).
        // Output = floor(shares * 110e18 assets / 100e18 shares)
        //        = 9_999_999_999_999_999_999 assets (18 decimals).
        uint256 expectedAssets = 9_999_999_999_999_999_999;

        vm.prank(caller_);
        (IERC20 tokenOut, uint256 amountOut) = IDepositManagerV1_1(address(depositManager))
            .previewWithdraw(iAsset, requestedAssets, false);

        assertEq(address(tokenOut), address(iAsset), "tokenOut should be the underlying asset");
        assertEq(amountOut, expectedAssets, "amountOut should use the vault redemption preview");
    }

    function test_givenVault_whenShareOutput() public givenIsEnabled givenAssetIsAdded {
        uint256 requestedAssets = 10e18;

        // Vault state: 100e18 shares represent 110e18 assets.
        // floor(10e18 assets * 100e18 shares / 110e18 assets)
        // = 9_090_909_090_909_090_909 shares (18 decimals).
        uint256 expectedShares = 9_090_909_090_909_090_909;

        (IERC20 tokenOut, uint256 amountOut) = IDepositManagerV1_1(address(depositManager))
            .previewWithdraw(iAsset, requestedAssets, true);

        assertEq(address(tokenOut), address(iVault), "tokenOut should be the vault share token");
        assertEq(amountOut, expectedShares, "amountOut should use convertToShares");
    }

    function test_givenIdleAsset_whenShareOutput_reverts()
        public
        givenIsEnabled
        givenAssetIsAddedWithZeroAddress
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_VaultRequired.selector,
                address(iAsset)
            )
        );

        // The call's exact revert data is asserted above, so its return values are unreachable.
        // forge-lint: disable-next-line(unused-return)
        IDepositManagerV1_1(address(depositManager)).previewWithdraw(iAsset, 1, true);
    }

    function test_givenExplicitShareWithdrawalRequirement_whenUnderlyingOutput_reverts()
        public
        givenIsEnabled
    {
        vm.startPrank(ADMIN);
        IDepositManagerV1_1(address(depositManager)).addAsset(
            iAsset,
            IERC4626(address(iVault)),
            type(uint256).max,
            0,
            true
        );
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(iVault)
            )
        );
        // The exact revert is asserted above, so the return values are unreachable.
        // forge-lint: disable-next-line(unused-return)
        IDepositManagerV1_1(address(depositManager)).previewWithdraw(iAsset, 1e18, false);
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
