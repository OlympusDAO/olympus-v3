// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity >=0.8.0;

//import {IERC20} from "../interfaces/IERC20.sol";

//interface IERC4626 is IERC20 {
interface IERC4626 {
    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    function asset() external view returns (address assetTokenAddress);

    function totalAssets() external view returns (uint256 totalManagedAssets);

    function convertToShares(uint256 assets)
        external
        view
        returns (uint256 shares);

    function convertToAssets(uint256 shares)
        external
        view
        returns (uint256 assets);

    function maxDeposit(address receiver)
        external
        view
        returns (uint256 maxAssets);

    function previewDeposit(uint256 assets)
        external
        view
        returns (uint256 shares);

    function deposit(uint256 assets, address receiver)
        external
        returns (uint256 shares);

    function maxMint(address receiver)
        external
        view
        returns (uint256 maxShares);

    function previewMint(uint256 shares) external view returns (uint256 assets);

    function mint(uint256 shares, address receiver)
        external
        returns (uint256 assets);

    function maxWithdraw(address owner)
        external
        view
        returns (uint256 maxAssets);

    function previewWithdraw(uint256 assets)
        external
        view
        returns (uint256 shares);

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    function maxRedeem(address owner) external view returns (uint256 maxShares);

    function previewRedeem(uint256 shares)
        external
        view
        returns (uint256 assets);

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);
}
