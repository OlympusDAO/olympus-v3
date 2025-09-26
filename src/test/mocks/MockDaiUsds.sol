// SPDX-License-Identifier: AGPL-3.0
// solhint-disable custom-errors
pragma solidity ^0.8.0;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IDaiUsds} from "policies/ReserveMigrator.sol";

/// @dev This is a mock converter contract that trades one ERC20 token for another at a fixed 1:1 ratio
/// by minting and burning the tokens. It is based on the DaiUsds contract.
contract MockDaiUsds is IDaiUsds {
    MockERC20 public dai;
    MockERC20 public usds;

    constructor(MockERC20 dai_, MockERC20 usds_) {
        dai = dai_;
        usds = usds_;
    }

    function daiToUsds(address usr, uint256 wad) external override {
        // Mock ERC20 does not check allowance, so check it here
        if (dai.allowance(usr, address(this)) < wad) revert("allowance");

        dai.burn(usr, wad);
        usds.mint(usr, wad);
    }

    function usdsToDai(address usr, uint256 wad) external {
        // Mock ERC20 does not check allowance, so check it here
        if (usds.allowance(usr, address(this)) < wad) revert("allowance");

        usds.burn(usr, wad);
        dai.mint(usr, wad);
    }
}
