// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansAuth} from "src/policies/burnerloans/BurnerLoansAuth.sol";
import {BurnerLoansAuthTest} from "src/test/policies/BurnerLoansAuth/BurnerLoansAuthTest.sol";
import {AuthKernelMock} from "src/test/policies/BurnerLoansAuth/fixtures/AuthKernelMock.sol";
import {AuthTemporaryBatch} from "src/test/policies/BurnerLoansAuth/fixtures/AuthTemporaryBatch.sol";

contract BurnerLoansAuthRotationTest is BurnerLoansAuthTest {
    // Scenarios: BLAUTH-ROTATE-P06.
    function test_givenCoreReportsNewKernel_whenAuthReplaced_oldCancellationRemainsAvailable()
        public
    {
        _approve(_grant(15, true));
        AuthKernelMock nextKernel = new AuthKernelMock();
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(nextKernel))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                address(nextKernel)
            )
        );
        _auth.captureAuthorization(_account, _operator, 1);

        BurnerLoansAuth next = new BurnerLoansAuth(address(nextKernel), address(_core));
        _core.select(address(next));
        IOperatorAuth.Grant memory grant = _grant(15, true);
        grant.pairEpoch = next.pairEpochs(_account, _operator);
        grant.accountEpoch = next.accountEpochs(_account);
        grant.context = next.authorizationContext(_account, _operator);
        vm.prank(_account);
        next.approveGrant(grant);
        bytes32 stamp = next.captureAuthorization(_account, _operator, 1);
        assertEq(
            next.validate(_account, _operator, 1, _asset, address(0), stamp),
            type(uint128).max,
            "Replacement Auth admits the independently trusted new Kernel"
        );

        vm.startPrank(_account);
        _auth.cancelGrant(_operator);
        _auth.cancelAllGrants();
        vm.stopPrank();
        assertEq(
            _auth.pairEpochs(_account, _operator),
            2,
            "Retired pair cancellation stays available"
        );
        assertEq(_auth.accountEpochs(_account), 1, "Retired account cancellation stays available");
        assertEq(
            next.pairEpochs(_account, _operator),
            1,
            "Old cancellation does not change new grants"
        );
    }

    // Scenarios: BLAUTH-ROTATE-P01.
    function test_givenReusableGrant_whenAuthReturns_oldGrantDoesNotRevive() public {
        _approve(_grant(15, true));
        bytes32 original = _auth.captureAuthorization(_account, _operator, 1);
        BurnerLoansAuth other = new BurnerLoansAuth(address(_kernel), address(_core));
        _core.select(address(other));
        _core.select(address(_auth));
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        _auth.validate(_account, _operator, 1, _asset, address(0), original);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            1,
            "Returning to Auth does not reset its pair sequence"
        );
        _approve(_grant(15, true));
        assertEq(
            _auth.pairEpochs(_account, _operator),
            2,
            "Reapproval advances the retained pair sequence"
        );
    }

    // Scenarios: BLAUTH-ROTATE-P02.
    function test_givenTemporaryGrant_whenSameTransactionAuthReturns_oldGrantDoesNotRevive()
        public
    {
        AuthTemporaryBatch batch = new AuthTemporaryBatch();
        BurnerLoansAuth other = new BurnerLoansAuth(address(_kernel), address(_core));
        (bool beforeRotation, bool afterRotation) = batch.acceptUseAndRotate(
            _auth,
            other,
            _core,
            _grant(15, false)
        );
        assertTrue(
            beforeRotation,
            "Temporary grant works in accepting transaction before rotation"
        );
        assertFalse(afterRotation, "Same-transaction transient data cannot revive on reselection");
        assertEq(
            _auth.pairEpochs(address(batch), _operator),
            1,
            "Temporary acceptance consumes only one epoch"
        );
    }

    // Scenarios: BLAUTH-ROTATE-I01.
    function test_givenOldSignature_whenAuthReturns_reverts() public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        bytes memory signature = _sign(grant, _auth);
        _core.select(address(new BurnerLoansAuth(address(_kernel), address(_core))));
        _core.select(address(_auth));
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(_operator);
        _auth.acceptGrant(grant, "", signature);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            0,
            "Old-namespace signature does not consume any epoch"
        );
    }

    // Scenarios: BLAUTH-ROTATE-P03.
    function test_givenFutureOtherAuthSignature_whenCurrentAuthCancelled_otherNamespaceUnaffected()
        public
    {
        BurnerLoansAuth other = new BurnerLoansAuth(address(_kernel), address(_core));
        IOperatorAuth.Grant memory grant = _grant(15, true);
        grant.context = keccak256(abi.encode(address(_core), uint256(2)));
        bytes memory signature = _sign(grant, other);
        vm.prank(_account);
        _auth.cancelAllGrants();
        _core.select(address(other));
        vm.prank(_operator);
        other.acceptGrant(grant, "", signature);
        assertEq(
            _auth.accountEpochs(_account),
            1,
            "Cancellation increments only the original Auth's account epoch"
        );
        assertEq(
            other.accountEpochs(_account),
            0,
            "Other Auth has its own approved cancellation namespace"
        );
        assertEq(
            other.pairEpochs(_account, _operator),
            1,
            "Intentionally signed future Auth request can be accepted"
        );
    }

    // Scenarios: BLAUTH-ROTATE-P04.
    function test_givenRetiredAndInactiveAuth_whenAccountCancels() public {
        _approve(_grant(15, true));
        _core.select(address(new BurnerLoansAuth(address(_kernel), address(_core))));
        _kernel.setActive(false);
        _core.setEnabled(false);
        vm.startPrank(_account);
        _auth.cancelGrant(_operator);
        _auth.cancelAllGrants();
        vm.stopPrank();
        assertEq(
            _auth.pairEpochs(_account, _operator),
            2,
            "Retired cancellation retains pair history"
        );
        assertEq(
            _auth.accountEpochs(_account),
            1,
            "Retired cancellation does not depend on Core readiness"
        );
    }
}
// forge-lint: disable-end(unused-return)
