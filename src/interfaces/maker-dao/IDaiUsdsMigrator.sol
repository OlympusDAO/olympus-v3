// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IDaiUsdsMigrator {
    event DaiToUsds(address indexed caller, address indexed usr, uint256 wad);
    event UsdsToDai(address indexed caller, address indexed usr, uint256 wad);

    function dai() external view returns (address);
    function daiJoin() external view returns (address);
    function daiToUsds(address usr, uint256 wad) external;
    function usds() external view returns (address);
    function usdsJoin() external view returns (address);
    function usdsToDai(address usr, uint256 wad) external;
}
