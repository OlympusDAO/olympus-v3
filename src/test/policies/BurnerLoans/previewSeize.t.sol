// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

import {BurnerLoansSeizureTestBase} from "./fixtures/BurnerLoansSeizureTestBase.sol";

contract BurnerLoansPreviewSeizeTest is BurnerLoansSeizureTestBase {
    function test_givenUnhealthyPosition_previewSeize_returnsBatchAmounts() public {
        _makeUnhealthy(alice);

        vm.prank(keeper);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );

        assertEq(preview.seizedDebtOhm, 100e9, "seized debt");
        assertEq(preview.seizedCollateral, 2_000e18, "seized collateral");
        assertEq(preview.keeperReward, 20e18, "one percent reward");
        assertEq(preview.collateralToTreasury, 1_980e18, "treasury collateral");
        assertTrue(preview.executable, "executable");
    }

    function test_givenProtocolSeizer_previewSeize_returnsZeroReward() public {
        _makeUnhealthy(alice);

        vm.prank(protocolSeizer);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );

        assertEq(preview.keeperReward, 0, "protocol reward");
        assertEq(preview.collateralToTreasury, 2_000e18, "treasury collateral");
    }

    function test_givenEmptyBatch_previewSeize_reverts() public {
        address[] memory borrowers = new address[](0);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidBatch.selector);
        burnerLoans.previewSeize(address(usds), borrowers);
    }

    function testFuzz_givenBatchAboveMaximum_previewSeize_reverts(uint256 batchLength_) public {
        uint256 batchLength = bound(batchLength_, 51, 100);
        address[] memory borrowers = new address[](batchLength);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidBatch.selector);
        burnerLoans.previewSeize(address(usds), borrowers);
    }

    function test_givenExactMaximumBatch_previewSeize_succeeds() public {
        address[] memory borrowers = new address[](50);
        for (uint256 i; i < borrowers.length; ++i) {
            address borrower = address(uint160(i + 100));
            borrowers[i] = borrower;
            burnerLoans.setPositionForTest(
                address(usds),
                borrower,
                IBurnerLoans.Position({
                    depositedCollateral: 0,
                    debtOhm: 1e9,
                    maturity: uint48(block.timestamp + 30 days),
                    lastBorrowBlock: 0,
                    status: IBurnerLoans.PositionStatus.Active
                })
            );
        }

        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            borrowers
        );

        assertEq(preview.seizedDebtOhm, 50e9, "seized debt");
        assertEq(preview.seizedCollateral, 0, "seized collateral");
        assertEq(preview.keeperReward, 0, "keeper reward");
        assertTrue(preview.executable, "executable");
    }

    function test_givenDuplicateBorrower_previewSeize_reverts() public {
        _makeUnhealthy(alice);

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_DuplicateBorrower.selector, alice)
        );
        burnerLoans.previewSeize(address(usds), _pair(alice, alice));
    }

    function test_givenZeroBorrower_previewSeize_reverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoans.previewSeize(address(usds), _single(address(0)));
    }

    function test_givenHealthyPosition_previewSeize_reverts() public {
        _borrow(alice, 2_000e18, 100e9);

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PositionNotSeizable.selector, alice)
        );
        burnerLoans.previewSeize(address(usds), _single(alice));
    }

    function test_givenDebtFreePosition_previewSeize_reverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_NoDebt.selector);
        burnerLoans.previewSeize(address(usds), _single(alice));
    }

    function test_givenStalePrices_previewSeize_reverts() public {
        _makeUnhealthy(alice);
        vm.warp(block.timestamp + 9 hours);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.previewSeize(address(usds), _single(alice));
    }

    function test_givenPolicyDisabled_previewSeize_reverts() public {
        _makeUnhealthy(alice);
        vm.prank(emergency);
        burnerLoans.disable(bytes(""));

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewSeize(address(usds), _single(alice));
    }

    function test_givenAssetOriginationsDisabled_previewSeizeRemainsAvailable() public {
        _makeUnhealthy(alice);
        vm.prank(burnerLoansAdmin);
        burnerLoans.disableAsset(address(usds));

        assertTrue(
            burnerLoans.previewSeize(address(usds), _single(alice)).executable,
            "disabled asset seizure preview"
        );
    }

    function test_givenZeroRewardBps_previewSeize_returnsZeroReward() public {
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.keeperRewardBps = 0;
        riskConfig.maxKeeperReward = 1_000e18;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(burnerLoans), address(usds), riskConfig);
        _makeUnhealthy(alice);

        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );

        assertEq(preview.keeperReward, 0, "keeper reward");
        assertEq(preview.collateralToTreasury, 2_000e18, "treasury collateral");
    }

    function test_givenZeroMaxReward_previewSeize_returnsZeroReward() public {
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.maxKeeperReward = 0;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(burnerLoans), address(usds), riskConfig);
        _makeUnhealthy(alice);

        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );

        assertEq(preview.keeperReward, 0, "keeper reward");
        assertEq(preview.collateralToTreasury, 2_000e18, "treasury collateral");
    }

    function test_givenMaxRewardBelowBpsReward_previewSeize_capsReward() public {
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.maxKeeperReward = 5e18;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(burnerLoans), address(usds), riskConfig);
        _makeUnhealthy(alice);

        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );

        assertEq(preview.keeperReward, 5e18, "capped keeper reward");
    }
}
