// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";

contract BurnerLoansConfigSupportsInterfaceTest is BurnerLoansConfigTest {
    // Scenarios: BLCFG-ERC165-P01.
    function test_whenConfigInterfaceQueried(address caller_, bool active_, bool enabled_) public {
        _setPolicyState(_config, active_, enabled_);
        vm.prank(caller_);
        assertTrue(
            _config.supportsInterface(type(IBurnerLoansConfig).interfaceId),
            "Advertised Config interface"
        );
    }

    // Scenarios: BLCFG-ERC165-P02.
    function test_whenOperatorInterfaceQueried(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_config, active_, enabled_);
        vm.prank(caller_);
        assertTrue(
            _config.supportsInterface(type(IConfigOperator).interfaceId),
            "Advertised Operator interface"
        );
    }

    // Scenarios: BLCFG-ERC165-P03.
    function test_whenVersionInterfaceQueried(address caller_, bool active_, bool enabled_) public {
        _setPolicyState(_config, active_, enabled_);
        vm.prank(caller_);
        assertTrue(
            _config.supportsInterface(type(IVersioned).interfaceId),
            "Advertised Version interface"
        );
    }

    // Scenarios: BLCFG-ERC165-P04.
    function test_whenERC165InterfaceQueried(address caller_, bool active_, bool enabled_) public {
        _setPolicyState(_config, active_, enabled_);
        vm.prank(caller_);
        assertTrue(
            _config.supportsInterface(type(IERC165).interfaceId),
            "Advertised ERC165 interface"
        );
    }

    // Scenarios: BLCFG-ERC165-P05.
    function test_whenEnablerInterfaceQueried(address caller_, bool active_, bool enabled_) public {
        _setPolicyState(_config, active_, enabled_);
        vm.prank(caller_);
        assertTrue(
            _config.supportsInterface(type(IEnabler).interfaceId),
            "Advertised Enabler interface"
        );
    }

    // Scenarios: BLCFG-ERC165-P06.
    function test_whenEnablerV2InterfaceQueried(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_config, active_, enabled_);
        vm.prank(caller_);
        assertTrue(
            _config.supportsInterface(type(IEnablerV2).interfaceId),
            "Advertised EnablerV2 interface"
        );
    }

    // Scenarios: BLCFG-ERC165-P07.
    function test_whenReEnablerInterfaceQueried(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_config, active_, enabled_);
        vm.prank(caller_);
        assertTrue(
            _config.supportsInterface(type(IReEnabler).interfaceId),
            "Advertised ReEnabler interface"
        );
    }

    // Scenarios: BLCFG-ERC165-P08.
    function test_whenGraceInterfaceQueried(address caller_, bool active_, bool enabled_) public {
        _setPolicyState(_config, active_, enabled_);
        vm.prank(caller_);
        assertTrue(
            _config.supportsInterface(type(IGracePeriod).interfaceId),
            "Advertised Grace interface"
        );
    }

    // Scenarios: BLCFG-ERC165-P12.
    function test_whenCoreBindingInterfaceQueried(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_config, active_, enabled_);
        vm.prank(caller_);
        assertTrue(
            _config.supportsInterface(type(IBurnerLoansCoreBound).interfaceId),
            "Immutable Core binding interface"
        );
    }

    // Scenarios: BLCFG-ERC165-P09.
    function test_whenInvalidInterfaceQueried(address caller_, bool active_, bool enabled_) public {
        _setPolicyState(_config, active_, enabled_);
        vm.prank(caller_);
        assertFalse(_config.supportsInterface(0xffffffff), "Unsupported interface");
    }

    // Scenarios: BLCFG-ERC165-P10.
    function test_whenZeroInterfaceQueried(address caller_, bool active_, bool enabled_) public {
        _setPolicyState(_config, active_, enabled_);
        vm.prank(caller_);
        assertFalse(_config.supportsInterface(0x00000000), "Unsupported interface");
    }

    // Scenarios: BLCFG-ERC165-P11.
    function test_whenUnknownInterfaceQueried(
        address caller_,
        bytes4 id_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_config, active_, enabled_);
        vm.assume(id_ != type(IBurnerLoansConfig).interfaceId);
        vm.assume(id_ != type(IConfigOperator).interfaceId);
        vm.assume(id_ != type(IVersioned).interfaceId);
        vm.assume(id_ != type(IERC165).interfaceId);
        vm.assume(id_ != type(IEnabler).interfaceId);
        vm.assume(id_ != type(IEnablerV2).interfaceId);
        vm.assume(id_ != type(IReEnabler).interfaceId);
        vm.assume(id_ != type(IGracePeriod).interfaceId);
        vm.assume(id_ != type(IBurnerLoansCoreBound).interfaceId && id_ != 0 && id_ != 0xffffffff);
        vm.prank(caller_);
        assertFalse(_config.supportsInterface(id_), "No speculative interface support");
    }
}
