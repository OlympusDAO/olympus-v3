// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)
// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {DefaultOperatorAuthHarness} from "./DefaultOperatorAuthHarness.sol";
import {OperatorAuthDriver} from "./OperatorAuthDriver.sol";
import {OperatorAuthHarness} from "./OperatorAuthHarness.sol";
import {OperatorAuthSequenceHandler} from "./OperatorAuthSequenceHandler.sol";
import {OperatorAuthTest} from "./OperatorAuthTest.sol";

contract OperatorAuthApproveGrantTest is OperatorAuthTest {
    OperatorAuthDriver internal _driver;
    OperatorAuthSequenceHandler internal _handler;

    function setUp() public override {
        super.setUp();
        _driver = new OperatorAuthDriver(_auth, _operator);
        _handler = new OperatorAuthSequenceHandler(_auth);
    }

    // Scenarios: OAGRANT-P11.
    function test_whenTemporaryPermissionLengthVaries(uint16 length_, bytes32 seed_) public {
        uint256 length = bound(length_, 0, 320);
        bytes memory permissions = new bytes(length);
        for (uint256 i; i < length; ++i) {
            permissions[i] = bytes1(keccak256(abi.encode(seed_, i)));
        }
        IOperatorAuth.Grant memory result = _driver.approveTemporaryAndRead(permissions);
        IOperatorAuth.Grant memory expected = IOperatorAuth.Grant({
            account: address(_driver),
            operator: _operator,
            accountEpoch: 0,
            pairEpoch: 0,
            deadline: type(uint48).max,
            multiple: false,
            actions: 15,
            context: bytes32(0),
            permissions: permissions
        });
        assertEq(abi.encode(result), abi.encode(expected), "All transient grant fields round-trip");
        assertEq(_auth.pairEpochs(address(_driver), _operator), 1, "One pair epoch consumed");
    }

    // Scenarios: OAGRANT-P11.
    function test_whenTemporaryPermissionLengthBoundarySeeds() public {
        uint16[7] memory lengths = [uint16(0), 1, 31, 32, 33, 319, 320];
        for (uint256 i; i < lengths.length; ++i) {
            uint256 checkpoint = vm.snapshotState();
            test_whenTemporaryPermissionLengthVaries(lengths[i], bytes32(i));
            assertTrue(vm.revertToStateAndDelete(checkpoint), "Restore independent length seed");
        }
    }

    // Scenarios: OAGRANT-P10.
    function test_whenApproved_emitsPermissionsHash(bool multiple_) public {
        IOperatorAuth.Grant memory g = _grant(multiple_);
        _expectGrantAccepted(_account, g);
        _approve(g);
    }

    // Scenarios: OAGRANT-A01.
    function test_whenUnrelatedCaller_reverts(address caller_) public {
        vm.assume(caller_ != _account);
        IOperatorAuth.Grant memory g = _grant(true);
        vm.prank(caller_);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        _auth.approveGrant(g);
        assertEq(_auth.pairEpochs(_account, _operator), 0, "Unauthorized approval preserves epoch");
    }

    // Scenarios: OAGRANT-I01.
    function test_whenOperatorZero_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        g.operator = address(0);
        vm.prank(_account);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        _auth.approveGrant(g);
    }

    // Scenarios: OAGRANT-I02.
    function test_whenSelfGrant_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        g.operator = _account;
        vm.prank(_account);
        vm.expectRevert(IOperatorAuth.OperatorAuth_SelfGrant.selector);
        _auth.approveGrant(g);
    }

    // Scenarios: OAGRANT-I03.
    function test_whenEmptyMask_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        g.actions = 0;
        vm.prank(_account);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidActions.selector, 0)
        );
        _auth.approveGrant(g);
    }

    // Scenarios: OAGRANT-I04.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_whenUnsupportedMask_reverts(uint8 mask_) public {
        mask_ = uint8(bound(mask_, 16, type(uint8).max));
        IOperatorAuth.Grant memory g = _grant(true);
        g.actions = mask_;
        vm.prank(_account);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidActions.selector, mask_)
        );
        _auth.approveGrant(g);
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: OAGRANT-I05.
    function test_whenWrongContext_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        g.context = bytes32(uint256(1));
        vm.prank(_account);
        _expectInvalidContext();
        _auth.approveGrant(g);
    }

    // Scenarios: OAGRANT-I06.
    function test_whenOversizedPermissions_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        g.permissions = new bytes(321);
        vm.prank(_account);
        vm.expectRevert(OperatorAuthHarness.PermissionsTooLong.selector);
        _auth.approveGrant(g);
    }

    // Scenarios: OAGRANT-L01.
    function test_givenCreationDisabled_whenApproved_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        _auth.setCreationAllowed(false);
        vm.prank(_account);
        vm.expectRevert(OperatorAuthHarness.CreationDisabled.selector);
        _auth.approveGrant(g);
    }

    // Scenarios: OAGRANT-N01.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_whenDeadlineInclusive(uint48 deadline_) public {
        deadline_ = uint48(bound(deadline_, 100, type(uint48).max));
        IOperatorAuth.Grant memory g = _grant(true);
        g.deadline = deadline_;
        vm.warp(deadline_);
        _approve(g);
        assertNotEq(
            _auth.captureAuthorization(_account, _operator, 1),
            bytes32(0),
            "Deadline equality is live"
        );
        vm.warp(uint256(deadline_) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, deadline_)
        );
        _auth.captureAuthorization(_account, _operator, 1);
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: OAGRANT-N02.
    function test_whenFullWidthTimestampExceedsUint48_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        vm.warp(uint256(type(uint48).max) + 1);
        vm.prank(_account);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_ExpiredGrant.selector,
                type(uint48).max
            )
        );
        _auth.approveGrant(g);
    }

    // Scenarios: OAGRANT-N03.
    function test_givenPairMax_whenApproved_reverts() public {
        _pairEpoch(type(uint256).max);
        IOperatorAuth.Grant memory g = _grant(true);
        vm.prank(_account);
        vm.expectRevert(IOperatorAuth.OperatorAuth_EpochExhausted.selector);
        _auth.approveGrant(g);
    }

    // Scenarios: OAGRANT-P01.
    function test_whenReusableApproved() public {
        IOperatorAuth.Grant memory g = _grant(true);
        _approve(g);
        assertEq(_auth.pairEpochs(_account, _operator), 1, "One acceptance epoch");
        assertEq(_auth.accountEpochs(_account), 0, "Account epoch unaffected");
        assertEq(
            _auth.getGrant(_account, _operator).permissions,
            g.permissions,
            "Getter preserves bytes"
        );
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        assertEq(
            _auth.validateAuthorization(_account, _operator, 1, stamp),
            g.permissions,
            "Original context validates"
        );
        assertEq(_auth.pairEpochs(_account, _operator), 1, "Repeated operations consume no epochs");
    }

    // Scenarios: OAGRANT-P02.
    function test_givenContextReturns_whenNoReplacement_oldRecordUsesOriginalContext() public {
        _approve(_grant(true));
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        _auth.setContext(bytes32(uint256(1)));
        _expectInvalidContext();
        _auth.captureAuthorization(_account, _operator, 1);
        _auth.setContext(0);
        assertEq(
            _auth.captureAuthorization(_account, _operator, 1),
            stamp,
            "Generic recurring context deliberately restores authority"
        );
    }

    // Scenarios: OAGRANT-P03.
    function test_givenNewNamespaceGrant_whenOldContextReturns_reverts() public {
        _approve(_grant(true));
        _auth.setContext(bytes32(uint256(1)));
        _approve(_grant(true));
        _auth.setContext(0);
        _expectInvalidContext();
        _auth.captureAuthorization(_account, _operator, 1);
        assertEq(_auth.pairEpochs(_account, _operator), 2, "Namespaces share one pair sequence");
    }

    // Scenarios: OAGRANT-I07.
    function test_whenAccountZero_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        g.account = address(0);
        vm.prank(address(0));
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        _auth.approveGrant(g);
    }

    // Scenarios: OAGRANT-N04.
    function test_whenZeroTimestampAndDeadline() public {
        vm.warp(0);
        IOperatorAuth.Grant memory g = _grant(true);
        g.deadline = 0;
        _approve(g);
        assertNotEq(
            _auth.captureAuthorization(_account, _operator, 1),
            bytes32(0),
            "Explicit zero deadline is valid only at timestamp zero"
        );
        vm.warp(1);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, 0)
        );
        _auth.captureAuthorization(_account, _operator, 1);
    }

    // Scenarios: OAGRANT-N05.
    function test_whenPairImmediatelyBelowMax_consumesLastEpoch() public {
        _pairEpoch(type(uint256).max - 1);
        _approve(_grant(true));
        assertEq(
            _auth.pairEpochs(_account, _operator),
            type(uint256).max,
            "Last representable pair epoch consumed without wrap"
        );
        assertNotEq(
            _auth.captureAuthorization(_account, _operator, 1),
            bytes32(0),
            "Final accepted grant remains usable"
        );
    }

    // Scenarios: OAGRANT-N06.
    function test_whenAccountEpochMax_acceptanceDoesNotIncrementIt() public {
        _accountEpoch(type(uint256).max);
        _approve(_grant(true));
        assertEq(
            _auth.accountEpochs(_account),
            type(uint256).max,
            "Acceptance leaves account epoch unchanged"
        );
        assertNotEq(
            _auth.captureAuthorization(_account, _operator, 1),
            bytes32(0),
            "Max account epoch can grant while pair is available"
        );
    }

    // Scenarios: OAGRANT-N07.
    function test_whenMaximumContextAndPermissionLengths() public {
        _auth.setContext(bytes32(type(uint256).max));
        IOperatorAuth.Grant memory g = _grant(true);
        g.permissions = new bytes(320);
        _approve(g);
        assertEq(
            _auth.getGrant(_account, _operator).context,
            bytes32(type(uint256).max),
            "Maximum opaque context retained"
        );
        assertEq(
            _auth.getGrant(_account, _operator).permissions.length,
            320,
            "Maximum consumer payload retained"
        );
    }

    // Scenarios: OAGRANT-N08.
    function test_whenEmptyAndSingleBytePermissions() public {
        IOperatorAuth.Grant memory g = _grant(true);
        g.permissions = "";
        _approve(g);
        assertEq(
            _auth.getGrant(_account, _operator).permissions.length,
            0,
            "Empty permissions permitted by this consumer"
        );
        g = _grant(true);
        g.permissions = hex"ff";
        _approve(g);
        assertEq(
            _auth.getGrant(_account, _operator).permissions,
            hex"ff",
            "One-byte permissions roundtrip"
        );
    }

    // Scenarios: OADEFAULT-P01.
    function test_whenDefaultConsumerApproves_noCoreRequired() public {
        _auth = OperatorAuthHarness(address(new DefaultOperatorAuthHarness(15)));
        IOperatorAuth.Grant memory g = _grant(true);
        _approve(g);
        assertEq(
            _auth.authorizationContext(_account, _operator),
            bytes32(0),
            "Zero is the default actual namespace"
        );
        assertNotEq(
            _auth.captureAuthorization(_account, _operator, 1),
            bytes32(0),
            "Default namespace grants live authority"
        );
    }

    // Scenarios: OATEMP-P01.
    function test_whenAcceptingTransactionContainsRepeatedActions_consumesOneEpoch() public {
        _driver.approveTemporaryAndUseRepeatedly();
        assertEq(_driver.uses(), 3, "Allowed actions repeat in any order");
        assertEq(
            _auth.pairEpochs(address(_driver), _operator),
            1,
            "Only acceptance consumes epoch"
        );
    }

    // Scenarios: OATEMP-P02.
    function test_givenTemporaryGrant_whenSecondTransactionSameBlock_reverts() public {
        uint256 blockBefore = block.number;
        _driver.approveTemporaryAndUseRepeatedly();
        _assertNoGrant(address(_driver), _operator);
        assertEq(block.number, blockBefore, "Transaction isolation does not advance block");
        _expectInvalidContext();
        _auth.captureAuthorization(address(_driver), _operator, 1);
    }

    // Scenarios: OATEMP-P03.
    function test_givenReusableGrant_whenTemporaryReplacementEnds_oldGrantCannotRevive() public {
        _driver.approve(true);
        _driver.approve(false);
        _assertNoGrant(address(_driver), _operator);
        _expectInvalidContext();
        _auth.captureAuthorization(address(_driver), _operator, 1);
        assertEq(
            _auth.pairEpochs(address(_driver), _operator),
            2,
            "Expired temporary acceptance remains consumed"
        );
    }

    // Scenarios: OATEMP-P04.
    function test_givenTemporary_whenReusableReplacesInSameTransaction_newRecordSelected() public {
        _driver.temporaryThenReusable();
        assertTrue(
            _auth.getGrant(address(_driver), _operator).multiple,
            "Current reusable selected over stale transient bytes"
        );
        assertNotEq(
            _auth.captureAuthorization(address(_driver), _operator, 1),
            bytes32(0),
            "Reusable survives next transaction"
        );
    }

    // Scenarios: OATEMP-P05.
    function test_whenTemporaryPayloadShrinks_noStaleTail() public {
        assertEq(
            _driver.longThenShortTemporary(),
            hex"ff",
            "Length selects exact new payload without historical tail"
        );
    }

    // Scenarios: OATEMP-C01.
    function test_whenAcceptingFrameReverts_epochAndPayloadRollback() public {
        vm.expectRevert(OperatorAuthDriver.IntentionalFailure.selector);
        _driver.approveThenRevert();
        assertEq(
            _auth.pairEpochs(address(_driver), _operator),
            0,
            "Reverted acceptance restores persistent counter"
        );
        _expectInvalidContext();
        _auth.captureAuthorization(address(_driver), _operator, 1);
    }

    // Scenarios: OATEMP-C02.
    function test_whenLaterActionFailureCaught_priorAcceptanceSurvives() public {
        assertEq(
            _driver.acceptThenCatchFailure(),
            hex"ff",
            "Earlier acceptance remains after caught action failure"
        );
        assertEq(
            _auth.pairEpochs(address(_driver), _operator),
            1,
            "Caught action failure does not undo prior acceptance"
        );
    }

    // Scenarios: OATEMP-C03.
    function test_givenOriginalAuthority_whenReplacementCompletionFails_rollsBackReplacement()
        public
    {
        _driver.approve(true);
        bytes32 stamp = _auth.captureAuthorization(address(_driver), _operator, 1);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        _driver.replaceThenComplete();
        assertEq(
            _auth.pairEpochs(address(_driver), _operator),
            1,
            "Failed containing frame restores original counter"
        );
        assertEq(
            _auth.captureAuthorization(address(_driver), _operator, 1),
            stamp,
            "Original grant remains after reverted replacement"
        );
    }

    // Scenarios: OAINV-P03.
    function test_whenTemporaryHandlerAccepts() public {
        _handler.changeContext(4);
        _handler.accept(70, 101, 128, false);
        assertEq(_handler.modelPairEpoch(0, 1), 1, "Temporary sequence acceptance succeeds");
    }

    // Scenarios: OAINV-P04.
    function test_whenAcceptingActorReturns_temporaryAuthorityRemainsInParentFrame() public {
        _handler.changeContext(4);
        _handler.acceptAcrossReturnedActor();
        assertEq(
            _auth.pairEpochs(_handler.account(0), _handler.operator(1)),
            1,
            "Acceptance remains consumed after actor RETURN"
        );
    }
}
// forge-lint: disable-end(unused-return)
