// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {BurnerLoansAuth} from "src/policies/burnerloans/BurnerLoansAuth.sol";
import {AuthCoreMock} from "src/test/policies/BurnerLoansAuth/fixtures/AuthCoreMock.sol";
import {AuthKernelMock} from "src/test/policies/BurnerLoansAuth/fixtures/AuthKernelMock.sol";

abstract contract BurnerLoansAuthTest is Test {
    uint256 internal constant _SIGNER_KEY = 0xA11CE;
    address internal _account;
    address internal _operator = address(0xB0B);
    address internal _recipient = address(0xCAFE);
    address internal _asset = address(0xA55E7);
    address internal _otherAsset = address(0xB55E7);
    AuthKernelMock internal _kernel;
    AuthCoreMock internal _core;
    BurnerLoansAuth internal _auth;

    function setUp() public virtual {
        _account = vm.addr(_SIGNER_KEY);
        _kernel = new AuthKernelMock();
        _core = new AuthCoreMock(address(_kernel));
        _core.setAsset(_asset, true);
        _core.setAsset(_otherAsset, true);
        _auth = new BurnerLoansAuth(address(_kernel), address(_core));
        _core.select(address(_auth));
    }

    function _permissions() internal view returns (IBurnerLoansAuth.Permissions memory) {
        return
            IBurnerLoansAuth.Permissions({
                depositAsset: _asset,
                maxCollateral: type(uint128).max,
                borrowAsset: _asset,
                borrowRecipient: _recipient,
                maxDebt: type(uint128).max,
                withdrawAsset: _asset,
                withdrawRecipient: _recipient,
                minCollateral: 0,
                extendAsset: _asset,
                maxMaturity: type(uint48).max
            });
    }

    // These calls enumerate bounded test actors/assets, including fixture helpers called by the loops.
    // forge-lint: disable-start(calls-loop)
    function _grant(
        uint8 actions_,
        bool multiple_
    ) internal view returns (IOperatorAuth.Grant memory) {
        return
            IOperatorAuth.Grant({
                account: _account,
                operator: _operator,
                accountEpoch: _auth.accountEpochs(_account),
                pairEpoch: _auth.pairEpochs(_account, _operator),
                deadline: type(uint48).max,
                multiple: multiple_,
                actions: actions_,
                context: _auth.authorizationContext(_account, _operator),
                permissions: abi.encode(_permissions())
            });
    }

    // forge-lint: disable-end(calls-loop)

    // These calls enumerate bounded test actors/assets, including fixture helpers called by the loops.
    // forge-lint: disable-start(calls-loop)
    function _approve(IOperatorAuth.Grant memory grant_) internal {
        vm.prank(grant_.account);
        _auth.approveGrant(grant_);
    }

    // forge-lint: disable-end(calls-loop)

    function _sign(
        IOperatorAuth.Grant memory grant_,
        BurnerLoansAuth auth_
    ) internal view returns (bytes memory) {
        bytes32 typeHash = keccak256(
            "Grant(address account,address operator,uint256 accountEpoch,uint256 pairEpoch,uint48 deadline,bool multiple,uint8 actions,bytes32 context,bytes32 permissionsHash,bytes32 signatureDataHash)"
        );
        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                grant_.account,
                grant_.operator,
                grant_.accountEpoch,
                grant_.pairEpoch,
                grant_.deadline,
                grant_.multiple,
                grant_.actions,
                grant_.context,
                keccak256(grant_.permissions),
                keccak256(bytes(""))
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", auth_.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_SIGNER_KEY, digest);
        return abi.encodePacked(r, s, v);
    }
}
