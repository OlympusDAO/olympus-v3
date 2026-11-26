// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";

// Libraries
import {Math} from "@openzeppelin-5.7.0/utils/math/Math.sol";

// Contracts
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin-5.7.0/token/ERC20/extensions/ERC4626.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @notice Realizes a configured underlying loss after a synchronous vault deposit.
contract BurnerLoansCollateralLossVault is ERC4626 {
    uint256 internal _loss;

    constructor(IERC20 underlying_) ERC20("Loss Vault", "LOSS") ERC4626(underlying_) {}

    function setDepositLoss(uint256 loss_) external {
        _loss = loss_;
    }

    function deposit(uint256 assets_, address receiver_) public override returns (uint256 shares) {
        shares = super.deposit(assets_, receiver_);
        if (_loss != 0) MockERC20(asset()).burn(address(this), _loss);
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
