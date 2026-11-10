// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Interfaces
import {IERC1271} from "@openzeppelin-5.7.0/interfaces/IERC1271.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {DefaultOperatorAuthHarness} from "src/test/policies/utils/OperatorAuth/DefaultOperatorAuthHarness.sol";
import {OperatorAuthHarness} from "src/test/policies/utils/OperatorAuth/OperatorAuthHarness.sol";
import {OperatorAuthTest} from "src/test/policies/utils/OperatorAuth/OperatorAuthTest.sol";
import {OperatorAuthWallet} from "src/test/policies/utils/OperatorAuth/OperatorAuthWallet.sol";
import {MutatingOperatorAuthWallet} from "src/test/policies/utils/OperatorAuth/fixtures/MutatingOperatorAuthWallet.sol";

contract OperatorAuthAcceptGrantTest is OperatorAuthTest {
    // Scenarios: OASIGN-I17.
    function test_givenReusableGrant_whenSignatureLengthIsInvalid_reverts(uint16 length_) public {
        vm.assume(length_ != 65);
        IOperatorAuth.Grant memory grant = _replacementGrant();
        _assertRejectedReplacement(grant, new bytes(length_));
    }

    // Scenarios: OASIGN-I17.
    function test_givenReusableGrant_whenSignatureLengthBoundarySeeds_reverts() public {
        test_givenReusableGrant_whenSignatureLengthIsInvalid_reverts(0);
        test_givenReusableGrant_whenSignatureLengthIsInvalid_reverts(1);
        test_givenReusableGrant_whenSignatureLengthIsInvalid_reverts(64);
        test_givenReusableGrant_whenSignatureLengthIsInvalid_reverts(66);
        test_givenReusableGrant_whenSignatureLengthIsInvalid_reverts(type(uint16).max);
    }

    // Scenarios: OASIGN-I18.
    function test_givenReusableGrant_whenRecoveryIdIsInvalid_reverts(uint8 recoveryId_) public {
        vm.assume(recoveryId_ != 27 && recoveryId_ != 28);
        IOperatorAuth.Grant memory grant = _replacementGrant();
        bytes memory signature = _signature(grant, "");
        signature[64] = bytes1(recoveryId_);
        _assertRejectedReplacement(grant, signature);
    }

    // Scenarios: OASIGN-I19.
    function test_givenReusableGrant_whenSignatureIsMalleable_reverts() public {
        IOperatorAuth.Grant memory grant = _replacementGrant();
        bytes memory signature = _signature(grant, "");
        bytes32 r;
        bytes32 s;
        assembly ("memory-safe") {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
        }
        // The equivalent (r, n-s, flipped v) signature must not bypass low-s enforcement.
        uint256 order = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;
        uint8 v = uint8(signature[64]) == 27 ? 28 : 27;
        _assertRejectedReplacement(grant, abi.encodePacked(r, bytes32(order - uint256(s)), v));
    }

    // Scenarios: OASIGN-I20.
    function test_givenReusableGrant_whenSignatureRecoversZero_reverts() public {
        IOperatorAuth.Grant memory grant = _replacementGrant();
        _assertRejectedReplacement(grant, abi.encodePacked(bytes32(0), bytes32(0), uint8(27)));
    }

    // Scenarios: OASIGN-I21.
    function test_givenReusableGrant_whenERC1271ReturnIsShort_reverts(uint8 length_) public {
        _account = address(new OperatorAuthWallet(_auth, _operator));
        IOperatorAuth.Grant memory grant = _replacementGrant();
        bytes memory response = abi.encode(IERC1271.isValidSignature.selector);
        uint256 length = bound(length_, 0, 31);
        assembly ("memory-safe") {
            mstore(response, length)
        }
        vm.mockCall(_account, abi.encodeWithSelector(IERC1271.isValidSignature.selector), response);
        _assertRejectedReplacement(grant, hex"11");
    }

    // Scenarios: OASIGN-I22.
    // Fixture/cheatcode calls deliberately interleave effects to exercise callbacks and model transitions.
    // forge-lint: disable-start(reentrancy-no-eth)
    function test_givenReusableGrant_whenERC1271WordIsNoncanonical_reverts(bytes32 word_) public {
        vm.assume(word_ != bytes32(IERC1271.isValidSignature.selector));
        _account = address(new OperatorAuthWallet(_auth, _operator));
        IOperatorAuth.Grant memory grant = _replacementGrant();
        vm.mockCall(
            _account,
            abi.encodeWithSelector(IERC1271.isValidSignature.selector),
            abi.encode(word_)
        );
        _assertRejectedReplacement(grant, hex"11");
    }

    // forge-lint: disable-end(reentrancy-no-eth)

    // Scenarios: OASIGN-I22.
    function test_givenReusableGrant_whenERC1271WordBoundarySeeds_reverts() public {
        test_givenReusableGrant_whenERC1271WordIsNoncanonical_reverts(bytes32(0));
        test_givenReusableGrant_whenERC1271WordIsNoncanonical_reverts(bytes32(uint256(0x1626ba7e)));
        test_givenReusableGrant_whenERC1271WordIsNoncanonical_reverts(
            bytes32(IERC1271.isValidSignature.selector) | bytes32(uint256(1))
        );
        test_givenReusableGrant_whenERC1271WordIsNoncanonical_reverts(bytes32(type(uint256).max));
    }

    // Scenarios: OASIGN-I23.
    function test_givenReusableGrant_whenERC1271Reverts_reverts() public {
        _account = address(new OperatorAuthWallet(_auth, _operator));
        IOperatorAuth.Grant memory grant = _replacementGrant();
        vm.mockCallRevert(
            _account,
            abi.encodeWithSelector(IERC1271.isValidSignature.selector),
            hex"ff"
        );
        _assertRejectedReplacement(grant, hex"11");
    }

    // Scenarios: OASIGN-P05.
    function test_givenReusableGrant_whenERC1271HasCanonicalWordAndTrailingData(
        uint8 extra_
    ) public {
        _account = address(new OperatorAuthWallet(_auth, _operator));
        IOperatorAuth.Grant memory grant = _replacementGrant();
        vm.mockCall(
            _account,
            abi.encodeWithSelector(IERC1271.isValidSignature.selector),
            bytes.concat(abi.encode(IERC1271.isValidSignature.selector), new bytes(extra_))
        );
        bytes memory signature = hex"11";
        vm.expectCall(
            _account,
            abi.encodeCall(IERC1271.isValidSignature, (_digest(grant, ""), signature))
        );
        vm.prank(_operator);
        _auth.acceptGrant(grant, "", signature);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            2,
            "Valid wallet replacement consumes one epoch"
        );
        assertEq(
            abi.encode(_auth.getGrant(_account, _operator)),
            abi.encode(grant),
            "Only accepted replacement becomes current"
        );
    }

    function _replacementGrant() private returns (IOperatorAuth.Grant memory grant) {
        _approve(_grant(true));
        grant = _grant(true);
    }

    // Fixture/cheatcode calls deliberately interleave effects to exercise callbacks and model transitions.
    // forge-lint: disable-start(reentrancy-no-eth)
    function _assertRejectedReplacement(
        IOperatorAuth.Grant memory grant_,
        bytes memory signature_
    ) private {
        uint256 pairEpoch = _auth.pairEpochs(_account, _operator);
        uint256 accountEpoch = _auth.accountEpochs(_account);
        bytes memory original = abi.encode(_auth.getGrant(_account, _operator));
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant(grant_, "", signature_);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            pairEpoch,
            "Invalid signature consumes no pair epoch"
        );
        assertEq(
            _auth.accountEpochs(_account),
            accountEpoch,
            "Invalid signature preserves account epoch"
        );
        assertEq(
            abi.encode(_auth.getGrant(_account, _operator)),
            original,
            "Invalid signature preserves original grant bytes"
        );
        assertEq(
            _auth.captureAuthorization(_account, _operator, 1),
            stamp,
            "Invalid replacement preserves original authority"
        );
    }

    // forge-lint: disable-end(reentrancy-no-eth)

    function _digest(
        IOperatorAuth.Grant memory g,
        bytes memory data_
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _auth.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            _TYPEHASH,
                            g.account,
                            g.operator,
                            g.accountEpoch,
                            g.pairEpoch,
                            g.deadline,
                            g.multiple,
                            g.actions,
                            g.context,
                            keccak256(g.permissions),
                            keccak256(data_)
                        )
                    )
                )
            );
    }

    // Scenarios: OASIGN-A01.
    function test_whenUnrelatedSubmitter_reverts(address caller_) public {
        vm.assume(caller_ != _operator);
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, "");
        vm.prank(caller_);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        _auth.acceptGrant(g, "", s);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            0,
            "Leaked signature did not consume epoch"
        );
    }

    // Scenarios: OASIGN-P01.
    function test_whenDesignatedOperatorAccepts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, "");
        _expectGrantAccepted(_operator, g);
        vm.prank(_operator);
        _auth.acceptGrant(g, "", s);
        assertEq(_auth.pairEpochs(_account, _operator), 1, "Operator acceptance consumes once");
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidEpoch.selector);
        _auth.acceptGrant(g, "", s);
    }

    // Scenarios: OASIGN-A02.
    function test_givenReusableGrant_whenAccountSubmitsSignature_reverts() public {
        IOperatorAuth.Grant memory g = _replacementGrant();
        bytes memory s = _signature(g, "");
        bytes memory original = abi.encode(_auth.getGrant(_account, _operator));
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        vm.prank(_account);
        _auth.acceptGrant(g, "", s);
        assertEq(_auth.pairEpochs(_account, _operator), 1, "Account submission consumes no epoch");
        assertEq(_auth.accountEpochs(_account), 0, "Account submission preserves its namespace");
        assertEq(
            abi.encode(_auth.getGrant(_account, _operator)),
            original,
            "Existing grant retained"
        );
        assertEq(
            _auth.captureAuthorization(_account, _operator, 1),
            stamp,
            "Existing authority retained"
        );
    }

    // Scenarios: OASIGN-I24.
    function test_givenReusableGrant_whenSignedSelfGrantAccepted_reverts() public {
        IOperatorAuth.Grant memory g = _replacementGrant();
        bytes memory original = abi.encode(_auth.getGrant(_account, _operator));
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        g.operator = _account;
        g.pairEpoch = _auth.pairEpochs(_account, _account);
        bytes memory signature = _signature(g, "");
        vm.expectRevert(IOperatorAuth.OperatorAuth_SelfGrant.selector);
        vm.prank(_account);
        _auth.acceptGrant(g, "", signature);
        assertEq(_auth.pairEpochs(_account, _operator), 1, "Original pair epoch is unchanged");
        assertEq(_auth.pairEpochs(_account, _account), 0, "No self-pair epoch is consumed");
        assertEq(_auth.accountEpochs(_account), 0, "Account epoch is unchanged");
        assertEq(
            abi.encode(_auth.getGrant(_account, _operator)),
            original,
            "Original grant retained"
        );
        assertEq(
            _auth.captureAuthorization(_account, _operator, 1),
            stamp,
            "Original authority retained"
        );
        _assertNoGrant(_account, _account);
    }

    // Scenarios: OASIGN-I01.
    function test_whenMalformedSignature_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant(g, "", hex"01");
    }

    // Scenarios: OASIGN-I02.
    function test_whenPermissionsTampered_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, "");
        g.permissions = hex"ff";
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant(g, "", s);
    }

    // Scenarios: OASIGN-I03.
    function test_whenOperatorTampered_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, "");
        g.operator = address(0xCAFE);
        vm.prank(g.operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant(g, "", s);
    }

    // Scenarios: OASIGN-I04.
    function test_whenContextTampered_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, "");
        g.context = bytes32(uint256(1));
        _auth.setContext(g.context);
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant(g, "", s);
    }

    // Scenarios: OASIGN-I05.
    function test_whenDeadlineTampered_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, "");
        g.deadline--;
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant(g, "", s);
    }

    // Scenarios: OASIGN-I06.
    function test_whenModeTampered_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, "");
        g.multiple = false;
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant(g, "", s);
    }

    // Scenarios: OASIGN-I07.
    function test_whenActionsTampered_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, "");
        g.actions = 1;
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant(g, "", s);
    }

    // Scenarios: OASIGN-I08.
    function test_whenAccountEpochTampered_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, "");
        vm.prank(_account);
        _auth.cancelAllGrants();
        g.accountEpoch = 1;
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant(g, "", s);
    }

    // Scenarios: OASIGN-I09.
    function test_whenPairEpochTampered_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, "");
        vm.prank(_account);
        _auth.cancelGrant(_operator);
        g.pairEpoch = 1;
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant(g, "", s);
    }

    // Scenarios: OASIGN-I10.
    function test_whenUnknownSignatureData_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory data_ = abi.encode(uint256(200));
        bytes memory s = _signature(g, data_);
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnsupportedSignatureData.selector);
        _auth.acceptGrant(g, data_, s);
    }

    // Scenarios: OASIGN-P06.
    function test_whenOpaqueSignatureDataAccepted() public {
        _auth.enableSignatureData();
        IOperatorAuth.Grant memory g = _grant(true);
        // Opaque bytes, not another timestamp or expiry.
        bytes memory data_ = abi.encode(bytes32(0));
        bytes memory s = _signature(g, data_);
        vm.prank(_operator);
        _auth.acceptGrant(g, data_, s);
        assertEq(
            abi.encode(_auth.getGrant(_account, _operator)),
            abi.encode(g),
            "Acceptance-only bytes do not alter the stored grant"
        );
        assertEq(_auth.pairEpochs(_account, _operator), 1, "One pair epoch consumed");
        assertTrue(
            _auth.captureAuthorization(_account, _operator, 1) != bytes32(0),
            "Grant is live"
        );
    }

    // Scenarios: OASIGN-I11.
    function test_whenSignatureDataTampered_reverts() public {
        _auth.enableSignatureData();
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, abi.encode(uint256(200)));
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant(g, abi.encode(uint256(201)), s);
    }

    // Scenarios: OASIGN-P04.
    function test_whenERC1271Accepted_policyChangesKeepGrant() public {
        OperatorAuthWallet wallet = new OperatorAuthWallet(_auth, _operator);
        _account = address(wallet);
        IOperatorAuth.Grant memory g = _grant(true);
        wallet.setExpected(_digest(g, ""));
        vm.prank(_operator);
        _auth.acceptGrant(g, "", hex"11");
        assertEq(_auth.pairEpochs(_account, _operator), 1, "Wallet observed preinstallation epoch");
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        wallet.setValid(false);
        assertEq(
            _auth.captureAuthorization(_account, _operator, 1),
            stamp,
            "Accepted grant does not recheck wallet policy"
        );
    }

    // Scenarios: OASIGN-C01.
    function test_whenERC1271Mutates_revertsBeforeInstallation() public {
        MutatingOperatorAuthWallet wallet = new MutatingOperatorAuthWallet();
        _account = address(wallet);
        IOperatorAuth.Grant memory g = _grant(true);
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant{gas: 1_000_000}(g, "", hex"11");
        assertEq(wallet.attempts(), 0, "Static ERC1271 mutation rolled back");
        assertEq(_auth.pairEpochs(_account, _operator), 0, "Invalid wallet consumed no epoch");
    }

    // Scenarios: OASIGN-I13.
    function test_whenSignatureReplayedToOtherAuth_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, "");
        OperatorAuthHarness other = new OperatorAuthHarness();
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        other.acceptGrant(g, "", s);
    }

    // Scenarios: OASIGN-I14.
    function test_whenChainChanges_rejectsOldSignature() public {
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, "");
        vm.chainId(block.chainid + 1);
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant(g, "", s);
    }

    // Scenarios: OASIGN-I15.
    function test_whenAccountTampered_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory signature = _signature(g, "");
        g.account = address(0xD00D);
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        _auth.acceptGrant(g, "", signature);
    }

    // Scenarios: OASIGN-I16.
    function test_whenSignatureDataOversized_reverts() public {
        _auth.enableSignatureData();
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory data_ = new bytes(33);
        bytes memory signature = _signature(g, data_);
        vm.prank(_operator);
        vm.expectRevert(OperatorAuthHarness.InvalidSignatureData.selector);
        _auth.acceptGrant(g, data_, signature);
    }

    // Scenarios: OADEFAULT-P02.
    function test_whenDefaultConsumerAcceptsSignature_noCoreRequired() public {
        _auth = OperatorAuthHarness(address(new DefaultOperatorAuthHarness(15)));
        IOperatorAuth.Grant memory g = _grant(true);
        bytes memory s = _signature(g, "");
        vm.prank(_operator);
        _auth.acceptGrant(g, "", s);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            1,
            "Generic signed acceptance has no target dependency"
        );
    }
}
