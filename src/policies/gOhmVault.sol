// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Kernel, Policy} from "../Kernel.sol";
import {OlympusStaking} from "../modules/STK.sol";
import {OlympusIndex} from "../modules/IDX.sol";
import {OlympusMinter} from "../modules/MNT.sol";

import {IERC4626} from "../interfaces/IERC4626.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";

contract gOhmVault is Policy, IERC4626, IERC20 {
    using TransferHelper for IERC20;

    OlympusStaking private STK;
    OlympusIndex private IDX;
    OlympusMinter private MNT;

    address public immutable asset;

    string public constant name = "Governance Olympus";
    string public constant symbol = "gOHM";
    uint8 public constant decimals = 18;

    constructor(Kernel kernel_, address ohm_) Policy(kernel_) {
        asset = ohm_;
    }

    function configureModules() external override onlyKernel {
        STK = OlympusStaking(requireModule("STK"));
        MNT = OlympusMinter(requireModule("MNT"));
        IDX = OlympusIndex(requireModule("IDX"));
        // TODO add CCX (cross chain transmitter)
    }

    function requestPermissions()
        external
        view
        override
        onlyKernel
        returns (bytes3[] memory permissions)
    {
        permissions[1] = "STK";
        permissions[2] = "MNT";
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets_, address receiver_)
        public
        override
        returns (uint256)
    {
        uint256 shares = convertToShares(assets_);
        MNT.burnOhm(msg.sender, assets_);
        STK.mint(msg.sender, assets_ * IDX.index());
        emit Deposit(msg.sender, receiver_, assets_, shares);
        return shares;
    }

    // Like deposit(), but specifies amount of shares the user wants to receive
    // Transfers assets equal to shares specified from sender
    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256)
    {
        uint256 assets = convertToAssets(shares);
        _stake(msg.sender, receiver, assets);
        emit Deposit(msg.sender, receiver, assets, shares);
        return assets;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256) {
        uint256 shares = _unstake(owner, receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256) {
        uint256 assets = convertToAssets(shares);
        _unstake(owner, receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return assets;
    }

    function _stake(
        address from_,
        address to_,
        uint256 nominal_
    ) internal returns (uint256) {
        uint256 shares = convertToShares(nominal_);
        MNT.burnOhm(from_, nominal_);
        STK.mint(to_, shares);
        return shares;
    }

    function _unstake(
        address from_,
        address to_,
        uint256 nominal_
    ) internal returns (uint256) {
        uint256 shares = convertToShares(nominal_);
        STK.burn(from_, shares);
        MNT.mintOhm(to_, nominal_);
        return shares;
    }

    /*///////////////////////////////////////////////////////////////
                        ERC20 Logic
    //////////////////////////////////////////////////////////////*/

    function transfer(address to_, uint256 amount_)
        external
        override
        returns (bool)
    {
        STK.transferFrom(msg.sender, to_, amount_);
        emit Transfer(msg.sender, to_, amount_);
        return true;
    }

    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    ) external override returns (bool) {
        STK.transferFrom(from_, to_, amount_);
        emit Transfer(from_, to_, amount_);
        return true;
    }

    function allowance(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return STK.allowances(owner, spender);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        STK.approve(msg.sender, spender, amount);
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /*///////////////////////////////////////////////////////////////
                           ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function balanceOf(address who_) public view returns (uint256) {
        return STK.indexedBalance(who_);
    }

    function totalAssets() public view returns (uint256) {
        return IERC20(asset).balanceOf(address(STK));
    }

    function totalSupply() public view returns (uint256) {
        return STK.indexedSupply();
    }

    //was fromSerialized()
    /// @notice Utility function to convert gOHM value into OHM value.
    function convertToAssets(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        // TODO use FullMath or equivalent
        return shares * IDX.index();
    }

    //was toSerialized()
    /// @notice Utility function to convert OHM value into gOHM value.
    function convertToShares(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        // TODO use FullMath or equivalent
        return assets / IDX.index();
    }

    function previewDeposit(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        return convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        return convertToShares(assets);
    }

    /// @notice Convenience function to get index.
    function getIndex() public view returns (uint256) {
        return IDX.index();
    }

    function previewRedeem(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        return convertToAssets(shares);
    }

    /*///////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    // TODO verify
    function maxDeposit(address) public pure override returns (uint256) {
        // TODO should be related to STK.TOTAL_GONS?
        return type(uint256).max;
    }

    // TODO verify
    function maxMint(address) public pure override returns (uint256) {
        // TODO should be related to STK.TOTAL_GONS?
        return type(uint256).max;
    }

    // TODO verify
    function maxWithdraw(address owner) public view override returns (uint256) {
        return convertToAssets(STK.indexedBalance(owner));
    }

    // TODO verify
    function maxRedeem(address owner) public view override returns (uint256) {
        return STK.indexedBalance(owner);
    }
}
