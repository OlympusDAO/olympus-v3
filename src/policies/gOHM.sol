// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Kernel, Policy} from "../Kernel.sol";
import {OlympusStaking} from "../modules/STK.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IERC20} from "../interfaces/IERC20.sol";

contract gOHM is Policy, IERC4626, IERC20 {
    using TransferHelper for IERC20;

    OlympusStaking public STK;

    address public immutable asset;

    string public constant name = "Governance Olympus";
    string public constant symbol = "gOHM";
    uint8 public constant decimals = 18;

    constructor(Kernel kernel_, address ohm_) Policy(kernel_) {
        asset = ohm_;
    }

    function configureModules() external override onlyKernel {
        STK = OlympusStaking(requireModule("STK"));
        // TODO add CCX (cross chain transmitter)
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256)
    {
        uint256 shares = _stake(msg.sender, receiver, assets);
        emit Deposit(msg.sender, receiver, assets, shares);
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
        //uint256 shares = convertToShares(assets);
        //staking.unstakeIndexed(owner, receiver, shares);
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
        IERC20(asset).safeTransferFrom(from_, address(STK), nominal_);
        return STK.convertToIndexed(address(STK), to_, nominal_);
    }

    function _unstake(
        address from_,
        address to_,
        uint256 nominal_
    ) internal returns (uint256) {
        uint256 shares = convertToShares(nominal_);
        STK.convertToNominal(from_, address(STK), shares);
        IERC20(asset).safeTransferFrom(address(STK), to_, nominal_);
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
        STK.transferIndexed(msg.sender, to_, amount_);
        emit Transfer(msg.sender, to_, amount_);
        return true;
    }

    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    ) external override returns (bool) {
        STK.transferIndexed(from_, to_, amount_);
        emit Transfer(from_, to_, amount_);
        return true;
    }

    function allowance(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return STK.getAllowanceIndexed(owner, spender);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        STK.approveIndexed(spender, amount);
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /*///////////////////////////////////////////////////////////////
                           ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function balanceOf(address who_) public view returns (uint256) {
        return STK.getIndexedBalance(who_);
    }

    function totalAssets() public view returns (uint256) {
        return IERC20(asset).balanceOf(address(STK));
    }

    function totalSupply() public view returns (uint256) {
        return STK.nominalSupply();
    }

    //was fromSerialized()
    /// @notice Utility function to convert gOHM value into OHM value.
    function convertToAssets(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        return STK.getNominalValue(shares);
    }

    //was toSerialized()
    /// @notice Utility function to convert OHM value into gOHM value.
    function convertToShares(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        return STK.getIndexedValue(assets);
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

    /// @notice Convenience function to get sOHM index.
    function getIndex() public view returns (uint256) {
        return STK.index();
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

    function maxDeposit(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return convertToAssets(STK.getIndexedBalance(owner));
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return STK.getIndexedBalance(owner);
    }
}
