// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaim.sol";
import {IBurnerLoansYieldClaimerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaimerTask.sol";

// Libraries
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {YieldClaimerModularTest} from "./fixtures/YieldClaimerModularTest.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";

contract BurnerLoansYieldClaimerTaskExecuteIntegrationTest is YieldClaimerModularTest {
    error IntegrationClaimReverted();

    // Scenarios: BLYC-EXECUTE-L02.
    function test_givenCoreDisabled_whenExecuted() public {
        _yieldAsset.mint(address(_yieldVault), 100e6);
        _core.disable("");
        uint256 custody = _yieldAsset.balanceOf(address(_depositManager));
        vm.recordLogs();
        vm.prank(_heart);
        _claimer.execute();
        assertEq(vm.getRecordedLogs().length, 0, "Unavailable Core emits no failure");
        assertEq(
            _yieldAsset.balanceOf(address(_depositManager)),
            custody,
            "Yield stays in custody"
        );
        assertEq(_claimer.nextAssetIndex(), 0, "No progress while Core is unavailable");
    }

    // Scenarios: BLYC-EXECUTE-P03.
    function test_givenInsufficientPeriodicBudget_whenClaimedDirectly() public {
        _yieldAsset.mint(address(_yieldVault), 100e6);
        _claimer.setExecutionGasLimit(1);
        vm.expectEmit(false, false, false, true, address(_claimer));
        emit IBurnerLoansYieldClaimerTask.ExecutionFailed(bytes4(0));
        vm.prank(_heart);
        _claimer.execute();
        uint256 before = _yieldAsset.balanceOf(_payout.treasury());
        (, uint256 amount) = _claimer.claimYield(address(_yieldAsset));
        // Direct custody retains one raw asset unit as the redemption buffer.
        assertEq(amount, 99_999_998, "Manual claim remains available");
        assertEq(
            _yieldAsset.balanceOf(_payout.treasury()) - before,
            amount,
            "Exact direct payment"
        );
    }

    // Scenarios: BLYC-EXECUTE-A02, BLYC-EXECUTE-L01, BLYC-EXECUTE-P01.
    function test_givenMultipleYieldAssets_whenHeartExecutes(address caller_) public {
        vm.assume(caller_ != address(0));
        if (!_roles.hasRole(caller_, HEART_ROLE)) _rolesAdmin.grantRole(HEART_ROLE, caller_);
        (MockERC20 later, MockERC4626 vault) = _newVault(false);
        _deposit(address(later), 2000e6);
        _yieldAsset.mint(address(_yieldVault), 100e6);
        later.mint(address(vault), 100e6);
        uint256 firstBefore = _yieldAsset.balanceOf(_payout.treasury());
        uint256 laterBefore = later.balanceOf(_payout.treasury());
        _claimer.setExecutionGasLimit(1_500_000);
        for (uint256 beat; beat < 3; ++beat) {
            vm.prank(caller_);
            _claimer.execute{gas: 2_000_000}();
        }
        // Raw custody yields 99_999_998. The 1:1 vault redeems 95,238,094 shares at 1.05
        // assets/share, flooring to 99,999,998 underlying units (six decimals).
        assertEq(
            _yieldAsset.balanceOf(_payout.treasury()) - firstBefore,
            99_999_998,
            "First exact yield"
        );
        assertEq(
            later.balanceOf(_payout.treasury()) - laterBefore,
            99_999_998,
            "Vault exact yield"
        );
        assertEq(_claimer.nextAssetIndex(), 0, "Full traversal wraps");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_yieldAsset)), address(_core)),
            2000e6,
            "Liabilities preserved"
        );
        _assertNoPayoutCustody(address(_yieldAsset));
        _assertNoPayoutCustody(address(later));
    }

    // Scenarios: BLYC-EXECUTE-P02.
    function test_givenFirstClaimReverts_whenLaterAssetIsClaimed() public {
        (MockERC20 later, MockERC4626 vault) = _newVault(false);
        _deposit(address(later), 2000e6);
        _yieldAsset.mint(address(_yieldVault), 100e6);
        later.mint(address(vault), 100e6);
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSelector(_core.settleYield.selector, address(_yieldAsset)),
            abi.encodeWithSelector(IntegrationClaimReverted.selector)
        );
        uint256 custody = _yieldAsset.balanceOf(address(_depositManager));
        uint256 before = later.balanceOf(_payout.treasury());
        vm.expectEmit(true, false, false, true, address(_claimer));
        emit IBurnerLoansYieldClaimerTask.YieldAssetClaimFailed(
            address(_yieldAsset),
            IntegrationClaimReverted.selector
        );
        vm.prank(_heart);
        _claimer.execute();
        assertEq(
            _yieldAsset.balanceOf(address(_depositManager)),
            custody,
            "Failed claim stays available"
        );
        assertEq(later.balanceOf(_payout.treasury()) - before, 99_999_998, "Later claim commits");
        assertEq(_claimer.nextAssetIndex(), 0, "Caught failure still advances traversal");
    }
}
