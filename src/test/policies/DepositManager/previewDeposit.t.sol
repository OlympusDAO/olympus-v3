// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Test contracts
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

contract DepositManagerPreviewDepositTest is DepositManagerTest {
    function test_givenThreeAssetsPerShare_whenFractionalRounding()
        public
        givenIsEnabled
        givenAssetIsAdded
        givenThreeAssetsPerShare
    {
        // 100e18 shares / 300e18 assets: floor(request / 3) shares, then shares * 3 credit.
        _assertFractionalDeposit(1, 0, 0);
        _assertFractionalDeposit(2, 0, 0);
        _assertFractionalDeposit(3, 1, 3);
        _assertFractionalDeposit(4, 1, 3);
        _assertFractionalDeposit(1e18, 333_333_333_333_333_333, 999_999_999_999_999_999);
        _assertFractionalDeposit(2e18, 666_666_666_666_666_666, 1_999_999_999_999_999_998);
        _assertFractionalDeposit(3e18, 1e18, 3e18);
    }

    function test_givenThreeFifthsAssetPerShare_whenFractionalRounding()
        public
        givenIsEnabled
        givenAssetIsAdded
        givenThreeFifthsAssetPerShare
    {
        // 100e18 shares / 60e18 assets: floor(request * 5 / 3) shares;
        // credit = floor(shares * 3 / 5), so both steps can discard fractional raw units.
        _assertFractionalDeposit(1, 1, 0);
        _assertFractionalDeposit(2, 3, 1);
        _assertFractionalDeposit(3, 5, 3);
        _assertFractionalDeposit(4, 6, 3);
        _assertFractionalDeposit(1e18, 1_666_666_666_666_666_666, 999_999_999_999_999_999);
        _assertFractionalDeposit(2e18, 3_333_333_333_333_333_333, 1_999_999_999_999_999_999);
        _assertFractionalDeposit(3e18, 5e18, 3e18);
    }

    function _assertFractionalDeposit(
        uint256 request_,
        uint256 expectedShares_,
        uint256 expectedCredit_
    ) internal view {
        (uint256 credit, uint256 shares) = IDepositManagerV1_1(address(depositManager))
            .previewDeposit(iAsset, request_);
        assertEq(shares, expectedShares_, "literal fractional deposit shares");
        assertEq(credit, expectedCredit_, "literal fractional deposit credit");
    }

    function test_givenSharePriceBelowOne(uint96 amount_) public givenIsEnabled givenAssetIsAdded {
        asset.burn(address(vault), 60e18);
        // Raw 18-decimal units: 100e18 shares represent 50e18 assets.
        // Shares = amount * 2; redeeming those shares returns amount exactly.
        (uint256 credit, uint256 shares) = IDepositManagerV1_1(address(depositManager))
            .previewDeposit(iAsset, amount_);
        assertEq(shares, uint256(amount_) * 2, "non-unit deposit shares");
        assertEq(credit, uint256(amount_), "non-unit deposit credit");
    }

    function test_givenSharePriceAboveOne(uint96 amount_) public givenIsEnabled givenAssetIsAdded {
        asset.mint(address(vault), 90e18);
        // Raw 18-decimal units: 100e18 shares represent 200e18 assets.
        // Shares = floor(amount / 2); credit = shares * 2, losing one unit for odd amounts.
        (uint256 credit, uint256 shares) = IDepositManagerV1_1(address(depositManager))
            .previewDeposit(iAsset, amount_);
        assertEq(shares, uint256(amount_) / 2, "non-unit deposit shares");
        assertEq(credit, uint256(amount_) - (uint256(amount_) % 2), "non-unit deposit credit");
    }

    function test_givenIdleAsset() public givenIsEnabled givenAssetIsAddedWithZeroAddress {
        uint256 assetAmount = 10e18;

        (uint256 creditedAssets, uint256 custodyShares) = IDepositManagerV1_1(
            address(depositManager)
        ).previewDeposit(iAsset, assetAmount);

        assertEq(creditedAssets, assetAmount, "idle credit should equal the asset amount");
        assertEq(custodyShares, assetAmount, "idle custody should use raw asset units");
    }

    function test_givenVault_whenCallerIsFuzzed(
        address caller_
    ) public givenIsEnabled givenAssetIsAdded {
        uint256 assetAmount = 10e18;

        // Pre-deposit vault state: 100e18 shares represent 110e18 assets.
        // Shares = floor(10e18 assets * 100e18 shares / 110e18 assets)
        //        = 9_090_909_090_909_090_909 shares (18 decimals).
        // Credit = floor(shares * 110e18 assets / 100e18 shares)
        //        = 9_999_999_999_999_999_999 assets (18 decimals).
        uint256 expectedShares = 9_090_909_090_909_090_909;
        uint256 expectedCredit = 9_999_999_999_999_999_999;

        vm.prank(caller_);
        (uint256 creditedAssets, uint256 custodyShares) = IDepositManagerV1_1(
            address(depositManager)
        ).previewDeposit(iAsset, assetAmount);

        assertEq(creditedAssets, expectedCredit, "credit should use the pre-deposit vault state");
        assertEq(custodyShares, expectedShares, "custody should use previewDeposit shares");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
