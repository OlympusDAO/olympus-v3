// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries

// Contracts
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";
import {IERC20 as OZIERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";

import {BurnerLoansLensTest} from "./BurnerLoansLensTest.sol";

// Explicit boundary values and casts model the declared fixture domains.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)

contract BurnerLoansLensGetAssetCollateralStatusTest is BurnerLoansLensTest {
    // Scenarios: BLLENS-COLLATERAL-STATUS-L03.
    function test_givenActiveEnabledCore_whenStatusRead(address caller_) public {
        _setCoreLifecycle(true, true);
        _mockStatus(102, 102, 0, 100, 1);
        _assertStatus(caller_, 102, 102, 0, 100, 1, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-L04.
    function test_givenActiveDisabledCore_whenStatusRead(address caller_) public {
        _setCoreLifecycle(true, false);
        _mockStatus(102, 102, 0, 100, 1);
        _assertStatus(caller_, 102, 102, 0, 100, 1, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-L05.
    function test_givenInactiveEnabledCore_whenStatusRead(address caller_) public {
        _setCoreLifecycle(false, true);
        _mockStatus(102, 102, 0, 100, 1);
        _assertStatus(caller_, 102, 102, 0, 100, 1, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-L06.
    function test_givenInactiveDisabledCore_whenStatusRead(address caller_) public {
        _setCoreLifecycle(false, false);
        _mockStatus(102, 102, 0, 100, 1);
        _assertStatus(caller_, 102, 102, 0, 100, 1, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-I01.
    function test_whenUnknownAsset_reverts(address caller_) public {
        address asset = makeAddr("unknown asset");
        vm.expectCall(
            address(_depositManager),
            abi.encodeWithSignature("getOperatorAssets(address,address)"),
            uint64(0)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset
            )
        );
        vm.prank(caller_);
        _lens.getAssetCollateralStatus(asset);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-I02.
    function test_whenZeroAsset_reverts(address caller_) public {
        address asset = address(0);
        vm.expectCall(
            address(_depositManager),
            abi.encodeWithSignature("getOperatorAssets(address,address)"),
            uint64(0)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset
            )
        );
        vm.prank(caller_);
        _lens.getAssetCollateralStatus(asset);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-L01.
    function test_givenDisabledCustody_whenStatusRead_reverts(address caller_) public {
        IEnabler(address(_depositManager)).disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(_depositManager)
            )
        );
        vm.prank(caller_);
        _lens.getAssetCollateralStatus(address(_asset));
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-D01.
    function test_givenUnconfiguredAsset_whenStatusRead_reverts(address caller_) public {
        IDepositManager.AssetConfiguration memory cfg;
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("getAssetConfiguration(address)", address(_asset)),
            abi.encode(cfg)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(_depositManager)
            )
        );
        vm.prank(caller_);
        _lens.getAssetCollateralStatus(address(_asset));
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-D02.
    function test_givenMissingPeriod_whenStatusRead_reverts(address caller_) public {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "isAssetPeriod(address,uint8,address)",
                address(_asset),
                uint8(1),
                address(_core)
            ),
            abi.encode(IDepositManager.AssetPeriodStatus(false, false))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(_depositManager)
            )
        );
        vm.prank(caller_);
        _lens.getAssetCollateralStatus(address(_asset));
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-L02.
    function test_givenDisabledPeriod_whenStatusRead(address caller_) public {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "isAssetPeriod(address,uint8,address)",
                address(_asset),
                uint8(1),
                address(_core)
            ),
            abi.encode(IDepositManager.AssetPeriodStatus(true, false))
        );
        _mockStatus(102, 102, 0, 100, 1);
        _assertStatus(caller_, 102, 102, 0, 100, 1, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-P01.
    function test_givenEquality_whenStatusRead(address caller_) public {
        _mockStatus(100, 100, 0, 100, 0);
        _assertStatus(caller_, 100, 100, 0, 100, 0, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-P02.
    function test_givenOneUnitDeficit_whenStatusRead(address caller_) public {
        _mockStatus(99, 99, 0, 100, 0);
        _assertStatus(caller_, 99, 99, 0, 100, 0, false);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-P03.
    function test_givenOneUnitSurplus_whenStatusRead(address caller_) public {
        _mockStatus(101, 101, 0, 100, 0);
        _assertStatus(caller_, 101, 101, 0, 100, 0, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-P04.
    function test_givenBorrowedEquality_whenStatusRead(address caller_) public {
        _mockStatus(60, 60, 40, 100, 0);
        _assertStatus(caller_, 60, 60, 40, 100, 0, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-P05.
    function test_givenBorrowedDeficit_whenStatusRead(address caller_) public {
        _mockStatus(60, 60, 39, 100, 0);
        _assertStatus(caller_, 60, 60, 39, 100, 0, false);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-P06.
    function test_givenBorrowedSurplus_whenStatusRead(address caller_) public {
        _mockStatus(60, 60, 41, 100, 0);
        _assertStatus(caller_, 60, 60, 41, 100, 0, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-P07.
    function test_givenEmptyNamespace_whenStatusRead(address caller_) public {
        _mockStatus(0, 0, 0, 0, 0);
        _assertStatus(caller_, 0, 0, 0, 0, 0, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-N01.
    function test_givenMaximumValues_whenStatusRead(address caller_) public {
        _mockStatus(type(uint256).max, type(uint256).max, type(uint256).max, type(uint256).max, 0);
        _assertStatus(
            caller_,
            type(uint256).max,
            type(uint256).max,
            type(uint256).max,
            type(uint256).max,
            0,
            true
        );
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-N02.
    function test_givenMaximumEquality_whenStatusRead(address caller_) public {
        _mockStatus(type(uint256).max - 1, type(uint256).max - 1, 1, type(uint256).max, 0);
        _assertStatus(
            caller_,
            type(uint256).max - 1,
            type(uint256).max - 1,
            1,
            type(uint256).max,
            0,
            true
        );
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-N03.
    function test_givenMaximumDeficit_whenStatusRead(address caller_) public {
        _mockStatus(type(uint256).max - 1, type(uint256).max - 1, 0, type(uint256).max, 0);
        _assertStatus(
            caller_,
            type(uint256).max - 1,
            type(uint256).max - 1,
            0,
            type(uint256).max,
            0,
            false
        );
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-P10.
    function test_givenShareRequired_whenStatusRead(address caller_) public {
        IDepositManager.AssetConfiguration memory cfg = _depositManager.getAssetConfiguration(
            IERC20(address(_asset))
        );
        cfg.vault = address(
            new MockERC7540ExternalShareVault(OZIERC20(address(_asset)), false, true, true)
        );
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("getAssetConfiguration(address)", address(_asset)),
            abi.encode(cfg)
        );
        vm.expectCall(
            cfg.vault,
            abi.encodeWithSignature("redeem(uint256,address,address)"),
            uint64(0)
        );
        _mockStatus(7, 14, 0, 10, 3);
        _assertStatus(caller_, 7, 14, 0, 10, 3, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-P11.
    function test_givenExternalShares_whenStatusRead(address caller_) public {
        IDepositManager.AssetConfiguration memory cfg = _depositManager.getAssetConfiguration(
            IERC20(address(_asset))
        );
        cfg.vault = address(
            new MockERC7540ExternalShareVault(OZIERC20(address(_asset)), false, true, true)
        );
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("getAssetConfiguration(address)", address(_asset)),
            abi.encode(cfg)
        );
        vm.expectCall(
            cfg.vault,
            abi.encodeWithSignature("redeem(uint256,address,address)"),
            uint64(0)
        );
        _mockStatus(5, 15, 0, 10, 4);
        _assertStatus(caller_, 5, 15, 0, 10, 4, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-P13.
    function test_givenMaximumYield_whenStatusRead(address caller_) public {
        _mockStatus(100, 100, 0, 100, type(uint256).max);
        _assertStatus(caller_, 100, 100, 0, 100, type(uint256).max, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-P12.
    function test_givenOtherOperator_whenStatusRead(address caller_) public {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("getOperatorAssets(address,address)"),
            abi.encode(uint256(999), uint256(888))
        );
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("getOperatorLiabilities(address,address)"),
            abi.encode(uint256(777))
        );
        _mockStatus(102, 102, 0, 100, 1);
        _assertStatus(caller_, 102, 102, 0, 100, 1, true);
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-T01.
    function test_givenLedgerFailure_whenStatusRead_reverts(address caller_) public {
        vm.mockCallRevert(
            address(_depositManager),
            abi.encodeWithSignature(
                "getOperatorAssets(address,address)",
                address(_asset),
                address(_core)
            ),
            abi.encodeWithSelector(CustodyReadFailed.selector)
        );
        vm.expectRevert(CustodyReadFailed.selector);
        vm.prank(caller_);
        _lens.getAssetCollateralStatus(address(_asset));
    }

    // Scenarios: BLLENS-COLLATERAL-STATUS-T02.
    function test_givenYieldFailure_whenStatusRead_reverts(address caller_) public {
        vm.mockCallRevert(
            address(_depositManager),
            abi.encodeWithSignature(
                "maxClaimYield(address,address)",
                address(_asset),
                address(_core)
            ),
            abi.encodeWithSelector(YieldReadFailed.selector)
        );
        vm.expectRevert(YieldReadFailed.selector);
        vm.prank(caller_);
        _lens.getAssetCollateralStatus(address(_asset));
    }

    function _mockStatus(
        uint256 shares_,
        uint256 assets_,
        uint256 borrowed_,
        uint256 liabilities_,
        uint256 yield_
    ) internal {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "getOperatorAssets(address,address)",
                address(_asset),
                address(_core)
            ),
            abi.encode(shares_, assets_)
        );
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "getBorrowedAmount(address,address)",
                address(_asset),
                address(_core)
            ),
            abi.encode(borrowed_)
        );
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "getOperatorLiabilities(address,address)",
                address(_asset),
                address(_core)
            ),
            abi.encode(liabilities_)
        );
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "maxClaimYield(address,address)",
                address(_asset),
                address(_core)
            ),
            abi.encode(yield_)
        );
    }

    function _assertStatus(
        address caller_,
        uint256 shares_,
        uint256 assets_,
        uint256 borrowed_,
        uint256 liabilities_,
        uint256 yield_,
        bool solvent_
    ) internal {
        vm.expectCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "getOperatorAssets(address,address)",
                address(_asset),
                address(_core)
            ),
            uint64(1)
        );
        vm.recordLogs();
        vm.prank(caller_);
        IBurnerLoansCore.AssetCollateralStatus memory s = _lens.getAssetCollateralStatus(
            address(_asset)
        );
        assertEq(s.shares, shares_, "Operator shares");
        assertEq(s.assets, assets_, "Operator assets");
        assertEq(s.borrowed, borrowed_, "Operator borrowing");
        assertEq(s.liabilities, liabilities_, "Operator liabilities");
        assertEq(s.claimableYield, yield_, "Custody yield forwarded unchanged");
        assertEq(s.solvent, solvent_, "Overflow-safe solvency");
        assertEq(vm.getRecordedLogs().length, 0, "Status emits no logs");
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
