// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IBasePool} from "./IBasePool.sol";

interface IStablePool is IBasePool {
    function getLastInvariant() external view returns (uint256, uint256);

    function getRate() external view returns (uint256);

    function getScalingFactors() external view returns (uint256[] memory);
}
