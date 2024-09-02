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
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {Protocoloop} from "policies/ProtocoLoop.sol";

// solhint-disable-next-line max-states-count
contract ProtocoLoopTest is Test {
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address internal bob;
    address internal guardian;
    address internal policy;
    address internal heart;

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

    MockClearinghouse internal clearinghouse;
    Protocoloop internal protocoloop;
    RolesAdmin internal rolesAdmin;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            /// Deploy bond system to test against
            address[] memory users = userCreator.create(5);
            alice = users[0];
            bob = users[1];
            guardian = users[2];
            policy = users[3];
            heart = users[4];
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
            RANGE = new OlympusRange(
                kernel,
                ERC20(ohm),
                ERC20(reserve),
                uint256(100),
                [uint256(2000), uint256(2500)],
                [uint256(2000), uint256(2500)]
            );
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

            /// Deploy protocol loop
            protocoloop = new Protocoloop(
                kernel,
                address(ohm),
                address(reserve),
                address(wrappedReserve),
                address(teller),
                address(auctioneer),
                address(clearinghouse),
                105_000_000e18, // initial reserve balance
                1_05e16 // initial conversion rate (1 wrappedReserve = 1.05 reserve)
            );

            /// Deploy ROLES administrator
            rolesAdmin = new RolesAdmin(kernel);
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
            kernel.executeAction(Actions.ActivatePolicy, address(protocoloop));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }
        {
            /// Configure access control

            /// Protocoloop ROLES
            rolesAdmin.grantRole("heart", address(heart));
            rolesAdmin.grantRole("loop_daddy", guardian);
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
    }

    function _mintYield() internal {
        // Get the balance of reserves in the wrappedReserve contract
        uint256 wrappedReserveBalance = wrappedReserve.totalAssets();

        // Calculate the yield to mint (0.01%)
        uint256 yield = wrappedReserveBalance / 10000;

        // Mint the yield
        reserve.mint(address(wrappedReserve), yield);
    }

    // test cases
    // [X] setup (contructor + configureDependencies)
    //   [X] addresses are set correctly
    //   [X] initial reserve balance is set correctly
    //   [X] initial conversion rate is set correctly
    //   [X] epoch is set correctly
    // [ ] endEpoch
    //   [ ] when contract is shutdown
    //     [ ] nothing happens
    //   [ ] when contract is not shutdown
    //     [ ] when epoch is not divisible by 3
    //       [ ] nothing happens
    //     [ ] when epoch is divisible by 3
    //       [ ] when epoch == epochLength
    //         [ ] The yield earned on the wrapped reserves over the past 21 epochs is withdrawn from the TRSRY (affecting the balanceInDai and bidAmount)
    //         [ ] OHM in the contract is burned and reserves are added at the backing rate
    //         [ ] a new bond market is created with correct bid amount
    //       [ ] when epoch != epochLength
    //         [ ] OHM in the contract is burned and reserves are added at the backing rate
    //         [ ] a new bond market is created with correct bid amount
    // [ ] adjustNextYield
    // [ ] shutdown
    // [ ] getNextYield
    // [ ] getReserveBalance

    function test_setup() public {
        // addresses are set correctly
        assertEq(address(protocoloop.ohm()), address(ohm));
        assertEq(address(protocoloop.dai()), address(reserve));
        assertEq(address(protocoloop.sdai()), address(wrappedReserve));
        assertEq(address(protocoloop.teller()), address(teller));
        assertEq(address(protocoloop.auctioneer()), address(auctioneer));

        // initial reserve balance is set correctly
        assertEq(protocoloop.lastReserveBalance(), 105_000_000e18);
        assertEq(protocoloop.getReserveBalance(), 105_000_000e18);

        // initial conversion rate is set correctly
        assertEq(protocoloop.lastConversionRate(), 1_05e16);
        assertEq((wrappedReserve.totalAssets() * 1e18) / wrappedReserve.totalSupply(), 1_05e16);

        // epoch is set correctly
        assertEq(protocoloop.epoch(), 20);
    }
}
