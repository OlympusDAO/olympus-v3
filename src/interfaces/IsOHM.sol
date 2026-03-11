// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";

interface IsOHM is IERC20 {
    function setIndex(uint256 _index) external;

    function setgOHM(address _gOHM) external;

    function initialize(address _stakingContract, address _treasury) external;

    function index() external view returns (uint256);

    function gOHM() external view returns (address);

    function stakingContract() external view returns (address);

    function treasury() external view returns (address);

    function circulatingSupply() external view returns (uint256);

    function gonsForBalance(uint256 amount) external view returns (uint256);

    function balanceForGons(uint256 gons) external view returns (uint256);
}
