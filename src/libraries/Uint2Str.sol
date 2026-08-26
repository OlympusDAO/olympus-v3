// SPDX-License-Identifier: MIT

/*
Copyright (c) 2015-2016 Oraclize SRL
Copyright (c) 2016-2019 Oraclize LTD
Copyright (c) 2019-2020 Provable Things Limited
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

pragma solidity ^0.8.0;

// Adapted for Solidity 0.8 from Provable Things revision
// c5c926eae55e2616729cc79df7d7d4e2e97d528f:
// https://github.com/provable-things/ethereum-api/blob/c5c926eae55e2616729cc79df7d7d4e2e97d528f/contracts/solidity-v0.6.x/provableAPI_0.6.sol
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
        bstr[k] = bytes1(uint8(48 + (_i % 10)));
        _i /= 10;
    }
    return string(bstr);
}
