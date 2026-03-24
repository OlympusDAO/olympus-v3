// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

interface IOlympusTreasury {
    enum MANAGING {
        RESERVEDEPOSITOR,
        RESERVESPENDER,
        RESERVETOKEN,
        RESERVEMANAGER,
        LIQUIDITYDEPOSITOR,
        LIQUIDITYTOKEN,
        LIQUIDITYMANAGER,
        DEBTOR,
        REWARDMANAGER,
        SOHM
    }

    function queue(MANAGING _managing, address _address) external returns (bool);

    function toggle(
        MANAGING _managing,
        address _address,
        address _calculator
    ) external returns (bool);

    function isReserveToken(address) external view returns (bool);

    function isReserveDepositor(address) external view returns (bool);

    function excessReserves() external view returns (uint256);

    function valueOf(address _token, uint256 _amount) external view returns (uint256 value_);

    function reserveTokenQueue(address) external view returns (uint256);

    function reserveDepositorQueue(address) external view returns (uint256);

    function deposit(
        uint256 _amount,
        address _token,
        uint256 _profit
    ) external returns (uint256 send_);
}
