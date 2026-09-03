// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {Actions, Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {BurnerLoansInventory} from "src/policies/BurnerLoansInventory.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {BurnerLoansInventoryTest} from "src/test/policies/BurnerLoansInventory/BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryHandler is Policy, Test {
    uint128 internal constant _MAX_CAP = 4_000_000e9;

    BurnerLoansInventory internal immutable _INVENTORY;
    MockOhm internal immutable _OHM;
    address internal immutable _CONFIG;
    address internal immutable _FACILITY;
    address internal immutable _PROVIDER;
    address internal immutable _RECIPIENT;

    constructor(
        Kernel kernel_,
        BurnerLoansInventory inventory_,
        MockOhm ohm_,
        address config_,
        address facility_,
        address provider_,
        address recipient_
    ) Policy(kernel_) {
        _INVENTORY = inventory_;
        _OHM = ohm_;
        _CONFIG = config_;
        _FACILITY = facility_;
        _PROVIDER = provider_;
        _RECIPIENT = recipient_;
    }

    function configureDependencies() external pure override returns (Keycode[] memory) {
        return new Keycode[](0);
    }

    function requestPermissions() external pure override returns (Permissions[] memory) {
        return new Permissions[](0);
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
    }

    function withdraw(uint128 amountSeed_) external {
        uint256 available = _INVENTORY.providerClaimOhm(_PROVIDER);
        uint256 idle = _INVENTORY.suppliedIdleOhm();
        if (idle < available) available = idle;
        if (available == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, available));

        vm.prank(_PROVIDER);
        _INVENTORY.withdraw(amount, _PROVIDER);
    }

    function draw(uint128 amountSeed_) external {
        uint256 capacity = _INVENTORY.availableCapacity();
        if (capacity == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, capacity));
        vm.prank(_FACILITY);
        _INVENTORY.draw(_RECIPIENT, amount);
    }

    function settleRepayment(uint128 amountSeed_) external {
        uint256 active = _INVENTORY.activePrincipalOhm();
        if (active == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, active));
        _OHM.mint(address(_INVENTORY), amount);
        vm.prank(_FACILITY);
        _INVENTORY.settleRepayment(amount);
    }

    function recordDefault(uint128 amountSeed_) external {
        uint256 active = _INVENTORY.activePrincipalOhm();
        if (active == 0) return;
        vm.prank(_FACILITY);
        _INVENTORY.recordDefault(uint128(bound(amountSeed_, 1, active)));
    }

    function setGlobalDebtCap(uint128 capSeed_) external {
        uint128 active = _INVENTORY.activePrincipalOhm();
        uint128 cap = uint128(bound(capSeed_, active, _MAX_CAP));
        vm.prank(_CONFIG);
        _INVENTORY.setGlobalDebtCap(cap);
    }
}

contract BurnerLoansInventoryInvariantTest is StdInvariant, BurnerLoansInventoryTest {
    BurnerLoansInventoryHandler internal handler;

    function setUp() public override {
        super.setUp();

        handler = new BurnerLoansInventoryHandler(
            kernel,
            inventory,
            ohm,
            address(config),
            address(facility),
            provider,
            recipient
        );

        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(handler));
        inventory.setConfigurator(address(config));
        inventory.enable("");
        vm.stopPrank();

        vm.prank(address(config));
        inventory.setGlobalDebtCap(DEFAULT_CAP);

        // Seed the campaign with idle greater than the cap so every invariant run covers the
        // custody-is-not-debt boundary before randomized transitions begin.
        _supply(DEFAULT_CAP + 1);

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.supply.selector;
        selectors[1] = handler.withdraw.selector;
        selectors[2] = handler.draw.selector;
        selectors[3] = handler.settleRepayment.selector;
        selectors[4] = handler.recordDefault.selector;
        selectors[5] = handler.setGlobalDebtCap.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // invariant
    // given any sequence of Burner Loans Inventory funding and lifecycle transitions
    //  when its aggregate accounting is inspected
    //   then the cap, approval, custody, claim, and capacity invariants hold
    function invariant_Accounting() public view {
        _assertInventoryInvariant();
    }
}
