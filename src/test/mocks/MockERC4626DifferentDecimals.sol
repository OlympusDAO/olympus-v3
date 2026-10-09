// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// This mock structurally implements IERC4626 but uses Solmate ERC20 for configurable share decimals.
// Explicit IERC4626 inheritance conflicts with the ERC20 base's public getters.
// forge-lint: disable-start(missing-inheritance)

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";
import {FullMath} from "src/libraries/FullMath.sol";

/// @notice Minimal 1:1-value ERC-4626 test vault with independently configurable share decimals.
contract MockERC4626DifferentDecimals is ERC20 {
    using SafeTransferLib for ERC20;

    uint256 internal constant _DECIMAL_BASE = 10;

    ERC20 internal immutable _ASSET;
    uint256 internal immutable _ASSET_SCALE;
    uint256 internal immutable _SHARE_SCALE;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    constructor(
        ERC20 asset_,
        uint8 shareDecimals_
    ) ERC20("Different Decimals Vault", "DDV", shareDecimals_) {
        _ASSET = asset_;
        _ASSET_SCALE = _DECIMAL_BASE ** asset_.decimals();
        _SHARE_SCALE = _DECIMAL_BASE ** shareDecimals_;
    }

    function asset() external view returns (address) {
        return address(_ASSET);
    }

    function totalAssets() external view returns (uint256) {
        return _ASSET.balanceOf(address(this));
    }

    function convertToShares(uint256 assets_) public view returns (uint256) {
        return FullMath.mulDiv(assets_, _SHARE_SCALE, _ASSET_SCALE);
    }

    function convertToAssets(uint256 shares_) public view returns (uint256) {
        return FullMath.mulDiv(shares_, _ASSET_SCALE, _SHARE_SCALE);
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets_) external view returns (uint256) {
        return convertToShares(assets_);
    }

    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares) {
        shares = convertToShares(assets_);
        _ASSET.safeTransferFrom(msg.sender, address(this), assets_);
        _mint(receiver_, shares);
        emit Deposit(msg.sender, receiver_, assets_, shares);
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewMint(uint256 shares_) external view returns (uint256) {
        return convertToAssets(shares_);
    }

    function mint(uint256 shares_, address receiver_) external returns (uint256 assets) {
        assets = convertToAssets(shares_);
        _ASSET.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver_, shares_);
        emit Deposit(msg.sender, receiver_, assets, shares_);
    }

    function maxWithdraw(address owner_) external view returns (uint256) {
        return convertToAssets(balanceOf[owner_]);
    }

    function previewWithdraw(uint256 assets_) external view returns (uint256) {
        return convertToShares(assets_);
    }

    function withdraw(
        uint256 assets_,
        address receiver_,
        address owner_
    ) external returns (uint256 shares) {
        shares = convertToShares(assets_);
        _spendAndBurn(owner_, shares);
        _ASSET.safeTransfer(receiver_, assets_);
        emit Withdraw(msg.sender, receiver_, owner_, assets_, shares);
    }

    function maxRedeem(address owner_) external view returns (uint256) {
        return balanceOf[owner_];
    }

    function previewRedeem(uint256 shares_) external view returns (uint256) {
        return convertToAssets(shares_);
    }

    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) external returns (uint256 assets) {
        assets = convertToAssets(shares_);
        _spendAndBurn(owner_, shares_);
        _ASSET.safeTransfer(receiver_, assets);
        emit Withdraw(msg.sender, receiver_, owner_, assets, shares_);
    }

    function _spendAndBurn(address owner_, uint256 shares_) internal {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender];
            if (allowed != type(uint256).max) allowance[owner_][msg.sender] = allowed - shares_;
        }
        _burn(owner_, shares_);
    }
}

// forge-lint: disable-end(missing-inheritance)
