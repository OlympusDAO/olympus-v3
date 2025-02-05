// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Some fancy math to convert a uint into a string, courtesy of Provable Things.
// Updated to work with solc 0.8.0.
// https://github.com/provable-things/ethereum-api/blob/master/provableAPI_0.6.sol
function uint2str(uint256 _i) pure returns (string memory) {
    if (_i == 0) {
        return "0";
    }
    uint256 j = _i;
    uint256 len;
    while (j != 0) {
        len++;
        j /= 10;
    }
    bytes memory bstr = new bytes(len);
    uint256 k = len;
    while (_i != 0) {
        k = k - 1;
        uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
        bytes1 b1 = bytes1(temp);
        bstr[k] = b1;
        _i /= 10;
    }
    return string(bstr);
}
