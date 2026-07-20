// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansHarvestTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarvestTestBase.sol";

contract BurnerLoansPreviewHarvestYieldTest is BurnerLoansHarvestTestBase {
    // given configured vault custody with borrower principal and earned yield
    //  when previewing harvest
    //   then the quote matches DepositManager and is executable
    function test_givenSurplus_returnsDepositManagerQuote() public {
        _depositCollateral();
        _addYield(10e6);

        uint256 expected = depositManager.maxClaimYield(
            IERC20(address(vaultAsset)),
            address(burnerLoans)
        );
        IBurnerLoans.HarvestPreview memory preview = burnerLoans.previewHarvestYield(
            address(vaultAsset)
        );

        assertEq(preview.amount, expected, "claimable yield");
        assertGt(preview.amount, 0, "positive yield");
        assertTrue(preview.executable, "preview executable");
    }

    // given configured custody without earned yield
    //  when previewing harvest
    //   then zero is returned as an executable no-op
    function test_givenNoSurplus_returnsExecutableZero() public {
        _depositCollateral();

        IBurnerLoans.HarvestPreview memory preview = burnerLoans.previewHarvestYield(
            address(vaultAsset)
        );

        assertEq(preview.amount, 0, "claimable yield");
        assertTrue(preview.executable, "preview executable");
    }

    // given custody assets fall below liabilities
    //  when previewing harvest
    //   then no yield is quoted and execution is marked unavailable
    function test_givenCustodyShortfall_returnsNotExecutable() public {
        _depositCollateral();
        _causeShortfall(1);

        IBurnerLoans.HarvestPreview memory preview = burnerLoans.previewHarvestYield(
            address(vaultAsset)
        );

        assertEq(preview.amount, 0, "claimable yield");
        assertFalse(preview.executable, "preview executable");
    }

    // given the policy is globally disabled
    //  when previewing harvest
    //   then the call reverts consistently with the write path
    function test_givenPolicyDisabled_reverts() public {
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewHarvestYield(address(vaultAsset));
    }

    // given the asset has no Burner Loans market
    //  when previewing harvest
    //   then the asset namespace is rejected
    function test_givenAssetNotConfigured_reverts() public {
        address unconfiguredAsset = makeAddr("unconfiguredAsset");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                unconfiguredAsset
            )
        );
        burnerLoans.previewHarvestYield(unconfiguredAsset);
    }

    // given FLOAN has two matching markets for this facility and token pair
    //  when previewing harvest
    //   then Burner Loans rejects the ambiguous asset namespace
    function test_givenMultipleMatchingMarkets_reverts() public {
        _createDuplicateMarketForTest(address(vaultAsset));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(vaultAsset),
                2
            )
        );
        burnerLoans.previewHarvestYield(address(vaultAsset));
    }

    // given DepositManager is disabled
    //  when previewing harvest
    //   then the quote cannot claim to be executable
    function test_givenDepositManagerDisabled_reverts() public {
        vm.prank(admin);
        depositManager.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoans.previewHarvestYield(address(vaultAsset));
    }
}
