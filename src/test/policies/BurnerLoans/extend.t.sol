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

    // Condition tree:
    // - Market schema: incompatible config ID with malformed data
    // - Action: preview and execute extension
    // - Expected branch: both reject the schema before position or fee handling
    function test_givenDifferentConfigId_previewAndExtendRevertBeforeDecoding() public {
        bytes16 incompatibleConfigId = bytes16("Different config");
        uint32 marketId = _replaceMarketConfigForTest(address(usds), incompatibleConfigId, hex"01");
        _setActivePositionForSchemaTest();
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_IncompatibleMarketConfig.selector,
            marketId,
            incompatibleConfigId
        );

        vm.expectRevert(expectedError);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(expectedError);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // Condition tree:
    // - Market schema: compatible config ID with malformed data length
    // - Action: preview and execute extension
    // - Expected branch: both reject the byte length before position or fee handling
    function test_givenInvalidConfigDataLength_previewAndExtendRevertBeforeDecoding() public {
        uint32 marketId = _replaceMarketConfigForTest(
            address(usds),
            bytes16("Burner Loans v1"),
            hex"01"
        );
        _setActivePositionForSchemaTest();
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_InvalidMarketConfigData.selector,
            marketId,
            1
        );

        vm.expectRevert(expectedError);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(expectedError);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    function _setActivePositionForSchemaTest() internal {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 2_000e18,
                debtOhm: 100e9,
                maturity: uint48(block.timestamp + 30 days),
                lastBorrowBlock: 0,
                status: IBurnerLoans.PositionStatus.Active
            })
        );
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
        assertGt(preview.fee, 0, "preview fee");
        assertEq(preview.maturity, beforePosition.maturity + 30 days, "preview maturity");
        assertGt(preview.healthFactor, 1e18, "preview health");
        assertTrue(preview.executable, "preview executable");
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
        assertEq(afterPosition.maturity, maturity, "position maturity");
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
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
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
        (, uint48 maturity, ) = burnerLoans.extend(address(usds), alice, 1, preview.fee);
        assertEq(usds.balanceOf(operator), 0, "operator paid fee");
        assertEq(maturity, preview.maturity, "returned maturity");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            preview.maturity,
            "position maturity"
        );
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
    function test_givenUnauthorizedCaller_extendReverts_fuzz(address caller_) public {
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

        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.previewExtend(address(usds), alice, 0);

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
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_MaturityHorizonExceeded.selector,
            block.timestamp + 120 days,
            block.timestamp + 90 days
        );

        vm.expectRevert(error);
        burnerLoans.previewExtend(address(usds), alice, 3);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.extend(address(usds), alice, 3, type(uint256).max);
    }

    // extend
    // given active position
    //  when extend is called
    //   then it succeeds within the maturity horizon
    function test_givenActivePosition_extendWithinHorizonSucceeds_fuzz(
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
        (, uint48 maturity, uint256 healthFactor) = burnerLoans.extend(
            address(usds),
            alice,
            termCount,
            preview.fee
        );

        assertEq(
            preview.maturity,
            originalMaturity + uint48(30 days * termCount),
            "preview maturity"
        );
        assertEq(maturity, preview.maturity, "returned maturity");
        assertEq(healthFactor, preview.healthFactor, "returned health");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            preview.maturity,
            "fuzzed maturity"
        );
    }

    // extend
    // given extension above horizon
    //  when extend is called
    //   then it reverts
    function test_givenExtensionAboveHorizon_extendReverts_fuzz(
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

        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_MaturityHorizonExceeded.selector,
            requested,
            maximum
        );

        vm.expectRevert(error);
        burnerLoans.previewExtend(address(usds), alice, termCount);

        vm.prank(alice);
        vm.expectRevert(error);
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
        (, uint48 maturity, ) = burnerLoans.extend(address(usds), alice, 3, preview.fee);
        assertEq(preview.maturity, block.timestamp + 90 days, "exact horizon");
        assertEq(maturity, preview.maturity, "returned maturity");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            preview.maturity,
            "position maturity"
        );
    }

    // extend
    // given updated term length
    //  when extend is called
    //   then it uses new term without changing existing maturity
    function test_givenUpdatedTermLength_extendUsesNewTermWithoutChangingExistingMaturity_fuzz(
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
        (, uint48 maturity, ) = burnerLoans.extend(address(usds), alice, 1, preview.fee);
        assertEq(preview.maturity, originalMaturity + termLength, "new term length");
        assertEq(maturity, preview.maturity, "returned maturity");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            preview.maturity,
            "position maturity"
        );
    }

    // extend
    // given unhealthy position
    //  when extend is called
    //   then it reverts
    function test_givenUnhealthyPosition_extendReverts() public {
        _borrowForAlice();
        price.setPrice(address(usds), 0.1e18);
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_UnhealthyPosition.selector,
            173_913_043_478_260_869
        );

        vm.expectRevert(error);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given a healthy position that matured less than one term ago
    //  when extend is called
    //   then it adds the term to the previous maturity
    function test_givenMaturedHealthyPosition_extendUsesPreviousMaturityAsBase_fuzz(
        uint48 elapsed_
    ) public {
        _borrowForAlice();
        uint48 previousMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        uint48 elapsed = uint48(bound(elapsed_, 30 days, 60 days - 1));
        vm.warp(block.timestamp + elapsed);
        price.setTimestamp(uint48(block.timestamp));
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );

        vm.prank(alice);
        (, uint48 maturity, ) = burnerLoans.extend(address(usds), alice, 1, preview.fee);

        uint48 expectedMaturity = previousMaturity + 30 days;
        assertEq(preview.maturity, expectedMaturity, "preview maturity");
        assertEq(maturity, expectedMaturity, "returned maturity");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            expectedMaturity,
            "position maturity"
        );
    }

    // extend
    // given a healthy position whose one-term extension would remain matured
    //  when previewing or executing one term
    //   then both reject the insufficient catch-up extension
    function test_givenExtensionDoesNotAdvanceMaturityBeyondCurrentTimestamp_reverts_fuzz(
        uint48 elapsed_
    ) public {
        _borrowForAlice();
        uint48 previousMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        uint48 elapsed = uint48(bound(elapsed_, 60 days, 365 days));
        vm.warp(block.timestamp + elapsed);
        price.setTimestamp(uint48(block.timestamp));
        uint256 requestedMaturity = uint256(previousMaturity) + 30 days;
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_ExtensionMaturityNotFuture.selector,
            requestedMaturity,
            block.timestamp
        );

        vm.expectRevert(error);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given originations disabled
    //  when extend is called
    //   then it reverts
    function test_givenAssetOriginationsDisabled_extendReverts() public {
        _borrowForAlice();
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_AssetOriginationsDisabled.selector,
            address(usds)
        );

        vm.expectRevert(error);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(error);
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

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewExtend(address(usds), alice, 1);

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

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.previewExtend(address(usds), alice, 1);

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
        bytes memory error = abi.encodeWithSelector(
            IPRICEv2.PRICE_PriceZero.selector,
            address(usds)
        );

        vm.expectRevert(error);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(error);
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
        burnerLoans.previewExtend(address(usds), alice, 1);

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

    // extend
    // given multiple markets for the facility and token pair
    //  when extension is previewed and executed
    //   then Burner Loans uses the first market
    function test_givenMultipleMarkets_previewAndExtendUseFirstMarket() public {
        _borrowForAlice();
        uint32 firstMarketId = burnerLoansConfig.marketId(address(usds));
        uint48 previousMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        uint32 secondMarketId = _createDuplicateUsdsMarketForTest();

        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, preview.fee);

        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            previousMaturity + 30 days,
            "first-market maturity"
        );
        assertEq(floan.getMarketPrincipalDue(firstMarketId), 100e9, "first-market debt");
        assertEq(floan.getMarketPrincipalDue(secondMarketId), 0, "second-market debt");
    }

    // extend
    // given missing market
    //  when extension is previewed and executed
    //   then both revert
    function test_givenMissingMarket_previewAndExtendRevert() public {
        address unknownAsset = makeAddr("unknown asset");
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
            unknownAsset
        );

        vm.expectRevert(error);
        burnerLoans.previewExtend(unknownAsset, alice, 1);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.extend(unknownAsset, alice, 1, type(uint256).max);
    }
}
