// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.27;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";

// Libraries
import {Math} from "@openzeppelin-5.7.0/utils/math/Math.sol";

// Contracts
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin-5.7.0/token/ERC20/extensions/ERC4626.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @notice Proportional vault that can realize a configured loss/yield during settlement.
contract DepositSettlementVault is ERC4626 {
    uint256 internal _loss;
    uint256 internal _yield;
    address internal _callbackTarget;
    bytes internal _callbackData;
    bool public callbackSucceeded;
    bytes public callbackResult;

    constructor(IERC20 asset_) ERC20("Settlement vault", "SETTLE") ERC4626(asset_) {}

    function setSettlementLoss(uint256 amount_) external {
        _loss = amount_;
    }

    function setSettlementYield(uint256 amount_) external {
        _yield = amount_;
    }

    function setCallback(address target_, bytes calldata data_) external {
        _callbackTarget = target_;
        _callbackData = data_;
    }

    function approveAsset(address spender_, uint256 amount_) external {
        IERC20(asset()).approve(spender_, amount_);
    }

    function deposit(uint256 assets_, address receiver_) public override returns (uint256 shares) {
        shares = super.deposit(assets_, receiver_);
        if (_loss != 0) MockERC20(asset()).burn(address(this), _loss);
        if (_yield != 0) MockERC20(asset()).mint(address(this), _yield);
        if (_callbackTarget != address(0)) {
            (callbackSucceeded, callbackResult) = _callbackTarget.call(_callbackData);
        }
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
