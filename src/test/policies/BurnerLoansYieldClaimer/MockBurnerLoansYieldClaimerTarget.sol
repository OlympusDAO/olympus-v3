// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test fixtures accept zero addresses to model unset, cleared, and invalid states.
// forge-lint: disable-start(missing-zero-check)

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/IBurnerLoansYieldClaim.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";

contract MockBurnerLoansYieldClaimerTarget is Policy, IERC165, IBurnerLoansYieldClaim {
    error ClaimReverted();
    error AssetViewReverted();
    error InvalidAssetIndex(uint256 index);

    bool public claimReverts;
    bool public claimRevertsWithShortData;
    bool public claimRevertsWithLargeData;
    address public claimConsumesAllGasAsset;
    bool public assetViewReverts;
    bool public supportsAssetView = true;
    uint256 public claimCalls;
    address public lastClaimedAsset;

    address internal constant _ASSET = address(0xA11CE);
    address[] internal _assets;

    constructor(Kernel kernel_) Policy(kernel_) {
        _assets.push(_ASSET);
    }

    function configureDependencies()
        external
        pure
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](0);
    }

    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

    function setClaimReverts(bool reverts_) external {
        claimReverts = reverts_;
    }

    function setClaimRevertsWithShortData(bool reverts_) external {
        claimRevertsWithShortData = reverts_;
    }

    function setClaimRevertsWithLargeData(bool reverts_) external {
        claimRevertsWithLargeData = reverts_;
    }

    function setClaimConsumesAllGasAsset(address asset_) external {
        claimConsumesAllGasAsset = asset_;
    }

    function setSupportsAssetView(bool supportsAssetView_) external {
        supportsAssetView = supportsAssetView_;
    }

    function setAssetViewReverts(bool reverts_) external {
        assetViewReverts = reverts_;
    }

    function setAssets(address[] calldata assets_) external {
        _assets = assets_;
    }

    function claimYield(address asset_) external override returns (uint256 claimed) {
        _claimYield(asset_);
        return 1;
    }

    function getAssetCount() external view returns (uint256 count) {
        if (assetViewReverts) revert AssetViewReverted();
        return _assets.length;
    }

    function getAssetAt(uint256 index_) external view returns (address asset) {
        if (assetViewReverts) revert AssetViewReverted();
        if (index_ >= _assets.length) revert InvalidAssetIndex(index_);
        return _assets[index_];
    }

    function _claimYield(address asset_) private {
        if (asset_ == claimConsumesAllGasAsset) {
            // INVALID consumes the remaining gas to exercise bounded-call failure handling.
            // forge-lint: disable-next-line(inline-assembly)
            assembly ("memory-safe") {
                invalid()
            }
        }
        if (claimRevertsWithShortData) {
            // Assembly constructs one-byte revert data that Solidity cannot express directly.
            // forge-lint: disable-next-line(inline-assembly)
            assembly ("memory-safe") {
                mstore(0, 0xab)
                revert(0x1f, 1)
            }
        }
        if (claimRevertsWithLargeData) {
            uint256 largeRevertDataSize = 100_000;
            // Assembly produces oversized revert data without copying a Solidity byte array.
            // forge-lint: disable-next-line(inline-assembly)
            assembly ("memory-safe") {
                revert(0, largeRevertDataSize)
            }
        }
        if (claimReverts) revert ClaimReverted();
        lastClaimedAsset = asset_;
        ++claimCalls;
    }

    function supportsInterface(bytes4 interfaceId_) external view override returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IBurnerLoansYieldClaim).interfaceId ||
            (supportsAssetView && interfaceId_ == type(IBurnerLoansView).interfaceId);
    }
}

// forge-lint: disable-end(missing-zero-check)
