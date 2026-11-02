// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

// Fixtures deliberately use fixed token units and bounded loops for independent read assertions.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
abstract contract BurnerLoansLensTest is BurnerLoansModularTest {
    error FloanReadFailed();
    error SnapshotReadFailed();
    error RiskHealthFailed();
    error CustodyReadFailed();
    error YieldReadFailed();
    error WithdrawalPreviewFailed();
    error RewardQuoteFailed();

    address internal constant _ALICE = address(0xA11CE);
    address internal constant _BOB = address(0xB0B);
    address internal constant _CAROL = address(0xCA901);
    address internal constant _DAVE = address(0xDA9E);

    function _setCoreLifecycle(bool active_, bool enabled_) internal {
        if (!enabled_) _core.disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
    }

    function _position(address borrower_) internal view returns (IFLOANv1.Position memory p) {
        (, uint64 id) = _floan.getPositionIdForMarketAndBorrowerAt(
            _core.marketId(address(_asset)),
            borrower_,
            0
        );
        return _floan.getPosition(id);
    }

    function _seedDebt(address borrower_, uint128 collateral_, uint128 debt_) internal {
        _asset.mint(borrower_, uint256(collateral_) + 1000e6);
        vm.startPrank(borrower_);
        _asset.approve(address(_core), type(uint256).max);
        _collateral.depositCollateral(address(_asset), collateral_, borrower_);
        _debt.borrow(address(_asset), debt_, borrower_, borrower_, type(uint256).max);
        vm.stopPrank();
    }

    function _repay(address borrower_, uint128 amount_) internal {
        vm.roll(vm.getBlockNumber() + 1);
        vm.startPrank(borrower_);
        _ohm.approve(address(_core), type(uint256).max);
        _debt.repay(address(_asset), amount_, borrower_);
        vm.stopPrank();
    }

    function _default(address borrower_) internal {
        vm.warp(_position(borrower_).maturity);
        _price.setTimestamp(uint48(block.timestamp));
        _price.setPrice(address(_ohm), 1e18);
        _price.setPrice(address(_asset), 1e18);
        address[] memory borrowers = new address[](1);
        borrowers[0] = borrower_;
        _liquidation.seize(address(_asset), borrowers);
    }

    function _mockPosition(
        address borrower_,
        uint128 collateral_,
        uint128 debt_,
        uint48 maturity_,
        uint32 lastBlock_
    ) internal {
        uint32 market = _core.marketId(address(_asset));
        uint64 id = uint64(uint160(borrower_));
        vm.mockCall(
            address(_floan),
            abi.encodeCall(
                IFLOANv1.getPositionIdForMarketAndBorrowerAt,
                (market, borrower_, uint256(0))
            ),
            abi.encode(true, id)
        );
        IFLOANv1.Position memory p = IFLOANv1.Position(
            borrower_,
            market,
            collateral_,
            debt_,
            debt_,
            0,
            maturity_,
            lastBlock_
        );
        vm.mockCall(address(_floan), abi.encodeCall(IFLOANv1.getPosition, (id)), abi.encode(p));
    }

    function _snapshot() internal pure returns (IBurnerLoansCore.PriceSnapshot memory) {
        return IBurnerLoansCore.PriceSnapshot(2e18, 3e18, 1e18);
    }

    function _mockRisk(uint256 health_) internal {
        vm.mockCall(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.snapshot, (address(_asset))),
            abi.encode(_snapshot())
        );
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encode(health_)
        );
    }

    function _expectNoRiskReads() internal {
        vm.expectCall(address(_core), abi.encodeCall(IBurnerLoansCore.risk, ()), uint64(0));
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            uint64(0)
        );
    }

    function _mockCount(uint256 count_) internal {
        vm.mockCall(
            address(_floan),
            abi.encodeCall(IFLOANv1.getActiveBorrowerCount, (_core.marketId(address(_asset)))),
            abi.encode(count_)
        );
    }

    function _mockBorrowers(address[] memory borrowers_) internal {
        _mockCount(borrowers_.length);
        for (uint256 i; i < borrowers_.length; ++i)
            vm.mockCall(
                address(_floan),
                abi.encodeCall(IFLOANv1.getActiveBorrowerAt, (_core.marketId(address(_asset)), i)),
                abi.encode(borrowers_[i])
            );
    }

    function _canonicalScan() internal {
        address[] memory borrowers = new address[](4);
        borrowers[0] = _ALICE;
        borrowers[1] = _BOB;
        borrowers[2] = _CAROL;
        borrowers[3] = _DAVE;
        _mockBorrowers(borrowers);
        _mockPosition(_ALICE, 100e6, 10e9, uint48(block.timestamp), 1);
        _mockPosition(_BOB, 200e6, 20e9, uint48(block.timestamp + 1 days), 1);
        _mockPosition(_CAROL, 300e6, 30e9, uint48(block.timestamp + 1 days), 1);
        _mockPosition(_DAVE, 400e6, 40e9, uint48(block.timestamp + 1 days), 1);
        _mockRisk(2e18);
        vm.mockCall(
            address(_risk),
            abi.encodeCall(
                IBurnerLoansRisk.health,
                (_snapshot(), _core.marketId(address(_asset)), uint256(300e6), uint256(30e9))
            ),
            abi.encode(uint256(1e18 - 1))
        );
    }

    function _assertPosition(
        address caller_,
        address borrower_,
        uint256 collateral_,
        uint128 debt_,
        uint48 maturity_,
        uint48 lastBlock_
    ) internal {
        vm.recordLogs();
        vm.prank(caller_);
        IBurnerLoansCore.Position memory p = _lens.getPosition(address(_asset), borrower_);
        assertEq(p.depositedCollateral, collateral_, "Canonical collateral");
        assertEq(p.debtOhm, debt_, "Canonical principal");
        assertEq(p.maturity, maturity_, "Canonical maturity");
        assertEq(p.lastBorrowBlock, lastBlock_, "Canonical last borrow block");
        assertEq(vm.getRecordedLogs().length, 0, "Position view emits no logs");
    }

    function _assertBorrowers(address caller_, address[] memory expected_, uint256 debt_) internal {
        vm.recordLogs();
        vm.startPrank(caller_);
        address[] memory borrowers = _lens.getActiveBorrowers(address(_asset));
        uint256 principal = _lens.assetActiveDebtOhm(address(_asset));
        vm.stopPrank();
        assertEq(borrowers.length, expected_.length, "Unique borrower count");
        for (uint256 i; i < expected_.length; ++i) {
            uint256 matches;
            for (uint256 j; j < borrowers.length; ++j) if (borrowers[j] == expected_[i]) ++matches;
            assertEq(matches, 1, "Expected borrower occurs exactly once");
        }
        assertEq(principal, debt_, "Aggregate principal");
        assertEq(
            principal,
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            "Principal agrees with authoritative FLOAN"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Borrower views emit no logs");
    }

    function _one(address borrower_) internal pure returns (address[] memory borrowers) {
        borrowers = new address[](1);
        borrowers[0] = borrower_;
    }

    function _two(
        address first_,
        address second_
    ) internal pure returns (address[] memory borrowers) {
        borrowers = new address[](2);
        borrowers[0] = first_;
        borrowers[1] = second_;
    }

    function _replaceRisk() internal returns (BurnerLoansRisk replacement) {
        replacement = new BurnerLoansRisk(
            _kernel,
            IERC20(address(_ohm)),
            _risk.backingOracle(),
            address(0),
            0,
            address(_core)
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.setConfigOperator(address(_config));
        replacement.enable("");
        _core.setRisk(address(replacement));
    }

    function _seedOtherMarket(address borrower_, uint128 debt_) internal returns (MockERC20 other) {
        other = new MockERC20("Other market", "OTH", 6);
        _price.setPrice(address(other), 1e18);
        _admit(address(other));
        other.mint(borrower_, 10000e6);
        vm.startPrank(borrower_);
        other.approve(address(_core), type(uint256).max);
        _collateral.depositCollateral(address(other), 5000e6, borrower_);
        _debt.borrow(address(other), debt_, borrower_, borrower_, type(uint256).max);
        vm.stopPrank();
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
