// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {OlympusConvertibleDepository} from "src/modules/CDEPO/OlympusConvertibleDepository.sol";

abstract contract CDEPOTest is Test {
    using ModuleTestFixtureGenerator for OlympusConvertibleDepository;

    Kernel public kernel;
    OlympusConvertibleDepository public CDEPO;
    MockERC20 public reserveToken;
    MockERC4626 public vault;
    address public godmode;

    uint48 public constant INITIAL_BLOCK = 100000000;

    function setUp() public {
        vm.warp(INITIAL_BLOCK);

        reserveToken = new MockERC20("Reserve Token", "RST", 18);
        vault = new MockERC4626(reserveToken, "sReserve Token", "sRST");

        // Mint reserve tokens to the vault without depositing, so that the conversion is not 1
        reserveToken.mint(address(vault), 10e18);

        kernel = new Kernel();
        CDEPO = new OlympusConvertibleDepository(address(kernel), address(vault));

        // Generate fixtures
        godmode = CDEPO.generateGodmodeFixture(type(OlympusConvertibleDepository).name);

        // Install modules and policies on Kernel
        kernel.executeAction(Actions.InstallModule, address(CDEPO));
        kernel.executeAction(Actions.ActivatePolicy, godmode);
    }

    // ========== ASSERTIONS ========== //

    // ========== MODIFIERS ========== //

    function _mintReserveToken(address to_, uint256 amount_) internal {
        reserveToken.mint(to_, amount_);
    }

    modifier givenAddressHasReserveToken(address to_, uint256 amount_) {
        _mintReserveToken(to_, amount_);
        _;
    }
}
