// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskSupportsInterfaceTest is BurnerLoansRiskTest {
    function _interfaces(address caller_) private {
        bytes4[10] memory ids = [
            type(IBurnerLoansRisk).interfaceId,
            type(IVersioned).interfaceId,
            type(IEnabler).interfaceId,
            type(IEnablerV2).interfaceId,
            type(IReEnabler).interfaceId,
            type(IGracePeriod).interfaceId,
            type(IERC165).interfaceId,
            type(IConfigOperator).interfaceId,
            bytes4(0xffffffff),
            type(IBurnerLoansCoreBound).interfaceId
        ];
        for (uint256 i; i < 8; ++i) {
            vm.prank(caller_);
            assertTrue(_risk.supportsInterface(ids[i]), "supported public interface");
        }
        vm.prank(caller_);
        assertFalse(_risk.supportsInterface(ids[8]), "invalid interface rejected");
        vm.prank(caller_);
        assertTrue(_risk.supportsInterface(ids[9]), "Immutable Core binding interface");
        vm.prank(caller_);
        (uint8 major, uint8 minor) = _risk.VERSION();
        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
    }

    // Scenarios: BLRISK-CONSTRUCTOR-V01, BLRISK-CONSTRUCTOR-V02, BLRISK-CONSTRUCTOR-V03, BLRISK-CONSTRUCTOR-V04, BLRISK-CONSTRUCTOR-V05, BLRISK-CONSTRUCTOR-V06, BLRISK-CONSTRUCTOR-V07, BLRISK-CONSTRUCTOR-V08, BLRISK-CONSTRUCTOR-V10, BLRISK-ERC165-P01.
    function test_givenOperational_whenInterfacesQueried(address caller_) public {
        _interfaces(caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-V01, BLRISK-CONSTRUCTOR-V02, BLRISK-CONSTRUCTOR-V03, BLRISK-CONSTRUCTOR-V04, BLRISK-CONSTRUCTOR-V05, BLRISK-CONSTRUCTOR-V06, BLRISK-CONSTRUCTOR-V07, BLRISK-CONSTRUCTOR-V08, BLRISK-CONSTRUCTOR-V10, BLRISK-ERC165-P01.
    function test_givenDisabled_whenInterfacesQueried(address caller_) public givenDisabled {
        _interfaces(caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-V01, BLRISK-CONSTRUCTOR-V02, BLRISK-CONSTRUCTOR-V03, BLRISK-CONSTRUCTOR-V04, BLRISK-CONSTRUCTOR-V05, BLRISK-CONSTRUCTOR-V06, BLRISK-CONSTRUCTOR-V07, BLRISK-CONSTRUCTOR-V08, BLRISK-CONSTRUCTOR-V10, BLRISK-ERC165-P01.
    function test_givenInactive_whenInterfacesQueried(address caller_) public givenInactive {
        _interfaces(caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-V01, BLRISK-CONSTRUCTOR-V02, BLRISK-CONSTRUCTOR-V03, BLRISK-CONSTRUCTOR-V04, BLRISK-CONSTRUCTOR-V05, BLRISK-CONSTRUCTOR-V06, BLRISK-CONSTRUCTOR-V07, BLRISK-CONSTRUCTOR-V08, BLRISK-CONSTRUCTOR-V10, BLRISK-ERC165-P01.
    function test_givenInactiveAndDisabled_whenInterfacesQueried(
        address caller_
    ) public givenDisabled givenInactive {
        _interfaces(caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-V01, BLRISK-CONSTRUCTOR-V02, BLRISK-CONSTRUCTOR-V03, BLRISK-CONSTRUCTOR-V04, BLRISK-CONSTRUCTOR-V05, BLRISK-CONSTRUCTOR-V06, BLRISK-CONSTRUCTOR-V07, BLRISK-CONSTRUCTOR-V08, BLRISK-CONSTRUCTOR-V10, BLRISK-ERC165-P01.
    function test_givenReEnabled_whenInterfacesQueried(address caller_) public givenReEnabled {
        _interfaces(caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-V08.
    function test_whenInterfaceIsUnknown(address caller_, bytes4 id_) public {
        vm.assume(id_ != bytes4(0xffffffff));
        vm.assume(
            id_ != type(IBurnerLoansRisk).interfaceId &&
                id_ != type(IVersioned).interfaceId &&
                id_ != type(IEnabler).interfaceId &&
                id_ != type(IEnablerV2).interfaceId &&
                id_ != type(IReEnabler).interfaceId &&
                id_ != type(IGracePeriod).interfaceId &&
                id_ != type(IERC165).interfaceId &&
                id_ != type(IConfigOperator).interfaceId &&
                id_ != type(IBurnerLoansCoreBound).interfaceId
        );
        vm.prank(caller_);
        assertFalse(_risk.supportsInterface(id_), "unknown interface");
    }
}
