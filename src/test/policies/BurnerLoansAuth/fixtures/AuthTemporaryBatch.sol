// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansAuth} from "src/policies/burnerloans/BurnerLoansAuth.sol";
import {AuthCoreMock} from "src/test/policies/BurnerLoansAuth/fixtures/AuthCoreMock.sol";

contract AuthTemporaryBatch {
    function acceptUseAndRotate(
        BurnerLoansAuth auth_,
        BurnerLoansAuth other_,
        AuthCoreMock core_,
        IOperatorAuth.Grant memory grant_
    ) external returns (bool beforeRotation, bool afterRotation) {
        grant_.account = address(this);
        grant_.context = auth_.authorizationContext(address(this), grant_.operator);
        auth_.approveGrant(grant_);
        bytes32 stamp = auth_.captureAuthorization(address(this), grant_.operator, 1);
        beforeRotation =
            auth_.validate(
                address(this),
                grant_.operator,
                1,
                abi.decode(grant_.permissions, (IBurnerLoansAuth.Permissions)).depositAsset,
                address(0),
                stamp
            ) ==
            type(uint128).max;
        core_.select(address(other_));
        core_.select(address(auth_));
        (afterRotation, ) = address(auth_).staticcall(
            abi.encodeCall(auth_.captureAuthorization, (address(this), grant_.operator, uint8(1)))
        );
    }
}
