// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, EMERGENCY_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {MockSeizerTaskDependency} from "./fixtures/MockSeizerTaskDependency.sol";
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {BurnerLoansSeize} from "src/policies/burnerloans/BurnerLoansSeize.sol";
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

abstract contract BurnerLoansSeizerTaskTest is Test {
    address internal constant _ALICE = address(0xA11CE);
    address internal constant _BOB = address(0xB0B);
    address internal constant _DAVE = address(0xDA9E);
    uint32 internal constant _EXECUTION_GAS_LIMIT = 10_000_000;
    uint32 internal constant _GRACE_PERIOD = 7 days;

    Kernel internal _kernel;
    OlympusRoles internal _roles;
    RolesAdmin internal _rolesAdmin;
    MockSeizerTaskDependency internal _core;
    BurnerLoansSeize internal _liquidation;
    IBurnerLoansLens internal _lens;
    BurnerLoansSeizerTask internal _task;
    MockERC20 internal _asset;
    MockERC20 internal _otherAsset;

    function setUp() public virtual {
        _kernel = new Kernel();
        _roles = new OlympusRoles(_kernel);
        _rolesAdmin = new RolesAdmin(_kernel);
        _core = new MockSeizerTaskDependency(_kernel, address(0));
        _liquidation = BurnerLoansSeize(
            address(new MockSeizerTaskDependency(_kernel, address(_core)))
        );
        _lens = IBurnerLoansLens(address(new MockSeizerTaskDependency(_kernel, address(_core))));
        _asset = new MockERC20("Asset", "AST", 6);
        _otherAsset = new MockERC20("Other", "OTH", 6);
        _core.setAssetRegistered(address(_asset), true);
        _core.setAssetRegistered(address(_otherAsset), true);
        _kernel.executeAction(Actions.InstallModule, address(_roles));
        _kernel.executeAction(Actions.ActivatePolicy, address(_rolesAdmin));
        _kernel.executeAction(Actions.ActivatePolicy, address(_core));
        _kernel.executeAction(Actions.ActivatePolicy, address(_liquidation));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(this));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, address(this));
        _rolesAdmin.grantRole(HEART_ROLE, address(this));
        _task = new BurnerLoansSeizerTask(
            _kernel,
            _liquidation,
            _lens,
            500,
            25,
            _EXECUTION_GAS_LIMIT
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(_task));
        _rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(_task));
        _task.enable("");
    }

    modifier givenTaskDisabled() {
        _setTaskEnabled(false);
        _;
    }

    modifier givenTaskReEnabled() {
        _setTaskEnabled(false);
        _task.reEnable();
        _;
    }

    function _setTaskEnabled(bool enabled_) internal {
        if (_task.isEnabled() == enabled_) return;
        if (enabled_) _task.enable("");
        else _task.disable("");
    }

    function _setPolicyActive(address policy_, bool active_) internal {
        if (_kernel.isPolicyActive(Policy(policy_)) == active_) return;
        _kernel.executeAction(active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy, policy_);
    }

    function _grantTaskAdmin(address caller_, uint8 roleClass_) internal {
        vm.assume(caller_ != address(0));
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        if (roleClass_ != 1) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (roleClass_ != 0) _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
    }

    function _setCoreLifecycle(bool active_, bool enabled_) internal {
        if (!enabled_) _core.disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
    }

    function _mockCount(uint256 population_) internal {
        MockSeizerTaskDependency(address(_lens)).setPopulation(address(_asset), population_);
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

    function _one(address account_) internal pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account_;
    }

    function _two(
        address first_,
        address second_
    ) internal pure returns (address[] memory accounts) {
        accounts = new address[](2);
        accounts[0] = first_;
        accounts[1] = second_;
    }
}
