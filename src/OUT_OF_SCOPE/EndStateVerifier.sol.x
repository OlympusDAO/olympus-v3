// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

interface EndStateVerifier {
    // explicitly not static to allow anything
    function verify() external returns (bool result, string memory failMessage);
}
