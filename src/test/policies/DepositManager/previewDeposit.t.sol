// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
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

    function test_givenZeroCap_whenEstimatedCreditIsZero_returnsZero()
        public
        givenIsEnabled
        givenAssetIsAdded
        givenThreeAssetsPerShare
    {
        _setAssetDepositCap(0);

        (uint256 credit, uint256 shares) = IDepositManagerV1_1(address(depositManager))
            .previewDeposit(iAsset, 1);

        assertEq(credit, 0, "zero estimated credit should not require headroom");
        assertEq(shares, 0, "sub-share preview should return zero shares");
    }

    function test_givenAggregateUtilization_whenPreviewingAtAndAboveHeadroom() public {
        uint256 utilization = 60e18;
        uint256 cap = 100e18;
        _configureIdleAssetForPreview(cap, DEPOSIT_OPERATOR);
        _approveSpendingAsset(DEPOSITOR, utilization);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: utilization,
                shouldWrap: false
            })
        );

        (uint256 credit, uint256 shares) = depositManager.previewDeposit(iAsset, cap - utilization);
        assertEq(credit, cap - utilization, "exact headroom credit");
        assertEq(shares, cap - utilization, "exact headroom shares");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_DepositCapExceeded.selector,
                address(iAsset),
                utilization,
                cap
            )
        );
        depositManager.previewDeposit(iAsset, cap - utilization + 1);
    }

    function test_givenCapLoweredBelowUtilization_whenPreviewingPositiveCredit_reverts() public {
        uint256 utilization = 60e18;
        uint256 loweredCap = 50e18;
        _configureIdleAssetForPreview(100e18, DEPOSIT_OPERATOR);
        _approveSpendingAsset(DEPOSITOR, utilization);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: utilization,
                shouldWrap: false
            })
        );
        _setAssetDepositCap(loweredCap);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_DepositCapExceeded.selector,
                address(iAsset),
                utilization,
                loweredCap
            )
        );
        depositManager.previewDeposit(iAsset, 1);
    }

    function test_givenHeadroomConsumedAfterPreview_whenExecuting_revertsAndRollsBack() public {
        address secondOperator = makeAddr("SECOND_OPERATOR");
        uint256 firstDeposit = 60e18;
        uint256 previewedDeposit = 40e18;
        uint256 cap = firstDeposit + previewedDeposit;
        _configureIdleAssetForPreview(cap, DEPOSIT_OPERATOR);

        vm.startPrank(ADMIN);
        rolesAdmin.grantRole("deposit_operator", secondOperator);
        depositManager.setOperatorName(secondOperator, "cd2");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, secondOperator);
        vm.stopPrank();
        asset.mint(DEPOSITOR, 1);
        _approveSpendingAsset(DEPOSITOR, cap + 1);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: firstDeposit,
                shouldWrap: false
            })
        );
        (uint256 previewedCredit, ) = depositManager.previewDeposit(iAsset, previewedDeposit);
        assertEq(previewedCredit, previewedDeposit, "preview should fit current headroom");

        vm.prank(secondOperator);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: previewedDeposit,
                shouldWrap: false
            })
        );
        uint256 depositorBalanceBefore = asset.balanceOf(DEPOSITOR);
        uint256 managerBalanceBefore = asset.balanceOf(address(depositManager));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_DepositCapExceeded.selector,
                address(iAsset),
                cap,
                cap
            )
        );
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 1,
                shouldWrap: false
            })
        );

        assertEq(asset.balanceOf(DEPOSITOR), depositorBalanceBefore, "depositor rollback");
        assertEq(
            asset.balanceOf(address(depositManager)),
            managerBalanceBefore,
            "custody rollback"
        );
        assertEq(_assetDepositCapUtilization(iAsset), cap, "utilization rollback");
    }

    function _configureIdleAssetForPreview(uint256 cap_, address operator_) internal {
        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(0)), cap_, 0);
        depositManager.setOperatorName(operator_, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, operator_);
        vm.stopPrank();
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

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
