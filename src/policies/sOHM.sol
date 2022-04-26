// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {Kernel, Policy} from "../Kernel.sol";
import {OlympusStaking} from "../modules/STK.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IERC20} from "../interfaces/IERC20.sol";

/// @notice sOHM token and vault that acts as a policy
contract sOHM is Policy, IERC4626, IERC20 {
    using TransferHelper for IERC20;

    OlympusStaking private STK;

    address public immutable asset;

    string public constant name = "Staked Olympus";
    string public constant symbol = "sOHM";
    uint8 public constant decimals = 9;

    constructor(Kernel kernel_, address ohm_) Policy(kernel_) {
        asset = ohm_;
    }

    function configureModules() external override onlyKernel {
        STK = OlympusStaking(requireModule("STK"));
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256)
    {
        _stake(msg.sender, receiver, assets);
        emit Deposit(msg.sender, receiver, assets, assets);
        return assets;
    }

    // Like deposit(), but specifies amount of shares the user wants to receive
    // Transfers assets equal to shares specified from sender
    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256)
    {
        _stake(msg.sender, receiver, shares);
        emit Deposit(msg.sender, receiver, shares, shares);
        return shares;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256) {
        _unstake(owner, receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, assets);
        return assets;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public returns (uint256) {
        _unstake(owner, receiver, shares);
        emit Withdraw(msg.sender, receiver, owner, shares, shares);
        return shares;
    }

    function _stake(
        address from_,
        address to_,
        uint256 amount_
    ) internal {
        IERC20(asset).safeTransferFrom(from_, to_, amount_);
        STK.transferNominal(address(STK), to_, amount_);
        // TODO instead, mint and propagate via CCX
    }

    function _unstake(
        address from_,
        address to_,
        uint256 amount_
    ) internal {
        STK.transferNominal(from_, to_, amount_);
        IERC20(asset).safeTransferFrom(from_, address(STK), amount_);
        // TODO instead, burn and propagate via CCX
    }

    /*///////////////////////////////////////////////////////////////
                        ERC20 Logic
    //////////////////////////////////////////////////////////////*/

    function transfer(address to_, uint256 amount_)
        external
        override
        returns (bool)
    {
        STK.transferNominal(msg.sender, to_, amount_);

        emit Transfer(msg.sender, to_, amount_);
        return true;
    }

    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    ) external override returns (bool) {
        STK.transferNominal(from_, to_, amount_);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return STK.getAllowanceNominal(owner, spender);
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        return STK.approveNominal(spender, amount);
    }

    /*///////////////////////////////////////////////////////////////
                           ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function balanceOf(address who_) public view override returns (uint256) {
        return STK.getNominalBalance(who_);
    }

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset).balanceOf(address(STK));
    }

    function totalSupply() public view override returns (uint256) {
        return STK.nominalSupply();
    }

    /// @notice Utility function to convert sOHM value into OHM value.
    function convertToAssets(uint256 shares)
        public
        pure
        override
        returns (uint256)
    {
        return shares;
    }

    /// @notice Utility function to convert OHM value into sOHM value.
    function convertToShares(uint256 assets)
        public
        pure
        override
        returns (uint256)
    {
        return assets;
    }

    function previewDeposit(uint256 assets)
        public
        pure
        override
        returns (uint256)
    {
        return assets;
    }

    function previewMint(uint256 shares)
        public
        pure
        override
        returns (uint256)
    {
        return shares;
    }

    function previewWithdraw(uint256 assets)
        public
        pure
        override
        returns (uint256)
    {
        return assets;
    }

    /// @notice Convenience function to get sOHM index.
    function getIndex() public view returns (uint256) {
        return STK.index();
    }

    function previewRedeem(uint256 shares)
        public
        pure
        override
        returns (uint256)
    {
        return shares;
    }

    /*///////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return STK.nominalGonsBalance(owner);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return STK.nominalGonsBalance(owner);
    }
}
