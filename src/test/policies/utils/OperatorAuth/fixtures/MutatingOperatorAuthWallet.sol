// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

contract MutatingOperatorAuthWallet {
    uint256 public attempts;

    function isValidSignature(bytes32, bytes calldata) external returns (bytes4) {
        attempts++;
        return 0x1626ba7e;
    }
}
