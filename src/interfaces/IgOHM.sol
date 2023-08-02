// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

interface IgOHM {
    function balanceFrom(uint256 gohmAmount_) external view returns (uint256);

    function balanceTo(uint256 ohmAmount_) external view returns (uint256);
}
