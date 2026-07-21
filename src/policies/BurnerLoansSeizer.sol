// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";

// Libraries
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyAdminOptimized} from "src/policies/utils/PolicyAdminOptimized.sol";
import {BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Burner Loans Seizer
/// @notice Bounded round-robin periodic seizure across configured collateral assets.
contract BurnerLoansSeizer is Policy, PolicyAdminOptimized, IBurnerLoansSeizer {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint16 public constant MAX_BORROWERS_TO_CHECK = 500;
    uint8 public constant MAX_BORROWERS_TO_SEIZE = 50;

    address internal immutable _BURNER_LOANS;

    uint16 public override maxBorrowersToCheck;
    uint8 public override maxBorrowersToSeize;
    uint256 public override nextAssetIndex;
    mapping(address => uint256) public override assetCursor;

    EnumerableSet.AddressSet private _assets;

    constructor(
        Kernel kernel_,
        address burnerLoans_,
        uint16 maxBorrowersToCheck_,
        uint8 maxBorrowersToSeize_
    ) Policy(kernel_) {
        if (burnerLoans_ == address(0)) revert BurnerLoansSeizer_ZeroAddress();
        _BURNER_LOANS = burnerLoans_;
        _setScanLimits(maxBorrowersToCheck_, maxBorrowersToSeize_);
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        (uint8 rolesMajor, ) = Module(address(ROLES)).VERSION();
        if (rolesMajor != 1) revert Policy_WrongModuleVersion(abi.encode([1]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

    /// @notice Returns the version of the policy.
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @inheritdoc IBurnerLoansSeizer
    function addAsset(address asset_) external override onlyAdminRole {
        if (asset_ == address(0)) revert BurnerLoansSeizer_ZeroAddress();
        if (!_assets.add(asset_)) revert BurnerLoansSeizer_AssetAlreadyManaged(asset_);
        emit AssetAdded(asset_);
    }

    /// @inheritdoc IBurnerLoansSeizer
    function removeAsset(address asset_) external override onlyAdminRole {
        if (!_assets.remove(asset_)) revert BurnerLoansSeizer_AssetNotManaged(asset_);
        delete assetCursor[asset_];

        uint256 remaining = _assets.length();
        if (remaining == 0) nextAssetIndex = 0;
        else if (nextAssetIndex >= remaining) nextAssetIndex %= remaining;
        emit AssetRemoved(asset_);
    }

    /// @inheritdoc IBurnerLoansSeizer
    function setScanLimits(
        uint16 maxBorrowersToCheck_,
        uint8 maxBorrowersToSeize_
    ) external override {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
        _setScanLimits(maxBorrowersToCheck_, maxBorrowersToSeize_);
    }

    /// @inheritdoc IPeriodicTask
    function execute() external override onlyRole(HEART_ROLE) {
        uint256 assetCount = _assets.length();
        if (assetCount == 0) return;

        uint256 assetIndex = nextAssetIndex % assetCount;
        address asset = _assets.at(assetIndex);
        nextAssetIndex = assetIndex + 1 == assetCount ? 0 : assetIndex + 1;

        if (!_hasRole(address(this), BURNER_LOANS_SEIZER_ROLE)) {
            emit SeizerRoleMissing(asset);
            return;
        }

        uint256 startIndex = assetCursor[asset];
        try
            IBurnerLoansView(_BURNER_LOANS).getSeizableBorrowers(
                asset,
                startIndex,
                maxBorrowersToCheck,
                maxBorrowersToSeize
            )
        returns (address[] memory borrowers, uint256 scannedNextIndex, uint256) {
            if (borrowers.length == 0) {
                assetCursor[asset] = scannedNextIndex;
                emit Executed(asset, startIndex, scannedNextIndex, 0);
                return;
            }

            try IBurnerLoansLifecycle(_BURNER_LOANS).seize(asset, borrowers) {
                assetCursor[asset] = scannedNextIndex;
                emit Executed(asset, startIndex, scannedNextIndex, borrowers.length);
            } catch (bytes memory reason) {
                emit SeizureFailed(asset, _reasonSelector(reason));
            }
        } catch (bytes memory reason) {
            emit ScanFailed(asset, _reasonSelector(reason));
        }
    }

    /// @inheritdoc IBurnerLoansSeizer
    function isAssetManaged(address asset_) external view override returns (bool) {
        return _assets.contains(asset_);
    }

    /// @inheritdoc IBurnerLoansSeizer
    function burnerLoans() external view override returns (address) {
        return _BURNER_LOANS;
    }

    /// @inheritdoc IBurnerLoansSeizer
    function getAssets() external view override returns (address[] memory) {
        return _assets.values();
    }

    /// @inheritdoc IPeriodicTask
    function supportsInterface(bytes4 interfaceId_) external pure override returns (bool) {
        return
            interfaceId_ == type(IPeriodicTask).interfaceId ||
            interfaceId_ == type(IBurnerLoansSeizer).interfaceId;
    }

    function _setScanLimits(uint16 maxBorrowersToCheck_, uint8 maxBorrowersToSeize_) private {
        if (
            maxBorrowersToCheck_ == 0 ||
            maxBorrowersToCheck_ > MAX_BORROWERS_TO_CHECK ||
            maxBorrowersToSeize_ == 0 ||
            maxBorrowersToSeize_ > MAX_BORROWERS_TO_SEIZE ||
            maxBorrowersToSeize_ > maxBorrowersToCheck_
        ) {
            revert BurnerLoansSeizer_InvalidScanLimits(maxBorrowersToCheck_, maxBorrowersToSeize_);
        }
        maxBorrowersToCheck = maxBorrowersToCheck_;
        maxBorrowersToSeize = maxBorrowersToSeize_;
        emit ScanLimitsSet(maxBorrowersToCheck_, maxBorrowersToSeize_);
    }

    function _reasonSelector(bytes memory reason_) private pure returns (bytes4 selector) {
        if (reason_.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(reason_, 0x20))
        }
    }
}
