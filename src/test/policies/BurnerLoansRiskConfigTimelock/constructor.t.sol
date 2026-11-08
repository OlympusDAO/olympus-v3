// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {BurnerLoansRiskConfigTimelock} from "src/policies/burnerloans/BurnerLoansRiskConfigTimelock.sol";

contract BurnerLoansRiskConfigTimelockConstructorTest is BurnerLoansRiskConfigTimelockTest {
    // Scenarios: BLRCT-CONSTRUCTOR-P01, BLRCT-CONSTRUCTOR-P03.
    function test_whenCompatibleTarget(bool active_, bool enabled_, address caller_) public {
        _setState(_risk, active_, enabled_);
        vm.prank(caller_);
        BurnerLoansRiskConfigTimelock fresh = new BurnerLoansRiskConfigTimelock(_kernel, _risk);
        assertEq(address(fresh.risk()), address(_risk), "immutable Risk binding");
        assertEq(address(fresh.kernel()), address(_kernel), "Kernel binding");
        assertFalse(fresh.isEnabled(), "starts disabled");
        assertEq(fresh.lastTransitionAt(), 0, "no transition history");
        assertEq(fresh.nextActionId(), 1, "first queue ID");
        assertEq(fresh.timelockDelay(), 1 days, "one day notice");
        assertEq(fresh.gracePeriod(), 7 days, "seven day grace");
        assertEq(fresh.requestPermissions().length, 0, "no module writes");
        assertFalse(_roles.hasRole(address(fresh), ADMIN_ROLE), "queue not granted ADMIN");
    }

    // Scenarios: BLRCT-CONSTRUCTOR-I01.
    function test_whenZeroOrEOATarget_reverts(address target_) public {
        vm.assume(target_.code.length == 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                target_
            )
        );
        new BurnerLoansRiskConfigTimelock(_kernel, IBurnerLoansRisk(target_));
    }

    // Scenarios: BLRCT-CONSTRUCTOR-I02.
    function test_whenRequiredInterfaceMissing_reverts(uint8 interface_) public {
        bytes4[3] memory interfaces = [
            type(IBurnerLoansRisk).interfaceId,
            type(IConfigOperator).interfaceId,
            type(IEnabler).interfaceId
        ];
        vm.mockCall(
            address(_risk),
            abi.encodeCall(IERC165.supportsInterface, (interfaces[bound(interface_, 0, 2)])),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        new BurnerLoansRiskConfigTimelock(_kernel, _risk);
    }

    // Scenarios: BLRCT-CONSTRUCTOR-D01.
    function test_whenForeignKernel_reverts() public {
        vm.mockCall(address(_risk), abi.encodeWithSignature("kernel()"), abi.encode(address(0xF0)));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_risk),
                address(_kernel),
                address(0xF0)
            )
        );
        new BurnerLoansRiskConfigTimelock(_kernel, _risk);
    }

    // Scenarios: BLRCT-CONSTRUCTOR-D02.
    function test_whenMalformedKernel_reverts() public {
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature("kernel()"),
            abi.encode(type(uint256).max)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
        new BurnerLoansRiskConfigTimelock(_kernel, _risk);
    }

    // Scenarios: BLRCT-CONSTRUCTOR-P02.
    function test_givenRuntimeGettersFail_whenConstructed() public {
        vm.mockCallRevert(address(_risk), abi.encodeWithSignature("isEnabled()"), hex"ff");
        vm.mockCallRevert(address(_risk), abi.encodeWithSignature("configOperator()"), hex"ff");
        vm.mockCallRevert(
            address(_kernel),
            abi.encodeWithSignature("isPolicyActive(address)", address(_risk)),
            hex"ff"
        );
        BurnerLoansRiskConfigTimelock fresh = new BurnerLoansRiskConfigTimelock(_kernel, _risk);
        assertEq(
            address(fresh.risk()),
            address(_risk),
            "constructor does not consume runtime services"
        );
    }

    // Scenarios: BLRCT-CONSTRUCTOR-P03.
    function test_whenFreshStartupHasNoCircularReadiness() public {
        BurnerLoansRisk candidate = new BurnerLoansRisk(
            _kernel,
            IERC20(address(_ohm)),
            _risk.backingOracle(),
            address(0),
            0,
            address(_core)
        );
        BurnerLoansRiskConfigTimelock queue = new BurnerLoansRiskConfigTimelock(_kernel, candidate);
        _kernel.executeAction(Actions.ActivatePolicy, address(candidate));
        candidate.setConfigOperator(address(queue));
        assertFalse(queue.isEnabled(), "operator can be bound before queue enablement");
        candidate.enable("");
        _kernel.executeAction(Actions.ActivatePolicy, address(queue));
        queue.enable("");
        assertEq(candidate.configOperator(), address(queue), "queue delegated authority");
        assertTrue(queue.isEnabled(), "startup completed");
        assertEq(queue.requestPermissions().length, 0, "queue requests no FLOAN writes");
        assertFalse(_roles.hasRole(address(queue), ADMIN_ROLE), "queue no ADMIN grant");
        queue.queueSetReferralFeeBps(2500);
    }

    // Scenarios: BLRCT-CONSTRUCTOR-I02.
    function test_givenDirtyErc165Bool_whenConstructed_reverts() public {
        vm.mockCall(
            address(_risk),
            abi.encodeCall(IERC165.supportsInterface, (type(IBurnerLoansRisk).interfaceId)),
            abi.encode(uint256(2))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        new BurnerLoansRiskConfigTimelock(_kernel, _risk);
    }

    function _interfaceId(uint8 index_) private pure returns (bytes4) {
        bytes4[5] memory ids = [
            type(IERC165).interfaceId,
            bytes4(0xffffffff),
            type(IBurnerLoansRisk).interfaceId,
            type(IConfigOperator).interfaceId,
            type(IEnabler).interfaceId
        ];
        return ids[index_];
    }

    // Scenarios: BLRCT-CONSTRUCTOR-I02.
    function test_givenInterfaceGetterReverts_whenConstructed_reverts(
        uint8 interface_,
        bytes memory reason_
    ) public {
        bytes4 id = _interfaceId(uint8(bound(interface_, 0, 4)));
        vm.mockCallRevert(address(_risk), abi.encodeCall(IERC165.supportsInterface, (id)), reason_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        new BurnerLoansRiskConfigTimelock(_kernel, _risk);
    }

    // Scenarios: BLRCT-CONSTRUCTOR-I02.
    function test_givenInterfaceLengthMalformed_whenConstructed_reverts(
        uint8 interface_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        bytes4 id = _interfaceId(uint8(bound(interface_, 0, 4)));
        vm.mockCall(address(_risk), abi.encodeCall(IERC165.supportsInterface, (id)), data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        new BurnerLoansRiskConfigTimelock(_kernel, _risk);
    }

    // Scenarios: BLRCT-CONSTRUCTOR-I02.
    function test_givenInterfaceBoolDirty_whenConstructed_reverts(
        uint8 interface_,
        uint256 word_
    ) public {
        bytes4 id = _interfaceId(uint8(bound(interface_, 0, 4)));
        uint256 word = bound(word_, 2, type(uint256).max);
        vm.mockCall(
            address(_risk),
            abi.encodeCall(IERC165.supportsInterface, (id)),
            abi.encode(word)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        new BurnerLoansRiskConfigTimelock(_kernel, _risk);
    }

    // Scenarios: BLRCT-CONSTRUCTOR-I02.
    function test_givenInterfaceMetadataFaultSeeds_whenConstructed_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 i; i < 5; ++i) {
            test_givenInterfaceGetterReverts_whenConstructed_reverts(i, hex"deadbeef");
            _restore(checkpoint);
            test_givenInterfaceLengthMalformed_whenConstructed_reverts(i, bytes(""));
            _restore(checkpoint);
            test_givenInterfaceLengthMalformed_whenConstructed_reverts(i, new bytes(31));
            _restore(checkpoint);
            test_givenInterfaceLengthMalformed_whenConstructed_reverts(
                i,
                bytes.concat(abi.encode(true), hex"00")
            );
            _restore(checkpoint);
            test_givenInterfaceBoolDirty_whenConstructed_reverts(i, 2);
            _restore(checkpoint);
            test_givenInterfaceBoolDirty_whenConstructed_reverts(i, type(uint256).max);
            _restore(checkpoint);
        }
    }

    // Scenarios: BLRCT-CONSTRUCTOR-I02.
    function test_givenErc165PredicatesWrong_whenConstructed_reverts(bool invalidId_) public {
        bytes4 id = invalidId_ ? bytes4(0xffffffff) : type(IERC165).interfaceId;
        vm.mockCall(
            address(_risk),
            abi.encodeCall(IERC165.supportsInterface, (id)),
            abi.encode(invalidId_)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        new BurnerLoansRiskConfigTimelock(_kernel, _risk);
    }

    // Scenarios: BLRCT-CONSTRUCTOR-D02.
    function test_givenInvalidKernelMetadata_whenConstructed_reverts(
        bool reverts_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        if (reverts_) vm.mockCallRevert(address(_risk), abi.encodeWithSignature("kernel()"), data_);
        else vm.mockCall(address(_risk), abi.encodeWithSignature("kernel()"), data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
        new BurnerLoansRiskConfigTimelock(_kernel, _risk);
    }
}
