// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test fixtures accept zero addresses to model unset, cleared, and invalid states.
// forge-lint: disable-start(missing-zero-check)

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {LoanMarket} from "src/policies/burnerloans/libraries/LoanMarket.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

contract MockBurnerLoansYieldClaimerTaskTarget is Policy, IERC165, IEnabler {
    error ClaimReverted();
    error AssetViewReverted();
    error InvalidAssetIndex(uint256 index);

    bool public claimReverts;
    bool public claimRevertsWithShortData;
    bool public claimRevertsWithLargeData;
    address public claimConsumesAllGasAsset;
    bool public assetViewReverts;
    uint256 public assetViewRevertIndex = type(uint256).max;
    bool public supportsCore = true;
    bool public supportsLifecycle = true;
    bool public override isEnabled = true;
    uint256 public claimCalls;
    address public lastClaimedAsset;
    address[] public claimedAssets;

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

    function setSupportsCore(bool supportsCore_) external {
        supportsCore = supportsCore_;
    }

    function setSupportsLifecycle(bool supportsLifecycle_) external {
        supportsLifecycle = supportsLifecycle_;
    }

    function enable(bytes calldata) external override {
        isEnabled = true;
        emit Enabled();
    }

    function disable(bytes calldata) external override {
        isEnabled = false;
        emit Disabled();
    }

    function setAssetViewReverts(bool reverts_) external {
        assetViewReverts = reverts_;
    }

    function setAssetViewRevertIndex(uint256 index_) external {
        assetViewRevertIndex = index_;
    }

    function setAssets(address[] calldata assets_) external {
        _assets = assets_;
    }

    // Minimal replaceable boundaries consumed by this action. Real custody, routing and share
    // conversion are exercised separately by the modular integration fixture.
    function depositManager() external view returns (address) {
        return address(this);
    }

    function floan() external view returns (address) {
        return address(this);
    }

    function payout() external view returns (address) {
        return address(this);
    }

    function yieldRecipient() external pure returns (address) {
        return address(0xBEEF);
    }

    function marketId(address) external pure returns (uint32) {
        return 1;
    }

    function getMarket(uint32) external pure returns (IFLOANv1.Market memory market) {
        market.configId = bytes16("Burner Loans v1");
    }

    function getMarketConfigData(uint32) external pure returns (bytes memory) {
        return abi.encode(LoanMarket.Data(false, 0, 0, 0, 0, 0, 0));
    }

    function getAssetConfiguration(
        address
    ) external pure returns (IDepositManager.AssetConfiguration memory cfg) {
        cfg.isConfigured = true;
    }

    function isAssetPeriod(
        address,
        uint8,
        address
    ) external pure returns (IDepositManager.AssetPeriodStatus memory status) {
        status.isConfigured = true;
        status.isEnabled = true;
    }

    function getOperatorAssets(address, address) external pure returns (uint256, uint256) {
        return (10, 10);
    }

    function getBorrowedAmount(address, address) external pure returns (uint256) {
        return 0;
    }

    function getOperatorLiabilities(address, address) external pure returns (uint256) {
        return 0;
    }

    function maxClaimYield(address, address) external pure returns (uint256) {
        return 1;
    }

    function settleYield(address asset_, uint256, address) external returns (address, uint256) {
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
        claimedAssets.push(asset_);
        ++claimCalls;
        return (asset_, 1);
    }

    function getAssetCount() external view returns (uint256 count) {
        if (assetViewReverts) revert AssetViewReverted();
        return _assets.length;
    }

    function getAssetAt(uint256 index_) external view returns (address asset) {
        if (assetViewReverts) revert AssetViewReverted();
        if (index_ == assetViewRevertIndex) revert AssetViewReverted();
        if (index_ >= _assets.length) revert InvalidAssetIndex(index_);
        return _assets[index_];
    }

    function supportsInterface(bytes4 interfaceId_) external view override returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            (supportsCore && interfaceId_ == type(IBurnerLoansCore).interfaceId) ||
            (supportsLifecycle && interfaceId_ == type(IEnabler).interfaceId);
    }
}

// forge-lint: disable-end(missing-zero-check)
