// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.7.5;

/// @notice Goerli DAO (GDAO) token
/// @dev This contract is the legacy v2 OHM token. Included in the repo for completeness,
///      since it is not being changed and is imported in some contracts.

// File: GDAO.sol

import "src/types/ERC20Permit.sol";
import "src/interfaces/IOlympusAuthority.sol";
import "src/types/OlympusAccessControlled.sol";
import "src/interfaces/IGDAO.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";


contract GDAO is ERC20Permit, IGDAO, OlympusAccessControlled {
    using SafeMath for uint256;

    constructor(address _authority)
        ERC20("Goerli Dao", "GDAO", 9)
        ERC20Permit("Goerli Dao")
        OlympusAccessControlled(IOlympusAuthority(_authority))
    {}

    function mint(address account_, uint256 amount_) external override onlyVault {
        _mint(account_, amount_);
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
