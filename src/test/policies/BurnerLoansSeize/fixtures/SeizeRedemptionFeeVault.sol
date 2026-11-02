// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";

// Contracts
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";

/// @dev Switch on a ten-percent redemption fee after the collateral deposit.
contract SeizeRedemptionFeeVault is MockERC4626 {
    bool internal _chargeFee;

    constructor(IERC20 asset_) MockERC4626(asset_, "Redemption fee vault", "RFV") {}

    function chargeRedemptionFee() external {
        _chargeFee = true;
    }

    function previewRedeem(uint256 shares_) public view override returns (uint256) {
        uint256 assets = super.previewRedeem(shares_);
        return _chargeFee ? (assets * 9) / 10 : assets;
    }
}
