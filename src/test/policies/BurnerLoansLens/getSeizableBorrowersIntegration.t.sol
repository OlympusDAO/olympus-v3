// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";

// Libraries

// Contracts
import {BurnerLoansLensScanTest} from "./fixtures/BurnerLoansLensScanTest.sol";

import {MockERC20} from "src/test/mocks/MockERC20.sol";

// Explicit boundary values and casts model the declared fixture domains.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)

contract BurnerLoansLensGetSeizableBorrowersIntegrationTest is BurnerLoansLensScanTest {
    // Scenarios: BLLENS-SEIZABLE-P08.
    function test_givenBorrowerRepaid_whenFinalPageScanned(address caller_) public {
        _realScanFixture();
        _assumeOrdinary(caller_);
        _assertScan(caller_, 0, 2, _one(_ALICE), 2, 17);
        _repayAlice();
        _assertScan(caller_, 2, 2, _one(_CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-P17.
    function test_givenBorrowerRepaid_whenSavedCursorIsInvalid_reverts(address caller_) public {
        _realScanFixture();
        _assumeOrdinary(caller_);
        _assertScan(caller_, 0, 3, _two(_ALICE, _CAROL), 3, 17);
        _repayAlice();
        _expectNoScanWork();
        _assertScanRevert(
            caller_,
            address(_asset),
            3,
            1,
            abi.encodeWithSelector(
                IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
                uint256(3),
                uint256(3)
            )
        );
    }

    // Scenarios: BLLENS-SEIZABLE-P18.
    function test_givenRejectedSavedCursor_whenCallerResets(address caller_) public {
        _realScanFixture();
        _assumeOrdinary(caller_);
        _repayAlice();
        _assertScanRevert(
            caller_,
            address(_asset),
            3,
            1,
            abi.encodeWithSelector(
                IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
                uint256(3),
                uint256(3)
            )
        );
        _assertScan(caller_, 0, 3, _one(_CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-P09.
    function test_givenBorrowerInOtherMarket_whenScanned(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        MockERC20 other = _seedOtherMarket(_ALICE, 100e9);
        uint32 otherMarket = _core.marketId(address(other));
        vm.expectCall(
            address(_floan),
            abi.encodeCall(
                IFLOANv1.getPositionIdForMarketAndBorrowerAt,
                (otherMarket, _ALICE, uint256(0))
            ),
            uint64(0)
        );
        _prepareReward(40e9, 400e6, 77, false, 17);
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 17);
    }

    function _realScanFixture() internal {
        _seedDebt(_ALICE, 100e6, 10e9);
        _seedDebt(_BOB, 200e6, 20e9);
        _seedDebt(_CAROL, 300e6, 30e9);
        _seedDebt(_DAVE, 400e6, 40e9);
        (, uint64 id) = _floan.getPositionIdForMarketAndBorrowerAt(
            _core.marketId(address(_asset)),
            _ALICE,
            0
        );
        IFLOANv1.Position memory p = _floan.getPosition(id);
        p.maturity = uint48(block.timestamp);
        vm.mockCall(address(_floan), abi.encodeCall(IFLOANv1.getPosition, (id)), abi.encode(p));
        _readRisk();
    }

    function _readRisk() internal {
        _mockRisk(2e18);
        vm.mockCall(
            address(_risk),
            abi.encodeCall(
                IBurnerLoansRisk.health,
                (_snapshot(), _core.marketId(address(_asset)), uint256(300e6), uint256(30e9))
            ),
            abi.encode(uint256(1e18 - 1))
        );
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("previewWithdraw(address,uint256,bool)", address(_asset)),
            abi.encode(IERC20(address(_asset)), uint256(77))
        );
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            abi.encode(uint256(17))
        );
    }

    function _repayAlice() internal {
        vm.clearMockedCalls();
        _repay(_ALICE, 10e9);
        _readRisk();
        address[] memory actual = _floan.getActiveBorrowers(_core.marketId(address(_asset)));
        assertEq(
            actual,
            _remainingBorrowers(),
            "Real FLOAN swap-and-pop order is Dave, Bob, Carol"
        );
    }

    function _remainingBorrowers() internal pure returns (address[] memory borrowers) {
        borrowers = new address[](3);
        borrowers[0] = _DAVE;
        borrowers[1] = _BOB;
        borrowers[2] = _CAROL;
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
