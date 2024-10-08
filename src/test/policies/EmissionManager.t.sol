// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {BondFixedTermSDA} from "test/lib/bonds/BondFixedTermSDA.sol";
import {BondAggregator} from "test/lib/bonds/BondAggregator.sol";
import {BondFixedTermTeller} from "test/lib/bonds/BondFixedTermTeller.sol";
import {RolesAuthority, Authority as SolmateAuthority} from "solmate/auth/authorities/RolesAuthority.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626, ERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {MockPrice} from "test/mocks/MockPrice.sol";
import {MockOhm} from "test/mocks/MockOhm.sol";
import {MockClearinghouse} from "test/mocks/MockClearinghouse.sol";

import {IBondSDA} from "interfaces/IBondSDA.sol";
import {IBondAggregator} from "interfaces/IBondAggregator.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/Kernel.sol";
import {OlympusRange} from "modules/RANGE/OlympusRange.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusClearinghouseRegistry} from "modules/CHREG/OlympusClearinghouseRegistry.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {EmissionManager} from "policies/EmissionManager.sol";

// solhint-disable-next-line max-states-count
contract EmissionManagerTest is Test {
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address internal bob;
    address internal guardian;

    RolesAuthority internal auth;
    BondAggregator internal aggregator;
    BondFixedTermTeller internal teller;
    BondFixedTermSDA internal auctioneer;
    MockOhm internal ohm;
    MockERC20 internal reserve;
    MockERC4626 internal wrappedReserve;

    Kernel internal kernel;
    MockPrice internal PRICE;
    OlympusRange internal RANGE;
    OlympusTreasury internal TRSRY;
    OlympusMinter internal MINTR;
    OlympusRoles internal ROLES;
    OlympusClearinghouseRegistry internal CHREG;

    MockClearinghouse internal clearinghouse;
    RolesAdmin internal rolesAdmin;
    EmissionManager internal emissionManager;

    // test cases
    //
    // core functionality
    // [ ] execute
    //   [ ] when not locally active
    //     [ ] it reverts
    //   [ ] when locally active
    //     [ ] when beatCounter != 2
    //        [ ] it returns without doing anything
    //     [ ] when beatCounter == 2
    //        [ ] when current OHM balance is not zero
    //           [ ] it reduces supply added from the last sale
    //        [ ] when current DAI balance is not zero
    //           [ ] it increments the reserves added from the last sale
    //           [ ] it deposits the DAI into sDAI and sends it to the treasury
    //           [ ] it updates the backing price value based on the reserves added and supply added values from the last sale
    //        [ ] when sell amount is greater than current OHM balance
    //           [ ] it mints the difference between the sell amount and the current OHM balance to the contract
    //        [ ] when sell amount is less than current OHM balance
    //           [ ] it burns the difference between the current OHM balance and the sell amount from the contract
    //        [ ] when the current balance equals the sell amount
    //           [ ] it does not mint or burn OHM
    //        [ ] when sell amount is not zero
    //           [ ] it creates a new bond market with the sell amount
    //        [ ] when sell amount is zero
    //           [ ] it does not create a new bond market
    //
    // view functions
    // [ ] getSupply
    // [ ] getReseves
    //
    // emergency functions
    // [ ] shutdown
    // [ ] restart
    //
    // admin functions
    // [ ] initialize
    // [ ] setBaseRate
    // [ ] setMinimumPremium
    // [ ] adjustBacking
    // [ ] adjustRestartTimeframe
    // [ ] updateBondContracts

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            /// Deploy bond system to test against
            address[] memory users = userCreator.create(3);
            alice = users[0];
            bob = users[1];
            guardian = users[2];
            auth = new RolesAuthority(guardian, SolmateAuthority(address(0)));

            /// Deploy the bond system
            aggregator = new BondAggregator(guardian, auth);
            teller = new BondFixedTermTeller(guardian, aggregator, guardian, auth);
            auctioneer = new BondFixedTermSDA(teller, aggregator, guardian, auth);

            /// Register auctioneer on the bond system
            vm.prank(guardian);
            aggregator.registerAuctioneer(auctioneer);
        }

        {
            /// Deploy mock tokens
            ohm = new MockOhm("Olympus", "OHM", 9);
            reserve = new MockERC20("Reserve", "RSV", 18);
            wrappedReserve = new MockERC4626(reserve, "wrappedReserve", "sRSV");
        }

        {
            /// Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            /// Deploy modules (some mocks)
            PRICE = new MockPrice(kernel, uint48(8 hours), 10 * 1e18);
            CHREG = new OlympusClearinghouseRegistry(kernel, address(0), new address[](0));
            TRSRY = new OlympusTreasury(kernel);
            MINTR = new OlympusMinter(kernel, address(ohm));
            ROLES = new OlympusRoles(kernel);

            /// Configure mocks
            PRICE.setMovingAverage(10 * 1e18);
            PRICE.setLastPrice(10 * 1e18);
            PRICE.setDecimals(18);
            PRICE.setLastTime(uint48(block.timestamp));
        }

        {
            // Deploy mock clearinghouse
            clearinghouse = new MockClearinghouse(address(reserve), address(wrappedReserve));

            /// Deploy ROLES administrator
            rolesAdmin = new RolesAdmin(kernel);

            // Deploy the emission manager
            emissionManager = new EmissionManager(
                kernel,
                address(ohm),
                address(reserve),
                address(wrappedReserve),
                address(clearinghouse)
            );
        }

        {
            /// Initialize system and kernel

            /// Install modules
            kernel.executeAction(Actions.InstallModule, address(PRICE));
            kernel.executeAction(Actions.InstallModule, address(RANGE));
            kernel.executeAction(Actions.InstallModule, address(TRSRY));
            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(ROLES));

            /// Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(emissionManager));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }
        {
            /// Configure access control

            /// YieldRepurchaseFacility ROLES
            rolesAdmin.grantRole("heart", address(heart));
            rolesAdmin.grantRole("loop_daddy", guardian);

            /// Operator ROLES
            rolesAdmin.grantRole("operator_admin", address(guardian));
        }

        // Mint tokens to users, clearinghouse, and TRSRY for testing
        uint256 testOhm = 1_000_000 * 1e9;
        uint256 testReserve = 1_000_000 * 1e18;

        ohm.mint(alice, testOhm * 20);

        reserve.mint(address(TRSRY), testReserve * 80);
        reserve.mint(address(clearinghouse), testReserve * 20);

        // Deposit TRSRY reserves into wrappedReserve
        vm.startPrank(address(TRSRY));
        reserve.approve(address(wrappedReserve), testReserve * 80);
        wrappedReserve.deposit(testReserve * 80, address(TRSRY));
        vm.stopPrank();

        // Deposit clearinghouse reserves into wrappedReserve
        vm.startPrank(address(clearinghouse));
        reserve.approve(address(wrappedReserve), testReserve * 20);
        wrappedReserve.deposit(testReserve * 20, address(clearinghouse));
        vm.stopPrank();

        // Mint additional reserve to the wrapped reserve to hit the initial conversion rate
        reserve.mint(address(wrappedReserve), 5 * testReserve);

        // Approve the bond teller for the tokens to swap
        vm.prank(alice);
        ohm.approve(address(teller), testOhm * 20);

        // Initialise the operator so that the range prices are set
        vm.prank(guardian);
        operator.initialize();

        // Set principal receivables for the clearinghouse
        clearinghouse.setPrincipalReceivables(uint256(100_000_000e18));

        // Initialize the yield repo facility
        vm.prank(guardian);
        yieldRepo.initialize(initialReserves, initialConversionRate, initialYield);
    }
}
