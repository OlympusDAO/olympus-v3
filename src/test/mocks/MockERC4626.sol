// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

contract MockERC4626 is ERC4626 {
    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset, _name, _symbol) {}


    function totalAssets() public view override returns (uint256) {
      return 0;
    }
}