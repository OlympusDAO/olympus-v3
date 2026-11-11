// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BackingOracle} from "src/policies/BackingOracle.sol";
import {BackingOracleConfigTimelock} from "src/policies/BackingOracleConfigTimelock.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BackingOracleSetBackingRiskIntegrationTest is BurnerLoansRiskTest {
    address internal constant _ADMIN = address(0xAD111);

    function setUp() public override {
        super.setUp();
        _rolesAdmin.grantRole(ADMIN_ROLE, _ADMIN);
        _rolesAdmin.revokeRole(ADMIN_ROLE, address(this));
    }

    // Scenarios: BO-SETBACKINGRISKINTEGRATION-03.
    function test_whenPriceScaleDiffers_roundsUp() public {
        BackingOracle oracle = new BackingOracle(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(oracle));
        vm.prank(_ADMIN);
        oracle.enable(abi.encode(uint256(1e18 + 1)));
        vm.prank(_ADMIN);
        _risk.setBackingOracle(address(oracle));
        _price.setPriceDecimals(8);
        _price.setPrice(address(_ohm), 3e8);
        _price.setPrice(address(_asset), 4e8);
        // ceil((1e18 + 1) * 1e8 / 1e18) = 100000001 (8 decimals).
        assertEq(
            _risk.snapshot(address(_asset)).backingPerOhmUsd,
            100000001,
            "protocol-favoring scale conversion"
        );
    }

    // Scenarios: BO-SETBACKINGRISKINTEGRATION-01.
    function test_whenRealOracleSelected() public {
        BackingOracle oracle = new BackingOracle(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(oracle));
        vm.prank(_ADMIN);
        oracle.enable(abi.encode(15e18));
        vm.prank(_ADMIN);
        _risk.setBackingOracle(address(oracle));
        IBurnerLoansCore.PriceSnapshot memory p = _risk.snapshot(address(_asset));
        assertEq(p.backingPerOhmUsd, 15e18, "18 decimal backing consumed directly");
        vm.prank(_ADMIN);
        oracle.setBacking(16e18);
        assertEq(_risk.snapshot(address(_asset)).backingPerOhmUsd, 16e18, "live ADMIN update");
        BackingOracleConfigTimelock timelock = new BackingOracleConfigTimelock(
            _kernel,
            IBackingOracle(address(oracle))
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(timelock));
        vm.prank(_ADMIN);
        oracle.setConfigOperator(address(timelock));
        vm.prank(_ADMIN);
        timelock.enable("");
        vm.prank(_ADMIN);
        uint64 id = timelock.queueSetBacking(17e18);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        // Refresh module price timestamps after the notice period.
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        _price.setPrice(address(_ohm), 1e18);
        _price.setPrice(address(_asset), 2e18);
        timelock.executeQueuedAction(id);
        assertEq(_risk.snapshot(address(_asset)).backingPerOhmUsd, 17e18, "live queued update");
        vm.prank(_ADMIN);
        oracle.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(oracle));
        assertEq(oracle.backing(), 17e18, "oracle getter remains readable");
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(oracle)
            )
        );
        // The expected revert prevents a snapshot return value.
        // forge-lint: disable-next-line(unused-return)
        _risk.snapshot(address(_asset));
    }

    // Scenarios: BO-SETBACKINGRISKINTEGRATION-02.
    function test_whenRealOracleInConstructor() public {
        BackingOracle oracle = new BackingOracle(_kernel);
        BurnerLoansRisk risk = new BurnerLoansRisk(
            _kernel,
            IERC20(address(_ohm)),
            address(oracle),
            address(0),
            60,
            address(this)
        );
        assertEq(
            risk.backingOracle(),
            address(oracle),
            "constructor accepts real uninitialized oracle"
        );
    }
}
