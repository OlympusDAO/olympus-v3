// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.15;

import {IBasePool} from "./IBasePool.sol";

interface IWeightedPool is IBasePool {
    function getNormalizedWeights() external view returns (uint256[] memory);

    function getInvariant() external view returns (uint256);
}
