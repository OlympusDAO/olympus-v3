// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IERC20} from "src/external/OlympusERC20.sol";

interface IgOHM is IERC20 {
    function mint(address _to, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;

    function index() external view returns (uint256);

    /**
        @notice converts gOHM amount to OHM
        @param _amount uint
        @return uint
     */
    function balanceFrom(uint256 _amount) external view returns (uint256);

    /**
        @notice converts OHM amount to gOHM
        @param _amount uint
        @return uint
     */
    function balanceTo(uint256 _amount) external view returns (uint256);

    function migrate(address _staking, address _sOHM) external;
}
