// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {TransferHelper} from "libraries/TransferHelper.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import "src/Kernel.sol";

contract Faucet is Policy, ReentrancyGuard {
    using TransferHelper for ERC20;

    /* ========== ERRORS =========== */
    error Faucet_InsufficientFunds(Asset asset);
    error Faucet_DripOnCooldown(Asset asset);
    error Faucet_DripFailed(Asset asset);

    /* ========== EVENTS =========== */
    event Drip(address receiver, Asset asset, uint256 amount);

    /* ========== STRUCTS ========== */
    enum Asset {
        ETH,
        OHM,
        RESERVE
    }

    /* ========== STATE VARIABLES ========== */
    mapping(Asset => uint256) public dripAmount;
    mapping(Asset => ERC20) public token;
    mapping(address => mapping(Asset => uint256)) public lastDrip;
    uint256 public dripInterval;

    /* ========== CONSTRUCTOR ========== */
    constructor(
        Kernel kernel_,
        ERC20 ohm_,
        ERC20 reserve_,
        uint256 ethDrip_,
        uint256 ohmDrip_,
        uint256 reserveDrip_,
        uint256 dripInterval_
    ) Policy(kernel_) {
        token[Asset.OHM] = ohm_;
        token[Asset.RESERVE] = reserve_;

        dripAmount[Asset.ETH] = ethDrip_;
        dripAmount[Asset.OHM] = ohmDrip_;
        dripAmount[Asset.RESERVE] = reserveDrip_;

        dripInterval = dripInterval_;
    }

    /* ========== PUBLIC FUNCTIONS ========== */
    function drip(Asset asset_) public nonReentrant {
        if (block.timestamp < lastDrip[msg.sender][asset_] + dripInterval)
            revert Faucet_DripOnCooldown(asset_);

        if (asset_ == Asset.ETH) {
            if (address(this).balance < dripAmount[asset_]) revert Faucet_InsufficientFunds(asset_);
            (bool success, ) = payable(msg.sender).call{value: dripAmount[asset_]}("");
            if (!success) revert Faucet_DripFailed(asset_);
        } else {
            if (token[asset_].balanceOf(address(this)) < dripAmount[asset_])
                revert Faucet_InsufficientFunds(asset_);
            token[asset_].safeTransfer(msg.sender, dripAmount[asset_]);
        }
    }

    function dripTestAmounts() external {
        drip(Asset.ETH);
        drip(Asset.OHM);
        drip(Asset.RESERVE);
    }

    receive() external payable {}

    /* ========== ADMIN FUNCTIONS ========== */

    function withdrawAll(address to_, Asset asset_) external onlyRole("faucet_admin") {
        if (asset_ == Asset.ETH) {
            (bool success, ) = payable(to_).call{value: address(this).balance}("");
            require(success, "Withdraw Failed");
        } else {
            token[asset_].safeTransfer(to_, token[asset_].balanceOf(address(this)));
        }
    }

    function setDripInterval(uint256 interval_) external onlyRole("faucet_admin") {
        dripInterval = interval_;
    }

    function setDripAmount(Asset asset_, uint256 amount_) external onlyRole("faucet_admin") {
        dripAmount[asset_] = amount_;
    }
}
