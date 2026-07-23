// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";
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

    // repay
    // given partial repayment
    //  when repay is called
    //   then it burns OHM and reduces only debt
    function test_givenPartialRepayment_repayBurnsOhmAndReducesOnlyDebt() public {
        _borrowForAlice(100e9);
        vm.roll(block.number + 1);
        _approveOhm(alice, 40e9);
        uint256 supplyBefore = ohm.totalSupply();

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

        vm.prank(alice);
        uint256 health = burnerLoans.repay(address(usds), 100e9, alice);

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(position.debtOhm, 0, "position debt");
        assertEq(position.depositedCollateral, 2_000e18, "position collateral");
        assertEq(position.maturity, 0, "maturity");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 0, "active borrowers");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "facility debt");
        assertEq(health, type(uint256).max, "debt-free health");
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

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_RepayExceedsDebt.selector,
                requested,
                100e9
            )
        );
        burnerLoans.repay(address(usds), requested, alice);
    }

    // repay
    // given zero amount
    //  when repay is called
    //   then it reverts
    function test_givenZeroAmount_repayReverts() public {
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

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                unsupported
            )
        );
        burnerLoans.repay(unsupported, 1e9, alice);
        assertEq(ohm.balanceOf(alice), balanceBefore, "OHM balance");
    }

    // repay
    // given ambiguous market
    //  when repay is called
    //   then it reverts before burn
    function test_givenAmbiguousMarket_repayRevertsBeforeBurn() public {
        _borrowForAlice(100e9);
        vm.roll(block.number + 1);
        _createDuplicateUsdsMarketForTest();
        _approveOhm(alice, 1e9);
        uint256 balanceBefore = ohm.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(usds),
                2
            )
        );
        burnerLoans.repay(address(usds), 1e9, alice);
        assertEq(ohm.balanceOf(alice), balanceBefore, "OHM balance");
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

contract BurnerLoansPreviewRepayTest is BurnerLoansTest {
    function setUp() public override {
        super.setUp();
        _addDefaultUsdsAsset();
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 1_000e6,
                debtOhm: 100e9,
                maturity: uint48(block.timestamp + 30 days),
                lastBorrowBlock: 0,
                status: IBurnerLoans.PositionStatus.NoDebt
            })
        );
        vm.roll(block.number + 1);
    }

    // previewRepay
    // given partial repayment
    //  when previewRepay is called
    //   then it returns conservative quote
    function test_givenPartialRepayment_previewRepayReturnsConservativeQuote() public view {
        IBurnerLoans.RepayPreview memory preview = burnerLoans.previewRepay(
            address(usds),
            40e9,
            alice
        );
        assertEq(preview.repayAmount, 40e9, "repay amount");
        assertEq(preview.remainingDebtOhm, 60e9, "remaining debt");
        assertEq(preview.resultingHealthFactor, 0, "unknown health sentinel");
        assertTrue(preview.executable, "executable");
    }

    // previewRepay
    // given full repayment
    //  when previewRepay is called
    //   then it returns debt free health
    function test_givenFullRepayment_previewRepayReturnsDebtFreeHealth() public view {
        IBurnerLoans.RepayPreview memory preview = burnerLoans.previewRepay(
            address(usds),
            100e9,
            alice
        );
        assertEq(preview.remainingDebtOhm, 0, "remaining debt");
        assertEq(preview.resultingHealthFactor, type(uint256).max, "health");
        assertTrue(preview.executable, "executable");
    }

    // previewRepay
    // given amount exceeds debt
    //  when previewRepay is called
    //   then it reverts
    function test_givenAmountExceedsDebt_previewRepayReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_RepayExceedsDebt.selector,
                100e9 + 1,
                100e9
            )
        );
        burnerLoans.previewRepay(address(usds), 100e9 + 1, alice);
    }

    // previewRepay
    // given zero amount
    //  when previewRepay is called
    //   then it reverts
    function test_givenZeroAmount_previewRepayReverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.previewRepay(address(usds), 0, alice);
    }

    // previewRepay
    // given originations disabled and price stale
    //  when previewRepay is called
    //   then it remains executable
    function test_givenAssetOriginationsDisabledAndPriceStale_previewRepayRemainsExecutable()
        public
    {
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        vm.warp(block.timestamp + 10 days);
        price.setTimestamp(uint48(block.timestamp - 9 hours));

        IBurnerLoans.RepayPreview memory preview = burnerLoans.previewRepay(
            address(usds),
            1e9,
            alice
        );
        assertEq(preview.remainingDebtOhm, 99e9, "remaining debt");
        assertTrue(preview.executable, "executable");
    }

    // previewRepay
    // given global policy disabled
    //  when previewRepay is called
    //   then it reverts
    function test_givenGlobalPolicyDisabled_previewRepayReverts() public {
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewRepay(address(usds), 1e9, alice);
    }

    // previewRepay
    // given ambiguous market
    //  when previewRepay is called
    //   then it reverts
    function test_givenAmbiguousMarket_previewRepayReverts() public {
        _createDuplicateUsdsMarketForTest();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(usds),
                2
            )
        );
        burnerLoans.previewRepay(address(usds), 1e9, alice);
    }
}
