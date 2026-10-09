// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.27;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";

// Libraries
import {Math} from "@openzeppelin-5.7.0/utils/math/Math.sol";

// Contracts
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin-5.7.0/token/ERC20/extensions/ERC4626.sol";

/// @notice OZ vault fixture with conversions that omit virtual assets and shares.
/// @dev The established tests expect no virtual assets or shares in conversions.
contract MockERC4626 is ERC4626 {
    error ZeroShares();

    constructor(
        IERC20 underlying_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC4626(underlying_) {}

    function deposit(uint256 assets_, address receiver_) public override returns (uint256 shares) {
        if (previewDeposit(assets_) == 0) revert ZeroShares();
        return super.deposit(assets_, receiver_);
    }

    function _convertToShares(
        uint256 assets_,
        Math.Rounding rounding_
    ) internal view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? assets_ : Math.mulDiv(assets_, supply, totalAssets(), rounding_);
    }

    function _convertToAssets(
        uint256 shares_,
        Math.Rounding rounding_
    ) internal view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares_ : Math.mulDiv(shares_, totalAssets(), supply, rounding_);
    }
}
