// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {BurnerLoansInventoryTest} from "src/test/policies/BurnerLoansInventory/BurnerLoansInventoryTest.sol";

contract BurnerLoansInventorySettleRepaymentTest is BurnerLoansInventoryTest {
    uint128 internal constant ACTIVE_PRINCIPAL = 500e9;
    uint128 internal constant SUPPLIED_CLAIM = 300e9;

    event RepaymentSettled(uint256 amount, uint256 retainedAmount, uint256 burnedAmount);

    function setUp() public override {
        super.setUp();
        _enableAndSetCap(1_000e9);
        _supply(300e9);
        vm.prank(address(facility));
        inventory.draw(recipient, 500e9);
    }

    // settleRepayment
    // [X] given the provider claim is not replenished, it retains repayment before burning
    function test_givenClaimDeficit_retainsRepayment(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, SUPPLIED_CLAIM));
        _transferRepayment(amount_);

        vm.expectEmit(true, true, true, true, address(inventory));
        emit RepaymentSettled(amount_, amount_, 0);
        vm.prank(address(facility));
        inventory.settleRepayment(amount_);

        // active = 500e9 - amount_ (9 decimals); retained idle = amount_ (9 decimals).
        assertEq(inventory.activePrincipalOhm(), ACTIVE_PRINCIPAL - amount_, "active principal");
        assertEq(inventory.suppliedIdleOhm(), amount_, "supplied idle");
        assertEq(inventory.suppliedOhm(), SUPPLIED_CLAIM, "supplied claim");
        assertEq(mintr.mintApproval(address(inventory)), 500e9, "mint approval");
        _assertInventoryInvariant();
    }

    // settleRepayment
    // [X] given the provider claim is already replenished, it burns the full repayment
    function test_givenClaimReplenished_burnsRepayment(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, ACTIVE_PRINCIPAL - SUPPLIED_CLAIM));
        _transferRepayment(SUPPLIED_CLAIM);
        vm.prank(address(facility));
        inventory.settleRepayment(SUPPLIED_CLAIM);
        _transferRepayment(amount_);

        uint256 supplyBefore = ohm.totalSupply();
        vm.prank(address(facility));
        inventory.settleRepayment(amount_);

        // active = 500e9 - 300e9 - amount_; approval = 500e9 + burned amount_.
        assertEq(
            inventory.activePrincipalOhm(),
            ACTIVE_PRINCIPAL - SUPPLIED_CLAIM - amount_,
            "active principal"
        );
        assertEq(inventory.suppliedIdleOhm(), SUPPLIED_CLAIM, "supplied idle");
        assertEq(ohm.totalSupply(), supplyBefore - amount_, "burned amount");
        assertEq(mintr.mintApproval(address(inventory)), 500e9 + amount_, "mint approval");
        _assertInventoryInvariant();
    }

    // settleRepayment
    // [X] given repayment crosses the remaining claim deficit, it retains then burns the excess
    function test_givenRepaymentCrossesClaimDeficit_splitsRetentionAndBurn(uint128 amount_) public {
        amount_ = uint128(bound(amount_, SUPPLIED_CLAIM + 1, ACTIVE_PRINCIPAL));
        uint128 burnedAmount = amount_ - SUPPLIED_CLAIM;
        _transferRepayment(amount_);
        uint256 supplyBefore = ohm.totalSupply();

        vm.expectEmit(true, true, true, true, address(inventory));
        emit RepaymentSettled(amount_, SUPPLIED_CLAIM, burnedAmount);
        vm.prank(address(facility));
        inventory.settleRepayment(amount_);

        // active = 500e9 - amount_; approval = 500e9 + (amount_ - 300e9).
        assertEq(inventory.activePrincipalOhm(), ACTIVE_PRINCIPAL - amount_, "active principal");
        assertEq(inventory.suppliedIdleOhm(), SUPPLIED_CLAIM, "supplied idle");
        assertEq(ohm.totalSupply(), supplyBefore - burnedAmount, "burned amount");
        assertEq(mintr.mintApproval(address(inventory)), 500e9 + burnedAmount, "mint approval");
        _assertInventoryInvariant();
    }

    // settleRepayment
    // [X] given MINTR rejects the burn, repayment accounting completes and leaves ordinary surplus
    function test_givenBurnFailure_settlesAndLeavesSurplus(uint128 burnAmount_) public {
        burnAmount_ = uint128(bound(burnAmount_, 1, 200e9));
        uint128 repaymentAmount = 300e9 + burnAmount_;
        _transferRepayment(repaymentAmount);
        bytes memory failure = abi.encodeWithSelector(MINTRv1.MINTR_NotApproved.selector);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeCall(MINTRv1.burnOhm, (address(inventory), burnAmount_)),
            failure
        );

        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.OhmBurnFailed(burnAmount_, failure);
        vm.prank(address(facility));
        inventory.settleRepayment(repaymentAmount);

        assertEq(inventory.activePrincipalOhm(), 200e9 - burnAmount_, "active principal settled");
        assertEq(inventory.suppliedIdleOhm(), 300e9, "provider claim replenished");
        assertEq(inventory.suppliedOhm(), 300e9, "claim unchanged");
        assertEq(inventory.surplusOhm(), burnAmount_, "failed burn surplus");
        assertEq(ohm.balanceOf(address(inventory)), repaymentAmount, "retained and surplus OHM");
        assertEq(mintr.mintApproval(address(inventory)), 500e9, "mint approval unchanged");
        assertEq(
            inventory.desiredMintApproval() - mintr.mintApproval(address(inventory)),
            burnAmount_,
            "mint approval deficit"
        );
        _assertInventoryInvariant();
    }

    // settleRepayment
    // [X] given no supplied OHM, every valid repayment unit is burned
    function test_givenNoSuppliedOhm_burnsFullRepayment(uint128 amount_) public {
        _transferRepayment(300e9);
        vm.prank(address(facility));
        inventory.settleRepayment(300e9);
        vm.prank(provider);
        inventory.withdraw(300e9, recipient);

        amount_ = uint128(bound(amount_, 1, 200e9));
        _transferRepayment(amount_);
        uint256 supplyBefore = ohm.totalSupply();

        vm.prank(address(facility));
        inventory.settleRepayment(amount_);

        assertEq(ohm.totalSupply(), supplyBefore - amount_, "full repayment burned");
        _assertInventoryState(address(inventory), 0, 200e9 - amount_, 0, 0, 800e9 + amount_);
    }

    // settleRepayment
    // [X] given repayment exceeds active principal, it reverts without changing accounting
    function test_givenAmountAbovePrincipal_reverts(uint128 excess_) public {
        excess_ = uint128(bound(excess_, 1, type(uint128).max - 500e9));
        uint128 amount = 500e9 + excess_;
        ohm.mint(address(inventory), amount);
        vm.prank(address(facility));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_ExcessivePrincipal.selector,
                amount,
                500e9
            )
        );
        inventory.settleRepayment(amount);
        assertEq(inventory.activePrincipalOhm(), 500e9, "active principal unchanged");
    }

    // settleRepayment
    // [X] given zero amount, it reverts without changing accounting
    function test_givenZeroAmount_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAmount.selector);
        vm.prank(address(facility));
        inventory.settleRepayment(0);

        assertEq(inventory.activePrincipalOhm(), 500e9, "active principal unchanged");
        _assertInventoryInvariant();
    }

    // settleRepayment
    // [X] given Burner Loans Inventory has not received the reported repayment, it reverts
    function test_givenInsufficientReceivedBalance_reverts(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 500e9));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientBalance.selector,
                amount_,
                0
            )
        );
        vm.prank(address(facility));
        inventory.settleRepayment(amount_);

        assertEq(inventory.activePrincipalOhm(), 500e9, "active principal unchanged");
        _assertInventoryInvariant();
    }

    // settleRepayment
    // [X] given the global pause is active, it blocks repayment exits
    function test_givenGloballyDisabled_reverts() public {
        vm.prank(emergency);
        inventory.disable("");
        ohm.mint(address(inventory), 1e9);
        vm.prank(address(facility));
        vm.expectRevert(IEnabler.NotEnabled.selector);
        inventory.settleRepayment(1e9);
    }

    // settleRepayment
    // [X] given an unrelated caller, it rejects lifecycle accounting
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != address(facility));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_Unauthorized.selector,
                caller_
            )
        );
        vm.prank(caller_);
        inventory.settleRepayment(1e9);
    }

    // settleRepayment
    // [X] given approval restoration fails after burning, settlement completes and records diagnostics
    function test_givenApprovalRestorationFailure_defersToAdminWithoutReverting(
        uint128 amount_
    ) public {
        amount_ = uint128(bound(amount_, 1, ACTIVE_PRINCIPAL - SUPPLIED_CLAIM));
        _transferRepayment(SUPPLIED_CLAIM);
        vm.prank(address(facility));
        inventory.settleRepayment(SUPPLIED_CLAIM);
        _transferRepayment(amount_);
        bytes memory failure = abi.encodeWithSelector(MINTRv1.MINTR_NotApproved.selector);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeCall(MINTRv1.increaseMintApproval, (address(inventory), amount_)),
            failure
        );

        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.ApprovalRestorationFailed(amount_, failure);
        vm.prank(address(facility));
        inventory.settleRepayment(amount_);

        assertEq(
            inventory.activePrincipalOhm(),
            ACTIVE_PRINCIPAL - SUPPLIED_CLAIM - amount_,
            "principal settled"
        );
        assertEq(
            inventory.desiredMintApproval() - mintr.mintApproval(address(inventory)),
            amount_,
            "approval deficit"
        );
        _assertInventoryInvariant();
    }

    // settleRepayment
    // [X] given another active policy in the same Kernel, exact facility authentication rejects it
    function test_givenActiveSameKernelNonFacility_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_Unauthorized.selector,
                address(config)
            )
        );
        vm.prank(address(config));
        inventory.settleRepayment(1e9);
    }
}
