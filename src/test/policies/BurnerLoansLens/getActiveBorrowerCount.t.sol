// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Contracts
import {BurnerLoansLensTest} from "./BurnerLoansLensTest.sol";

contract BurnerLoansLensGetActiveBorrowerCountTest is BurnerLoansLensTest {
    // Scenarios: BLLENS-COUNT-A01, BLLENS-COUNT-L01, BLLENS-COUNT-N01.
    function test_givenCoreLifecycle_whenCountQueried(
        address caller_,
        bool active_,
        bool enabled_,
        uint256 population_
    ) public {
        _expectNoRiskReads();
        vm.expectCall(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.getActiveBorrowers.selector),
            uint64(0)
        );
        _assertCount(caller_, active_, enabled_, population_);
    }

    // Scenarios: BLLENS-COUNT-L01, BLLENS-COUNT-N01.
    function test_whenLifecycleAndCountBoundariesSeeded() public {
        _expectNoRiskReads();
        vm.expectCall(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.getActiveBorrowers.selector),
            uint64(0)
        );
        uint256[3] memory populations = [uint256(0), uint256(1), type(uint256).max];
        for (uint256 flags; flags < 4; ++flags) {
            for (uint256 i; i < populations.length; ++i) {
                uint256 checkpoint = vm.snapshotState();
                _assertCount(_ALICE, flags & 1 != 0, flags & 2 != 0, populations[i]);
                assertTrue(
                    vm.revertToState(checkpoint),
                    "Restore lifecycle after each boundary seed"
                );
            }
        }
    }

    // Scenarios: BLLENS-COUNT-I01.
    function test_whenAssetUnregistered_reverts(address caller_, address asset_) public {
        vm.assume(!_core.isAssetRegistered(asset_));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset_
            )
        );
        vm.prank(caller_);
        _lens.getActiveBorrowerCount(asset_);
    }

    // Scenarios: BLLENS-COUNT-I01.
    function test_whenZeroAsset_reverts() public {
        test_whenAssetUnregistered_reverts(_ALICE, address(0));
    }

    // Scenarios: BLLENS-COUNT-P01.
    function test_givenBorrowerDebtChanges_whenCountQueried_thenLiveCount() public {
        assertEq(_lens.getActiveBorrowerCount(address(_asset)), 0, "Empty market count");
        _seedDebt(_ALICE, 1000e6, 100e9);
        _seedDebt(_BOB, 1000e6, 100e9);
        assertEq(_lens.getActiveBorrowerCount(address(_asset)), 2, "Two distinct active borrowers");
        _repay(_ALICE, 100e9);
        assertEq(
            _lens.getActiveBorrowerCount(address(_asset)),
            1,
            "Full repayment removes one borrower"
        );
        _default(_BOB);
        assertEq(
            _lens.getActiveBorrowerCount(address(_asset)),
            0,
            "Default removes the remaining borrower"
        );
    }

    // Scenarios: BLLENS-COUNT-T01.
    function test_givenCountReadFails_whenQueried_reverts() public {
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.getActiveBorrowerCount.selector),
            abi.encodeWithSelector(FloanReadFailed.selector)
        );
        vm.expectRevert(FloanReadFailed.selector);
        _lens.getActiveBorrowerCount(address(_asset));
    }

    function _assertCount(
        address caller_,
        bool active_,
        bool enabled_,
        uint256 population_
    ) private {
        _setCoreLifecycle(active_, enabled_);
        _mockCount(population_);
        vm.prank(caller_);
        assertEq(
            _lens.getActiveBorrowerCount(address(_asset)),
            population_,
            "Forward canonical count without allocating the borrower array"
        );
    }
}
