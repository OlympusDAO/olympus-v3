// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {MockSiloLens, MockBaseSilo} from "test/mocks/MockSilo.sol";

import {FullMath} from "libraries/FullMath.sol";
import {Math as OZMath} from "@openzeppelin/contracts/utils/math/Math.sol";

import "src/modules/SPPLY/OlympusSupply.sol";
import {SiloSupply} from "src/modules/SPPLY/submodules/SiloSupply.sol";

import {OlympusPricev2} from "modules/PRICE/OlympusPrice.v2.sol";

contract SiloSupplyTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusSupply;

    MockERC20 internal ohm;
    MockGohm internal gOhm;

    Kernel internal kernel;

    OlympusSupply internal moduleSupply;

    SiloSupply internal submoduleSiloSupply;

    address internal writer;

    MockSiloLens internal siloLens;
    MockBaseSilo internal siloBase;

    address internal siloAmo;

    UserFactory public userFactory;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant INITIAL_CROSS_CHAIN_SUPPLY = 0; // 0 OHM

    // Real values from:
    // https://etherscan.io/address/0xf5ffabab8f9a6f4f6de1f0dd6e0820f68657d7db
    uint256 internal constant LENS_BORROWED_AMOUNT = 477149187374;
    uint256 internal constant LENS_TOTAL_DEPOSITED_AMOUNT = 97364239386463;
    uint256 internal constant LENS_SUPPLIED_AMOUNT = 23401686713550;

    event SourcesUpdated(address amo_, address lens_, address silo_);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Tokens
        {
            ohm = new MockERC20("OHM", "OHM", 9);
            gOhm = new MockGohm(GOHM_INDEX);
        }

        // Locations
        {
            userFactory = new UserFactory();
            address[] memory users = userFactory.create(1);
            siloAmo = users[0];
        }

        // Bophades
        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy SPPLY module
            address[2] memory tokens = [address(ohm), address(gOhm)];
            moduleSupply = new OlympusSupply(kernel, tokens, INITIAL_CROSS_CHAIN_SUPPLY);

            // Deploy mock module writer
            writer = moduleSupply.generateGodmodeFixture(type(OlympusSupply).name);
        }

        // Deploy Silo submodule
        {
            siloLens = new MockSiloLens();
            siloLens.setTotalDepositsWithInterest(LENS_TOTAL_DEPOSITED_AMOUNT);
            siloLens.setTotalBorrowAmountWithInterest(LENS_BORROWED_AMOUNT);
            siloLens.setBalanceOfUnderlying(LENS_SUPPLIED_AMOUNT);

            siloBase = new MockBaseSilo();
            siloBase.setCollateralToken(0x907136B74abA7D5978341eBA903544134A66B065);

            submoduleSiloSupply = new SiloSupply(
                moduleSupply,
                siloAmo,
                address(siloLens),
                address(siloBase)
            );
        }

        // Initialize
        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(moduleSupply));
            kernel.executeAction(Actions.ActivatePolicy, address(writer));

            // Install submodules on SPPLY module
            vm.startPrank(writer);
            moduleSupply.installSubmodule(submoduleSiloSupply);
            vm.stopPrank();
        }
    }

    // Test checklist
    // [X] Submodule
    //  [X] Version
    //  [X] Subkeycode
    //  [X] Incorrect parent
    // [X] getCollateralizedOhm
    //  [X] supplied > borrowed
    //  [X] supplied < borrowed
    //  [X] supplied == borrowed
    // [X] getProtocolOwnedBorrowableOhm
    //  [X] supplied > borrowed
    //  [X] supplied < borrowed
    //  [X] supplied == borrowed
    // [X] getProtocolOwnedLiquidityOhm
    // [X] getProtocolOwnedTreasuryOhm
    // [X] setSources
    //  [X] not parent
    //  [X] amo address
    //  [X] lens address
    //  [X] silo address
    //  [X] multiple addresses

    // =========  TESTS ========= //

    // =========  Module Information ========= //

    function test_submodule_version() public {
        uint8 major;
        uint8 minor;
        (major, minor) = submoduleSiloSupply.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_submodule_parent() public {
        assertEq(fromKeycode(submoduleSiloSupply.PARENT()), "SPPLY");
    }

    function test_submodule_subkeycode() public {
        assertEq(fromSubKeycode(submoduleSiloSupply.SUBKEYCODE()), "SPPLY.SILO");
    }

    function test_submodule_parent_notModule_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        // There's no error message, so just check that a revert happens when attempting to call the module
        vm.expectRevert();

        new SiloSupply(Module(newLocations[0]), siloAmo, address(siloLens), address(siloBase));
    }

    function test_submodule_parent_notSpply_reverts() public {
        // Pass the PRICEv2 module as the parent
        OlympusPricev2 modulePrice = new OlympusPricev2(kernel, 18, 8 hours);

        bytes memory err = abi.encodeWithSignature("Submodule_InvalidParent()");
        vm.expectRevert(err);

        new SiloSupply(modulePrice, siloAmo, address(siloLens), address(siloBase));
    }

    function test_submodule_emitsEvent() public {
        // Expect an event
        vm.expectEmit(true, false, false, true);
        emit SourcesUpdated(siloAmo, address(siloLens), address(siloBase));

        // Create a new submodule
        vm.startPrank(writer);
        submoduleSiloSupply = new SiloSupply(
            moduleSupply,
            siloAmo,
            address(siloLens),
            address(siloBase)
        );
        vm.stopPrank();

        assertEq(submoduleSiloSupply.getSourceCount(), 1);
    }

    // =========  getCollateralizedOhm ========= //

    function test_getCollateralizedOhm_fuzz(uint256 borrowed_) public {
        uint256 borrowed = bound(borrowed_, 0, LENS_TOTAL_DEPOSITED_AMOUNT);
        siloLens.setTotalBorrowAmountWithInterest(borrowed);

        // Any OHM (up to the supplied amount) that is borrowed is collateralized
        uint256 expected = OZMath.min(borrowed, LENS_SUPPLIED_AMOUNT);

        assertEq(submoduleSiloSupply.getCollateralizedOhm(), expected);

        // Check the assertion
        uint256 pobo = submoduleSiloSupply.getProtocolOwnedBorrowableOhm();
        assertEq(pobo + expected, LENS_SUPPLIED_AMOUNT);
    }

    // =========  getProtocolOwnedBorrowableOhm ========= //

    function test_getProtocolOwnedBorrowableOhm_fuzz(uint256 borrowed_) public {
        uint256 borrowed = bound(borrowed_, 0, LENS_TOTAL_DEPOSITED_AMOUNT);
        siloLens.setTotalBorrowAmountWithInterest(borrowed);

        // Any OHM (up to the supplied amount) that is not borrowed is POBO
        uint256 expected;
        if (borrowed < LENS_SUPPLIED_AMOUNT) {
            expected = LENS_SUPPLIED_AMOUNT - borrowed;
        } else {
            expected = 0;
        }

        assertEq(submoduleSiloSupply.getProtocolOwnedBorrowableOhm(), expected);

        // Check the assertion
        uint256 col = submoduleSiloSupply.getCollateralizedOhm();
        assertEq(col + expected, LENS_SUPPLIED_AMOUNT);
    }

    // =========  getProtocolOwnedLiquidityOhm ========= //

    function test_getProtocolOwnedLiquidityOhm_fuzz(uint256 borrowed_) public {
        uint256 borrowed = bound(borrowed_, 0, LENS_TOTAL_DEPOSITED_AMOUNT);
        siloLens.setTotalBorrowAmountWithInterest(borrowed);

        // No OHM is liquidity OHM
        assertEq(submoduleSiloSupply.getProtocolOwnedLiquidityOhm(), 0);
    }

    // =========  getProtocolOwnedTreasuryOhm  ========= //

    function test_getProtocolOwnedTreasuryOhm_fuzz(uint256 borrowed_) public {
        uint256 borrowed = bound(borrowed_, 0, LENS_TOTAL_DEPOSITED_AMOUNT);
        siloLens.setTotalBorrowAmountWithInterest(borrowed);

        // No OHM is treasury OHM
        assertEq(submoduleSiloSupply.getProtocolOwnedTreasuryOhm(), 0);
    }

    // =========  getProtocolOwnedLiquidityReserves ========= //

    function test_getProtocolOwnedLiquidityReserves_fuzz(uint256 borrowed_) public {
        uint256 borrowed = bound(borrowed_, 0, LENS_TOTAL_DEPOSITED_AMOUNT);
        siloLens.setTotalBorrowAmountWithInterest(borrowed);

        SPPLYv1.Reserves[] memory reserves = submoduleSiloSupply
            .getProtocolOwnedLiquidityReserves();

        // No POL
        assertEq(reserves.length, 1);
        assertEq(reserves[0].source, address(siloBase));
        assertEq(reserves[0].tokens.length, 0);
        assertEq(reserves[0].balances.length, 0);
    }

    // =========  setSources ========= //

    function test_setSources_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleSiloSupply.setSources(siloAmo, address(siloLens), address(siloBase));
    }

    function test_setSources_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writer)
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        submoduleSiloSupply.setSources(siloAmo, address(siloLens), address(siloBase));
        vm.stopPrank();
    }

    function test_setSources_amo() public {
        address[] memory newLocations = userFactory.create(1);
        address newAmo = newLocations[0];

        // Expect an event
        vm.expectEmit(true, false, false, true);
        emit SourcesUpdated(newAmo, address(siloLens), address(siloBase));

        vm.startPrank(address(moduleSupply));
        submoduleSiloSupply.setSources(newAmo, address(0), address(0));
        vm.stopPrank();

        assertEq(submoduleSiloSupply.amo(), newAmo);
        assertEq(address(submoduleSiloSupply.lens()), address(siloLens));
        assertEq(address(submoduleSiloSupply.silo()), address(siloBase));

        assertEq(submoduleSiloSupply.getSourceCount(), 1);
    }

    function test_setSources_lens() public {
        address[] memory newLocations = userFactory.create(1);
        address newLens = newLocations[0];

        // Expect an event
        vm.expectEmit(true, false, false, true);
        emit SourcesUpdated(siloAmo, newLens, address(siloBase));

        vm.startPrank(address(moduleSupply));
        submoduleSiloSupply.setSources(address(0), newLens, address(0));
        vm.stopPrank();

        assertEq(submoduleSiloSupply.amo(), siloAmo);
        assertEq(address(submoduleSiloSupply.lens()), newLens);
        assertEq(address(submoduleSiloSupply.silo()), address(siloBase));

        assertEq(submoduleSiloSupply.getSourceCount(), 1);
    }

    function test_setSources_silo() public {
        address[] memory newLocations = userFactory.create(1);
        address newSilo = newLocations[0];

        // Expect an event
        vm.expectEmit(true, false, false, true);
        emit SourcesUpdated(siloAmo, address(siloLens), newSilo);

        vm.startPrank(address(moduleSupply));
        submoduleSiloSupply.setSources(address(0), address(0), newSilo);
        vm.stopPrank();

        assertEq(submoduleSiloSupply.amo(), siloAmo);
        assertEq(address(submoduleSiloSupply.lens()), address(siloLens));
        assertEq(address(submoduleSiloSupply.silo()), newSilo);

        assertEq(submoduleSiloSupply.getSourceCount(), 1);
    }

    function test_setSources_multiple() public {
        address[] memory newLocations = userFactory.create(3);
        address newAmo = newLocations[0];
        address newLens = newLocations[1];
        address newSilo = newLocations[2];

        // Expect an event
        vm.expectEmit(true, false, false, true);
        emit SourcesUpdated(newAmo, newLens, newSilo);

        vm.startPrank(address(moduleSupply));
        submoduleSiloSupply.setSources(newAmo, newLens, newSilo);
        vm.stopPrank();

        assertEq(submoduleSiloSupply.amo(), newAmo);
        assertEq(address(submoduleSiloSupply.lens()), newLens);
        assertEq(address(submoduleSiloSupply.silo()), newSilo);

        assertEq(submoduleSiloSupply.getSourceCount(), 1);
    }
}
