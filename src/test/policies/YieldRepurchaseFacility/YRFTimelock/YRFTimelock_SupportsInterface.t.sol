// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYRFTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYRFTimelock.sol";

import {YRFTimelockTestBase} from "src/test/policies/YieldRepurchaseFacility/YRFTimelock/YRFTimelockTestBase.sol";

contract YRFTimelockTests_SupportsInterface is YRFTimelockTestBase {
    // supportsInterface
    // given the advertised interface set (IYRFTimelock, ITimelockBatchQueue, IVersioned,
    //   IEnablerV2, IEnabler, IReEnabler, IGracePeriod, IERC165)
    //  when querying each identifier
    //   then it returns true
    function test_givenSupportedInterfaces_returnsTrue() public view {
        assertTrue(
            yrfTimelock.supportsInterface(type(IYRFTimelock).interfaceId),
            "IYRFTimelock"
        );
        assertTrue(
            yrfTimelock.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            "ITimelockBatchQueue"
        );
        assertTrue(yrfTimelock.supportsInterface(type(IVersioned).interfaceId), "IVersioned");
        assertTrue(yrfTimelock.supportsInterface(type(IEnablerV2).interfaceId), "IEnablerV2");
        assertTrue(yrfTimelock.supportsInterface(type(IEnabler).interfaceId), "IEnabler");
        assertTrue(yrfTimelock.supportsInterface(type(IReEnabler).interfaceId), "IReEnabler");
        assertTrue(yrfTimelock.supportsInterface(type(IGracePeriod).interfaceId), "IGracePeriod");
        assertTrue(yrfTimelock.supportsInterface(type(IERC165).interfaceId), "IERC165");
    }

    // supportsInterface
    // given an unsupported interface identifier (including 0xffffffff)
    //  when querying it
    //   then it returns false
    function test_givenUnsupportedInterface_returnsFalse() public view {
        assertFalse(yrfTimelock.supportsInterface(0xffffffff), "0xffffffff");
        assertFalse(
            yrfTimelock.supportsInterface(type(IYieldRepurchaseFacilityV2).interfaceId),
            "IYieldRepurchaseFacilityV2"
        );
    }

    // supportsInterface
    // given the zero interface identifier
    //  when querying it
    //   then it returns false (regression: no function-less interfaceId is advertised)
    function test_givenZeroInterfaceId_returnsFalse() public view {
        assertFalse(yrfTimelock.supportsInterface(bytes4(0)), "0x00000000");
    }
}
