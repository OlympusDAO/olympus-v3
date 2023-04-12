// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "src/types/ERC20Permit.sol";
import "./GDAOAccessControlled.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

interface ITestGDAO is IERC20 {
      function mint(address account_, uint256 amount_) external;

    function burn(uint256 amount) external;

    function burnFrom(address account_, uint256 amount_) external;

}

contract TestGDAO is ERC20Permit, ITestGDAO, GDAOAccessControlled {
    using SafeMath for uint256;

    constructor(address _authority)
        ERC20("TEST Goerli DAO", "GDAO", 9)
        ERC20Permit("TEST Goerli DAO")
        GDAOAccessControlled(IGDAOAuthority(_authority))
    {}

    function mint(address account_, uint256 amount_) external override onlyVault {
        _mint(account_, amount_);
    }

    function faucetMint(address recipient_) external {
        _mint(recipient_, 10000000000);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account_, uint256 amount_) external override {
        _burnFrom(account_, amount_);
    }

    function _burnFrom(address account_, uint256 amount_) internal {
        uint256 decreasedAllowance_ = allowance(account_, msg.sender).sub(
            amount_,
            "ERC20: burn amount exceeds allowance"
        );

        _approve(account_, msg.sender, decreasedAllowance_);
        _burn(account_, amount_);
    }
}