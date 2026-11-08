// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {BurnerLoansLensTest} from "./BurnerLoansLensTest.sol";

// Explicit boundary values and casts model the declared fixture domains.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)

contract BurnerLoansLensGetPositionTest is BurnerLoansLensTest {
    // Scenarios: BLLENS-POSITION-L01.
    function test_givenActiveEnabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(true, true);
        _assertPosition(caller_, _ALICE, 0, 0, 0, 0);
    }

    // Scenarios: BLLENS-POSITION-L02.
    function test_givenActiveDisabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(true, false);
        _assertPosition(caller_, _ALICE, 0, 0, 0, 0);
    }

    // Scenarios: BLLENS-POSITION-L03.
    function test_givenInactiveEnabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(false, true);
        _assertPosition(caller_, _ALICE, 0, 0, 0, 0);
    }

    // Scenarios: BLLENS-POSITION-L04.
    function test_givenInactiveDisabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(false, false);
        _assertPosition(caller_, _ALICE, 0, 0, 0, 0);
    }

    // Scenarios: BLLENS-POSITION-I02.
    function test_whenZeroAsset_reverts(address caller_) public {
        address asset = address(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset
            )
        );
        vm.prank(caller_);
        _lens.getPosition(asset, _ALICE);
    }

    // Scenarios: BLLENS-POSITION-I01.
    function test_whenUnknownAsset_reverts(address caller_) public {
        address asset = makeAddr("unknown asset");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset
            )
        );
        vm.prank(caller_);
        _lens.getPosition(asset, _ALICE);
    }

    // Scenarios: BLLENS-POSITION-P02.
    function test_givenNoPosition_whenQueried(address caller_) public {
        _assertPosition(caller_, _ALICE, 0, 0, 0, 0);
    }

    // Scenarios: BLLENS-POSITION-P03.
    function test_whenZeroBorrower(address caller_) public {
        _assertPosition(caller_, address(0), 0, 0, 0, 0);
    }

    // Scenarios: BLLENS-POSITION-P01.
    function test_givenCollateralOnly_whenQueried(address caller_) public {
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1000e6, _borrower);
        _assertPosition(caller_, _borrower, 1000e6, 0, 0, 0);
    }

    // Scenarios: BLLENS-POSITION-P04.
    function test_givenActiveDebt_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        IFLOANv1.Position memory original = _position(_ALICE);

        _assertPosition(
            caller_,
            _ALICE,
            1000e6,
            100e9,
            original.maturity,
            original.lastBorrowBlock
        );
    }

    // Scenarios: BLLENS-POSITION-P05.
    function test_givenPartialRepayment_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        IFLOANv1.Position memory original = _position(_ALICE);
        _repay(_ALICE, 40e9);
        _assertPosition(caller_, _ALICE, 1000e6, 60e9, original.maturity, original.lastBorrowBlock);
    }

    // Scenarios: BLLENS-POSITION-P06.
    function test_givenFullRepayment_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);

        _repay(_ALICE, 100e9);
        _assertPosition(caller_, _ALICE, 1000e6, 0, 0, 0);
    }

    // Scenarios: BLLENS-POSITION-P07.
    function test_givenDefault_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);

        _default(_ALICE);
        _assertPosition(caller_, _ALICE, 0, 0, 0, 0);
    }

    // Scenarios: BLLENS-POSITION-P08.
    function test_givenReopenedEpisode_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        _repay(_ALICE, 100e9);
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.roll(vm.getBlockNumber() + 1);
        vm.prank(_ALICE);
        _debt.borrow(address(_asset), 70e9, _ALICE, _ALICE, type(uint256).max, address(0));
        _assertPosition(
            caller_,
            _ALICE,
            1000e6,
            70e9,
            uint48(block.timestamp + 30 days),
            uint48(block.number)
        );
    }

    // Scenarios: BLLENS-POSITION-P09.
    function test_givenAnotherMarket_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        IFLOANv1.Position memory original = _position(_ALICE);
        _seedOtherMarket(_ALICE, 500e9);
        _assertPosition(
            caller_,
            _ALICE,
            1000e6,
            100e9,
            original.maturity,
            original.lastBorrowBlock
        );
    }

    // Scenarios: BLLENS-POSITION-P10.
    function test_givenMultiplePositions_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        IFLOANv1.Position memory original = _position(_ALICE);
        vm.startPrank(address(_core));
        uint64 second = _floan.createPosition(_core.marketId(address(_asset)), _ALICE);
        _floan.addCollateral(second, 777);
        vm.stopPrank();
        _assertPosition(
            caller_,
            _ALICE,
            1000e6,
            100e9,
            original.maturity,
            original.lastBorrowBlock
        );
    }

    // Scenarios: BLLENS-POSITION-D01.
    function test_givenBrokenRisk_whenQueried(address caller_) public {
        _mockPosition(_ALICE, 1000e6, 100e9, 99_999, 33);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.snapshot, (address(_asset))),
            abi.encodeWithSelector(SnapshotReadFailed.selector)
        );
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encodeWithSelector(RiskHealthFailed.selector)
        );
        _expectNoRiskReads();
        _assertPosition(caller_, _ALICE, 1000e6, 100e9, 99_999, 33);
    }

    // Scenarios: BLLENS-POSITION-D02.
    function test_givenReplacementRisk_whenQueried(address caller_) public {
        _mockPosition(_ALICE, 1000e6, 100e9, 99_999, 33);
        _replaceRisk();
        _expectNoRiskReads();
        _assertPosition(caller_, _ALICE, 1000e6, 100e9, 99_999, 33);
    }

    // Scenarios: BLLENS-POSITION-T01.
    function test_givenFloanFailure_whenQueried_reverts(address caller_) public {
        _mockPosition(_ALICE, 1000e6, 100e9, 99_999, 33);
        vm.mockCallRevert(
            address(_floan),
            abi.encodeCall(IFLOANv1.getPosition, (uint64(uint160(_ALICE)))),
            abi.encodeWithSelector(FloanReadFailed.selector)
        );
        vm.expectRevert(FloanReadFailed.selector);
        vm.prank(caller_);
        _lens.getPosition(address(_asset), _ALICE);
    }

    function test_givenMaximumFields_whenQueried(address caller_) public {
        _mockPosition(
            _ALICE,
            type(uint128).max,
            type(uint128).max,
            type(uint48).max,
            type(uint32).max
        );
        _assertPosition(
            caller_,
            _ALICE,
            type(uint128).max,
            type(uint128).max,
            type(uint48).max,
            type(uint32).max
        );
    }

    // Scenarios: BLLENS-POSITION-L02.
    function test_givenDisabledCore_whenLensReads_thenPositionRemainsVisible()
        public
        givenDebtBearingPosition
    {
        _core.disable("");
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            2000e6,
            "Read helper does not depend on Core enablement"
        );
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
