// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(missing-zero-check,unsafe-typecast,unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts

import {Test} from "forge-std/Test.sol";
import {BurnerLoansInventory} from "src/policies/burnerloans/BurnerLoansInventory.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.
// Test fixtures accept zero addresses to model unset, cleared, and invalid states.
// Scenario-specific contracts and fixtures have no cross-file consumers.

contract BurnerLoansInventoryHandler is Test {
    uint128 internal constant _MAX_CAP = 4_000_000e9;

    BurnerLoansInventory internal immutable _INVENTORY;
    MockOhm internal immutable _OHM;
    address internal immutable _ADMIN;
    uint256 public modelPrincipal;
    uint256 public modelClaim;
    uint256 public modelIdle;
    address internal immutable _FACILITY;
    address internal immutable _PROVIDER;
    address internal immutable _RECIPIENT;

    constructor(
        BurnerLoansInventory inventory_,
        MockOhm ohm_,
        address admin_,
        address facility_,
        address provider_,
        address recipient_
    ) {
        _INVENTORY = inventory_;
        _OHM = ohm_;
        _ADMIN = admin_;
        _FACILITY = facility_;
        _PROVIDER = provider_;
        _RECIPIENT = recipient_;
    }

    function supply(uint128 amountSeed_) external {
        uint256 remainingClaim = _MAX_CAP - _INVENTORY.suppliedOhm();
        if (remainingClaim == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, remainingClaim));

        _OHM.mint(_PROVIDER, amount);
        vm.startPrank(_PROVIDER);
        _OHM.approve(address(_INVENTORY), amount);
        _INVENTORY.supply(amount);
        vm.stopPrank();
        modelClaim += amount;
        modelIdle += amount;
    }

    function withdraw(uint128 amountSeed_) external {
        uint256 available = _INVENTORY.providerClaimOhm(_PROVIDER);
        uint256 idle = _INVENTORY.suppliedIdleOhm();
        if (idle < available) available = idle;
        if (available == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, available));

        vm.prank(_PROVIDER);
        _INVENTORY.withdraw(amount, _PROVIDER);
        modelClaim -= amount;
        modelIdle -= amount;
    }

    function draw(uint128 amountSeed_) external {
        uint256 capacity = _INVENTORY.availableCapacity();
        if (capacity == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, capacity));
        vm.prank(_FACILITY);
        _INVENTORY.draw(_RECIPIENT, amount);
        modelPrincipal += amount;
        modelIdle -= amount < modelIdle ? amount : modelIdle;
    }

    function settleRepayment(uint128 amountSeed_) external {
        uint256 active = _INVENTORY.activePrincipalOhm();
        if (active == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, active));
        _OHM.mint(address(_INVENTORY), amount);
        vm.prank(_FACILITY);
        _INVENTORY.settleRepayment(amount);
        modelPrincipal -= amount;
        uint256 deficit = modelClaim - modelIdle;
        modelIdle += amount < deficit ? amount : deficit;
    }

    function settleDefault(uint128 amountSeed_) external {
        uint256 active = _INVENTORY.activePrincipalOhm();
        if (active == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, active));
        vm.prank(_FACILITY);
        _INVENTORY.settleDefault(amount);
        modelPrincipal -= amount;
    }

    function setGlobalDebtCap(uint128 capSeed_) external {
        uint128 active = _INVENTORY.activePrincipalOhm();
        uint128 cap = uint128(bound(capSeed_, active, _MAX_CAP));
        vm.prank(_ADMIN);
        _INVENTORY.setGlobalDebtCap(cap);
    }

    function pauseAndRecover(bool useReEnable_) external {
        vm.prank(_ADMIN);
        _INVENTORY.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_PROVIDER);
        _INVENTORY.supply(1);
        vm.prank(_ADMIN);
        if (useReEnable_) _INVENTORY.reEnable();
        else _INVENTORY.enable("");
    }
}

// forge-lint: disable-end(missing-zero-check,unsafe-typecast,unused-return)
