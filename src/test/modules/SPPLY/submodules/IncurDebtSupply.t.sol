// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";

import {FullMath} from "libraries/FullMath.sol";
import {Math as OZMath} from "@openzeppelin/contracts/utils/math/Math.sol";

import "src/modules/SPPLY/OlympusSupply.sol";
import {IncurDebtSupply, IIncurDebt} from "src/modules/SPPLY/submodules/IncurDebtSupply.sol";

import {OlympusPricev2} from "modules/PRICE/OlympusPrice.v2.sol";

contract MockIncurDebt is IIncurDebt {
    uint256 public totalDebt;

    constructor(uint256 totalDebt_) {
        totalDebt = totalDebt_;
    }

    function totalOutstandingGlobalDebt() external view override returns (uint256) {
        return totalDebt;
    }

    function setTotalDebt(uint256 totalDebt_) external {
        totalDebt = totalDebt_;
    }
}

contract IncurDebtSupplyTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusSupply;

    MockERC20 internal ohm;
    MockGohm internal gOhm;

    Kernel internal kernel;

    OlympusSupply internal moduleSupply;

    IncurDebtSupply internal submoduleIncurDebtSupply;
    MockIncurDebt incurDebt;

    address internal writer;

    UserFactory public userFactory;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant INITIAL_CROSS_CHAIN_SUPPLY = 0; // 0 OHM

    event IncurDebtUpdated(address incurDebt_);

    uint256 internal constant TOTAL_DEBT = 1000e9;

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

        // Deploy submodule
        {
            incurDebt = new MockIncurDebt(TOTAL_DEBT);

            submoduleIncurDebtSupply = new IncurDebtSupply(moduleSupply, address(incurDebt));
        }

        // Initialize
        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(moduleSupply));
            kernel.executeAction(Actions.ActivatePolicy, address(writer));

            // Install submodules on SPPLY module
            vm.startPrank(writer);
            moduleSupply.installSubmodule(submoduleIncurDebtSupply);
            vm.stopPrank();
        }
    }

    // Test checklist
    // [X] Submodule
    //  [X] Version
    //  [X] Subkeycode
    // [X] Constructor
    //  [X] Incorrect parent
    //  [X] Zero address
    //  [X] Success
    // [X] getCollateralizedOhm
    // [X] getProtocolOwnedBorrowableOhm
    // [X] getProtocolOwnedLiquidityOhm
    // [X] getProtocolOwnedTreasuryOhm
    // [X] setIncurDebt
    //  [X] not parent
    //  [X] address(0)
    //  [X] success

    // =========  TESTS ========= //

    // =========  Module Information ========= //

    function test_submodule_version() public {
        uint8 major;
        uint8 minor;
        (major, minor) = submoduleIncurDebtSupply.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_submodule_parent() public {
        assertEq(fromKeycode(submoduleIncurDebtSupply.PARENT()), "SPPLY");
    }

    function test_submodule_subkeycode() public {
        assertEq(fromSubKeycode(submoduleIncurDebtSupply.SUBKEYCODE()), "SPPLY.INCURDEBT");
    }

    // =========  Constructor ========= //

    function test_constructor_parent_notModule_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        // There's no error message, so just check that a revert happens when attempting to call the module
        vm.expectRevert();

        new IncurDebtSupply(Module(newLocations[0]), address(incurDebt));
    }

    function test_constructor_parent_notSpply_reverts() public {
        // Pass the PRICEv2 module as the parent
        OlympusPricev2 modulePrice = new OlympusPricev2(kernel, 18, 8 hours);

        bytes memory err = abi.encodeWithSignature("Submodule_InvalidParent()");
        vm.expectRevert(err);

        new IncurDebtSupply(modulePrice, address(incurDebt));
    }

    function test_constructor_zeroAddress() public {
        bytes memory err = abi.encodeWithSignature("IncurDebtSupply_InvalidParams()");
        vm.expectRevert(err);

        new IncurDebtSupply(moduleSupply, address(0));
    }

    function test_constructor_emitsEvent() public {
        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit IncurDebtUpdated(address(incurDebt));

        // New IncurDebtSupply
        submoduleIncurDebtSupply = new IncurDebtSupply(moduleSupply, address(incurDebt));

        assertEq(submoduleIncurDebtSupply.getIncurDebt(), address(incurDebt));

        assertEq(submoduleIncurDebtSupply.getSourceCount(), 1);
    }

    // =========  getCollateralizedOhm ========= //

    function test_getCollateralizedOhm_fuzz(uint256 totalDebt_) public {
        uint256 totalDebt = bound(totalDebt_, 0, 1000e9);
        incurDebt.setTotalDebt(totalDebt);

        assertEq(submoduleIncurDebtSupply.getCollateralizedOhm(), totalDebt);
    }

    // =========  getProtocolOwnedBorrowableOhm ========= //

    function test_getProtocolOwnedBorrowableOhm_fuzz(uint256 totalDebt_) public {
        uint256 totalDebt = bound(totalDebt_, 0, 1000e9);
        incurDebt.setTotalDebt(totalDebt);

        assertEq(submoduleIncurDebtSupply.getProtocolOwnedBorrowableOhm(), 0);
    }

    // =========  getProtocolOwnedLiquidityOhm ========= //

    function test_getProtocolOwnedLiquidityOhm_fuzz(uint256 totalDebt_) public {
        uint256 totalDebt = bound(totalDebt_, 0, 1000e9);
        incurDebt.setTotalDebt(totalDebt);

        assertEq(submoduleIncurDebtSupply.getProtocolOwnedLiquidityOhm(), 0);
    }

    // =========  getProtocolOwnedTreasuryOhm  ========= //

    function test_getProtocolOwnedTreasuryOhm_fuzz(uint256 totalDebt_) public {
        uint256 totalDebt = bound(totalDebt_, 0, 1000e9);
        incurDebt.setTotalDebt(totalDebt);

        assertEq(submoduleIncurDebtSupply.getProtocolOwnedTreasuryOhm(), 0);
    }

    // =========  getProtocolOwnedLiquidityReserves ========= //

    function test_getProtocolOwnedLiquidityReserves_fuzz(uint256 totalDebt_) public {
        uint256 totalDebt = bound(totalDebt_, 0, 1000e9);
        incurDebt.setTotalDebt(totalDebt);

        SPPLYv1.Reserves[] memory reserves = submoduleIncurDebtSupply
            .getProtocolOwnedLiquidityReserves();

        // No POL
        assertEq(reserves.length, 1);
        assertEq(reserves[0].source, address(incurDebt));
        assertEq(reserves[0].tokens.length, 0);
        assertEq(reserves[0].balances.length, 0);
    }

    // =========  setIncurDebt ========= //

    function test_setIncurDebt_notParent_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleIncurDebtSupply.setIncurDebt(address(newLocations[0]));
    }

    function test_setIncurDebt_notParent_writer_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writer)
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        submoduleIncurDebtSupply.setIncurDebt(address(newLocations[0]));
        vm.stopPrank();
    }

    function test_setIncurDebt_addressZero_reverts() public {
        bytes memory err = abi.encodeWithSignature("IncurDebtSupply_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(address(moduleSupply));
        submoduleIncurDebtSupply.setIncurDebt(address(0));
        vm.stopPrank();
    }

    function test_setIncurDebt() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit IncurDebtUpdated(address(newLocations[0]));

        // New IncurDebtSupply
        submoduleIncurDebtSupply = new IncurDebtSupply(moduleSupply, address(newLocations[0]));

        assertEq(submoduleIncurDebtSupply.getIncurDebt(), address(newLocations[0]));
    }
}
