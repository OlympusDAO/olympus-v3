// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

// Interfaces
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Mocks
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {MockClearinghouse} from "src/test/mocks/MockClearinghouse.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";

// Bond stack (vendored production contracts)
import {RolesAuthority, Authority as SolmateAuthority} from "solmate/auth/authorities/RolesAuthority.sol";
import {BondAggregator} from "src/test/lib/bonds/BondAggregator.sol";
import {BondFixedTermSDA} from "src/test/lib/bonds/BondFixedTermSDA.sol";
import {BondFixedTermTeller} from "src/test/lib/bonds/BondFixedTermTeller.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusClearinghouseRegistry} from "src/modules/CHREG/OlympusClearinghouseRegistry.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {BackingOracle} from "src/policies/BackingOracle.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {YieldRepurchaseFacilityV2} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2.sol";
import {YieldRepurchaseFacilityConfigTimelock} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityConfigTimelock.sol";

/// @notice PRICE mock reporting the version the facility pins: major 1, minor >= 2 (the
///         `getPriceIn` surface of the live `OlympusPricev1_2`).
contract MockPriceV1_2 is MockPrice {
    constructor(
        Kernel kernel_,
        uint8 decimals_,
        uint32 observationFrequency_
    ) MockPrice(kernel_, decimals_, observationFrequency_) {}

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 2);
    }
}

/// @notice Shared unit-test base for the YRF v2 stack.
/// @dev `_deployStack` assembles a local kernel with the real TRSRY, ROLES, and CHREG
///      modules, a PRICE mock pinned to version 1.2 with 18 decimals, the vendored bond
///      stack, and the un-enabled BackingOracle, then deploys `configTimelock` and a facility
///      pinned to it, wires the pair, and enables the timelock. The facility itself is left
///      disabled; tests that need the enabled facility call `_enableFacility`.
///
///      Roles: `guardian` holds admin and emergency, `yrfAdmin` holds yrf_admin, and
///      `heart` holds the heart role. The test contract itself is the kernel executor and
///      the RolesAdmin admin.
///
///      CHREG holds two mock Clearinghouses: `clearinghouse` (active) and
///      `includableClearinghouse` (inactive). Both are registry members, so either passes
///      the facility's `includeClearinghouse` validation.
// solhint-disable-next-line max-states-count
abstract contract YieldRepurchaseFacilityV2TestBase is Test {
    // ========== ACTORS ========== //

    address internal guardian;
    address internal yrfAdmin;
    address internal heart;

    // ========== TOKENS ========== //

    MockOhm internal ohm;
    MockERC20 internal reserve;
    MockERC4626 internal sReserve;

    // ========== BOND STACK ========== //

    RolesAuthority internal auth;
    BondAggregator internal aggregator;
    BondFixedTermTeller internal teller;
    BondFixedTermSDA internal auctioneer;

    // ========== KERNEL AND MODULES ========== //

    Kernel internal kernel;
    OlympusTreasury internal TRSRY;
    OlympusRoles internal ROLES;
    OlympusClearinghouseRegistry internal CHREG;
    MockPriceV1_2 internal PRICE;

    // ========== CLEARINGHOUSES ========== //

    MockClearinghouse internal clearinghouse;
    MockClearinghouse internal includableClearinghouse;

    // ========== POLICIES ========== //

    RolesAdmin internal rolesAdmin;
    BackingOracle internal backingOracle;
    YieldRepurchaseFacilityConfigTimelock internal configTimelock;
    YieldRepurchaseFacilityV2 internal yieldRepo;

    // ========== PARAMETERS ========== //

    uint48 internal configTimelockDelay = 1 days;
    uint32 internal gracePeriod = 5 days;

    /// @notice The discount `_enableFacility` seeds through the enable payload (3%).
    uint256 internal initialDiscount = 3e16;

    /// @notice The max price premium `_enableFacility` seeds through the enable payload
    ///         (10%).
    uint256 internal maxPricePremium = 10e16;

    /// @notice The mocked OHM price, in the 18-decimal oracle scale.
    uint256 internal ohmPrice = 10e18;

    /// @notice The mocked price of every reserve token, in the 18-decimal oracle scale.
    uint256 internal reservePrice = 1e18;

    // ========== SETUP ========== //

    function _deployStack() internal {
        // A fixed recent timestamp, far from the uint48 domain edges.
        vm.warp(1_750_000_000);

        guardian = makeAddr("guardian");
        yrfAdmin = makeAddr("yrfAdmin");
        heart = makeAddr("heart");

        // Tokens
        ohm = new MockOhm("Olympus", "OHM", 9);
        vm.label(address(ohm), "ohm");
        reserve = new MockERC20("Reserve", "RSV", 18);
        vm.label(address(reserve), "reserve");
        sReserve = new MockERC4626(reserve, "sReserve", "sRSV");
        vm.label(address(sReserve), "sReserve");

        // Bond stack; the guardian owns the bond contracts and their authority.
        auth = new RolesAuthority(guardian, SolmateAuthority(address(0)));
        vm.label(address(auth), "bondAuthority");
        aggregator = new BondAggregator(guardian, auth);
        vm.label(address(aggregator), "bondAggregator");
        teller = new BondFixedTermTeller(guardian, aggregator, guardian, auth);
        vm.label(address(teller), "bondTeller");
        auctioneer = new BondFixedTermSDA(teller, aggregator, guardian, auth);
        vm.label(address(auctioneer), "bondAuctioneer");
        vm.prank(guardian);
        aggregator.registerAuctioneer(auctioneer);

        // Kernel and modules; the test contract is the executor.
        kernel = new Kernel();
        vm.label(address(kernel), "kernel");
        TRSRY = new OlympusTreasury(kernel);
        vm.label(address(TRSRY), "TRSRY");
        ROLES = new OlympusRoles(kernel);
        vm.label(address(ROLES), "ROLES");
        PRICE = new MockPriceV1_2(kernel, 18, uint32(8 hours));
        vm.label(address(PRICE), "PRICE");

        clearinghouse = new MockClearinghouse(address(reserve), address(sReserve));
        vm.label(address(clearinghouse), "clearinghouse");
        includableClearinghouse = new MockClearinghouse(address(reserve), address(sReserve));
        vm.label(address(includableClearinghouse), "includableClearinghouse");
        address[] memory inactive = new address[](1);
        inactive[0] = address(includableClearinghouse);
        CHREG = new OlympusClearinghouseRegistry(kernel, address(clearinghouse), inactive);
        vm.label(address(CHREG), "CHREG");

        // Policies. The facility pins the config timelock as an immutable address, so the
        // timelock is deployed first and wired to the facility afterwards. The backing
        // oracle stays un-enabled: only its pure `decimals()` is read by these tests.
        backingOracle = new BackingOracle(kernel);
        vm.label(address(backingOracle), "backingOracle");
        configTimelock = new YieldRepurchaseFacilityConfigTimelock(
            kernel,
            configTimelockDelay,
            gracePeriod
        );
        vm.label(address(configTimelock), "configTimelock");
        yieldRepo = new YieldRepurchaseFacilityV2(
            kernel,
            address(ohm),
            address(backingOracle),
            address(auctioneer),
            address(configTimelock),
            gracePeriod
        );
        vm.label(address(yieldRepo), "yieldRepo");
        rolesAdmin = new RolesAdmin(kernel);
        vm.label(address(rolesAdmin), "rolesAdmin");

        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.InstallModule, address(PRICE));
        kernel.executeAction(Actions.InstallModule, address(CHREG));
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(configTimelock));
        kernel.executeAction(Actions.ActivatePolicy, address(yieldRepo));

        rolesAdmin.grantRole("admin", guardian);
        rolesAdmin.grantRole("emergency", guardian);
        rolesAdmin.grantRole("yrf_admin", yrfAdmin);
        rolesAdmin.grantRole("heart", heart);

        // The facility is its own bond callback, which the auctioneer owner authorizes.
        vm.prank(guardian);
        auctioneer.setCallbackAuthStatus(address(yieldRepo), true);

        // Prices for the OHM quote and the shared reserve; per-asset helpers register
        // their own reserves.
        PRICE.setPrice(address(ohm), ohmPrice);
        PRICE.setPrice(address(reserve), reservePrice);

        // Wire and enable the timelock; the facility stays disabled by default.
        vm.startPrank(guardian);
        configTimelock.setFacility(address(yieldRepo));
        configTimelock.enable("");
        vm.stopPrank();
    }

    // ========== STATE HELPERS ========== //

    /// @notice Enables the facility with the base-configured initial discount and max
    ///         price premium, and no next-yield seeds.
    function _enableFacility() internal {
        vm.prank(guardian);
        yieldRepo.enable(
            abi.encode(
                initialDiscount,
                maxPricePremium,
                new IYieldRepurchaseFacilityV2.NextYieldSeed[](0)
            )
        );
    }
}
