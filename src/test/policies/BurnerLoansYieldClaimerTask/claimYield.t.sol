// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaim.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {YieldClaimerModularTest} from "./fixtures/YieldClaimerModularTest.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansYieldClaimerTaskClaimYieldTest is YieldClaimerModularTest {
    // Scenarios: BLYC-CLAIM-YIELD-D04.
    function test_givenPositiveYieldAndDepositManagerInactive_whenClaimed_reverts(
        address caller_
    ) public {
        _yieldAsset.mint(address(_yieldVault), 3);
        uint256 custodyBefore = _yieldAsset.balanceOf(address(_yieldVault));
        _kernel.executeAction(Actions.DeactivatePolicy, address(_depositManager));
        bytes memory reason = abi.encodeWithSelector(
            PolicyDependency.PolicyDependency_NotActive.selector,
            address(_depositManager)
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _claimer.previewClaimYield(address(_yieldAsset));
        vm.expectRevert(reason);
        vm.prank(caller_);
        _claimer.claimYield(address(_yieldAsset));
        assertEq(
            _yieldAsset.balanceOf(address(_yieldVault)),
            custodyBefore,
            "Inactive custody is untouched"
        );
        _assertNoPayoutCustody(address(_yieldAsset));
    }

    // Scenarios: BLYC-CLAIM-YIELD-P09.
    function test_givenZeroYieldAndUnavailablePayout_whenClaimed(
        address caller_,
        bool payoutActive_
    ) public {
        _payout.disable("");
        if (!payoutActive_) _kernel.executeAction(Actions.DeactivatePolicy, address(_payout));
        _rolesAdmin.revokeRole(BL_YIELD_CLAIMER_ROLE, address(_claimer));
        vm.prank(caller_);
        IBurnerLoansYieldClaim.ClaimYieldPreview memory quote = _claimer.previewClaimYield(
            address(_yieldAsset)
        );
        assertEq(quote.requestedAssetAmount, 0, "No requested yield");
        assertEq(quote.amountOut, 0, "No output quoted");
        assertEq(quote.recipient, address(0), "No delivery needs no recipient");
        assertTrue(quote.executable, "Zero claim needs no Payout or settlement role");
        vm.recordLogs();
        vm.prank(caller_);
        (address token, uint256 amount) = _claimer.claimYield(address(_yieldAsset));
        assertEq(token, quote.tokenOut, "Zero claim token matches quote");
        assertEq(amount, quote.amountOut, "Zero claim amount matches quote");
        assertEq(vm.getRecordedLogs().length, 0, "No settlement or transfers");
        _assertNoPayoutCustody(token);
    }

    // Scenarios: BLYC-CLAIM-YIELD-A01, BLYC-CLAIM-YIELD-L01, BLYC-CLAIM-YIELD-P06.
    function test_givenOneUnitYield_whenAnyCallerClaims(address caller_, address viewer_) public {
        _yieldAsset.mint(address(_yieldVault), 3);
        uint256 callerBefore = _yieldAsset.balanceOf(caller_);
        uint256 before = _yieldAsset.balanceOf(_payout.treasury());
        vm.prank(viewer_);
        IBurnerLoansYieldClaim.ClaimYieldPreview memory quote = _claimer.previewClaimYield(
            address(_yieldAsset)
        );
        assertEq(quote.amountOut, 1, "Three surplus units minus buffer then floor shares");
        assertEq(quote.recipient, _payout.treasury(), "Live Treasury route");
        vm.expectEmit(true, true, true, true, address(_core));
        emit IBurnerLoansYieldClaim.YieldClaimed(
            address(_yieldAsset),
            2,
            address(_yieldAsset),
            1,
            _payout.treasury()
        );
        vm.prank(caller_);
        (address token, uint256 amount) = _claimer.claimYield(address(_yieldAsset));
        assertEq(token, address(_yieldAsset), "Underlying output identity");
        assertEq(amount, 1, "Exact raw output");
        assertEq(
            _yieldAsset.balanceOf(caller_) - callerBefore,
            caller_ == _payout.treasury() ? 1 : 0,
            "Initiating a claim creates no caller entitlement"
        );
        assertEq(_yieldAsset.balanceOf(_payout.treasury()) - before, 1, "Only destination is paid");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_yieldAsset)), address(_core)),
            2000e6,
            "Liabilities unchanged"
        );
        _assertNoPayoutCustody(token);
    }

    // Scenarios: BLYC-CLAIM-YIELD-P02, BLYC-CLAIM-YIELD-P05, BLYC-CLAIM-YIELD-P08.
    function test_givenZeroYieldAndRevokedRole_whenClaimed(address caller_) public {
        _rolesAdmin.revokeRole(BL_YIELD_CLAIMER_ROLE, address(_claimer));
        IBurnerLoansYieldClaim.ClaimYieldPreview memory quote = _claimer.previewClaimYield(
            address(_yieldAsset)
        );
        assertEq(quote.amountOut, 0, "Solvent equality quotes no work");
        vm.recordLogs();
        vm.prank(caller_);
        (address token, uint256 amount) = _claimer.claimYield(address(_yieldAsset));
        assertEq(token, address(_yieldAsset), "Zero result has correct token");
        assertEq(amount, 0, "No work needs no settlement role");
        assertEq(vm.getRecordedLogs().length, 0, "No Core settlement event");
    }

    // Scenarios: BLYC-CLAIM-YIELD-P04.
    function test_givenPositiveYieldAndRevokedRole_whenClaimed_reverts(address caller_) public {
        _yieldAsset.mint(address(_yieldVault), 3);
        _rolesAdmin.revokeRole(BL_YIELD_CLAIMER_ROLE, address(_claimer));
        bytes memory reason = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            BL_YIELD_CLAIMER_ROLE
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _claimer.previewClaimYield(address(_yieldAsset));
        vm.expectRevert(reason);
        vm.prank(caller_);
        _claimer.claimYield(address(_yieldAsset));
    }

    // Scenarios: BLYC-CLAIM-YIELD-P01.
    function test_givenInsolventCustody_whenClaimed_reverts(address caller_) public {
        _yieldAsset.burn(address(_yieldVault), 1);
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansCore.BurnerLoansCore_Insolvent.selector,
            address(_yieldAsset),
            2000e6,
            2000e6 - 1,
            0
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _claimer.previewClaimYield(address(_yieldAsset));
        vm.expectRevert(reason);
        vm.prank(caller_);
        _claimer.claimYield(address(_yieldAsset));
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_yieldAsset)), address(_core)),
            2000e6,
            "Failed claim preserves liabilities"
        );
    }

    // Scenarios: BLYC-CLAIM-YIELD-L02, BLYC-CLAIM-YIELD-L03, BLYC-CLAIM-YIELD-L04, BLYC-CLAIM-YIELD-L05.
    function test_givenDisabledTask_whenClaimed_reverts(
        address caller_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _claimer.disable("");
        _setCore(coreActive_, coreEnabled_);
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _claimer.previewClaimYield(address(_yieldAsset));
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _claimer.claimYield(address(_yieldAsset));
    }

    // Scenarios: BLYC-CLAIM-YIELD-L10, BLYC-CLAIM-YIELD-L11, BLYC-CLAIM-YIELD-L12, BLYC-CLAIM-YIELD-L13.
    function test_givenInactiveDisabledTask_whenClaimed_reverts(
        address caller_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _claimer.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_claimer));
        _setCore(coreActive_, coreEnabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_claimer)
            )
        );
        vm.prank(caller_);
        _claimer.previewClaimYield(address(_yieldAsset));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_claimer)
            )
        );
        vm.prank(caller_);
        _claimer.claimYield(address(_yieldAsset));
    }

    // Scenarios: BLYC-CLAIM-YIELD-L06, BLYC-CLAIM-YIELD-L07, BLYC-CLAIM-YIELD-L08, BLYC-CLAIM-YIELD-L09.
    function test_givenInactiveTask_whenClaimed_reverts(
        address caller_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _setCore(coreActive_, coreEnabled_);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_claimer));
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
            address(_claimer)
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _claimer.previewClaimYield(address(_yieldAsset));
        vm.expectRevert(reason);
        vm.prank(caller_);
        _claimer.claimYield(address(_yieldAsset));
    }

    // Scenarios: BLYC-CLAIM-YIELD-D01, BLYC-CLAIM-YIELD-D02, BLYC-CLAIM-YIELD-D03.
    function test_givenUnavailableCore_whenClaimed_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        _setCore(active_, enabled_);
        bytes memory reason = abi.encodeWithSelector(
            PolicyDependency.PolicyDependency_NotActive.selector,
            address(_core)
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _claimer.previewClaimYield(address(_yieldAsset));
        vm.expectRevert(reason);
        vm.prank(caller_);
        _claimer.claimYield(address(_yieldAsset));
    }

    function _setCore(bool active_, bool enabled_) internal {
        if (!enabled_) _core.disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
    }

    // Scenarios: BLYC-CLAIM-YIELD-A01, BLYC-CLAIM-YIELD-L01.
    function test_whenPermissionlessCallerSeeds() public {
        address[6] memory callers = [
            address(0),
            address(this),
            address(_core),
            address(_claimer),
            _borrower,
            _heart
        ];
        uint256 snapshot = vm.snapshotState();
        for (uint256 i; i < callers.length; ++i) {
            test_givenOneUnitYield_whenAnyCallerClaims(callers[i], callers[callers.length - 1 - i]);
            vm.revertToState(snapshot);
        }
    }

    // Scenarios: BLYC-CLAIM-YIELD-L01.
    function test_givenReEnabledAndReactivated_whenClaimed() public {
        _claimer.disable("");
        _claimer.reEnable();
        _kernel.executeAction(Actions.DeactivatePolicy, address(_claimer));
        _kernel.executeAction(Actions.ActivatePolicy, address(_claimer));
        test_givenOneUnitYield_whenAnyCallerClaims(address(0), address(this));
    }

    // Scenarios: BLYC-CLAIM-YIELD-P02, BLYC-CLAIM-YIELD-P05.
    function test_givenDirectCustodyDonation_whenYieldClaimed_thenOperatorSharesBoundOutput()
        public
        givenDebtBearingPosition
    {
        _asset.mint(address(_depositManager), 100e6);
        IBurnerLoansYieldClaim.ClaimYieldPreview memory quote = _claimer.previewClaimYield(
            address(_asset)
        );
        assertEq(quote.amountOut, 0, "Direct donation creates no operator-attributed shares");
        uint256 before = _asset.balanceOf(quote.recipient);
        (address token, uint256 amount) = _claimer.claimYield(address(_asset));
        assertEq(amount, 0, "Unattributed donation is not claimable operator yield");
        assertEq(token, address(_asset), "Direct custody yield returns the asset");
        assertEq(amount, quote.amountOut, "Yield output matches its owner preview");
        assertEq(
            _asset.balanceOf(quote.recipient),
            before + amount,
            "DepositManager directly pays the selected recipient"
        );
        assertEq(_asset.balanceOf(address(_payout)), 0, "Yield never enters payout custody");
    }
}
