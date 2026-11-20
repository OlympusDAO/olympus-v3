// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {StdStorage, stdStorage} from "@forge-std-1.16.2/StdStorage.sol";

// Contracts
import {OperatorAuthHarness} from "./OperatorAuthHarness.sol";
import {Test} from "@forge-std-1.16.2/Test.sol";

abstract contract OperatorAuthTest is Test {
    event GrantAccepted(
        address indexed caller,
        address indexed account,
        address indexed operator,
        uint256 accountEpoch,
        uint256 pairEpoch,
        uint48 deadline,
        bool multiple,
        uint8 actions,
        bytes32 context,
        bytes32 permissionsHash
    );

    function _expectGrantAccepted(address caller_, IOperatorAuth.Grant memory g) internal {
        vm.expectEmit(true, true, true, true, address(_auth));
        emit GrantAccepted(
            caller_,
            g.account,
            g.operator,
            g.accountEpoch,
            g.pairEpoch,
            g.deadline,
            g.multiple,
            g.actions,
            g.context,
            keccak256(g.permissions)
        );
    }

    using stdStorage for StdStorage;
    OperatorAuthHarness internal _auth;
    address internal _account;
    address internal _operator = address(0xB0B);
    uint256 internal constant _ACCOUNT_KEY = 0xA11CE;
    bytes32 internal constant _TYPEHASH =
        keccak256(
            "Grant(address account,address operator,uint256 accountEpoch,uint256 pairEpoch,uint48 deadline,bool multiple,uint8 actions,bytes32 context,bytes32 permissionsHash,bytes32 signatureDataHash)"
        );

    function setUp() public virtual {
        _auth = new OperatorAuthHarness();
        _account = vm.addr(_ACCOUNT_KEY);
        vm.warp(100);
    }

    function _grant(bool multiple_) internal view returns (IOperatorAuth.Grant memory) {
        return
            IOperatorAuth.Grant(
                _account,
                _operator,
                _auth.accountEpochs(_account),
                _auth.pairEpochs(_account, _operator),
                type(uint48).max,
                multiple_,
                15,
                _auth.authorizationContext(_account, _operator),
                hex"010203"
            );
    }

    // Fixture/cheatcode calls deliberately interleave effects to exercise callbacks and model transitions.
    // forge-lint: disable-start(reentrancy-no-eth)
    function _approve(IOperatorAuth.Grant memory grant_) internal {
        vm.prank(grant_.account);
        _auth.approveGrant(grant_);
    }

    // forge-lint: disable-end(reentrancy-no-eth)

    function _signature(
        IOperatorAuth.Grant memory grant_,
        bytes memory data_
    ) internal view returns (bytes memory) {
        bytes32 hash = keccak256(
            abi.encode(
                _TYPEHASH,
                grant_.account,
                grant_.operator,
                grant_.accountEpoch,
                grant_.pairEpoch,
                grant_.deadline,
                grant_.multiple,
                grant_.actions,
                grant_.context,
                keccak256(grant_.permissions),
                keccak256(data_)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _ACCOUNT_KEY,
            keccak256(abi.encodePacked("\x19\x01", _auth.DOMAIN_SEPARATOR(), hash))
        );
        return abi.encodePacked(r, s, v);
    }

    function _pairEpoch(uint256 value_) internal {
        stdstore
            .target(address(_auth))
            .sig("pairEpochs(address,address)")
            .with_key(_account)
            .with_key(_operator)
            .checked_write(value_);
    }

    function _accountEpoch(uint256 value_) internal {
        stdstore
            .target(address(_auth))
            .sig("accountEpochs(address)")
            .with_key(_account)
            .checked_write(value_);
    }

    // These calls enumerate bounded test actors/assets, including fixture helpers called by the loops.
    // forge-lint: disable-start(calls-loop)
    function _assertNoGrant(address account_, address operator_) internal view {
        IOperatorAuth.Grant memory empty;
        assertEq(
            abi.encode(_auth.getGrant(account_, operator_)),
            abi.encode(empty),
            "Getter returns a completely empty grant"
        );
    }

    // forge-lint: disable-end(calls-loop)

    function _expectInvalidContext() internal {
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
    }
}
