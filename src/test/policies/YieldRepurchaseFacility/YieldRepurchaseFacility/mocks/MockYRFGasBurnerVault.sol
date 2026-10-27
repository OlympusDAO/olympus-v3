// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// Fixture of the YRF v2 step gas limit tests. The setters are unrestricted test knobs, and the
// reverts with long data are produced in assembly from uninitialized memory.
// forge-lint: disable-start(missing-events-access-control,inline-assembly)

import {FullMath} from "src/libraries/FullMath.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";

/// @notice An ERC-4626 vault that is its own ERC-20 share token, whose conversion rate is the
///         ratio of its asset balance to its share supply, and which can be switched to fail
///         in its conversion functions or in the transfer of its shares.
contract MockGasBurnerVault is ERC20 {
    using FullMath for uint256;
    using SafeTransferLib for ERC20;

    /// @notice The behaviour of a switched function.
    /// @dev - `None`: the normal result.
    ///      - `BurnGas`: an endless loop that consumes all the gas of the call to the vault. The
    ///        calling frame keeps back one 64th of its gas, so a facility step that calls the
    ///        vault fails with that share of its gas limit unspent.
    ///      - `RevertLong`: a revert with `LONG_REVERT_LENGTH` bytes of data.
    ///      - `RevertBomb`: a revert with `BOMB_REVERT_LENGTH` bytes of data. A facility step
    ///        that calls the vault copies the data to bubble the revert and runs out of gas in
    ///        its own frame, so the step consumes its whole gas limit.
    enum FailMode {
        None,
        BurnGas,
        RevertLong,
        RevertBomb
    }

    error MockGasBurnerVault_UnauthorizedOwner();

    /// @notice The revert data length of the `RevertLong` mode, above the 256 bytes the
    ///         facility captures from an isolated call.
    uint256 public constant LONG_REVERT_LENGTH = 512;

    /// @notice The revert data length of the `RevertBomb` mode.
    /// @dev Expanding memory to 800_000 bytes (25_000 words) costs
    ///      3 * 25_000 + 25_000^2 / 512 = 1_295_703 gas. The vault pays it once out of the gas
    ///      of a step limited to 2_000_000, and the gas left to the step does not pay it again.
    uint256 public constant BOMB_REVERT_LENGTH = 800_000;

    ERC20 internal immutable _ASSET;

    /// @notice The behaviour of the conversion functions, `deposit`, and `redeem`.
    FailMode public convertMode;
    /// @notice The behaviour of `transfer`.
    FailMode public transferMode;

    constructor(
        ERC20 asset_,
        uint8 shareDecimals_
    ) ERC20("Mock Gas Burner Vault", "MGBV", shareDecimals_) {
        _ASSET = asset_;
    }

    // ============ TEST KNOBS ============ //

    function setConvertMode(FailMode mode_) external {
        convertMode = mode_;
    }

    function setTransferMode(FailMode mode_) external {
        transferMode = mode_;
    }

    // ============ ERC-4626 ============ //

    function asset() external view returns (address) {
        return address(_ASSET);
    }

    function totalAssets() public view returns (uint256) {
        return _ASSET.balanceOf(address(this));
    }

    function convertToShares(uint256 assets_) external view returns (uint256) {
        return _toShares(assets_, false);
    }

    function convertToAssets(uint256 shares_) external view returns (uint256) {
        return _toAssets(shares_);
    }

    function previewDeposit(uint256 assets_) external view returns (uint256) {
        return _toShares(assets_, false);
    }

    function previewRedeem(uint256 shares_) external view returns (uint256) {
        return _toAssets(shares_);
    }

    function previewWithdraw(uint256 assets_) external view returns (uint256) {
        return _toShares(assets_, true);
    }

    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_) {
        shares_ = _toShares(assets_, false);
        _ASSET.safeTransferFrom(msg.sender, address(this), assets_);
        _mint(receiver_, shares_);
    }

    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) external returns (uint256 assets_) {
        assets_ = _toAssets(shares_);
        if (msg.sender != owner_) revert MockGasBurnerVault_UnauthorizedOwner();
        _burn(owner_, shares_);
        _ASSET.safeTransfer(receiver_, assets_);
    }

    // ============ ERC-20 ============ //

    function transfer(address to_, uint256 amount_) public override returns (bool) {
        _fail(transferMode);
        return super.transfer(to_, amount_);
    }

    // ============ INTERNALS ============ //

    /// @dev assets (asset decimals) * supply (share decimals) / totalAssets (asset decimals)
    ///      = shares (share decimals); one to one while the vault is empty.
    function _toShares(uint256 assets_, bool roundUp_) internal view returns (uint256) {
        uint256 supply = _shareSupply();
        uint256 assetsHeld = totalAssets();
        if (supply == 0 || assetsHeld == 0) return assets_;
        return roundUp_ ? assets_.mulDivUp(supply, assetsHeld) : assets_.mulDiv(supply, assetsHeld);
    }

    /// @dev shares (share decimals) * totalAssets (asset decimals) / supply (share decimals)
    ///      = assets (asset decimals), rounded down; one to one while the vault is empty.
    function _toAssets(uint256 shares_) internal view returns (uint256) {
        uint256 supply = _shareSupply();
        if (supply == 0) return shares_;
        return shares_.mulDiv(totalAssets(), supply);
    }

    /// @notice Returns the share supply, applying the behaviour of the conversion functions.
    function _shareSupply() internal view returns (uint256) {
        _fail(convertMode);
        return totalSupply;
    }

    function _fail(FailMode mode_) internal pure {
        if (mode_ == FailMode.BurnGas) {
            while (true) {}
        }
        if (mode_ == FailMode.RevertLong) {
            assembly {
                revert(0, LONG_REVERT_LENGTH)
            }
        }
        if (mode_ == FailMode.RevertBomb) {
            assembly {
                revert(0, BOMB_REVERT_LENGTH)
            }
        }
    }
}
// forge-lint: disable-end(missing-events-access-control,inline-assembly)
