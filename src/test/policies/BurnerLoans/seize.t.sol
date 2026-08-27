// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";
import {BurnerLoansSeizureTestBase} from "./fixtures/BurnerLoansSeizureTestBase.sol";

contract BurnerLoansSeizeTest is BurnerLoansSeizureTestBase {
    // seize
    // given unhealthy position
    //  when seize is called
    //   then it closes position and routes collateral
    function test_givenUnhealthyPosition_seizeClosesPositionAndRoutesCollateral() public {
        _makeUnhealthy(alice);
        uint256 mintApprovalBefore = mintr.mintApproval(address(inventory));
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        assertEq(preview.seizedDebtOhm, 100e9, "preview seized debt");
        assertEq(preview.seizedCollateral, 2_000e18, "preview seized collateral");
        assertEq(preview.keeperReward, 20e18, "preview one percent reward");
        assertEq(preview.collateralToTreasury, 1_980e18, "preview treasury collateral");
        assertTrue(preview.executable, "preview executable");
        uint256 keeperBefore = usds.balanceOf(keeper);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.PrincipalDefaulted(100e9);
        vm.prank(keeper);
        (uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(address(usds), _single(alice));

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(reward, preview.keeperReward, "reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "treasury amount");
        assertEq(usds.balanceOf(keeper), keeperBefore + reward, "keeper balance");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBefore + treasuryAmount,
            "treasury balance"
        );
        assertEq(position.debtOhm, 0, "debt cleared");
        assertEq(position.depositedCollateral, 0, "collateral cleared");
        assertEq(position.maturity, 0, "maturity cleared");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "global active debt");
        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), 0, "asset active debt");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds))),
            100e9,
            "market defaulted principal"
        );
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 0, "active borrowers");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "no residual collateral");
        assertEq(
            mintr.mintApproval(address(inventory)),
            mintApprovalBefore + 100e9,
            "seizure restores defaulted capacity"
        );
        assertEq(inventory.activePrincipalOhm(), 0, "Burner Loans Inventory active principal");
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
    }

    // seize
    // given two seizable borrowers
    //  when seize is called
    //   then it closes homogeneous batch
    function test_givenTwoSeizableBorrowers_seizeClosesHomogeneousBatch() public {
        _borrow(alice, 2_000e18, 100e9);
        _borrow(bob, 4_000e18, 200e9);
        _configurePrice(address(ohm), 20e18);

        vm.prank(keeper);
        burnerLoans.seize(address(usds), _pair(alice, bob));

        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds))),
            300e9,
            "defaulted principal"
        );
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 0, "active set");
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
        _assertFloanPositionMatchesBurnerLoans(address(usds), bob);
    }

    // setGlobalDebtCap
    // given defaulted principal
    //  when setGlobalDebtCap is called
    //   then it reconciles capacity against active principal only
    function test_givenDefaultedPrincipal_setGlobalDebtCap_reconcilesActiveCapacity() public {
        _makeUnhealthy(alice);
        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));

        vm.startPrank(admin);
        burnerLoansConfig.setGlobalDebtCap(50e9);
        assertEq(mintr.mintApproval(address(inventory)), 50e9, "default releases capacity");

        burnerLoansConfig.setGlobalDebtCap(200e9);
        vm.stopPrank();

        assertEq(
            mintr.mintApproval(address(inventory)),
            200e9,
            "capacity depends only on active principal"
        );
    }

    // seize
    // given matured healthy position
    //  when seize is called
    //   then it succeeds
    function test_givenMaturedHealthyPosition_seizeSucceeds() public {
        _makeMatured(alice);

        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));

        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 0, "debt cleared");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            0,
            "collateral cleared"
        );
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
    }

    // seize
    // given zero collateral debt position
    //  when seize is called
    //   then it closes position
    function test_givenZeroCollateralDebtPosition_seizeClosesPosition() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 0,
                debtOhm: 100e9,
                maturity: uint48(block.timestamp + 30 days),
                lastBorrowBlock: 0
            })
        );

        vm.prank(keeper);
        (uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(address(usds), _single(alice));

        assertEq(reward, 0, "reward");
        assertEq(treasuryAmount, 0, "treasury amount");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt");
    }

    // seize
    // given protocol seizer
    //  when seize is called
    //   then it routes all collateral to treasury
    function test_givenProtocolSeizer_seizeRoutesAllCollateralToTreasury() public {
        _makeUnhealthy(alice);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        vm.prank(protocolSeizer);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        assertEq(preview.keeperReward, 0, "preview protocol reward");
        assertEq(preview.collateralToTreasury, 2_000e18, "preview treasury collateral");

        vm.prank(protocolSeizer);
        (uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(address(usds), _single(alice));

        assertEq(reward, preview.keeperReward, "protocol reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "all collateral to treasury");
        assertEq(usds.balanceOf(address(trsry)), treasuryBefore + 2_000e18, "treasury balance");
    }

    // seize
    // given invalid borrower in batch
    //  when seize is called
    //   then it reverts atomically
    function test_givenInvalidBorrowerInBatch_seizeRevertsAtomically() public {
        _borrow(alice, 2_000e18, 100e9);
        _borrow(bob, 4_000e18, 100e9);
        _configurePrice(address(ohm), 20e18);
        uint256 activeDebtBefore = burnerLoans.totalActiveDebtOhm();
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_PositionNotSeizable.selector,
            bob
        );

        vm.prank(keeper);
        vm.expectRevert(error);
        burnerLoans.previewSeize(address(usds), _pair(alice, bob));

        vm.prank(keeper);
        vm.expectRevert(error);
        burnerLoans.seize(address(usds), _pair(alice, bob));

        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 100e9, "alice debt");
        assertEq(burnerLoans.getPosition(address(usds), bob).debtOhm, 100e9, "bob debt");
        assertEq(burnerLoans.totalActiveDebtOhm(), activeDebtBefore, "active debt unchanged");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds))),
            0,
            "defaulted principal unchanged"
        );
    }

    // seize
    // given deposit manager withdraw failure
    //  when seize is called
    //   then it rolls back all state
    function test_givenDepositManagerWithdrawFailure_seizeRollsBackAllState() public {
        _makeUnhealthy(alice);
        IDepositManager.WithdrawParams memory params = IDepositManager.WithdrawParams({
            asset: IERC20(address(usds)),
            depositPeriod: 1,
            depositor: address(burnerLoans),
            recipient: address(burnerLoans),
            amount: 2_000e18,
            isWrapped: false
        });
        bytes memory failure = bytes("forced withdraw failure");
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeCall(IDepositManager.withdraw, (params)),
            failure
        );

        vm.prank(keeper);
        vm.expectRevert(failure);
        burnerLoans.seize(address(usds), _single(alice));

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(position.debtOhm, 100e9, "debt rolled back");
        assertEq(position.depositedCollateral, 2_000e18, "collateral rolled back");
        assertEq(burnerLoans.totalActiveDebtOhm(), 100e9, "active debt rolled back");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 1, "active set rolled back");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds))),
            0,
            "defaulted principal rolled back"
        );
    }

    // seize
    // given collateral transfers report success without moving the withdrawn collateral
    //  when seize is called
    //   then the residual-balance guard reverts and rolls back all seizure state
    function test_givenCollateralTransferLeavesResidualBalance_seizeRevertsAndRollsBack() public {
        _makeUnhealthy(alice);
        uint256 burnerLoansBalanceBefore = usds.balanceOf(address(burnerLoans));
        uint256 keeperBalanceBefore = usds.balanceOf(keeper);
        uint256 treasuryBalanceBefore = usds.balanceOf(address(trsry));
        vm.mockCall(
            address(usds),
            abi.encodeCall(ERC20.transfer, (keeper, 20e18)),
            abi.encode(true)
        );
        vm.mockCall(
            address(usds),
            abi.encodeCall(ERC20.transfer, (address(trsry), 1_980e18)),
            abi.encode(true)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_ResidualCollateralBalance.selector,
                address(usds),
                2_000e18
            )
        );
        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(position.debtOhm, 100e9, "position debt rolled back");
        assertEq(position.depositedCollateral, 2_000e18, "position collateral rolled back");
        assertEq(burnerLoans.totalActiveDebtOhm(), 100e9, "active debt rolled back");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 1, "active set rolled back");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds))),
            0,
            "defaulted principal rolled back"
        );
        assertEq(
            usds.balanceOf(address(burnerLoans)),
            burnerLoansBalanceBefore,
            "Burner Loans balance rolled back"
        );
        assertEq(usds.balanceOf(keeper), keeperBalanceBefore, "keeper balance rolled back");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBalanceBefore,
            "treasury balance rolled back"
        );
    }

    // seize
    // given a position has been seized and its episode state cleared
    //  when the borrower deposits collateral and borrows again
    //   then Burner Loans reuses the same FLOAN position ID
    //   then the reused position receives a fresh maturity
    function test_givenSeizedPosition_borrowerCanStartNewEpisodeWithSamePositionId() public {
        _makeUnhealthy(alice);
        uint48 firstMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        uint256[] memory positionIdsBefore = floan.getPositionIdsForMarketAndBorrower(
            marketId,
            alice
        );
        uint256 positionCountBefore = floan.getPositionCount();

        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));

        IFLOANv1.Position memory closedPosition = floan.getPosition(uint64(positionIdsBefore[0]));
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
        assertEq(closedPosition.principalDrawn, 0, "seized principal drawn cleared");
        assertEq(closedPosition.maturity, 0, "seized maturity cleared");

        vm.warp(block.timestamp + 1 days);
        _configurePrice(address(ohm), 10e18);
        price.setTimestamp(uint48(block.timestamp));
        usds.mint(alice, 2_100e18);
        vm.startPrank(alice);
        burnerLoans.depositCollateral(address(usds), 2_000e18, alice);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            100e9,
            alice
        );
        assertEq(preview.maturity, block.timestamp + 30 days, "new episode maturity");
        assertGt(preview.maturity, firstMaturity, "new maturity should not reuse old maturity");
        burnerLoans.borrow(address(usds), 100e9, alice, alice, preview.fee);
        vm.stopPrank();

        uint256[] memory positionIdsAfter = floan.getPositionIdsForMarketAndBorrower(
            marketId,
            alice
        );
        assertEq(floan.getPositionCount(), positionCountBefore, "position count unchanged");
        assertEq(positionIdsAfter.length, 1, "one position retained");
        assertEq(positionIdsAfter[0], positionIdsBefore[0], "same position ID reused");
        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 100e9, "new debt");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            preview.maturity,
            "stored new episode maturity"
        );
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 1, "borrower active");
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
    }

    // seize
    // given policy disabled
    //  when seize is called
    //   then it reverts
    function test_givenPolicyDisabled_seizeReverts() public {
        _makeUnhealthy(alice);
        vm.prank(emergency);
        burnerLoans.disable(bytes(""));

        vm.prank(keeper);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewSeize(address(usds), _single(alice));

        vm.prank(keeper);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.seize(address(usds), _single(alice));

        assertEq(burnerLoans.totalActiveDebtOhm(), 100e9, "active debt unchanged");
    }

    // seize
    // given Burner Loans Inventory is globally disabled after a position becomes unhealthy
    //  when seizure is previewed or executed
    //   then both report the strict Burner Loans Inventory pause
    function test_givenInventoryDisabled_previewAndSeizeRevert() public {
        _makeUnhealthy(alice);
        vm.prank(emergency);
        inventory.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewSeize(address(usds), _single(alice));

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.seize(address(usds), _single(alice));
    }

    // seize
    // given asset originations disabled
    //  when seize is called
    //   then it still succeeds
    function test_givenAssetOriginationsDisabled_seizeStillSucceeds() public {
        _makeUnhealthy(alice);
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        vm.prank(keeper);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        assertTrue(preview.executable, "disabled asset seizure preview");

        vm.prank(keeper);
        (uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(address(usds), _single(alice));

        assertEq(reward, preview.keeperReward, "keeper reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "treasury collateral");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt");
    }

    // seize
    // given multiple markets for the facility and token pair
    //  when seizure is previewed and executed
    //   then Burner Loans uses the first market
    function test_givenMultipleMarkets_previewAndSeizeUseFirstMarket() public {
        _makeUnhealthy(alice);
        uint32 firstMarketId = burnerLoansConfig.marketId(address(usds));
        uint32 secondMarketId = _createDuplicateUsdsMarketForTest();

        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));

        assertEq(preview.seizedDebtOhm, 100e9, "preview first-market debt");
        assertEq(floan.getMarketPrincipalDefaulted(firstMarketId), 100e9, "first-market default");
        assertEq(floan.getMarketPrincipalDefaulted(secondMarketId), 0, "second-market default");
    }

    // seize
    // given heart caller
    //  when seizure is previewed and executed
    //   then it returns zero reward and routes all collateral to treasury
    function test_givenHeartCaller_seizeRoutesAllCollateralToTreasury() public {
        _makeUnhealthy(alice);
        vm.prank(admin);
        rolesAdmin.grantRole(HEART_ROLE, keeper);

        vm.prank(keeper);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );

        assertEq(preview.keeperReward, 0, "heart reward");
        assertEq(preview.collateralToTreasury, 2_000e18, "treasury collateral");

        vm.prank(keeper);
        (uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(address(usds), _single(alice));
        assertEq(reward, preview.keeperReward, "executed heart reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "executed treasury collateral");
    }

    // seize
    // given empty batch
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenEmptyBatch_seizeReverts() public {
        address[] memory borrowers = new address[](0);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidBatch.selector);
        burnerLoans.previewSeize(address(usds), borrowers);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidBatch.selector);
        burnerLoans.seize(address(usds), borrowers);
    }

    // seize
    // given batch above maximum
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenBatchAboveMaximum_seizeReverts(uint256 batchLength_) public {
        uint256 batchLength = bound(batchLength_, 51, 100);
        address[] memory borrowers = new address[](batchLength);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidBatch.selector);
        burnerLoans.previewSeize(address(usds), borrowers);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidBatch.selector);
        burnerLoans.seize(address(usds), borrowers);
    }

    // seize
    // given exact maximum batch
    //  when seizure is previewed and executed
    //   then both succeed with matching totals
    function test_givenExactMaximumBatch_seizeSucceeds() public {
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
                    lastBorrowBlock: 0
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

        vm.prank(keeper);
        (uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(address(usds), borrowers);
        assertEq(reward, preview.keeperReward, "executed keeper reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "executed treasury collateral");
    }

    // seize
    // given duplicate borrower
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenDuplicateBorrower_seizeReverts() public {
        _makeUnhealthy(alice);
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_DuplicateBorrower.selector,
            alice
        );

        vm.expectRevert(error);
        burnerLoans.previewSeize(address(usds), _pair(alice, alice));

        vm.expectRevert(error);
        burnerLoans.seize(address(usds), _pair(alice, alice));
    }

    // seize
    // given zero borrower
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenZeroBorrower_seizeReverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoans.previewSeize(address(usds), _single(address(0)));

        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoans.seize(address(usds), _single(address(0)));
    }

    // seize
    // given healthy position
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenHealthyPosition_seizeReverts() public {
        _borrow(alice, 2_000e18, 100e9);
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_PositionNotSeizable.selector,
            alice
        );

        vm.expectRevert(error);
        burnerLoans.previewSeize(address(usds), _single(alice));

        vm.expectRevert(error);
        burnerLoans.seize(address(usds), _single(alice));
    }

    // seize
    // given debt free position
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenDebtFreePosition_seizeReverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_NoDebt.selector);
        burnerLoans.previewSeize(address(usds), _single(alice));

        vm.expectRevert(IBurnerLoans.BurnerLoans_NoDebt.selector);
        burnerLoans.seize(address(usds), _single(alice));
    }

    // seize
    // given stale prices
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenStalePrices_seizeReverts() public {
        _makeUnhealthy(alice);
        vm.warp(block.timestamp + 9 hours);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.previewSeize(address(usds), _single(alice));

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.seize(address(usds), _single(alice));
    }

    // seize
    // given zero reward BPS
    //  when seizure is previewed and executed
    //   then both return zero reward
    function test_givenZeroRewardBps_seizeReturnsZeroReward() public {
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.keeperRewardBps = 0;
        riskConfig.maxKeeperReward = 1_000e18;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), riskConfig);
        _makeUnhealthy(alice);

        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );

        assertEq(preview.keeperReward, 0, "keeper reward");
        assertEq(preview.collateralToTreasury, 2_000e18, "treasury collateral");

        vm.prank(keeper);
        (uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(address(usds), _single(alice));
        assertEq(reward, preview.keeperReward, "executed keeper reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "executed treasury collateral");
    }

    // seize
    // given zero max reward
    //  when seizure is previewed and executed
    //   then both return zero reward
    function test_givenZeroMaxReward_seizeReturnsZeroReward() public {
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.maxKeeperReward = 0;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), riskConfig);
        _makeUnhealthy(alice);

        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );

        assertEq(preview.keeperReward, 0, "keeper reward");
        assertEq(preview.collateralToTreasury, 2_000e18, "treasury collateral");

        vm.prank(keeper);
        (uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(address(usds), _single(alice));
        assertEq(reward, preview.keeperReward, "executed keeper reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "executed treasury collateral");
    }

    // seize
    // given max reward below BPS reward
    //  when seizure is previewed and executed
    //   then both cap the reward
    function test_givenMaxRewardBelowBpsReward_seizeCapsReward() public {
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.maxKeeperReward = 5e18;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), riskConfig);
        _makeUnhealthy(alice);

        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );

        assertEq(preview.keeperReward, 5e18, "capped keeper reward");

        vm.prank(keeper);
        (uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(address(usds), _single(alice));
        assertEq(reward, preview.keeperReward, "executed capped keeper reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "executed treasury collateral");
    }
}

contract BurnerLoansGetSeizableBorrowersTest is BurnerLoansSeizureTestBase {
    // getSeizableBorrowers
    // given no active borrowers
    //  when getSeizableBorrowers is called
    //   then it returns empty
    function test_givenNoActiveBorrowers_getSeizableBorrowersReturnsEmpty() public view {
        (address[] memory borrowers, uint256 nextIndex, uint256 reward) = burnerLoans
            .getSeizableBorrowers(address(usds), 0, 10, 10);

        assertEq(borrowers.length, 0, "borrowers");
        assertEq(nextIndex, 0, "cursor");
        assertEq(reward, 0, "reward");
    }

    // getSeizableBorrowers
    // given return limit above maximum
    //  when getSeizableBorrowers is called
    //   then it reverts
    function test_givenReturnLimitAboveMaximum_getSeizableBorrowers_reverts(
        uint256 returnLimit_
    ) public {
        uint256 returnLimit = bound(returnLimit_, 51, 100);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidBatch.selector);
        burnerLoans.getSeizableBorrowers(address(usds), 0, 100, returnLimit);
    }

    // getSeizableBorrowers
    // given policy disabled
    //  when getSeizableBorrowers is called
    //   then it reverts
    function test_givenPolicyDisabled_getSeizableBorrowers_reverts() public {
        vm.prank(emergency);
        burnerLoans.disable(bytes(""));

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.getSeizableBorrowers(address(usds), 0, 10, 10);
    }

    // getSeizableBorrowers
    // given stale prices
    //  when getSeizableBorrowers is called
    //   then it reverts
    function test_givenStalePrices_getSeizableBorrowers_reverts() public {
        _makeUnhealthy(alice);
        vm.warp(block.timestamp + 9 hours);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.getSeizableBorrowers(address(usds), 0, 1, 1);
    }

    // getSeizableBorrowers
    // given mixed active borrowers
    //  when getSeizableBorrowers is called
    //   then it returns only eligible positions
    function test_givenMixedActiveBorrowers_getSeizableBorrowersReturnsOnlyEligiblePositions()
        public
    {
        _borrow(alice, 2_000e18, 100e9);
        _borrow(bob, 4_000e18, 100e9);
        _configurePrice(address(ohm), 20e18);

        vm.prank(keeper);
        (address[] memory borrowers, uint256 nextIndex, uint256 reward) = burnerLoans
            .getSeizableBorrowers(address(usds), 0, 2, 2);

        assertEq(borrowers.length, 1, "seizable count");
        assertEq(borrowers[0], alice, "seizable borrower");
        assertEq(nextIndex, 0, "wrapped cursor");
        // Alice contributes 2,000e18 seized USDS; the configured 1% reward is 20e18 USDS.
        // This is below both the 1,000e18 cap and the collateral surplus above required backing.
        assertEq(reward, 20e18, "keeper reward");
    }

    // getSeizableBorrowers
    // given protocol seizer
    //  when getSeizableBorrowers is called
    //   then it returns zero reward
    function test_givenProtocolSeizer_getSeizableBorrowersReturnsZeroReward() public {
        _makeUnhealthy(alice);

        vm.prank(protocolSeizer);
        (address[] memory borrowers, , uint256 reward) = burnerLoans.getSeizableBorrowers(
            address(usds),
            0,
            1,
            1
        );

        assertEq(borrowers.length, 1, "borrower count");
        assertEq(reward, 0, "protocol reward");
    }

    // getSeizableBorrowers
    // given return limit
    //  when getSeizableBorrowers is called
    //   then it stops at limit
    function test_givenReturnLimit_getSeizableBorrowersStopsAtLimit() public {
        _borrow(alice, 2_000e18, 100e9);
        _borrow(bob, 2_000e18, 100e9);
        _configurePrice(address(ohm), 20e18);

        (address[] memory borrowers, uint256 nextIndex, ) = burnerLoans.getSeizableBorrowers(
            address(usds),
            0,
            2,
            1
        );

        assertEq(borrowers.length, 1, "return limit");
        assertEq(nextIndex, 1, "next cursor");
    }

    // getSeizableBorrowers
    // given zero check limit
    //  when getSeizableBorrowers is called
    //   then it returns empty without advancing
    function test_givenZeroCheckLimit_getSeizableBorrowersReturnsEmptyWithoutAdvancing() public {
        _makeUnhealthy(alice);

        (address[] memory borrowers, uint256 nextIndex, uint256 reward) = burnerLoans
            .getSeizableBorrowers(address(usds), 0, 0, 1);

        assertEq(borrowers.length, 0, "borrowers");
        assertEq(nextIndex, 0, "cursor");
        assertEq(reward, 0, "reward");
    }

    // getSeizableBorrowers
    // given start at end
    //  when getSeizableBorrowers is called
    //   then it wraps to zero
    function test_givenStartAtEnd_getSeizableBorrowersWrapsToZero() public {
        _makeUnhealthy(alice);

        (address[] memory borrowers, uint256 nextIndex, ) = burnerLoans.getSeizableBorrowers(
            address(usds),
            1,
            1,
            1
        );

        assertEq(borrowers.length, 1, "borrowers");
        assertEq(nextIndex, 0, "wrapped cursor");
    }
}

contract BurnerLoansIsSeizableTest is BurnerLoansBorrowTestBase {
    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _position(
        uint256 collateral_,
        uint256 debt_,
        uint48 maturity_
    ) internal pure returns (IBurnerLoans.Position memory) {
        return
            IBurnerLoans.Position({
                depositedCollateral: collateral_,
                debtOhm: debt_,
                maturity: maturity_,
                lastBorrowBlock: 0
            });
    }

    // isSeizable
    // given healthy active position
    //  when isSeizable is called
    //   then it returns false
    function test_givenHealthyActivePosition_isSeizable_returnsFalse() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(2_000e18, 100e9, uint48(block.timestamp + 30 days))
        );

        assertFalse(burnerLoans.isSeizable(address(usds), alice), "healthy position");
    }

    // isSeizable
    // given health below one WAD
    //  when isSeizable is called
    //   then it returns true
    function test_givenHealthBelowOneWad_isSeizable_returnsTrue() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(1_149e18, 100e9, uint48(block.timestamp + 30 days))
        );

        assertTrue(burnerLoans.isSeizable(address(usds), alice), "unhealthy position");
    }

    // isSeizable
    // given health exactly one WAD
    //  when isSeizable is called
    //   then it returns false
    function test_givenHealthExactlyOneWad_isSeizable_returnsFalse() public {
        // debt value = 100 OHM * $10 = $1,000
        // required collateral = ceil($1,000 * 10,000 / 8,500)
        //                     = $1,176.470588235294117648
        // health = required collateral / required collateral = 1e18
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(1_176_470_588_235_294_117_648, 100e9, uint48(block.timestamp + 30 days))
        );

        assertFalse(burnerLoans.isSeizable(address(usds), alice), "exact health boundary");
    }

    // isSeizable
    // given matured healthy position
    //  when isSeizable is called
    //   then it returns true
    function test_givenMaturedHealthyPosition_isSeizable_returnsTrue() public {
        uint48 maturity = uint48(block.timestamp + 1 days);
        burnerLoans.setPositionForTest(address(usds), alice, _position(2_000e18, 100e9, maturity));
        vm.warp(maturity);
        price.setTimestamp(uint48(block.timestamp));

        assertTrue(burnerLoans.isSeizable(address(usds), alice), "matured position");
    }

    // isSeizable
    // given debt free position
    //  when isSeizable is called
    //   then it returns false without price read
    function test_givenDebtFreePosition_isSeizable_returnsFalseWithoutPriceRead() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(2_000e18, 0, uint48(block.timestamp + 30 days))
        );
        vm.warp(block.timestamp + 9 hours);

        assertFalse(burnerLoans.isSeizable(address(usds), alice), "debt-free position");
    }

    // isSeizable
    // given stale price
    //  when isSeizable is called
    //   then it reverts
    function test_givenStalePrice_isSeizable_reverts() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(2_000e18, 100e9, uint48(block.timestamp + 30 days))
        );
        vm.warp(block.timestamp + 9 hours);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.isSeizable(address(usds), alice);
    }

    // isSeizable
    // given missing market
    //  when isSeizable is called
    //   then it reverts
    function test_givenMissingMarket_isSeizable_reverts() public {
        address otherAsset = makeAddr("otherAsset");

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, otherAsset)
        );
        burnerLoans.isSeizable(otherAsset, alice);
    }

    // isSeizable
    // given multiple markets
    //  when isSeizable is called
    //   then it uses the first market
    function test_givenMultipleMarkets_isSeizableUsesFirstMarket() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(2_000e18, 100e9, uint48(block.timestamp + 30 days))
        );
        _createDuplicateUsdsMarketForTest();

        assertFalse(burnerLoans.isSeizable(address(usds), alice), "first-market health");
    }
}
