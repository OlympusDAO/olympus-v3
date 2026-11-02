// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts

import {BurnerLoansLensTest} from "../BurnerLoansLensTest.sol";

// Explicit boundary values and casts model the declared fixture domains.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)

abstract contract BurnerLoansLensScanTest is BurnerLoansLensTest {
    /// @dev Four canonical borrowers; Alice and Carol qualify. Reward is a fixed aggregate quote,
    ///      independent of the number selected, so these scan tests do not repeat reward arithmetic.
    function _canonicalRewardScan() internal {
        _canonicalScan();
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("previewWithdraw(address,uint256,bool)", address(_asset)),
            abi.encode(address(_asset), uint256(100e6))
        );
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            abi.encode(uint256(7))
        );
    }

    function _assertEmptyBoundedPage(
        address caller_,
        address actor_,
        uint256 count_,
        uint256 limit_
    ) internal {
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(actor_, address(_asset), 0, count_, limit_);
        assertEq(borrowers.length, 0, "Zero limit returns no borrowers");
        assertEq(cursor, 0, "Zero limit preserves the starting cursor");
        assertEq(reward, 0, "Empty page receives no reward");
    }

    function _assumeOrdinary(address caller_) internal view {
        vm.assume(
            !_roles.hasRole(caller_, HEART_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_SEIZER_ROLE)
        );
    }

    function _mockWithdrawal(uint256 collateral_, uint256 output_) internal {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "previewWithdraw(address,uint256,bool)",
                address(_asset),
                collateral_
            ),
            abi.encode(IERC20(address(_asset)), output_)
        );
    }

    function _prepareReward(
        uint256 debt_,
        uint256 collateral_,
        uint256 output_,
        bool protocol_,
        uint256 reward_
    ) internal {
        _mockWithdrawal(collateral_, output_);
        bytes memory data = abi.encodeCall(
            IBurnerLoansRisk.keeperReward,
            (_snapshot(), _core.marketId(address(_asset)), debt_, collateral_, output_, protocol_)
        );
        vm.mockCall(address(_risk), data, abi.encode(reward_));
        vm.expectCall(address(_risk), data, uint64(2));
        vm.expectCall(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.snapshot, (address(_asset))),
            uint64(2)
        );
    }

    function _assertScan(
        address caller_,
        uint256 start_,
        uint256 count_,
        address[] memory expected_,
        uint256 cursor_,
        uint256 reward_
    ) internal {
        vm.recordLogs();
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens.getSeizableBorrowers(
            address(_asset),
            start_,
            count_
        );
        assertEq(borrowers, expected_, "Convenience candidate order");
        assertEq(cursor, cursor_, "Convenience cursor");
        assertEq(reward, reward_, "Convenience reward");
        (borrowers, cursor, reward) = _lens.getSeizableBorrowersFor(
            caller_,
            address(_asset),
            start_,
            count_
        );
        assertEq(borrowers, expected_, "Explicit unpranked actor candidates");
        assertEq(cursor, cursor_, "Explicit actor cursor");
        assertEq(reward, reward_, "Explicit actor reward");
        assertEq(vm.getRecordedLogs().length, 0, "Scans emit no logs");
    }

    function _assertScanRevert(
        address caller_,
        address asset_,
        uint256 start_,
        uint256 count_,
        bytes memory error_
    ) internal {
        vm.expectRevert(error_);
        vm.prank(caller_);
        _lens.getSeizableBorrowers(asset_, start_, count_);
        vm.expectRevert(error_);
        _lens.getSeizableBorrowersFor(caller_, asset_, start_, count_);
    }

    function _expectNoScanWork() internal {
        _expectNoRiskReads();
        vm.expectCall(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.getActiveBorrowerAt.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_depositManager),
            abi.encodeWithSignature("previewWithdraw(address,uint256,bool)"),
            uint64(0)
        );
    }

    function _expectCanonicalVisits(uint256 start_, uint256 count_) internal {
        uint32 market = _core.marketId(address(_asset));
        for (uint256 i; i < 4; ++i)
            vm.expectCall(
                address(_floan),
                abi.encodeCall(IFLOANv1.getActiveBorrowerAt, (market, i)),
                uint64(i >= start_ && i < start_ + count_ ? 2 : 0)
            );
    }

    function _assertInvalidStartCounts(
        address caller_,
        uint256 start_,
        uint256 population_
    ) internal {
        bytes memory failure = abi.encodeWithSelector(
            IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
            start_,
            population_
        );
        _assertScanRevert(caller_, address(_asset), start_, 0, failure);
        _assertScanRevert(caller_, address(_asset), start_, 1, failure);
        _assertScanRevert(caller_, address(_asset), start_, type(uint256).max, failure);
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
