// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";

contract BurnerLoansExtendTest is BurnerLoansBorrowTestBase {
    address internal operator;

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function setUp() public override {
        super.setUp();
        operator = makeAddr("operator");
    }

    // extend
    // given an active position whose collateral vault has fallen below borrower liabilities
    //  when previewing or executing an extension
    //   then the asset-level custody shortfall blocks the extension
    function test_givenCustodyShortfall_reverts() public {
        (MockERC20 asset, MockERC4626 vault) = _addVaultAssetForTest();
        uint128 collateral = 2_000e18;
        asset.mint(alice, collateral + 100e18);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(asset), collateral, alice);
        IBurnerLoans.BorrowPreview memory borrowPreview = burnerLoans.previewBorrow(
            address(asset),
            100e9,
            alice
        );
        burnerLoans.borrow(address(asset), 100e9, alice, alice, borrowPreview.fee);
        vm.stopPrank();
        asset.burn(address(vault), 1);

        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_CustodyShortfall.selector,
            address(asset),
            collateral,
            collateral - 1,
            0
        );
        vm.expectRevert(expectedError);
        burnerLoans.previewExtend(address(asset), alice, 1);

        vm.prank(alice);
        vm.expectRevert(expectedError);
        burnerLoans.extend(address(asset), alice, 1, type(uint256).max);
    }

    // extend
    // given healthy active position
    //  when extend is called
    //   then it adds one term and charges collateral fee
    function test_givenHealthyActivePosition_extendAddsOneTermAndChargesCollateralFee() public {
        _borrowForAlice();
        IBurnerLoans.Position memory beforePosition = burnerLoans.getPosition(address(usds), alice);
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.Extended(alice, address(usds), alice, preview.maturity, preview.fee);
        vm.prank(alice);
        (uint256 fee, uint48 maturity, uint256 health) = burnerLoans.extend(
            address(usds),
            alice,
            1,
            preview.fee
        );

        IBurnerLoans.Position memory afterPosition = burnerLoans.getPosition(address(usds), alice);
        assertEq(fee, preview.fee, "fee");
        assertEq(maturity, beforePosition.maturity + 30 days, "maturity");
        assertEq(health, preview.healthFactor, "health");
        assertEq(usds.balanceOf(address(trsry)), treasuryBefore + fee, "treasury fee");
        assertEq(afterPosition.debtOhm, beforePosition.debtOhm, "debt");
        assertEq(
            afterPosition.depositedCollateral,
            beforePosition.depositedCollateral,
            "collateral"
        );
        assertEq(afterPosition.lastBorrowBlock, beforePosition.lastBorrowBlock, "borrow block");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 1, "active borrowers");
    }

    // extend
    // given two terms
    //  when extend is called
    //   then it charges twice single term fee
    function test_givenTwoTerms_extendChargesTwiceSingleTermFee() public {
        _borrowForAlice();
        IBurnerLoans.ExtendPreview memory single = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        IBurnerLoans.ExtendPreview memory doubleTerm = burnerLoans.previewExtend(
            address(usds),
            alice,
            2
        );
        assertEq(doubleTerm.fee, single.fee * 2, "linear extension fee");

        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 2, doubleTerm.fee);
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            uint48(block.timestamp + 90 days),
            "maturity"
        );
    }

    // extend
    // given authorized operator
    //  when extend is called
    //   then it succeeds and operator pays fee
    function test_givenAuthorizedOperator_extendSucceedsAndOperatorPaysFee() public {
        _borrowForAlice();
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        usds.mint(operator, preview.fee);
        vm.prank(operator);
        usds.approve(address(burnerLoans), preview.fee);

        vm.prank(operator);
        burnerLoans.extend(address(usds), alice, 1, preview.fee);
        assertEq(usds.balanceOf(operator), 0, "operator paid fee");
    }

    // extend
    // given unauthorized caller
    //  when extend is called
    //   then it reverts
    function test_givenUnauthorizedCaller_extendReverts() public {
        _borrowForAlice();

        vm.prank(operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given unauthorized caller
    //  when extend is called
    //   then it reverts
    function testFuzz_givenUnauthorizedCaller_extendReverts(address caller_) public {
        vm.assume(caller_ != alice);
        _borrowForAlice();

        vm.prank(caller_);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given expired authorization
    //  when extend is called
    //   then it reverts
    function test_givenExpiredAuthorization_extendReverts() public {
        _borrowForAlice();
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp));
        vm.warp(block.timestamp + 1);

        vm.prank(operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given zero term count
    //  when extend is called
    //   then it reverts
    function test_givenZeroTermCount_extendReverts() public {
        _borrowForAlice();

        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.extend(address(usds), alice, 0, type(uint256).max);
    }

    // extend
    // given extension beyond horizon
    //  when extend is called
    //   then it reverts
    function test_givenExtensionBeyondHorizon_extendReverts() public {
        _borrowForAlice();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_MaturityHorizonExceeded.selector,
                block.timestamp + 120 days,
                block.timestamp + 90 days
            )
        );
        burnerLoans.extend(address(usds), alice, 3, type(uint256).max);
    }

    // extend
    // given active position
    //  when extend is called
    //   then it succeeds within the maturity horizon
    function testFuzz_givenActivePosition_extendWithinHorizonSucceeds(
        uint16 termCount_,
        uint32 elapsed_
    ) public {
        uint16 termCount = uint16(bound(termCount_, 1, 2));
        uint256 elapsed = bound(elapsed_, 0, 30 days - 1);
        _borrowForAlice();
        uint48 originalMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        vm.warp(block.timestamp + elapsed);
        price.setTimestamp(uint48(block.timestamp));
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            termCount
        );

        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, termCount, preview.fee);

        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            originalMaturity + uint48(30 days * termCount),
            "fuzzed maturity"
        );
    }

    // extend
    // given extension above horizon
    //  when extend is called
    //   then it reverts
    function testFuzz_givenExtensionAboveHorizon_extendReverts(
        uint16 termCount_,
        uint32 elapsed_
    ) public {
        uint16 termCount = uint16(bound(termCount_, 3, type(uint16).max));
        uint256 elapsed = bound(elapsed_, 0, 30 days - 1);
        _borrowForAlice();
        uint48 originalMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        vm.warp(block.timestamp + elapsed);
        price.setTimestamp(uint48(block.timestamp));
        uint256 requested = originalMaturity + uint256(30 days) * termCount;
        uint256 maximum = block.timestamp + 90 days;

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_MaturityHorizonExceeded.selector,
                requested,
                maximum
            )
        );
        burnerLoans.extend(address(usds), alice, termCount, type(uint256).max);
    }

    // extend
    // given extension at exact horizon
    //  when extend is called
    //   then it succeeds
    function test_givenExtensionAtExactHorizon_extendSucceeds() public {
        _borrowForAlice();
        vm.warp(block.timestamp + 30 days);
        price.setTimestamp(uint48(block.timestamp));
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            3
        );

        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 3, preview.fee);
        assertEq(preview.maturity, block.timestamp + 90 days, "exact horizon");
    }

    // extend
    // given updated term length
    //  when extend is called
    //   then it uses new term without changing existing maturity
    function testFuzz_givenUpdatedTermLength_extendUsesNewTermWithoutChangingExistingMaturity(
        uint32 termLength_
    ) public {
        uint48 termLength = uint48(bound(termLength_, 1 days, 29 days));
        _borrowForAlice();
        uint48 originalMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.termLength = termLength;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), riskConfig);
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            originalMaturity,
            "configuration does not mutate maturity"
        );
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );

        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, preview.fee);
        assertEq(preview.maturity, originalMaturity + termLength, "new term length");
    }

    // extend
    // given unhealthy position
    //  when extend is called
    //   then it reverts
    function test_givenUnhealthyPosition_extendReverts() public {
        _borrowForAlice();
        price.setPrice(address(usds), 0.1e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnhealthyPosition.selector,
                173_913_043_478_260_869
            )
        );
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given matured healthy position
    //  when extend is called
    //   then it uses current timestamp as base
    function test_givenMaturedHealthyPosition_extendUsesCurrentTimestampAsBase() public {
        _borrowForAlice();
        vm.warp(block.timestamp + 31 days);
        price.setTimestamp(uint48(block.timestamp));
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );

        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, preview.fee);
        assertEq(preview.maturity, block.timestamp + 30 days, "maturity from current time");
    }

    // extend
    // given originations disabled
    //  when extend is called
    //   then it reverts
    function test_givenAssetOriginationsDisabled_extendReverts() public {
        _borrowForAlice();
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetOriginationsDisabled.selector,
                address(usds)
            )
        );
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given global policy disabled
    //  when extend is called
    //   then it reverts
    function test_givenGlobalPolicyDisabled_extendReverts() public {
        _borrowForAlice();
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.prank(alice);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given stale price
    //  when extend is called
    //   then it reverts
    function test_givenStalePrice_extendReverts() public {
        _borrowForAlice();
        vm.warp(block.timestamp + 1 days);
        price.setTimestamp(uint48(block.timestamp - 9 hours));

        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given unavailable price
    //  when extend is called
    //   then it reverts
    function test_givenUnavailablePrice_extendReverts() public {
        _borrowForAlice();
        price.setPrice(address(usds), 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(usds)));
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given no debt
    //  when extend is called
    //   then it reverts
    function test_givenNoDebt_extendReverts() public {
        usds.mint(alice, 1e18);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 1e18, alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_NoDebt.selector);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
        vm.stopPrank();
    }

    // extend
    // given fee above max
    //  when extend is called
    //   then it reverts without maturity change
    function test_givenFeeAboveMax_extendRevertsWithoutMaturityChange() public {
        _borrowForAlice();
        IBurnerLoans.Position memory beforePosition = burnerLoans.getPosition(address(usds), alice);
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_FeeExceedsMax.selector,
                preview.fee,
                preview.fee - 1
            )
        );
        burnerLoans.extend(address(usds), alice, 1, preview.fee - 1);
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            beforePosition.maturity,
            "maturity"
        );
    }

    // extend
    // given missing fee allowance
    //  when extend is called
    //   then it reverts without maturity change
    function test_givenMissingFeeAllowance_extendRevertsWithoutMaturityChange() public {
        _borrowForAlice();
        IBurnerLoans.Position memory beforePosition = burnerLoans.getPosition(address(usds), alice);
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        vm.prank(alice);
        usds.approve(address(burnerLoans), 0);

        vm.prank(alice);
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        burnerLoans.extend(address(usds), alice, 1, preview.fee);
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            beforePosition.maturity,
            "maturity"
        );
    }

    // extend
    // given missing fee balance
    //  when extend is called
    //   then it reverts without maturity change
    function test_givenMissingFeeBalance_extendRevertsWithoutMaturityChange() public {
        _borrowForAlice();
        IBurnerLoans.Position memory beforePosition = burnerLoans.getPosition(address(usds), alice);
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        uint256 aliceBalance = usds.balanceOf(alice);
        vm.prank(alice);
        usds.transfer(operator, aliceBalance);

        vm.prank(alice);
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        burnerLoans.extend(address(usds), alice, 1, preview.fee);
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            beforePosition.maturity,
            "maturity"
        );
    }

    function _borrowForAlice() internal {
        usds.mint(alice, 2_100e18);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 2_000e18, alice);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            100e9,
            alice
        );
        burnerLoans.borrow(address(usds), 100e9, alice, alice, preview.fee);
        vm.stopPrank();
    }
}

contract BurnerLoansPreviewExtendTest is BurnerLoansBorrowTestBase {
    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function setUp() public override {
        super.setUp();
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 2_000e18,
                debtOhm: 100e9,
                maturity: uint48(block.timestamp + 30 days),
                lastBorrowBlock: 0,
                status: IBurnerLoans.PositionStatus.NoDebt
            })
        );
    }

    // previewExtend
    // given healthy position
    //  when previewExtend is called
    //   then it returns fee maturity and health
    function test_givenHealthyPosition_previewExtendReturnsFeeMaturityAndHealth() public view {
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        assertGt(preview.fee, 0, "fee");
        assertEq(preview.maturity, block.timestamp + 60 days, "maturity");
        assertGt(preview.healthFactor, 1e18, "health");
        assertTrue(preview.executable, "executable");
    }

    // previewExtend
    // given zero terms
    //  when previewExtend is called
    //   then it reverts
    function test_givenZeroTerms_previewExtendReverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.previewExtend(address(usds), alice, 0);
    }

    // previewExtend
    // given no debt
    //  when previewExtend is called
    //   then it reverts
    function test_givenNoDebt_previewExtendReverts() public {
        address bob = makeAddr("bob");
        burnerLoans.setPositionForTest(
            address(usds),
            bob,
            IBurnerLoans.Position({
                depositedCollateral: 1e18,
                debtOhm: 0,
                maturity: 0,
                lastBorrowBlock: 0,
                status: IBurnerLoans.PositionStatus.NoDebt
            })
        );

        vm.expectRevert(IBurnerLoans.BurnerLoans_NoDebt.selector);
        burnerLoans.previewExtend(address(usds), bob, 1);
    }

    // previewExtend
    // given ambiguous market
    //  when previewExtend is called
    //   then it reverts
    function test_givenAmbiguousMarket_previewExtendReverts() public {
        _createDuplicateUsdsMarketForTest();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(usds),
                2
            )
        );
        burnerLoans.previewExtend(address(usds), alice, 1);
    }

    // previewExtend
    // given missing market
    //  when previewExtend is called
    //   then it reverts
    function test_givenMissingMarket_previewExtendReverts() public {
        address unknownAsset = makeAddr("unknown asset");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                unknownAsset
            )
        );
        burnerLoans.previewExtend(unknownAsset, alice, 1);
    }

    // previewExtend
    // given originations disabled
    //  when previewExtend is called
    //   then it reverts
    function test_givenAssetOriginationsDisabled_previewExtendReverts() public {
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetOriginationsDisabled.selector,
                address(usds)
            )
        );
        burnerLoans.previewExtend(address(usds), alice, 1);
    }

    // previewExtend
    // given global policy disabled
    //  when previewExtend is called
    //   then it reverts
    function test_givenGlobalPolicyDisabled_previewExtendReverts() public {
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewExtend(address(usds), alice, 1);
    }

    // previewExtend
    // given stale price
    //  when previewExtend is called
    //   then it reverts
    function test_givenStalePrice_previewExtendReverts() public {
        vm.warp(block.timestamp + 1 days);
        price.setTimestamp(uint48(block.timestamp - 9 hours));

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.previewExtend(address(usds), alice, 1);
    }

    // previewExtend
    // given unavailable price
    //  when previewExtend is called
    //   then it reverts
    function test_givenUnavailablePrice_previewExtendReverts() public {
        price.setPrice(address(usds), 0);

        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(usds)));
        burnerLoans.previewExtend(address(usds), alice, 1);
    }

    // previewExtend
    // given unhealthy position
    //  when previewExtend is called
    //   then it reverts
    function test_givenUnhealthyPosition_previewExtendReverts() public {
        price.setPrice(address(usds), 0.1e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnhealthyPosition.selector,
                173_913_043_478_260_869
            )
        );
        burnerLoans.previewExtend(address(usds), alice, 1);
    }

    // previewExtend
    // given extension beyond horizon
    //  when previewExtend is called
    //   then it reverts
    function test_givenExtensionBeyondHorizon_previewExtendReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_MaturityHorizonExceeded.selector,
                block.timestamp + 120 days,
                block.timestamp + 90 days
            )
        );
        burnerLoans.previewExtend(address(usds), alice, 3);
    }

    // previewExtend
    // given matured healthy position
    //  when previewExtend is called
    //   then it uses current timestamp as base
    function test_givenMaturedHealthyPosition_previewExtendUsesCurrentTimestampAsBase() public {
        vm.warp(block.timestamp + 31 days);
        price.setTimestamp(uint48(block.timestamp));

        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        assertEq(preview.maturity, block.timestamp + 30 days, "maturity from current time");
    }

    // previewExtend
    // given two terms
    //  when previewExtend is called
    //   then it returns linear fee
    function test_givenTwoTerms_previewExtendReturnsLinearFee() public view {
        IBurnerLoans.ExtendPreview memory single = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        IBurnerLoans.ExtendPreview memory doubleTerm = burnerLoans.previewExtend(
            address(usds),
            alice,
            2
        );

        assertEq(doubleTerm.fee, single.fee * 2, "linear fee");
        assertEq(doubleTerm.maturity, single.maturity + 30 days, "second term");
    }
}
