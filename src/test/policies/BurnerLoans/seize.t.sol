// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

import {BurnerLoansSeizureTestBase} from "./fixtures/BurnerLoansSeizureTestBase.sol";

contract BurnerLoansSeizeTest is BurnerLoansSeizureTestBase {
    function test_givenUnhealthyPosition_seizeClosesPositionAndRoutesCollateral() public {
        _makeUnhealthy(alice);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        uint256 keeperBefore = usds.balanceOf(keeper);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

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
        assertEq(uint8(position.status), uint8(IBurnerLoans.PositionStatus.Seized), "status");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "global active debt");
        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), 0, "asset active debt");
        assertEq(
            floan.facilityPrincipalDefaulted(address(burnerLoans), address(ohm)),
            100e9,
            "facility defaulted principal"
        );
        assertEq(
            floan.marketPrincipalDefaulted(burnerLoans.marketId(address(usds))),
            100e9,
            "market defaulted principal"
        );
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 0, "active borrowers");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "no residual collateral");
    }

    function test_givenTwoSeizableBorrowers_seizeClosesHomogeneousBatch() public {
        _borrow(alice, 2_000e18, 100e9);
        _borrow(bob, 4_000e18, 200e9);
        _configurePrice(address(ohm), 20e18);

        vm.prank(keeper);
        burnerLoans.seize(address(usds), _pair(alice, bob));

        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt");
        assertEq(
            floan.facilityPrincipalDefaulted(address(burnerLoans), address(ohm)),
            300e9,
            "defaulted principal"
        );
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 0, "active set");
    }

    function test_givenMaturedHealthyPosition_seizeSucceeds() public {
        _makeMatured(alice);

        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));

        assertEq(
            uint8(burnerLoans.getPosition(address(usds), alice).status),
            uint8(IBurnerLoans.PositionStatus.Seized),
            "seized status"
        );
    }

    function test_givenZeroCollateralDebtPosition_seizeClosesPosition() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 0,
                debtOhm: 100e9,
                maturity: uint48(block.timestamp + 30 days),
                lastBorrowBlock: 0,
                status: IBurnerLoans.PositionStatus.Active
            })
        );

        vm.prank(keeper);
        (uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(address(usds), _single(alice));

        assertEq(reward, 0, "reward");
        assertEq(treasuryAmount, 0, "treasury amount");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt");
        assertEq(
            uint8(burnerLoans.getPosition(address(usds), alice).status),
            uint8(IBurnerLoans.PositionStatus.Seized),
            "status"
        );
    }

    function test_givenProtocolSeizer_seizeRoutesAllCollateralToTreasury() public {
        _makeUnhealthy(alice);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

        vm.prank(protocolSeizer);
        (uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(address(usds), _single(alice));

        assertEq(reward, 0, "protocol reward");
        assertEq(treasuryAmount, 2_000e18, "all collateral to treasury");
        assertEq(usds.balanceOf(address(trsry)), treasuryBefore + 2_000e18, "treasury balance");
    }

    function test_givenInvalidBorrowerInBatch_seizeRevertsAtomically() public {
        _borrow(alice, 2_000e18, 100e9);
        _borrow(bob, 4_000e18, 100e9);
        _configurePrice(address(ohm), 20e18);
        uint256 activeDebtBefore = burnerLoans.totalActiveDebtOhm();

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PositionNotSeizable.selector, bob)
        );
        burnerLoans.seize(address(usds), _pair(alice, bob));

        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 100e9, "alice debt");
        assertEq(burnerLoans.getPosition(address(usds), bob).debtOhm, 100e9, "bob debt");
        assertEq(burnerLoans.totalActiveDebtOhm(), activeDebtBefore, "active debt unchanged");
        assertEq(
            floan.facilityPrincipalDefaulted(address(burnerLoans), address(ohm)),
            0,
            "defaulted principal unchanged"
        );
    }

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
            floan.facilityPrincipalDefaulted(address(burnerLoans), address(ohm)),
            0,
            "defaulted principal rolled back"
        );
    }

    function test_givenAlreadySeizedPosition_seizeReverts() public {
        _makeUnhealthy(alice);
        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));

        vm.expectRevert(IBurnerLoans.BurnerLoans_PositionSeized.selector);
        burnerLoans.seize(address(usds), _single(alice));
    }

    function test_givenPolicyDisabled_seizeReverts() public {
        _makeUnhealthy(alice);
        vm.prank(emergency);
        burnerLoans.disable(bytes(""));

        vm.prank(keeper);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.seize(address(usds), _single(alice));

        assertEq(burnerLoans.totalActiveDebtOhm(), 100e9, "active debt unchanged");
    }

    function test_givenAssetOriginationsDisabled_seizeStillSucceeds() public {
        _makeUnhealthy(alice);
        vm.prank(burnerLoansAdmin);
        burnerLoans.disableAsset(address(usds));

        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));

        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt");
    }
}
