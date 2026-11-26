// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces

import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";

// Libraries
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";
import {Actions} from "src/Kernel.sol";

import {BurnerLoansLensTest} from "./BurnerLoansLensTest.sol";

// Explicit boundary values and casts model the declared fixture domains.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)

contract BurnerLoansLensGetSeizableBorrowersTaskIntegrationTest is BurnerLoansLensTest {
    address internal _seizerHeart;

    function test_givenTaskCheckLimitAboveSettlementLimit_whenExecuted() public {
        BurnerLoansSeizerTask task = _task(500);
        vm.mockCall(
            address(_lens),
            abi.encodeCall(
                IBurnerLoansLens.getUnhealthyBorrowersBoundedFor,
                (address(task), address(_asset), uint256(0), uint256(500), uint256(50))
            ),
            abi.encode(new address[](0), uint256(0), uint256(0))
        );
        vm.expectCall(
            address(_lens),
            abi.encodeCall(
                IBurnerLoansLens.getUnhealthyBorrowersBoundedFor,
                (address(task), address(_asset), uint256(0), uint256(500), uint256(50))
            ),
            uint64(1)
        );
        vm.prank(_seizerHeart);
        task.execute();
    }

    function test_givenStaleTaskCursor_whenNextTicksRun_thenEligibleBorrowerRemainsReachable()
        public
    {
        _seedDebt(_ALICE, 10e6, 1e9);
        BurnerLoansSeizerTask task = _task(500);
        vm.mockCall(
            address(_lens),
            abi.encodeCall(
                IBurnerLoansLens.getUnhealthyBorrowersBoundedFor,
                (address(task), address(_asset), uint256(0), uint256(500), uint256(50))
            ),
            abi.encode(new address[](0), uint256(3), uint256(0))
        );
        vm.prank(_seizerHeart);
        task.execute();
        assertEq(
            task.unhealthyAssetCursor(address(_asset)),
            3,
            "Retained cursor predates borrower-list shrinkage"
        );
        assertEq(
            task.expiredAssetCursor(address(_asset)),
            0,
            "Expiry page independently wrapped before maturity"
        );
        assertEq(_inventory.activePrincipalOhm(), 1e9, "Debt remains before stale-cursor recovery");
        assertEq(
            _lens.getActiveBorrowerCount(address(_asset)),
            1,
            "Saved offset exceeds live count"
        );
        vm.clearMockedCalls();
        vm.warp(_position(_ALICE).maturity);
        _price.setTimestamp(uint48(block.timestamp));
        vm.prank(_seizerHeart);
        task.execute();
        assertEq(
            task.expiredAssetCursor(address(_asset)),
            0,
            "Expiry lane processes the current page in the same tick"
        );
        assertEq(
            task.unhealthyAssetCursor(address(_asset)),
            0,
            "Stale unhealthy offset is independently repaired"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            0,
            "Recovery tick settles remaining expired debt"
        );
        assertEq(
            _lens.getPosition(address(_asset), _ALICE).debtOhm,
            0,
            "No permanently stranded borrower"
        );
    }

    function test_givenTaskEqualLimits_whenExecuted() public {
        BurnerLoansSeizerTask task = _task(50);
        bytes memory callData = abi.encodeCall(
            IBurnerLoansLens.getUnhealthyBorrowersBoundedFor,
            (address(task), address(_asset), uint256(0), uint256(50), uint256(50))
        );
        vm.mockCall(address(_lens), callData, abi.encode(new address[](0), uint256(0), uint256(0)));
        vm.expectCall(address(_lens), callData, uint64(1));
        vm.prank(_seizerHeart);
        task.execute();
    }

    function _task(uint16 checks_) internal returns (BurnerLoansSeizerTask task) {
        task = new BurnerLoansSeizerTask(
            _kernel,
            _liquidation,
            IBurnerLoansLens(address(_lens)),
            checks_,
            50,
            2_000_000
        );
        _executeFixtureKernelAction(Actions.ActivatePolicy, address(task));
        _seizerHeart = makeAddr("seizerHeart");
        _grantFixtureRole(HEART_ROLE, _seizerHeart);
        _grantFixtureRole(BURNER_LOANS_SEIZER_ROLE, address(task));
        vm.prank(_fixtureAdmin);
        task.enable("");
        vm.prank(_fixtureAdmin);
        task.addAsset(address(_asset));
        return task;
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
