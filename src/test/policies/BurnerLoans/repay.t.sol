// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";

contract BurnerLoansRepayTest is BurnerLoansBorrowTestBase {
    address internal bob;

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function setUp() public override {
        super.setUp();
        bob = makeAddr("bob");
    }

    // Condition tree:
    // - Market schema: incompatible config ID with malformed data
    // - Action: preview and execute repayment
    // - Expected branch: both reject the schema before position or token handling
    function test_givenDifferentConfigId_previewAndRepayRevertBeforeDecoding() public {
        bytes16 incompatibleConfigId = bytes16("Different config");
        uint32 marketId = _replaceMarketConfigForTest(address(usds), incompatibleConfigId, hex"01");
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_IncompatibleMarketConfig.selector,
            marketId,
            incompatibleConfigId
        );

        vm.expectRevert(expectedError);
        burnerLoans.previewRepay(address(usds), 1e9, alice);

        vm.prank(alice);
        vm.expectRevert(expectedError);
        burnerLoans.repay(address(usds), 1e9, alice);
    }

    // Condition tree:
    // - Market schema: compatible config ID with malformed data length
    // - Action: preview and execute repayment
    // - Expected branch: both reject the byte length before position or token handling
    function test_givenInvalidConfigDataLength_previewAndRepayRevertBeforeDecoding() public {
        uint32 marketId = _replaceMarketConfigForTest(
            address(usds),
            bytes16("Burner Loans v1"),
            hex"01"
        );
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_InvalidMarketConfigData.selector,
            marketId,
            1
        );

        vm.expectRevert(expectedError);
        burnerLoans.previewRepay(address(usds), 1e9, alice);

        vm.prank(alice);
        vm.expectRevert(expectedError);
        burnerLoans.repay(address(usds), 1e9, alice);
    }

    // repay
    // given partial repayment
    //  when repay is called
    //   then it burns OHM and reduces only debt
    function test_givenPartialRepayment_repayBurnsOhmAndReducesOnlyDebt() public {
        _borrowForAlice(100e9);
        vm.roll(block.number + 1);
        _approveOhm(alice, 40e9);
        uint256 supplyBefore = ohm.totalSupply();
        IBurnerLoans.RepayPreview memory preview = burnerLoans.previewRepay(
            address(usds),
            40e9,
            alice
        );
        assertEq(preview.repayAmount, 40e9, "preview repay amount");
        assertEq(preview.remainingDebtOhm, 60e9, "preview remaining debt");
        assertEq(preview.resultingHealthFactor, 0, "preview unknown health sentinel");
        assertTrue(preview.executable, "preview executable");

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.Repaid(alice, address(usds), alice, 40e9, 60e9);
        vm.prank(alice);
        uint256 health = burnerLoans.repay(address(usds), 40e9, alice);

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(ohm.totalSupply(), supplyBefore - 40e9, "OHM supply");
        assertEq(position.debtOhm, 60e9, "position debt");
        assertEq(position.depositedCollateral, 2_000e18, "position collateral");
        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), 60e9, "asset debt");
        assertEq(burnerLoans.totalActiveDebtOhm(), 60e9, "facility debt");
        assertEq(
            mintr.mintApproval(address(burnerLoans)),
            burnerLoans.globalDebtCapOhm() - 60e9,
            "recycled mint approval"
        );
        assertEq(health, 0, "unknown partial health sentinel");
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
    }

    // repay
    // given fuzzed partial repayment
    //  when repay is called
    //   then it burns exactly debt reduction
    function test_givenFuzzedPartialRepayment_repayBurnsExactlyDebtReduction(
        uint128 repayOhm_
    ) public {
        repayOhm_ = uint128(bound(repayOhm_, 1, 100e9 - 1));
        _borrowForAlice(100e9);
        vm.roll(block.number + 1);
        _approveOhm(alice, repayOhm_);
        uint256 supplyBefore = ohm.totalSupply();
        IBurnerLoans.RepayPreview memory preview = burnerLoans.previewRepay(
            address(usds),
            repayOhm_,
            alice
        );
        assertEq(preview.repayAmount, repayOhm_, "preview repay amount");
        assertEq(preview.remainingDebtOhm, 100e9 - repayOhm_, "preview remaining debt");
        assertTrue(preview.executable, "preview executable");

        vm.prank(alice);
        burnerLoans.repay(address(usds), repayOhm_, alice);

        assertEq(ohm.totalSupply(), supplyBefore - repayOhm_, "OHM burned");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).debtOhm,
            100e9 - repayOhm_,
            "debt reduction"
        );
    }

    // repay
    // given full repayment
    //  when repay is called
    //   then it clears debt and active borrower only
    function test_givenFullRepayment_repayClearsDebtAndActiveBorrowerOnly() public {
        _borrowForAlice(100e9);
        vm.roll(block.number + 1);
        _approveOhm(alice, 100e9);
        IBurnerLoans.RepayPreview memory preview = burnerLoans.previewRepay(
            address(usds),
            100e9,
            alice
        );
        assertEq(preview.repayAmount, 100e9, "preview repay amount");
        assertEq(preview.remainingDebtOhm, 0, "preview remaining debt");
        assertEq(preview.resultingHealthFactor, type(uint256).max, "preview debt-free health");
        assertTrue(preview.executable, "preview executable");

        vm.prank(alice);
        uint256 health = burnerLoans.repay(address(usds), 100e9, alice);

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(position.debtOhm, 0, "position debt");
        assertEq(position.depositedCollateral, 2_000e18, "position collateral");
        assertEq(position.maturity, 0, "maturity");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 0, "active borrowers");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "facility debt");
        assertEq(health, type(uint256).max, "debt-free health");
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
    }

    // repay
    // given the global mint capacity has been fully consumed
    //  when all borrowed OHM is repaid and burned
    //   then the exact capacity is restored
    //   then the same amount can be borrowed again
    function test_givenGlobalMintCapacityConsumed_repayRestoresCapacityForAnotherBorrow() public {
        vm.prank(admin);
        burnerLoans.setGlobalDebtCap(100e9);
        _borrowForAlice(100e9);
        assertEq(mintr.mintApproval(address(burnerLoans)), 0, "consumed approval");

        vm.roll(block.number + 1);
        _approveOhm(alice, 100e9);
        vm.prank(alice);
        burnerLoans.repay(address(usds), 100e9, alice);
        assertEq(mintr.mintApproval(address(burnerLoans)), 100e9, "restored approval");

        vm.startPrank(alice);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            100e9,
            alice
        );
        burnerLoans.borrow(address(usds), 100e9, alice, alice, preview.fee);
        vm.stopPrank();

        assertEq(burnerLoans.totalActiveDebtOhm(), 100e9, "active debt");
        assertEq(mintr.mintApproval(address(burnerLoans)), 0, "reconsumed approval");
    }

    // repay
    // given same borrow block
    //  when repay is called
    //   then it reverts
    function test_givenSameBorrowBlock_repayReverts() public {
        _borrowForAlice(100e9);
        _approveOhm(alice, 1e9);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_SameBlockRepay.selector,
                uint48(block.number)
            )
        );
        burnerLoans.previewRepay(address(usds), 1e9, alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_SameBlockRepay.selector,
                uint48(block.number)
            )
        );
        burnerLoans.repay(address(usds), 1e9, alice);
    }

    // repay
    // given repay amount exceeds debt
    //  when repay is called
    //   then it reverts
    function test_givenRepayAmountExceedsDebt_repayReverts(uint128 surplus_) public {
        surplus_ = uint128(bound(surplus_, 1, type(uint128).max - 100e9));
        uint128 requested = 100e9 + surplus_;
        _borrowForAlice(100e9);
        vm.roll(block.number + 1);
        _approveOhm(alice, requested);
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_RepayExceedsDebt.selector,
            requested,
            100e9
        );

        vm.expectRevert(error);
        burnerLoans.previewRepay(address(usds), requested, alice);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.repay(address(usds), requested, alice);
    }

    // repay
    // given zero amount
    //  when repay is called
    //   then it reverts
    function test_givenZeroAmount_repayReverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.previewRepay(address(usds), 0, alice);

        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.repay(address(usds), 0, alice);
    }

    // repay
    // given no debt
    //  when repay is called
    //   then it reverts
    function test_givenNoDebt_repayReverts() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 1e18,
                debtOhm: 0,
                maturity: 0,
                lastBorrowBlock: 0,
                status: IBurnerLoans.PositionStatus.NoDebt
            })
        );
        vm.expectRevert(IBurnerLoans.BurnerLoans_NoDebt.selector);
        burnerLoans.previewRepay(address(usds), 1, alice);

        vm.expectRevert(IBurnerLoans.BurnerLoans_NoDebt.selector);
        burnerLoans.repay(address(usds), 1, alice);
    }

    // repay
    // given global policy disabled
    //  when repay is called
    //   then it reverts
    function test_givenGlobalPolicyDisabled_repayReverts() public {
        _borrowForAlice(100e9);
        vm.roll(block.number + 1);
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewRepay(address(usds), 1e9, alice);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.repay(address(usds), 1e9, alice);
    }

    // repay
    // given originations disabled and price stale
    //  when repay is called
    //   then it succeeds
    function test_givenAssetOriginationsDisabledAndPriceStale_repaySucceeds() public {
        _borrowForAlice(100e9);
        vm.roll(block.number + 1);
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        vm.warp(block.timestamp + 10 days);
        price.setTimestamp(uint48(block.timestamp - 9 hours));
        _approveOhm(alice, 1e9);
        IBurnerLoans.RepayPreview memory preview = burnerLoans.previewRepay(
            address(usds),
            1e9,
            alice
        );
        assertEq(preview.remainingDebtOhm, 99e9, "preview remaining debt");
        assertTrue(preview.executable, "preview executable");

        vm.prank(alice);
        burnerLoans.repay(address(usds), 1e9, alice);
        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 99e9, "debt");
    }

    // repay
    // given matured unhealthy position
    //  when repay is called
    //   then it succeeds without price
    function test_givenMaturedUnhealthyPosition_repaySucceedsWithoutPrice() public {
        _borrowForAlice(100e9);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 31 days);
        price.setPrice(address(usds), 0);
        _approveOhm(alice, 1e9);
        IBurnerLoans.RepayPreview memory preview = burnerLoans.previewRepay(
            address(usds),
            1e9,
            alice
        );
        assertEq(preview.remainingDebtOhm, 99e9, "preview remaining debt");
        assertTrue(preview.executable, "preview executable");

        vm.prank(alice);
        burnerLoans.repay(address(usds), 1e9, alice);
        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 99e9, "debt");
    }

    // repay
    // given unrelated caller
    //  when repay is called
    //   then it can pay another borrower debt
    function test_givenUnrelatedCaller_repayCanPayAnotherBorrowerDebt() public {
        _borrowForAlice(100e9);
        vm.roll(block.number + 1);
        ohm.mint(bob, 25e9);
        _approveOhm(bob, 25e9);

        vm.prank(bob);
        burnerLoans.repay(address(usds), 25e9, alice);
        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 75e9, "alice debt");
        assertEq(usds.balanceOf(bob), 0, "caller collateral");
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
    }

    // repay
    // given missing allowance
    //  when repay is called
    //   then it reverts and preserves debt
    function test_givenMissingAllowance_repayRevertsAndPreservesDebt() public {
        _borrowForAlice(100e9);
        vm.roll(block.number + 1);

        vm.prank(alice);
        vm.expectRevert();
        burnerLoans.repay(address(usds), 1e9, alice);
        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 100e9, "debt");
    }

    // repay
    // given missing balance
    //  when repay is called
    //   then it reverts and preserves debt
    function test_givenMissingBalance_repayRevertsAndPreservesDebt() public {
        _borrowForAlice(100e9);
        vm.roll(block.number + 1);
        _approveOhm(bob, 1e9);

        vm.prank(bob);
        vm.expectRevert();
        burnerLoans.repay(address(usds), 1e9, alice);
        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 100e9, "debt");
    }

    // repay
    // given missing market
    //  when repay is called
    //   then it reverts before burn
    function test_givenMissingMarket_repayRevertsBeforeBurn() public {
        address unsupported = makeAddr("unsupported");
        ohm.mint(alice, 1e9);
        _approveOhm(alice, 1e9);
        uint256 balanceBefore = ohm.balanceOf(alice);
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
            unsupported
        );

        vm.expectRevert(error);
        burnerLoans.previewRepay(unsupported, 1e9, alice);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.repay(unsupported, 1e9, alice);
        assertEq(ohm.balanceOf(alice), balanceBefore, "OHM balance");
    }

    // repay
    // given multiple markets for the facility and token pair
    //  when repayment is previewed and executed
    //   then Burner Loans uses the first market
    function test_givenMultipleMarkets_previewAndRepayUseFirstMarket() public {
        _borrowForAlice(100e9);
        vm.roll(block.number + 1);
        uint32 firstMarketId = burnerLoansConfig.marketId(address(usds));
        _createDuplicateUsdsMarketForTest();
        _approveOhm(alice, 1e9);

        IBurnerLoans.RepayPreview memory preview = burnerLoans.previewRepay(
            address(usds),
            1e9,
            alice
        );
        assertEq(preview.remainingDebtOhm, 99e9, "preview first-market debt");
        vm.prank(alice);
        burnerLoans.repay(address(usds), 1e9, alice);

        assertEq(floan.getMarketPrincipalDue(firstMarketId), 99e9, "first-market debt");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).debtOhm,
            99e9,
            "first-market position"
        );
    }

    // repay
    // given multiple borrowers
    //  when repay is called
    //   then it updates only target position
    function test_givenMultipleBorrowers_repayUpdatesOnlyTargetPosition() public {
        _borrowForAlice(100e9);
        _borrowFor(bob, 50e9);
        vm.roll(block.number + 1);
        _approveOhm(alice, 10e9);

        vm.prank(alice);
        burnerLoans.repay(address(usds), 10e9, alice);
        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 90e9, "alice debt");
        assertEq(burnerLoans.getPosition(address(usds), bob).debtOhm, 50e9, "bob debt");
        assertEq(burnerLoans.totalActiveDebtOhm(), 140e9, "facility debt");
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
        _assertFloanPositionMatchesBurnerLoans(address(usds), bob);
    }

    // repay
    // given debt in another market
    //  when repay is called
    //   then it preserves other market debt
    function test_givenDebtInAnotherMarket_repayPreservesOtherMarketDebt() public {
        _borrowForAlice(100e9);
        MockERC20 otherAsset = _setOtherMarketDebtForTest(50e9);
        vm.roll(block.number + 1);
        _approveOhm(alice, 10e9);

        vm.prank(alice);
        burnerLoans.repay(address(usds), 10e9, alice);
        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), 90e9, "USDS debt");
        assertEq(burnerLoans.assetActiveDebtOhm(address(otherAsset)), 50e9, "other debt");
        assertEq(burnerLoans.totalActiveDebtOhm(), 140e9, "facility debt");
    }

    function _borrowForAlice(uint128 amount_) internal {
        _borrowFor(alice, amount_);
    }

    function _borrowFor(address account_, uint128 amount_) internal {
        usds.mint(account_, 2_100e18);
        vm.startPrank(account_);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 2_000e18, account_);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            amount_,
            account_
        );
        burnerLoans.borrow(address(usds), amount_, account_, account_, preview.fee);
        vm.stopPrank();
    }

    function _approveOhm(address account_, uint256 amount_) internal {
        vm.prank(account_);
        ohm.approve(address(burnerLoans), amount_);
    }
}
