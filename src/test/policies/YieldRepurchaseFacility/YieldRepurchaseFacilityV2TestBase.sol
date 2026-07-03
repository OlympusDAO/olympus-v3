// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "src/test/lib/UserFactory.sol";

import {BondFixedTermSDA} from "src/test/lib/bonds/BondFixedTermSDA.sol";
import {BondAggregator} from "src/test/lib/bonds/BondAggregator.sol";
import {BondFixedTermTeller} from "src/test/lib/bonds/BondFixedTermTeller.sol";
import {RolesAuthority, Authority as SolmateAuthority} from "solmate/auth/authorities/RolesAuthority.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {MockPrice} from "src/test/mocks/MockPrice.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockClearinghouse} from "src/test/mocks/MockClearinghouse.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusClearinghouseRegistry} from "modules/CHREG/OlympusClearinghouseRegistry.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {OlympusBackingOracle} from "policies/OlympusBackingOracle.sol";
import {YieldRepurchaseFacilityV2} from "policies/YieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2} from "policies/interfaces/IYieldRepurchaseFacilityV2.sol";

/// @notice Shared harness for the multi-asset YRF v2 tests. It deploys the common stack (the bond
///         system, OHM, the USDS-like backing reserve and its vault, the kernel and modules, the
///         facility, the backing oracle and the roles), grants the `heart`/`admin` roles, and
///         authorizes the facility callback. Funding and asset registration are left to each test,
///         since they differ per scenario.
abstract contract YieldRepurchaseFacilityV2TestBase is Test {
    UserFactory internal userCreator;
    address internal guardian;
    address internal heart;

    RolesAuthority internal auth;
    BondAggregator internal aggregator;
    BondFixedTermTeller internal teller;
    BondFixedTermSDA internal auctioneer;

    MockOhm internal ohm;
    MockERC20 internal reserve; // backing reserve (USDS-like)
    MockERC4626 internal sReserve; // backing vault (sUSDS-like, redeem-to-reserve)

    Kernel internal kernel;
    MockPrice internal PRICE;
    OlympusTreasury internal TRSRY;
    OlympusMinter internal MINTR;
    OlympusRoles internal ROLES;
    OlympusClearinghouseRegistry internal CHREG;

    MockClearinghouse internal clearinghouse;
    YieldRepurchaseFacilityV2 internal yieldRepo;
    OlympusBackingOracle internal backingOracle;
    RolesAdmin internal rolesAdmin;

    // Backing value: 11.33 per OHM at 18 decimals.
    uint256 internal backingPerToken = 1133 * 1e16;
    // 3% initial bond discount (18 decimals).
    uint256 internal initialDiscount = 3e16;

    /// @notice Deploys the common stack: bond system, tokens, kernel and modules, the facility, the
    ///         backing oracle and the roles. Sets the oracle price to 10e18 and authorizes the
    ///         facility callback. Does not fund the treasury or register any reserve asset.
    function _deployStack() internal {
        // Set an absolute starting timestamp (the PRICE/Heart cadence is epoch-count based).
        vm.warp(51 * 365 * 24 * 60 * 60);

        userCreator = new UserFactory();
        {
            address[] memory users = userCreator.create(2);
            guardian = users[0];
            heart = users[1];
            vm.label(guardian, "guardian");
            vm.label(heart, "heart");
            auth = new RolesAuthority(guardian, SolmateAuthority(address(0)));
            vm.label(address(auth), "RolesAuthority");

            aggregator = new BondAggregator(guardian, auth);
            vm.label(address(aggregator), "BondAggregator");
            teller = new BondFixedTermTeller(guardian, aggregator, guardian, auth);
            vm.label(address(teller), "BondTeller");
            auctioneer = new BondFixedTermSDA(teller, aggregator, guardian, auth);
            vm.label(address(auctioneer), "BondAuctioneer");

            vm.prank(guardian);
            aggregator.registerAuctioneer(auctioneer);
        }

        {
            ohm = new MockOhm("Olympus", "OHM", 9);
            vm.label(address(ohm), "OHM");
            reserve = new MockERC20("Reserve", "RSV", 18);
            vm.label(address(reserve), "reserve");
            sReserve = new MockERC4626(reserve, "sReserve", "sRSV");
            vm.label(address(sReserve), "sReserve");
        }

        {
            kernel = new Kernel();
            vm.label(address(kernel), "Kernel");

            PRICE = new MockPrice(kernel, uint48(8 hours), 10 * 1e18);
            vm.label(address(PRICE), "PRICE");
            TRSRY = new OlympusTreasury(kernel);
            vm.label(address(TRSRY), "TRSRY");
            MINTR = new OlympusMinter(kernel, address(ohm));
            vm.label(address(MINTR), "MINTR");
            ROLES = new OlympusRoles(kernel);
            vm.label(address(ROLES), "ROLES");

            clearinghouse = new MockClearinghouse(address(reserve), address(sReserve));
            vm.label(address(clearinghouse), "clearinghouse");
            CHREG = new OlympusClearinghouseRegistry(
                kernel,
                address(clearinghouse),
                new address[](0)
            );
            vm.label(address(CHREG), "CHREG");

            PRICE.setMovingAverage(10 * 1e18);
            PRICE.setLastPrice(10 * 1e18);
            PRICE.setDecimals(18);
            PRICE.setLastTime(uint48(vm.getBlockTimestamp()));
        }

        {
            backingOracle = new OlympusBackingOracle(kernel);
            vm.label(address(backingOracle), "backingOracle");
            yieldRepo = new YieldRepurchaseFacilityV2(
                kernel,
                address(ohm),
                address(backingOracle),
                address(auctioneer),
                address(teller)
            );
            vm.label(address(yieldRepo), "yieldRepo");
            rolesAdmin = new RolesAdmin(kernel);
            vm.label(address(rolesAdmin), "rolesAdmin");
        }

        {
            kernel.executeAction(Actions.InstallModule, address(PRICE));
            kernel.executeAction(Actions.InstallModule, address(TRSRY));
            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(ROLES));
            kernel.executeAction(Actions.InstallModule, address(CHREG));

            kernel.executeAction(Actions.ActivatePolicy, address(yieldRepo));
            kernel.executeAction(Actions.ActivatePolicy, address(backingOracle));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }

        rolesAdmin.grantRole("heart", address(heart));
        rolesAdmin.grantRole("admin", guardian);

        // V2 creates bond markets with a callback, which requires the market owner to be
        // authorized on the auctioneer.
        vm.prank(guardian);
        auctioneer.setCallbackAuthStatus(address(yieldRepo), true);
    }

    /// @notice Enables the backing oracle (with `backingPerToken`) and the facility (with the
    ///         common enable params). Funding and asset registration should be done before this.
    function _enableFacility() internal {
        vm.startPrank(guardian);
        backingOracle.enable(abi.encode(backingPerToken));
        yieldRepo.enable(abi.encode(initialDiscount));
        vm.stopPrank();
    }

    /// @notice Donates 0.01% of the backing vault's assets to it, simulating accrued yield.
    function _mintYield() internal {
        reserve.mint(address(sReserve), sReserve.totalAssets() / 10000);
    }
}
