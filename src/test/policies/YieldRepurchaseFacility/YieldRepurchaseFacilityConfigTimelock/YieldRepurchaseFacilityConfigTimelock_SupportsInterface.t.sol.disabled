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
import {IYieldRepurchaseFacilityConfigTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityConfigTimelock.sol";

import {YieldRepurchaseFacilityConfigTimelockTestBase} from "src/test/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityConfigTimelock/YieldRepurchaseFacilityConfigTimelockTestBase.sol";

contract YieldRepurchaseFacilityConfigTimelockTests_SupportsInterface is
    YieldRepurchaseFacilityConfigTimelockTestBase
{
    // supportsInterface
    // given the advertised interface set (IYieldRepurchaseFacilityConfigTimelock, ITimelockBatchQueue, IVersioned,
    //   IEnablerV2, IEnabler, IReEnabler, IGracePeriod, IERC165)
    //  when querying each identifier
    //   then it returns true
    function test_givenSupportedInterfaces_returnsTrue() public view {
        assertTrue(
            configTimelock.supportsInterface(
                type(IYieldRepurchaseFacilityConfigTimelock).interfaceId
            ),
            "IYieldRepurchaseFacilityConfigTimelock"
        );
        assertTrue(
            configTimelock.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            "ITimelockBatchQueue"
        );
        assertTrue(configTimelock.supportsInterface(type(IVersioned).interfaceId), "IVersioned");
        assertTrue(configTimelock.supportsInterface(type(IEnablerV2).interfaceId), "IEnablerV2");
        assertTrue(configTimelock.supportsInterface(type(IEnabler).interfaceId), "IEnabler");
        assertTrue(configTimelock.supportsInterface(type(IReEnabler).interfaceId), "IReEnabler");
        assertTrue(
            configTimelock.supportsInterface(type(IGracePeriod).interfaceId),
            "IGracePeriod"
        );
        assertTrue(configTimelock.supportsInterface(type(IERC165).interfaceId), "IERC165");
    }

    // supportsInterface
    // given an unsupported interface identifier (including 0xffffffff)
    //  when querying it
    //   then it returns false
    function test_givenUnsupportedInterface_returnsFalse() public view {
        assertFalse(configTimelock.supportsInterface(0xffffffff), "0xffffffff");
        assertFalse(
            configTimelock.supportsInterface(type(IYieldRepurchaseFacilityV2).interfaceId),
            "IYieldRepurchaseFacilityV2"
        );
    }

    // supportsInterface
    // given the zero interface identifier
    //  when querying it
    //   then it returns false (regression: no function-less interfaceId is advertised)
    function test_givenZeroInterfaceId_returnsFalse() public view {
        assertFalse(configTimelock.supportsInterface(bytes4(0)), "0x00000000");
    }
}
