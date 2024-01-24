// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockSohm, MockGohm, MockGohmWithSohmDep} from "test/mocks/OlympusMocks.sol";

import "src/modules/SPPLY/OlympusSupply.sol";
import {BrickedSupply} from "src/modules/SPPLY/submodules/BrickedSupply.sol";

contract BrickedSupplyTest is Test {
    using ModuleTestFixtureGenerator for OlympusSupply;

    MockERC20 internal ohm;
    MockSohm internal sohm;
    MockGohm internal gOhm;
    MockGohmWithSohmDep internal gOhmWithSohmDep;

    Kernel internal kernel;

    OlympusSupply internal spply;

    BrickedSupply internal submoduleBrickedSupply;

    address internal godmode;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals

    function setUp() public {
        // Create tokens
        {
            ohm = new MockERC20("OHM", "OHM", 9);
            sohm = new MockSohm(GOHM_INDEX);
            gOhm = new MockGohm(GOHM_INDEX);
            gOhmWithSohmDep = new MockGohmWithSohmDep(address(sohm));
        }

        // Create kernel and modules
        {
            kernel = new Kernel();

            address[2] memory tokens = [address(ohm), address(gOhm)];
            spply = new OlympusSupply(kernel, tokens, 0);
        }

        // Create submodule
        {
            address[] memory ohmDenominatedTokens = new address[](2);
            address[] memory gohmDenominatedTokens = new address[](1);

            ohmDenominatedTokens[0] = address(ohm);
            ohmDenominatedTokens[1] = address(sohm);

            gohmDenominatedTokens[0] = address(gOhm);

            submoduleBrickedSupply = new BrickedSupply(
                spply,
                address(ohm),
                ohmDenominatedTokens,
                gohmDenominatedTokens
            );
        }

        // Create godmode
        {
            godmode = spply.generateGodmodeFixture(type(OlympusSupply).name);
        }

        // Install modules and submodules
        {
            kernel.executeAction(Actions.InstallModule, address(spply));
            kernel.executeAction(Actions.ActivatePolicy, godmode);

            vm.prank(godmode);
            spply.installSubmodule(submoduleBrickedSupply);
        }

        // Add base bricked supply
        {
            sohm.mint(address(sohm), 4106e9);
        }
    }

    // ========= Module Information ========= //

    // [X]  VERSION
    // [X]  PARENT
    // [X]  SUBKEYCODE

    function test_VERSION() public {
        (uint8 major, uint8 minor) = submoduleBrickedSupply.VERSION();

        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_PARENT() public {
        assertEq(fromKeycode(submoduleBrickedSupply.PARENT()), "SPPLY");
    }

    function test_SUBKEYCODE() public {
        assertEq(fromSubKeycode(submoduleBrickedSupply.SUBKEYCODE()), "SPPLY.BRICKED");
    }

    // ========= getProtocolOwnedTreasuryOhm ========= //

    // [X]   Tracks bricked supply in base sOHM case
    // [X]   Tracks bricked suppply in the case of gOHM's reliance on sOHM index
    // [X]   Tracks bricked supply in multiple OHM denominated tokens case
    // [X]   Tracks bricked supply in multiple OHM denominated tokens + gOHM denominated token case

    function test_getProtocolOwnedTreasuryOhm_base() public {
        assertEq(submoduleBrickedSupply.getProtocolOwnedTreasuryOhm(), 4106e9);
    }

    function test_getProtocolOwnedTreasuryOhm_gohmSohmReliannce() public {
        // Mint gOHM to gOHM
        gOhmWithSohmDep.mint(address(gOhmWithSohmDep), 100e18);

        // Set gOHM as only token to check
        address[] memory gohmDenominatedTokens = new address[](1);
        gohmDenominatedTokens[0] = address(gOhmWithSohmDep);

        vm.startPrank(address(spply));
        submoduleBrickedSupply.setOhmDenominatedTokens(new address[](0));
        submoduleBrickedSupply.setGohmDenominatedTokens(gohmDenominatedTokens);
        vm.stopPrank();

        // Check bricked supply
        uint256 gohmAsOhm = gOhmWithSohmDep.balanceFrom(100e18);
        assertEq(submoduleBrickedSupply.getProtocolOwnedTreasuryOhm(), gohmAsOhm);
    }

    function test_getProtocolOwnedTreasuryOhm_ohmDenominatedTokens() public {
        ohm.mint(address(ohm), 1000e9);

        assertEq(submoduleBrickedSupply.getProtocolOwnedTreasuryOhm(), 5106e9);
    }

    function test_getProtocolOwnedTreasuryOhm_gohmDenominatedTokens() public {
        ohm.mint(address(ohm), 1000e9);
        gOhm.mint(address(gOhm), 100e18);

        uint256 gohmAsOhm = gOhm.balanceFrom(100e18);
        uint256 expectedOffset = 5106e9 + gohmAsOhm;

        assertEq(submoduleBrickedSupply.getProtocolOwnedTreasuryOhm(), expectedOffset);
    }

    // ========= getProtocolOwnedBorrowableOhm ========= //

    // [X]   Should always be 0

    function test_getProtocolOwnedBorrowableOhm() public {
        assertEq(submoduleBrickedSupply.getProtocolOwnedBorrowableOhm(), 0);
    }

    // ========= getProtocolOwnedLiquidityOhm ========= //

    // [X]   Should always be 0

    function test_getProtocolOwnedLiquidityOhm() public {
        assertEq(submoduleBrickedSupply.getProtocolOwnedLiquidityOhm(), 0);
    }

    // ========= setOhmDenominatedTokens ========= //

    // [X]   Should only be callable by parent
    // [X]   Should update ohmDenominatedTokens

    function test_setOhmDenominatedTokens_notParent(address caller_) public {
        vm.assume(caller_ != address(spply));

        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(caller_)
        );
        vm.expectRevert(err);

        vm.prank(caller_);
        submoduleBrickedSupply.setOhmDenominatedTokens(new address[](0));
    }

    function test_setOhmDenominatedTokens(address token0_) public {
        vm.assume(token0_ != address(0) && token0_ != address(ohm) && token0_ != address(sohm));

        assertEq(submoduleBrickedSupply.ohmDenominatedTokens(0), address(ohm));
        assertEq(submoduleBrickedSupply.ohmDenominatedTokens(1), address(sohm));

        address[] memory ohmDenominatedTokens = new address[](1);
        ohmDenominatedTokens[0] = token0_;

        vm.prank(address(spply));
        submoduleBrickedSupply.setOhmDenominatedTokens(ohmDenominatedTokens);

        assertEq(submoduleBrickedSupply.ohmDenominatedTokens(0), token0_);
    }

    function test_setOhmDenominatedTokens_zeroAddress(uint8 index_) public {
        uint8 zeroAddressIndex = uint8(bound(index_, 0, 1));

        address[] memory ohmDenominatedTokens = new address[](2);
        ohmDenominatedTokens[0] = zeroAddressIndex == 0 ? address(0) : address(ohm);
        ohmDenominatedTokens[1] = zeroAddressIndex == 1 ? address(0) : address(ohm);

        // Expect the ZeroToken error
        bytes memory err = abi.encodeWithSelector(
            BrickedSupply.BrickedSupply_ZeroToken.selector,
            address(0)
        );
        vm.expectRevert(err);

        vm.prank(address(spply));
        submoduleBrickedSupply.setOhmDenominatedTokens(ohmDenominatedTokens);
    }

    function test_setOhmDenominatedTokens_exists() public {
        address[] memory ohmDenominatedTokens = new address[](2);
        ohmDenominatedTokens[0] = address(ohm);
        ohmDenominatedTokens[1] = address(gOhm); // Already exists in gOhmDenominatedTokens

        // Expect the TokenExists error
        bytes memory err = abi.encodeWithSelector(
            BrickedSupply.BrickedSupply_TokenExists.selector,
            address(gOhm)
        );
        vm.expectRevert(err);

        vm.prank(address(spply));
        submoduleBrickedSupply.setOhmDenominatedTokens(ohmDenominatedTokens);
    }

    // ========= setGohmDenominatedTokens ========= //

    // [X]   Should only be callable by parent
    // [X]   Should update gohmDenominatedTokens

    function test_setGohmDenominatedTokens_notParent(address caller_) public {
        vm.assume(caller_ != address(spply));

        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(caller_)
        );
        vm.expectRevert(err);

        vm.prank(caller_);
        submoduleBrickedSupply.setGohmDenominatedTokens(new address[](0));
    }

    function test_setGohmDenominatedTokens(address token0_) public {
        vm.assume(token0_ != address(0) && token0_ != address(gOhm));

        assertEq(submoduleBrickedSupply.gohmDenominatedTokens(0), address(gOhm));

        address[] memory gohmDenominatedTokens = new address[](1);
        gohmDenominatedTokens[0] = token0_;

        vm.prank(address(spply));
        submoduleBrickedSupply.setGohmDenominatedTokens(gohmDenominatedTokens);

        assertEq(submoduleBrickedSupply.gohmDenominatedTokens(0), token0_);
    }

    function test_setGohmDenominatedTokens_zeroAddress(uint8 index_) public {
        uint8 zeroAddressIndex = uint8(bound(index_, 0, 1));

        address[] memory gohmDenominatedTokens = new address[](2);
        gohmDenominatedTokens[0] = zeroAddressIndex == 0 ? address(0) : address(gOhm);
        gohmDenominatedTokens[1] = zeroAddressIndex == 1 ? address(0) : address(gOhm);

        // Expect the ZeroToken error
        bytes memory err = abi.encodeWithSelector(
            BrickedSupply.BrickedSupply_ZeroToken.selector,
            address(0)
        );
        vm.expectRevert(err);

        vm.prank(address(spply));
        submoduleBrickedSupply.setGohmDenominatedTokens(gohmDenominatedTokens);
    }

    function test_setGohmDenominatedTokens_exists() public {
        address[] memory gohmDenominatedTokens = new address[](2);
        gohmDenominatedTokens[0] = address(ohm); // Already exists in ohmDenominatedTokens
        gohmDenominatedTokens[1] = address(gOhm);

        // Expect the TokenExists error
        bytes memory err = abi.encodeWithSelector(
            BrickedSupply.BrickedSupply_TokenExists.selector,
            address(ohm)
        );
        vm.expectRevert(err);

        vm.prank(address(spply));
        submoduleBrickedSupply.setGohmDenominatedTokens(gohmDenominatedTokens);
    }
}
