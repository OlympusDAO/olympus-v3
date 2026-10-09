// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// Test fixtures are kept together so invalid share-token variants stay local to onboarding tests.
// Mutable zero-address states deliberately model invalid live ERC-7575 identity.
// forge-lint: disable-start(missing-events-access-control, missing-inheritance, missing-zero-check, multi-contract-file)

// Interfaces
import {IERC7575} from "@openzeppelin-community-contracts-0.0.1/interfaces/IERC7575.sol";
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";

interface IMockMintableShareToken {
    function mint(address recipient_, uint256 amount_) external;

    function burn(address owner_, uint256 amount_) external;
}

contract MockERC7575ShareToken is ERC20, IMockMintableShareToken {
    error OnlyVault();

    address internal immutable _MINTER;

    constructor() ERC20("ERC-7575 Share", "E75S", 18) {
        _MINTER = msg.sender;
    }

    function mint(address recipient_, uint256 amount_) external override {
        if (msg.sender != _MINTER) revert OnlyVault();
        _mint(recipient_, amount_);
    }

    function burn(address owner_, uint256 amount_) external override {
        if (msg.sender != _MINTER) revert OnlyVault();
        _burn(owner_, amount_);
    }
}

contract MockIncompatibleShareToken {}

contract MockRevertingShareToken {
    error BalanceQueryReverted();

    function balanceOf(address) external pure returns (uint256) {
        revert BalanceQueryReverted();
    }
}

/// @notice ERC-7575 share token shared by multiple asset-specific vault entry points.
contract MockSharedERC7575ShareToken is ERC20 {
    error OnlyAdmin();
    error OnlyVault();

    address internal immutable _ADMIN;
    mapping(address vault_ => bool) internal _authorizedVaults;

    constructor() ERC20("Shared ERC-7575 Share", "SE75", 18) {
        _ADMIN = msg.sender;
    }

    function authorizeVault(address vault_) external {
        if (msg.sender != _ADMIN) revert OnlyAdmin();
        _authorizedVaults[vault_] = true;
    }

    function mint(address recipient_, uint256 amount_) external {
        if (!_authorizedVaults[msg.sender]) revert OnlyVault();
        _mint(recipient_, amount_);
    }

    function burn(address owner_, uint256 amount_) external {
        if (!_authorizedVaults[msg.sender]) revert OnlyVault();
        _burn(owner_, amount_);
    }
}

/// @notice One synchronous ERC-7575 entry point backed by a shared external share token.
contract MockSharedERC7575Vault is IERC165 {
    using SafeTransferLib for ERC20;

    error UnauthorizedOwner();

    bytes4 internal constant _ERC7575_INTERFACE_ID =
        type(IERC4626).interfaceId ^ type(IERC7575).interfaceId;

    ERC20 internal immutable _ASSET;
    MockSharedERC7575ShareToken internal immutable _SHARE;

    constructor(ERC20 asset_, MockSharedERC7575ShareToken share_) {
        _ASSET = asset_;
        _SHARE = share_;
    }

    function asset() external view returns (address) {
        return address(_ASSET);
    }

    function share() external view returns (address) {
        return address(_SHARE);
    }

    function convertToShares(uint256 assets_) public pure returns (uint256) {
        return assets_;
    }

    function convertToAssets(uint256 shares_) public pure returns (uint256) {
        return shares_;
    }

    function previewDeposit(uint256 assets_) external pure returns (uint256) {
        return assets_;
    }

    function previewRedeem(uint256 shares_) external pure returns (uint256) {
        return shares_;
    }

    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_) {
        _ASSET.safeTransferFrom(msg.sender, address(this), assets_);
        _SHARE.mint(receiver_, assets_);
        return assets_;
    }

    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) external returns (uint256 assets_) {
        if (msg.sender != owner_) revert UnauthorizedOwner();
        _SHARE.burn(owner_, shares_);
        _ASSET.safeTransfer(receiver_, shares_);
        return shares_;
    }

    function supportsInterface(bytes4 interfaceId_) external pure override returns (bool) {
        return interfaceId_ == type(IERC165).interfaceId || interfaceId_ == _ERC7575_INTERFACE_ID;
    }
}

/// @notice Mutable synchronous ERC-4626 plus ERC-7575 fixture.
contract MockERC7575Vault is ERC20, IERC165 {
    using SafeTransferLib for ERC20;

    error ShareQueryReverted();
    error UnauthorizedOwner();

    bytes4 internal constant _ERC7575_INTERFACE_ID =
        type(IERC4626).interfaceId ^ type(IERC7575).interfaceId;

    ERC20 internal immutable _ASSET;
    address internal _reportedShare;
    bool internal _shareQueryReverts;

    constructor(ERC20 asset_, bool externalShare_) ERC20("ERC-7575 Vault", "E75V", 18) {
        _ASSET = asset_;
        _reportedShare = externalShare_ ? address(new MockERC7575ShareToken()) : address(this);
    }

    function asset() external view returns (address) {
        return address(_ASSET);
    }

    function share() external view returns (address) {
        if (_shareQueryReverts) revert ShareQueryReverted();
        return _reportedShare;
    }

    function setReportedShare(address shareToken_) external {
        _reportedShare = shareToken_;
    }

    function setShareQueryReverts(bool reverts_) external {
        _shareQueryReverts = reverts_;
    }

    function convertToShares(uint256 assets_) public pure returns (uint256) {
        return assets_;
    }

    function convertToAssets(uint256 shares_) public pure returns (uint256) {
        return shares_;
    }

    function previewDeposit(uint256 assets_) external pure returns (uint256) {
        return convertToShares(assets_);
    }

    function previewRedeem(uint256 shares_) external pure returns (uint256) {
        return convertToAssets(shares_);
    }

    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_) {
        shares_ = convertToShares(assets_);
        _ASSET.safeTransferFrom(msg.sender, address(this), assets_);
        if (_reportedShare == address(this)) _mint(receiver_, shares_);
        else IMockMintableShareToken(_reportedShare).mint(receiver_, shares_);
    }

    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) external returns (uint256 assets_) {
        if (msg.sender != owner_) revert UnauthorizedOwner();
        assets_ = convertToAssets(shares_);
        if (_reportedShare == address(this)) _burn(owner_, shares_);
        else IMockMintableShareToken(_reportedShare).burn(owner_, shares_);
        _ASSET.safeTransfer(receiver_, assets_);
    }

    function supportsInterface(bytes4 interfaceId_) external pure override returns (bool) {
        return interfaceId_ == type(IERC165).interfaceId || interfaceId_ == _ERC7575_INTERFACE_ID;
    }
}

// forge-lint: disable-end(missing-events-access-control, missing-inheritance, missing-zero-check, multi-contract-file)
