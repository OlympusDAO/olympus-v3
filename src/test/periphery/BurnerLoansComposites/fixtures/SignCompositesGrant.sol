// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.34;

import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {BurnerLoansAuth} from "src/policies/burnerloans/BurnerLoansAuth.sol";

function signCompositesGrant(
    Vm vm_,
    BurnerLoansAuth auth_,
    IOperatorAuth.Grant memory grant_,
    uint256 key_
) view returns (IExecutor.SignedGrant memory) {
    bytes32 digest = auth_.grantDigest(grant_, "");
    (uint8 v, bytes32 r, bytes32 s) = vm_.sign(key_, digest);
    return IExecutor.SignedGrant(grant_, bytes(""), abi.encodePacked(r, s, v));
}
