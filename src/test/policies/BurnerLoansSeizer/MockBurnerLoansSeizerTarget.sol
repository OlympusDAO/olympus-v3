// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";

contract MockBurnerLoansSeizerTarget is Policy, IERC165 {
    error ScanReverted();
    error SeizureReverted();
    error SyncReverted();

    mapping(address => address[]) internal _borrowers;
    mapping(address => uint256) internal _nextIndexes;
    mapping(address => uint256) internal _rewards;

    bool public scanReverts;
    bool public scanConsumesAllGas;
    bool public seizureReverts;
    bool public syncReverts;
    uint256 public seizureCalls;
    uint256 public syncCalls;
    uint256 public syncApproval;
    address public lastSeizedAsset;
    address[] internal _lastSeizedBorrowers;

    constructor(Kernel kernel_) Policy(kernel_) {}

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

    function setScanResult(
        address asset_,
        address[] calldata borrowers_,
        uint256 nextIndex_,
        uint256 reward_
    ) external {
        _borrowers[asset_] = borrowers_;
        _nextIndexes[asset_] = nextIndex_;
        _rewards[asset_] = reward_;
    }

    function setScanReverts(bool reverts_) external {
        scanReverts = reverts_;
    }

    function setScanConsumesAllGas(bool consumesAllGas_) external {
        scanConsumesAllGas = consumesAllGas_;
    }

    function setSeizureReverts(bool reverts_) external {
        seizureReverts = reverts_;
    }

    function setSyncReverts(bool reverts_) external {
        syncReverts = reverts_;
    }

    function setSyncApproval(uint256 approval_) external {
        syncApproval = approval_;
    }

    function getSeizableBorrowers(
        address asset_,
        uint256,
        uint256,
        uint256
    ) external view returns (address[] memory, uint256, uint256) {
        if (scanConsumesAllGas) {
            assembly ("memory-safe") {
                invalid()
            }
        }
        if (scanReverts) revert ScanReverted();
        return (_borrowers[asset_], _nextIndexes[asset_], _rewards[asset_]);
    }

    function seize(
        address asset_,
        address[] calldata borrowers_
    ) external returns (uint256, uint256) {
        if (seizureReverts) revert SeizureReverted();
        ++seizureCalls;
        lastSeizedAsset = asset_;
        _lastSeizedBorrowers = borrowers_;
        return (0, 0);
    }

    function syncMintApproval() external returns (uint256 approval) {
        if (syncReverts) revert SyncReverted();
        ++syncCalls;
        return syncApproval;
    }

    function getLastSeizedBorrowers() external view returns (address[] memory) {
        return _lastSeizedBorrowers;
    }

    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IBurnerLoansLifecycle).interfaceId ||
            interfaceId_ == type(IBurnerLoansView).interfaceId;
    }
}
