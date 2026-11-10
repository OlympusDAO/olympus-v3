// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {StdStorage, stdStorage} from "@forge-std-1.16.2/StdStorage.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansCoreTest} from "src/test/policies/BurnerLoansCore/BurnerLoansCoreTest.sol";
import {AuthSelectionCandidate} from "src/test/policies/BurnerLoansCore/fixtures/AuthSelectionCandidate.sol";

// Address-only checks intentionally ignore the epoch; epoch effects are asserted separately.
// forge-lint: disable-start(unused-return)

contract BurnerLoansCoreSetAuthTest is BurnerLoansCoreTest {
    using stdStorage for StdStorage;

    // Scenarios: BLCORE-AUTH-P05.
    function test_whenEpochRead_onlyCombinedGetterIsExposed() public view {
        (address selected, uint256 epoch) = _core.authConfig();
        assertEq(selected, address(_auth), "Combined getter returns the selected Auth");
        assertEq(epoch, 1, "Combined getter returns the initial installation epoch");
        (bool success, ) = address(_core).staticcall(abi.encodeWithSignature("globalAuthEpoch()"));
        assertFalse(success, "Epoch has no duplicate standalone public getter");
        (success, ) = address(_core).staticcall(abi.encodeWithSignature("auth()"));
        assertFalse(success, "Auth selection has no duplicate standalone public getter");
    }

    // Scenarios: BLCORE-AUTH-A01.
    function test_whenCallerIsConfigOperator_reverts() public {
        test_whenCallerIsNotAdmin_reverts(address(_config));
    }

    // Scenarios: BLCORE-AUTH-L03.
    function test_givenAuthUnset_whenCoreEnabled_reverts(bool recovery_) public {
        _core.disable("");
        stdstore
            .target(address(_core))
            .sig(IBurnerLoansCore.authConfig.selector)
            .depth(0)
            .checked_write(address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidAuth.selector,
                address(0)
            )
        );
        if (recovery_) _core.reEnable();
        else _core.enable("");
        assertFalse(
            _core.isEnabled(),
            "Unset authorization prevents both normal and recovery admission"
        );
    }

    // Scenarios: BLCORE-AUTH-A01.
    function test_whenCallerIsNotAdmin_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        uint256 epoch = _currentAuthEpoch();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _core.setAuth(address(1));
        assertEq(_currentAuthEpoch(), epoch, "Unauthorized selection preserves global epoch");
    }

    // Scenarios: BLCORE-AUTH-P01.
    function test_whenAuthReplaced() public {
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        uint256 epoch = _currentAuthEpoch();
        bytes32 ledger = _ledger();
        _core.setAuth(address(next));
        (address selected, ) = _core.authConfig();
        assertEq(selected, address(next), "Auth pointer selects the compatible replacement");
        assertEq(_currentAuthEpoch(), epoch + 1, "One successful replacement advances once");
        assertEq(_ledger(), ledger, "Auth selection preserves custody and canonical accounting");
    }

    // Scenarios: BLCORE-AUTH-L01.
    function test_givenCoreDisabled_whenAuthReplaced() public {
        _core.disable("");
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        uint256 epoch = _currentAuthEpoch();
        _core.setAuth(address(next));
        assertEq(_currentAuthEpoch(), epoch + 1, "Disabled Core permits Auth recovery");
        assertFalse(_core.isEnabled(), "Replacement does not enable Core");
    }

    // Scenarios: BLCORE-AUTH-P02.
    function test_whenOldAuthSelectedAgain() public {
        (address original, ) = _core.authConfig();
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        uint256 epoch = _currentAuthEpoch();
        _core.setAuth(address(next));
        _core.setAuth(original);
        (address selected, ) = _core.authConfig();
        assertEq(selected, original, "Returning to the prior Auth is allowed");
        assertEq(_currentAuthEpoch(), epoch + 2, "Returning never restores the old epoch");
    }

    // Scenarios: BLCORE-AUTH-L02.
    function test_givenCoreInactive_whenAuthReplaced_reverts(bool enabled_) public {
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        _setCoreLifecycle(false, enabled_);
        uint256 epoch = _currentAuthEpoch();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_core)
            )
        );
        _core.setAuth(address(next));
        assertEq(_currentAuthEpoch(), epoch, "Inactive Core does not alter Auth generation");
    }

    // Scenarios: BLCORE-AUTH-I01.
    function test_whenZeroAuthSelected_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidAuth.selector,
                address(0)
            )
        );
        _core.setAuth(address(0));
    }

    // Scenarios: BLCORE-AUTH-I01.
    function test_whenEoaSelected_reverts(address candidate_) public {
        vm.assume(candidate_ != address(0) && candidate_.code.length == 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidAuth.selector,
                candidate_
            )
        );
        _core.setAuth(candidate_);
    }

    // Scenarios: BLCORE-AUTH-I01.
    function test_whenWrongCoreSelected_reverts(address target_) public {
        vm.assume(target_ != address(_core));
        AuthSelectionCandidate next = new AuthSelectionCandidate(target_);
        uint256 epoch = _currentAuthEpoch();
        (address current, ) = _core.authConfig();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidAuth.selector,
                address(next)
            )
        );
        _core.setAuth(address(next));
        (address selected, ) = _core.authConfig();
        assertEq(selected, current, "Wrong binding leaves the original selection intact");
        assertEq(_currentAuthEpoch(), epoch, "Wrong binding does not consume a global epoch");
    }

    // Scenarios: BLCORE-AUTH-I02.
    function test_whenUnchangedAuthSelected_reverts() public {
        (address current, ) = _core.authConfig();
        uint256 epoch = _currentAuthEpoch();
        vm.mockCallRevert(
            current,
            abi.encodeWithSignature("core()"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_UnchangedAddress.selector,
                current
            )
        );
        _core.setAuth(current);
        assertEq(_currentAuthEpoch(), epoch, "Unchanged selection rejects before candidate probes");
    }

    // Scenarios: BLCORE-AUTH-I01.
    function test_whenMalformedCoreBinding_reverts(uint8 length_) public {
        uint256 length = bound(length_, 0, 64);
        vm.assume(length != 32);
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        vm.mockCall(address(next), abi.encodeWithSignature("core()"), new bytes(length));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidAuth.selector,
                address(next)
            )
        );
        _core.setAuth(address(next));
    }

    // Scenarios: BLCORE-AUTH-I01.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_whenNoncanonicalCoreAddress_reverts(uint96 padding_) public {
        padding_ = uint96(bound(padding_, 1, type(uint96).max));
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        vm.mockCall(
            address(next),
            abi.encodeWithSignature("core()"),
            abi.encode((uint256(padding_) << 160) | uint160(address(_core)))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidAuth.selector,
                address(next)
            )
        );
        _core.setAuth(address(next));
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLCORE-AUTH-P06.
    function test_whenVersionMetadataUnavailable() public {
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        vm.mockCall(
            address(next),
            abi.encodeCall(IERC165.supportsInterface, (type(IVersioned).interfaceId)),
            abi.encode(false)
        );
        vm.mockCallRevert(
            address(next),
            abi.encodeCall(IVersioned.VERSION, ()),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        uint256 epoch = _currentAuthEpoch();
        bytes32 ledger = _ledger();
        _core.setAuth(address(next));
        (address selected, ) = _core.authConfig();
        assertEq(selected, address(next), "Consumed interfaces and Core binding admit Auth");
        assertEq(_currentAuthEpoch(), epoch + 1, "Version-free admission advances once");
        assertEq(_ledger(), ledger, "Version-free admission preserves custody and accounting");
    }

    // Scenarios: BLCORE-AUTH-P06.
    function test_whenVersionGetterReturnsOversizedData() public {
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        vm.mockCall(address(next), abi.encodeWithSignature("VERSION()"), new bytes(4096));
        uint256 epoch = _currentAuthEpoch();
        bytes32 ledger = _ledger();
        _core.setAuth(address(next));
        (address selected, ) = _core.authConfig();
        assertEq(selected, address(next), "Unconsumed version metadata does not gate Auth");
        assertEq(_currentAuthEpoch(), epoch + 1, "Admission advances the epoch once");
        assertEq(_ledger(), ledger, "Admission preserves custody and accounting");
    }

    // Scenarios: BLCORE-AUTH-P03.
    function test_whenErc165PositiveResponseNonzero() public {
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        uint256 epoch = _currentAuthEpoch();
        bytes32 ledger = _ledger();
        vm.mockCall(
            address(next),
            abi.encodeCall(IERC165.supportsInterface, (type(IERC165).interfaceId)),
            abi.encode(uint256(2))
        );
        _core.setAuth(address(next));
        (address selected, ) = _core.authConfig();
        assertEq(selected, address(next), "Standard ERC165 checker accepts nonzero words");
        assertEq(_currentAuthEpoch(), epoch + 1, "Accepted Auth advances the epoch once");
        assertEq(_ledger(), ledger, "Auth selection preserves canonical state and custody");
    }

    // Scenarios: BLCORE-AUTH-P04.
    function test_whenErc165NegativeResponseHasTrailingData() public {
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        uint256 epoch = _currentAuthEpoch();
        bytes32 ledger = _ledger();
        vm.mockCall(
            address(next),
            abi.encodeCall(IERC165.supportsInterface, (bytes4(0xffffffff))),
            abi.encode(uint256(0), uint256(0))
        );
        _core.setAuth(address(next));
        (address selected, ) = _core.authConfig();
        assertEq(selected, address(next), "Standard ERC165 checker permits trailing data");
        assertEq(_currentAuthEpoch(), epoch + 1, "Accepted Auth advances the epoch once");
        assertEq(_ledger(), ledger, "Auth selection preserves canonical state and custody");
    }

    // Scenarios: BLCORE-AUTH-I01.
    function test_whenRequiredAuthInterfaceMissing_reverts(uint8 interface_) public {
        bytes4[3] memory interfaces = [
            type(IERC165).interfaceId,
            type(IBurnerLoansAuth).interfaceId,
            type(IBurnerLoansCoreBound).interfaceId
        ];
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        vm.mockCall(
            address(next),
            abi.encodeCall(IERC165.supportsInterface, (interfaces[bound(interface_, 0, 2)])),
            abi.encode(false)
        );
        _expectInvalidAuth(next);
        _core.setAuth(address(next));
    }

    // Scenarios: BLCORE-AUTH-I01.
    function test_whenErc165InvalidInterfaceSupported_reverts() public {
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        vm.mockCall(
            address(next),
            abi.encodeCall(IERC165.supportsInterface, (bytes4(0xffffffff))),
            abi.encode(true)
        );
        _expectInvalidAuth(next);
        _core.setAuth(address(next));
    }

    // Scenarios: BLCORE-AUTH-I01.
    function test_whenErc165ResponseTooShort_reverts(uint8 length_) public {
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        vm.mockCall(
            address(next),
            abi.encodeCall(IERC165.supportsInterface, (type(IERC165).interfaceId)),
            new bytes(bound(length_, 0, 31))
        );
        _expectInvalidAuth(next);
        _core.setAuth(address(next));
    }

    // Scenarios: BLCORE-AUTH-I01.
    function test_whenErc165ProbeReverts_reverts() public {
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        vm.mockCallRevert(
            address(next),
            abi.encodeCall(IERC165.supportsInterface, (type(IERC165).interfaceId)),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        _expectInvalidAuth(next);
        _core.setAuth(address(next));
    }

    function _expectInvalidAuth(AuthSelectionCandidate candidate_) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidAuth.selector,
                address(candidate_)
            )
        );
    }

    // Scenarios: BLCORE-AUTH-N01.
    function test_givenExhaustedGlobalEpoch_whenAuthReplaced_reverts() public {
        AuthSelectionCandidate next = new AuthSelectionCandidate(address(_core));
        stdstore
            .target(address(_core))
            .sig(IBurnerLoansCore.authConfig.selector)
            .depth(1)
            .checked_write(type(uint256).max);
        (address current, ) = _core.authConfig();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_AuthEpochExhausted.selector);
        _core.setAuth(address(next));
        assertEq(_currentAuthEpoch(), type(uint256).max, "Global epoch never wraps");
        (address selected, ) = _core.authConfig();
        assertEq(selected, current, "Exhaustion rolls back the replacement pointer");
    }
}

// forge-lint: disable-end(unused-return)
