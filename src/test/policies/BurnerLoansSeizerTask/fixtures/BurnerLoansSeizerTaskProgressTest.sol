// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";

// Libraries
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {BurnerLoansLensTest} from "src/test/policies/BurnerLoansLens/BurnerLoansLensTest.sol";

/// @dev Real Core/FLOAN/Seize deployment, independent of the legacy task fixture.
abstract contract BurnerLoansSeizerTaskProgressTest is BurnerLoansLensTest {
    BurnerLoansSeizerTask internal _task;
    MockERC20 internal _otherAsset;

    function setUp() public virtual override {
        super.setUp();
        _otherAsset = new MockERC20("Other", "OTH", 6);
        _price.setPrice(address(_otherAsset), 1e18);
        _admit(address(_otherAsset));
        _rolesAdmin.grantRole(HEART_ROLE, address(this));
        _task = _newTask();
    }

    function _newTask() internal returns (BurnerLoansSeizerTask task) {
        task = new BurnerLoansSeizerTask(
            _kernel,
            _liquidation,
            IBurnerLoansLens(address(_lens)),
            500,
            25,
            10_000_000
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(task));
        _rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(task));
        task.enable("");
    }

    function _mature() internal {
        vm.warp(vm.getBlockTimestamp() + 31 days);
        // Fixture time is a contemporary timestamp plus a fixed 31-day term.
        // forge-lint: disable-next-line(unsafe-typecast)
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
    }

    function _boundedScan(address asset_, uint256 start_) internal view returns (bytes memory) {
        return
            abi.encodeCall(
                IBurnerLoansLens.getSeizableBorrowersBoundedFor,
                (
                    address(_task),
                    asset_,
                    start_,
                    uint256(_task.maxBorrowersToCheck()),
                    uint256(_task.maxBorrowersToSeize())
                )
            );
    }
}
