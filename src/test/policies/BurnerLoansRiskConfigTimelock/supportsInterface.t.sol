// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";

contract BurnerLoansRiskConfigTimelockSupportsInterfaceTest is BurnerLoansRiskConfigTimelockTest {
    // Scenarios: BLRCT-ERC165-P01.
    function test_whenAdvertisedInterfacesQueried(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setState(_timelock, active_, enabled_);
        bytes4[9] memory ids = [
            type(IBurnerLoansRiskConfigTimelock).interfaceId,
            type(IVersioned).interfaceId,
            type(ITimelockBatchQueue).interfaceId,
            type(IConfigTimelockBatchQueue).interfaceId,
            type(IERC165).interfaceId,
            type(IEnabler).interfaceId,
            type(IEnablerV2).interfaceId,
            type(IReEnabler).interfaceId,
            type(IGracePeriod).interfaceId
        ];
        vm.mockCallRevert(address(_risk), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        for (uint256 i; i < ids.length; ++i) {
            vm.prank(caller_);
            assertTrue(
                _timelock.supportsInterface(ids[i]),
                "advertised interface independent of lifecycle"
            );
        }
    }

    // Scenarios: BLRCT-ERC165-I01.
    function test_whenUnknownInterfaceQueried(bytes4 id_, address caller_) public {
        bytes4[9] memory ids = [
            type(IBurnerLoansRiskConfigTimelock).interfaceId,
            type(IVersioned).interfaceId,
            type(ITimelockBatchQueue).interfaceId,
            type(IConfigTimelockBatchQueue).interfaceId,
            type(IERC165).interfaceId,
            type(IEnabler).interfaceId,
            type(IEnablerV2).interfaceId,
            type(IReEnabler).interfaceId,
            type(IGracePeriod).interfaceId
        ];
        for (uint256 i; i < ids.length; ++i) vm.assume(id_ != ids[i]);
        vm.prank(caller_);
        assertFalse(_timelock.supportsInterface(id_), "unknown interface unsupported");
        assertFalse(
            _timelock.supportsInterface(0xffffffff),
            "invalid ERC165 interface unsupported"
        );
    }
}
