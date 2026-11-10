// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansRiskHandler} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskHandler.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskOperatorInvariantTest is BurnerLoansRiskTest {
    BurnerLoansRiskHandler internal _handler;

    function setUp() public override {
        super.setUp();
        _handler = new BurnerLoansRiskHandler(_risk, address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_handler));
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = _handler.selectOperator.selector;
        selectors[1] = _handler.setAgeAsAdmin.selector;
        selectors[2] = _handler.setAgeAsOperator.selector;
        selectors[3] = _handler.attemptUnauthorizedAge.selector;
        selectors[4] = _handler.pause.selector;
        selectors[5] = _handler.enable.selector;
        selectors[6] = _handler.setBackingEnabled.selector;
        selectors[7] = _handler.setBackingActive.selector;
        targetContract(address(_handler));
        targetSelector(FuzzSelector(address(_handler), selectors));
    }

    // Scenarios: BLRISK-CONFIGURATOR-S01.
    function invariant_selectedAuthorityAndAgeFollowAuthorizedActions() public view {
        assertEq(
            _risk.configOperator(),
            _handler.expectedOperator(),
            "latest authorized controller"
        );
        assertEq(_risk.priceCacheMaxAge(), _handler.expectedAge(), "latest authorized age");
        assertEq(
            _risk.isEnabled(),
            _handler.expectedEnabled(),
            "lifecycle changes only through transitions"
        );
        assertEq(_risk.backingOracle(), address(_oracle), "oracle remains unchanged");
        assertEq(_risk.priceCache(), address(0), "cache remains unchanged");
    }

    // Scenarios: BLRISK-SNAPSHOT-S01.
    function invariant_backingConsumptionRequiresReadiness() public {
        if (!_risk.isEnabled()) return;
        if (!_kernel.isPolicyActive(_oracle) || !_oracle.isEnabled()) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    PolicyDependency.PolicyDependency_NotActive.selector,
                    address(_oracle)
                )
            );
            _risk.snapshot(address(_asset));
            return;
        }
        assertEq(
            _risk.snapshot(address(_asset)).backingPerOhmUsd,
            1e18,
            "ready backing remains consumable across lifecycle sequences"
        );
    }
}
