// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)
// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {OperatorAuthDriver} from "./OperatorAuthDriver.sol";
import {OperatorAuthTest} from "./OperatorAuthTest.sol";

contract OperatorAuthGetGrantTest is OperatorAuthTest {
    OperatorAuthDriver internal _driver;

    function setUp() public override {
        super.setUp();
        _driver = new OperatorAuthDriver(_auth, _operator);
    }

    // Scenarios: OAGRANT-V07.
    // The bounds below keep casts within uint48 and separate read time from grant expiry.
    // forge-lint: disable-start(unsafe-typecast)
    function test_givenReusableGrant_whenReadBeforeUse(
        address viewer_,
        uint48 deadline_,
        uint48 readAt_
    ) public {
        IOperatorAuth.Grant memory g = _grant(true);
        g.deadline = uint48(bound(deadline_, 101, type(uint48).max));
        uint256 readAt = bound(readAt_, 100, uint256(g.deadline) - 1);
        _approve(g);
        vm.warp(readAt);
        vm.prank(viewer_);
        assertEq(
            abi.encode(_auth.getGrant(_account, _operator)),
            abi.encode(g),
            "Unused reusable grant is retained"
        );
        assertEq(_auth.pairEpochs(_account, _operator), 1, "Reading consumes no pair epoch");
        assertEq(_auth.accountEpochs(_account), 0, "Reading changes no account epoch");
    }

    // Scenarios: OAGRANT-V08.
    function test_givenReusableGrant_whenReadAfterRepeatedUse(
        address viewer_,
        uint48 deadline_,
        uint48 readAt_
    ) public {
        IOperatorAuth.Grant memory g = _grant(true);
        g.deadline = uint48(bound(deadline_, 101, type(uint48).max));
        uint256 readAt = bound(readAt_, 100, uint256(g.deadline) - 1);
        _approve(g);
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        assertEq(
            _auth.validateAuthorization(_account, _operator, 1, stamp),
            g.permissions,
            "First use retains permissions"
        );
        vm.warp(readAt);
        assertEq(
            _auth.validateAuthorization(_account, _operator, 2, stamp),
            g.permissions,
            "Later use retains permissions"
        );
        vm.prank(viewer_);
        assertEq(
            abi.encode(_auth.getGrant(_account, _operator)),
            abi.encode(g),
            "Used reusable grant is unchanged"
        );
        assertEq(
            _auth.captureAuthorization(_account, _operator, 1),
            stamp,
            "Use does not replace the stamp"
        );
        assertEq(_auth.pairEpochs(_account, _operator), 1, "Uses consume no further pair epochs");
        assertEq(_auth.accountEpochs(_account), 0, "Uses change no account epoch");
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: OAGRANT-V07, OAGRANT-V08.
    function test_whenReusableGrantReadTimeBoundarySeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenReusableGrant_whenReadBeforeUse(address(0), 101, 100);
        assertTrue(vm.revertToStateAndDelete(checkpoint), "Restore minimum unused-grant seed");
        checkpoint = vm.snapshotState();
        test_givenReusableGrant_whenReadAfterRepeatedUse(address(0), 101, 100);
        assertTrue(vm.revertToStateAndDelete(checkpoint), "Restore minimum used-grant seed");
        checkpoint = vm.snapshotState();
        test_givenReusableGrant_whenReadBeforeUse(_account, type(uint48).max, type(uint48).max - 1);
        assertTrue(vm.revertToStateAndDelete(checkpoint), "Restore maximum unused-grant seed");
        test_givenReusableGrant_whenReadAfterRepeatedUse(
            _account,
            type(uint48).max,
            type(uint48).max - 1
        );
    }

    // Scenarios: OAGRANT-V09.
    function test_givenUsedReusableGrant_whenDeadlinePasses_returnsEmpty() public {
        IOperatorAuth.Grant memory g = _grant(true);
        g.deadline = 101;
        _approve(g);
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        assertEq(
            _auth.validateAuthorization(_account, _operator, 1, stamp),
            g.permissions,
            "First use succeeds"
        );
        vm.warp(101);
        assertEq(
            _auth.validateAuthorization(_account, _operator, 2, stamp),
            g.permissions,
            "Reuse at expiry equality succeeds"
        );
        vm.warp(102);
        _assertNoGrant(_account, _operator);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, uint48(101))
        );
        _auth.validateAuthorization(_account, _operator, 1, stamp);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            1,
            "Expiry does not reset or consume epochs"
        );
        assertEq(_auth.accountEpochs(_account), 0, "Expiry does not cancel the account");
    }

    // Scenarios: OAGRANT-V01.
    function test_givenExpiredGrant_whenRead_returnsEmpty() public {
        IOperatorAuth.Grant memory g = _grant(true);
        g.deadline = 100;
        _approve(g);
        vm.warp(101);
        _assertNoGrant(_account, _operator);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, g.deadline)
        );
        _auth.captureAuthorization(_account, _operator, 1);
    }

    // Scenarios: OAGRANT-V02.
    function test_givenNoGrant_whenRead_returnsEmpty(
        address account_,
        address operator_
    ) public view {
        _assertNoGrant(account_, operator_);
    }

    // Scenarios: OAGRANT-V03.
    function test_givenAccountCancelled_whenRead_returnsEmpty() public {
        IOperatorAuth.Grant memory g = _grant(true);
        _approve(g);
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        assertEq(
            _auth.validateAuthorization(_account, _operator, 1, stamp),
            g.permissions,
            "Grant is usable before cancellation"
        );
        vm.prank(_account);
        _auth.cancelAllGrants();
        _assertNoGrant(_account, _operator);
        _expectInvalidContext();
        _auth.validateAuthorization(_account, _operator, 1, stamp);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            1,
            "Account cancellation leaves pair epoch unchanged"
        );
        assertEq(_auth.accountEpochs(_account), 1, "Only account cancellation advances its epoch");
    }

    // Scenarios: OAGRANT-V10.
    function test_givenUsedReusableGrant_whenPairCancelled_returnsEmpty() public {
        IOperatorAuth.Grant memory g = _grant(true);
        _approve(g);
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        assertEq(
            _auth.validateAuthorization(_account, _operator, 1, stamp),
            g.permissions,
            "Grant is usable before cancellation"
        );
        vm.prank(_account);
        _auth.cancelGrant(_operator);
        _assertNoGrant(_account, _operator);
        _expectInvalidContext();
        _auth.validateAuthorization(_account, _operator, 1, stamp);
        assertEq(_auth.pairEpochs(_account, _operator), 2, "Pair cancellation advances its epoch");
        assertEq(_auth.accountEpochs(_account), 0, "Pair cancellation preserves account epoch");
    }

    // Scenarios: OAGRANT-V11.
    function test_givenUsedReusableGrant_whenReplaced_returnsReplacement() public {
        IOperatorAuth.Grant memory g = _grant(true);
        _approve(g);
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        assertEq(
            _auth.validateAuthorization(_account, _operator, 1, stamp),
            g.permissions,
            "Original grant is used"
        );
        IOperatorAuth.Grant memory replacement = _grant(true);
        replacement.permissions = hex"0405";
        _approve(replacement);
        assertEq(
            abi.encode(_auth.getGrant(_account, _operator)),
            abi.encode(replacement),
            "Getter selects the complete replacement"
        );
        _expectInvalidContext();
        _auth.validateAuthorization(_account, _operator, 1, stamp);
        bytes32 newStamp = _auth.captureAuthorization(_account, _operator, 1);
        assertTrue(newStamp != stamp, "Replacement changes the immutable stamp");
        assertEq(
            _auth.validateAuthorization(_account, _operator, 1, newStamp),
            replacement.permissions,
            "Replacement remains usable"
        );
        assertEq(
            _auth.pairEpochs(_account, _operator),
            2,
            "Only replacement consumes another epoch"
        );
        assertEq(_auth.accountEpochs(_account), 0, "Replacement preserves account epoch");
    }

    // Scenarios: OAGRANT-V04.
    function test_givenDeadlineEquality_whenRead_returnsLiveGrant() public {
        IOperatorAuth.Grant memory g = _grant(true);
        g.deadline = 100;
        _approve(g);
        assertEq(
            abi.encode(_auth.getGrant(_account, _operator)),
            abi.encode(g),
            "Inclusive deadline is live"
        );
    }

    // Scenarios: OAGRANT-V05.
    function test_givenFullWidthTimeBeyondMaximumDeadline_whenRead_returnsEmpty() public {
        _approve(_grant(true));
        vm.warp(uint256(type(uint48).max) + 1);
        _assertNoGrant(_account, _operator);
    }

    // Scenarios: OAGRANT-V06.
    function test_givenDifferentContext_whenRead_returnsEmpty() public {
        _approve(_grant(true));
        _auth.setContext(bytes32(uint256(1)));
        _assertNoGrant(_account, _operator);
    }

    // Scenarios: OATEMP-P06.
    function test_givenTemporaryGrant_whenReadInAcceptingTransaction_returnsLiveGrant() public {
        IOperatorAuth.Grant memory g = _driver.approveTemporaryAndRead(hex"010203");
        assertEq(g.account, address(_driver), "Temporary account retained");
        assertEq(g.operator, _operator, "Temporary operator retained");
        assertFalse(g.multiple, "Transaction-local mode retained");
        assertEq(g.permissions, hex"010203", "Live temporary permissions returned");
    }
}
// forge-lint: disable-end(unused-return)
