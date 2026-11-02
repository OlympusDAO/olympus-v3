// SPDX-License-Identifier: AGPL-3.0
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
    function test_givenTaskCheckLimitAboveSettlementLimit_whenExecuted() public {
        BurnerLoansSeizerTask task = _task(500);
        vm.mockCall(
            address(_lens),
            abi.encodeCall(
                IBurnerLoansLens.getSeizableBorrowersBoundedFor,
                (address(task), address(_asset), uint256(0), uint256(500), uint256(50))
            ),
            abi.encode(new address[](0), uint256(0), uint256(0))
        );
        vm.expectCall(
            address(_lens),
            abi.encodeCall(
                IBurnerLoansLens.getSeizableBorrowersBoundedFor,
                (address(task), address(_asset), uint256(0), uint256(500), uint256(50))
            ),
            uint64(1)
        );
        task.execute();
    }

    function test_givenStaleTaskCursor_whenNextTicksRun_thenEligibleBorrowerRemainsReachable()
        public
    {
        _seedDebt(_ALICE, 10e6, 1e9);
        vm.warp(_position(_ALICE).maturity);
        _price.setTimestamp(uint48(block.timestamp));
        BurnerLoansSeizerTask task = _task(500);
        vm.mockCall(
            address(_lens),
            abi.encodeCall(
                IBurnerLoansLens.getSeizableBorrowersBoundedFor,
                (address(task), address(_asset), uint256(0), uint256(500), uint256(50))
            ),
            abi.encode(new address[](0), uint256(3), uint256(0))
        );
        task.execute();
        assertEq(
            task.assetCursor(address(_asset)),
            3,
            "Retained cursor predates borrower-list shrinkage"
        );
        vm.clearMockedCalls();
        task.execute();
        assertEq(
            task.assetCursor(address(_asset)),
            0,
            "Invalid start is repaired and processed in the same tick"
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
            IBurnerLoansLens.getSeizableBorrowersBoundedFor,
            (address(task), address(_asset), uint256(0), uint256(50), uint256(50))
        );
        vm.mockCall(address(_lens), callData, abi.encode(new address[](0), uint256(0), uint256(0)));
        vm.expectCall(address(_lens), callData, uint64(1));
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
        _kernel.executeAction(Actions.ActivatePolicy, address(task));
        _rolesAdmin.grantRole(HEART_ROLE, address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(task));
        task.enable("");
        task.addAsset(address(_asset));
        return task;
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
