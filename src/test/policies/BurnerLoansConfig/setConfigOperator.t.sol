// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigSetConfigOperatorTest is BurnerLoansConfigTest {
    // Scenarios: BLCFG-CONFIG-OPERATOR-A01.
    function test_whenCallerIsNotAdmin_reverts(address caller_, address next_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.setConfigOperator, (next_)),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: BLCFG-CONFIG-OPERATOR-A02, BLCFG-CONFIG-OPERATOR-L04, BLCFG-CONFIG-OPERATOR-P03.
    function test_givenAdmin_whenOperatorChanged(address caller_, address next_) public {
        vm.assume(next_ != _configurationCaller);
        _grantAdmin(caller_);
        bytes32 funds = _economicDigest();
        vm.expectEmit(address(_config));
        emit IConfigOperator.ConfigOperatorSet(next_);
        vm.prank(caller_);
        _config.setConfigOperator(next_);
        assertEq(_config.configOperator(), next_, "Exact delegated operator");
        assertEq(_economicDigest(), funds, "Authority update preserves funds and loans");
    }

    // Scenarios: BLCFG-CONFIG-OPERATOR-P02.
    function test_whenOperatorCleared() public {
        _config.setConfigOperator(address(0));
        assertEq(_config.configOperator(), address(0), "Cleared operator");
        _mutationReverts(
            _configurationCaller,
            _capCall(1),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        _mutationReverts(
            address(0),
            _capCall(1),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: BLCFG-CONFIG-OPERATOR-P01.
    function test_whenSameOperatorSelected_reverts() public {
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.setConfigOperator, (_configurationCaller)),
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unchanged.selector)
        );
        _config.setConfigOperator(address(0));
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.setConfigOperator, (address(0))),
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unchanged.selector)
        );
    }

    // Scenarios: BLCFG-CONFIG-OPERATOR-L01.
    function test_givenActiveDisabled_whenOperatorChanged_reverts(
        address caller_,
        address next_
    ) public givenConfigDisabled {
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.setConfigOperator, (next_)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFG-CONFIG-OPERATOR-L03.
    function test_givenInactiveEnabled_whenOperatorChanged_reverts(
        address caller_,
        address next_
    ) public givenConfigInactive {
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.setConfigOperator, (next_)),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFG-CONFIG-OPERATOR-L05.
    function test_givenInactiveDisabled_whenOperatorChanged_reverts(
        address caller_,
        address next_
    ) public givenConfigDisabled givenConfigInactive {
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.setConfigOperator, (next_)),
            _inactiveError(address(_config))
        );
    }
}
