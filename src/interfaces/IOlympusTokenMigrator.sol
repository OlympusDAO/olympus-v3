// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

interface IOlympusTokenMigrator {
    enum TYPE {
        UNSTAKED,
        STAKED,
        WRAPPED
    }

    function migrate(uint256 _amount, TYPE _from, TYPE _to) external;

    function oldSupply() external view returns (uint256);
}
