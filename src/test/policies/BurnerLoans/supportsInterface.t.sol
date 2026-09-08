// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {IBurnerLoansSeizureContext} from "src/policies/interfaces/IBurnerLoansSeizureContext.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/IBurnerLoansYieldClaim.sol";
import {IYieldRepurchaseRecipient} from "src/policies/interfaces/IYieldRepurchaseRecipient.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";
import {MockYieldRepurchaseRecipient} from "./fixtures/MockYieldRepurchaseRecipient.sol";

contract BurnerLoansSupportsInterfaceTest is BurnerLoansTest {
    // supportsInterface
    // given interface ids are expected for BurnerLoans
    //  when supportsInterface is called
    //   then supported ids return true and unrelated ids return false
    function test_supportsInterface_givenSupportedInterfaces_returnsTrue() public view {
        assertTrue(burnerLoans.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(burnerLoans.supportsInterface(type(IEnabler).interfaceId), "IEnabler");
        assertTrue(burnerLoans.supportsInterface(type(IEnablerV2).interfaceId), "IEnablerV2");
        assertTrue(burnerLoans.supportsInterface(type(IGracePeriod).interfaceId), "IGracePeriod");
        assertTrue(burnerLoans.supportsInterface(type(IReEnabler).interfaceId), "IReEnabler");
        assertTrue(burnerLoans.supportsInterface(type(IVersioned).interfaceId), "IVersioned");
        assertTrue(burnerLoans.supportsInterface(type(IOperatorAuth).interfaceId), "IOperatorAuth");
        assertTrue(
            burnerLoans.supportsInterface(type(IBurnerLoansLifecycle).interfaceId),
            "IBurnerLoansLifecycle"
        );
        assertTrue(
            burnerLoans.supportsInterface(type(IBurnerLoansSeizureContext).interfaceId),
            "IBurnerLoansSeizureContext"
        );
        assertTrue(
            burnerLoans.supportsInterface(type(IBurnerLoansView).interfaceId),
            "IBurnerLoansView"
        );
        assertTrue(
            burnerLoans.supportsInterface(type(IBurnerLoansYieldClaim).interfaceId),
            "IBurnerLoansYieldClaim"
        );
        assertFalse(
            burnerLoans.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            "BurnerLoans ITimelockBatchQueue"
        );
    }

    function test_whenYieldRepurchaseRecipientInterfaceIsQueried_preservesSelectorSet()
        public
        pure
    {
        bytes4 expectedInterfaceId = IYieldRepurchaseRecipient.getVaults.selector ^
            IYieldRepurchaseRecipient.getVaultConfig.selector;

        assertEq(
            type(IYieldRepurchaseRecipient).interfaceId,
            expectedInterfaceId,
            "IYieldRepurchaseRecipient selector set"
        );
    }

    function test_givenYieldRepurchaseRecipientMock_whenInterfaceIsQueried_advertisesInterface()
        public
    {
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);

        assertTrue(
            recipient.supportsInterface(type(IYieldRepurchaseRecipient).interfaceId),
            "mock IYieldRepurchaseRecipient"
        );
        assertFalse(
            recipient.supportsInterface(type(IBurnerLoansLifecycle).interfaceId),
            "mock unrelated interface"
        );
    }
}
