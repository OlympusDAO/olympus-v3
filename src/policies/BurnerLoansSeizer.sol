// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";

// Libraries
import {ExcessivelySafeCall} from "@excessively-safe-call-0.0.1/ExcessivelySafeCall.sol";
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Burner Loans Seizer
/// @notice Heart task for bounded round-robin seizure.
/// @dev Scan and seizure failures are isolated so this non-essential task cannot
///      revert the Heart transaction or block later periodic tasks.
contract BurnerLoansSeizer is Policy, PolicyEnablerV2, IBurnerLoansSeizer {
    using ExcessivelySafeCall for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Maximum revert data copied from the gas-bounded self-call.
    uint16 internal constant _MAX_RETURN_DATA_BYTES = 4;

    /// @notice Maximum borrowers that one execution may scan.
    uint16 public constant MAX_BORROWERS_TO_CHECK = 500;

    /// @notice Maximum borrowers that one execution may seize.
    uint8 public constant MAX_BORROWERS_TO_SEIZE = 50;

    /// @dev Burner Loans lifecycle policy scanned and reconciled by this task.
    address internal immutable _BURNER_LOANS;

    /// @inheritdoc IBurnerLoansSeizer
    uint16 public override maxBorrowersToCheck;

    /// @inheritdoc IBurnerLoansSeizer
    uint8 public override maxBorrowersToSeize;

    /// @inheritdoc IBurnerLoansSeizer
    uint32 public override executionGasLimit;

    /// @inheritdoc IBurnerLoansSeizer
    uint256 public override nextAssetIndex;

    /// @inheritdoc IBurnerLoansSeizer
    mapping(address => uint256) public override assetCursor;

    /// @dev Collateral assets included in round-robin scanning.
    EnumerableSet.AddressSet private _assets;

    /// @notice Deploys a gas-bounded Heart task for a same-Kernel Burner Loans policy.
    /// @dev Reverts if the target is zero, does not expose the required lifecycle/view interfaces,
    ///      belongs to a different Kernel, or any initial execution/scan limit is invalid.
    /// @param kernel_ Kernel shared with the Burner Loans target.
    /// @param burnerLoans_ Burner Loans lifecycle policy scanned and reconciled by this task.
    /// @param maxBorrowersToCheck_ Maximum active borrowers inspected per execution.
    /// @param maxBorrowersToSeize_ Maximum seizable borrowers settled per execution.
    /// @param executionGasLimit_ Maximum gas forwarded to the complete task body.
    constructor(
        Kernel kernel_,
        address burnerLoans_,
        uint16 maxBorrowersToCheck_,
        uint8 maxBorrowersToSeize_,
        uint32 executionGasLimit_
    ) Policy(kernel_) {
        if (burnerLoans_ == address(0)) revert BurnerLoansSeizer_ZeroAddress();
        if (
            !ERC165Checker.supportsInterface(
                burnerLoans_,
                type(IBurnerLoansLifecycle).interfaceId
            ) || !ERC165Checker.supportsInterface(burnerLoans_, type(IBurnerLoansView).interfaceId)
        ) {
            revert BurnerLoansSeizer_InvalidBurnerLoans(burnerLoans_);
        }
        address burnerLoansKernel = address(Policy(burnerLoans_).kernel());
        if (burnerLoansKernel != address(kernel_)) {
            revert BurnerLoansSeizer_KernelMismatch(address(kernel_), burnerLoansKernel);
        }
        _BURNER_LOANS = burnerLoans_;
        _setScanLimits(maxBorrowersToCheck_, maxBorrowersToSeize_);
        _setExecutionGasLimit(executionGasLimit_);
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

    /// @inheritdoc IBurnerLoansSeizer
    function setExecutionGasLimit(uint32 executionGasLimit_) external override {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
        _setExecutionGasLimit(executionGasLimit_);
    }

    /// @inheritdoc IPeriodicTask
    function execute() external override onlyRole(HEART_ROLE) {
        if (!isEnabled) return;

        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            executionGasLimit,
            0,
            _MAX_RETURN_DATA_BYTES,
            abi.encodeCall(this.selfExecuteTask, ())
        );
        if (!success) emit ExecutionFailed(bytes4(reason));
    }

    /// @inheritdoc IBurnerLoansSeizer
    function selfExecuteTask() external override {
        if (msg.sender != address(this)) revert BurnerLoansSeizer_OnlySelf();
        _scanAndSeize();
    }

    /// @dev Scans and optionally seizes one managed asset. All external failures are reported.
    function _scanAndSeize() private {
        uint256 assetCount = _assets.length();
        if (assetCount == 0) return;

        // Advance the asset cursor before external work so every successful Heart tick rotates
        // fairly even when scanning or seizure later fails for this asset.
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
                emit SeizureExecuted(asset, startIndex, scannedNextIndex, 0);
                return;
            }

            try IBurnerLoansLifecycle(_BURNER_LOANS).seize(asset, borrowers) {
                // Commit the borrower cursor only after Burner Loans atomically settles the batch.
                assetCursor[asset] = scannedNextIndex;
                emit SeizureExecuted(asset, startIndex, scannedNextIndex, borrowers.length);
            } catch (bytes memory reason) {
                emit SeizureFailed(asset, bytes4(reason));
            }
        } catch (bytes memory reason) {
            emit ScanFailed(asset, bytes4(reason));
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

    /// @dev Revalidates the constructor-bound Burner Loans policy before operational enablement.
    function _beforeEnable(bytes calldata) internal view override {
        if (!kernel.isPolicyActive(Policy(_BURNER_LOANS))) {
            revert BurnerLoansSeizer_InvalidBurnerLoans(_BURNER_LOANS);
        }
    }

    /// @inheritdoc IPeriodicTask
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(EnablerV2, IPeriodicTask) returns (bool) {
        return
            interfaceId_ == type(IPeriodicTask).interfaceId ||
            interfaceId_ == type(IBurnerLoansSeizer).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @notice Stores validated nonzero scan and seizure limits.
    /// @dev Reverts when either limit exceeds its maximum or the seizure limit exceeds the scan
    ///      limit.
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

    /// @notice Stores the gas forwarded to the fail-soft self-call.
    /// @dev Reverts when `executionGasLimit_` is zero.
    function _setExecutionGasLimit(uint32 executionGasLimit_) private {
        if (executionGasLimit_ == 0) revert BurnerLoansSeizer_InvalidExecutionGasLimit();
        executionGasLimit = executionGasLimit_;
        emit ExecutionGasLimitSet(executionGasLimit_);
    }
}
