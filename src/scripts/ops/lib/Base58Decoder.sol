// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {Vm} from "@forge-std-1.9.6/Vm.sol";

/// @title Base58Decoder
/// @notice A library for decoding Base58 encoded strings
library Base58Decoder {
    Vm internal constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    function decode(string memory base58String) public returns (bytes32) {
        string[] memory inputs = new string[](9);
        inputs[0] = "echo";
        inputs[1] = base58String;
        inputs[2] = "|";
        inputs[3] = "bs58 -d";
        inputs[4] = "|";
        inputs[5] = "xxd";
        inputs[6] = "-p";
        inputs[7] = "-c";
        inputs[8] = "32";

        bytes memory res = vm.ffi(inputs);
        bytes memory decodedRes = abi.decode(res, (bytes));
        if (decodedRes.length != 32) {
            // solhint-disable-next-line gas-custom-errors
            revert("Invalid base58 string");
        }

        return bytes32(decodedRes);
    }
}
