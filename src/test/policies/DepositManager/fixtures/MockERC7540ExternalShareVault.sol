// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// The share token is private to this vault fixture and is kept beside it for readable test setup.
// forge-lint: disable-start(missing-inheritance, multi-contract-file)

// Interfaces
import {IERC7540Deposit, IERC7540Operator, IERC7540Redeem} from "@openzeppelin-community-contracts-0.0.1/interfaces/IERC7540.sol";
import {IERC7575} from "@openzeppelin-community-contracts-0.0.1/interfaces/IERC7575.sol";
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

// Libraries
import {Math} from "@openzeppelin-5.7.0/utils/math/Math.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";

contract MockERC7540ExternalShareToken is ERC20 {
    error OnlyVault();

    address internal immutable _VAULT;

    constructor() ERC20("External Vault Share", "EVS", 6) {
        _VAULT = msg.sender;
    }

    function mint(address recipient_, uint256 amount_) external {
        if (msg.sender != _VAULT) revert OnlyVault();
        _mint(recipient_, amount_);
    }

    function burn(address owner_, uint256 amount_) external {
        if (msg.sender != _VAULT) revert OnlyVault();
        _burn(owner_, amount_);
    }
}

/// @notice ERC-7540 capability fixture whose ERC-7575 share token is not the vault contract.
/// @dev The underlying uses 18 decimals and shares use 6 decimals. Redemption previews and direct
///      redemption revert when asynchronous redemption is enabled.
contract MockERC7540ExternalShareVault is IERC165 {
    using SafeTransferLib for ERC20;

    error AsyncRedeem();
    error AsyncDeposit();
    error UnauthorizedOwner();

    bytes4 internal constant _ERC7575_INTERFACE_ID =
        type(IERC4626).interfaceId ^ type(IERC7575).interfaceId;
    uint256 internal _assetsPerShare = 1e12;

    ERC20 internal immutable _ASSET;
    MockERC7540ExternalShareToken internal immutable _SHARE;
    bool internal _asyncDeposit;
    bool internal _asyncRedeem;
    bool internal _supportsOperator;
    bool internal _supportsERC7575;
    bool internal _depositResultsOverridden;
    bool internal _assetsPerShareOverridden;
    uint256 internal _mintedSharesOverride;
    uint256 internal _returnedSharesOverride;
    uint256 internal _previewRedeemDiscount;

    constructor(
        ERC20 asset_,
        bool asyncDeposit_,
        bool asyncRedeem_,
        bool reportRequiredInterfaces_
    ) {
        _ASSET = asset_;
        _asyncDeposit = asyncDeposit_;
        _asyncRedeem = asyncRedeem_;
        _supportsOperator = reportRequiredInterfaces_;
        _supportsERC7575 = reportRequiredInterfaces_;
        _SHARE = new MockERC7540ExternalShareToken();
    }

    function asset() external view returns (address) {
        return address(_ASSET);
    }

    function share() external view returns (address) {
        return address(_SHARE);
    }

    function setCapabilities(
        bool asyncDeposit_,
        bool asyncRedeem_,
        bool supportsOperator_,
        bool supportsERC7575_
    ) external {
        _asyncDeposit = asyncDeposit_;
        _asyncRedeem = asyncRedeem_;
        _supportsOperator = supportsOperator_;
        _supportsERC7575 = supportsERC7575_;
    }

    function setDepositResults(uint256 mintedShares_, uint256 returnedShares_) external {
        _depositResultsOverridden = true;
        _mintedSharesOverride = mintedShares_;
        _returnedSharesOverride = returnedShares_;
    }

    function setPreviewRedeemDiscount(uint256 discount_) external {
        _previewRedeemDiscount = discount_;
    }

    function setAssetsPerShare(uint256 assetsPerShare_) external {
        _assetsPerShareOverridden = true;
        _assetsPerShare = assetsPerShare_;
    }

    function convertToShares(uint256 assets_) public view returns (uint256) {
        if (_assetsPerShareOverridden) return assets_ / _assetsPerShare;

        uint256 shareSupply = _SHARE.totalSupply();
        uint256 totalAssets = _ASSET.balanceOf(address(this));
        // Before the first deposit, 1e12 underlying units mint one 6-decimal share unit.
        if (shareSupply == 0 || totalAssets == 0) return assets_ / _assetsPerShare;
        // assets (18 decimals) * shareSupply (6 decimals) / totalAssets (18 decimals)
        // = shares (6 decimals), rounded down.
        return Math.mulDiv(assets_, shareSupply, totalAssets);
    }

    function convertToAssets(uint256 shares_) public view returns (uint256) {
        uint256 shareSupply = _SHARE.totalSupply();
        uint256 totalAssets = _ASSET.balanceOf(address(this));
        uint256 assets = _assetsPerShareOverridden || shareSupply == 0
            ? shares_ * _assetsPerShare
            : Math.mulDiv(shares_, totalAssets, shareSupply);
        // shares (6 decimals) * totalAssets (18 decimals) / shareSupply (6 decimals)
        // = assets (18 decimals), rounded down.
        return assets;
    }

    function previewDeposit(uint256 assets_) external view returns (uint256) {
        if (_asyncDeposit) revert AsyncDeposit();
        return convertToShares(assets_);
    }

    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_) {
        if (_asyncDeposit) revert AsyncDeposit();
        shares_ = convertToShares(assets_);
        _ASSET.safeTransferFrom(msg.sender, address(this), assets_);
        _SHARE.mint(receiver_, _depositResultsOverridden ? _mintedSharesOverride : shares_);
        if (_depositResultsOverridden) shares_ = _returnedSharesOverride;
    }

    function previewRedeem(uint256 shares_) external view returns (uint256) {
        if (_asyncRedeem) revert AsyncRedeem();
        uint256 assets = convertToAssets(shares_);
        return _previewRedeemDiscount < assets ? assets - _previewRedeemDiscount : 0;
    }

    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) external returns (uint256 assets_) {
        if (_asyncRedeem) revert AsyncRedeem();
        if (msg.sender != owner_) revert UnauthorizedOwner();
        assets_ = convertToAssets(shares_);
        _SHARE.burn(owner_, shares_);
        _ASSET.safeTransfer(receiver_, assets_);
    }

    function supportsInterface(bytes4 interfaceId_) external view override returns (bool) {
        if (interfaceId_ == type(IERC7540Deposit).interfaceId) return _asyncDeposit;
        if (interfaceId_ == type(IERC7540Redeem).interfaceId) return _asyncRedeem;
        if (interfaceId_ == type(IERC7540Operator).interfaceId) return _supportsOperator;
        if (interfaceId_ == _ERC7575_INTERFACE_ID) return _supportsERC7575;
        return interfaceId_ == type(IERC165).interfaceId;
    }
}

// forge-lint: disable-end(missing-inheritance, multi-contract-file)
