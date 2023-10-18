// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";
import {FullMath} from "libraries/FullMath.sol";

import {ERC4626Price} from "modules/PRICE/submodules/feeds/ERC4626Price.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
// import {ERC4626} from "solmate/mixins/ERC4626.sol";

contract ERC4626Test is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for ERC4626Price;

    MockPrice internal mockPrice;
    ERC4626Price internal submodule;

    address internal constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    uint256 internal constant SDAI_CONVERT_TO_ASSETS = 1039077574409367874; // 1e18 sDAI = 1039077574409367874 DAI

    MockERC4626 internal sDai;

    uint8 internal constant MIN_DECIMALS = 6;
    uint8 internal constant MAX_DECIMALS = 50;

    uint8 internal constant PRICE_DECIMALS = 18;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Set up the submodule
        {
            Kernel kernel = new Kernel();
            mockPrice = new MockPrice(kernel, uint8(18), uint32(8 hours));
            mockPrice.setPriceDecimals(PRICE_DECIMALS);
            mockPrice.setTimestamp(uint48(block.timestamp));
            submodule = new ERC4626Price(mockPrice);
        }

        // Set up the ERC4626 asset
        {
            sDai = new MockERC4626(ERC20(DAI_ADDRESS), "Savings DAI", "sDAI");
        }

        // Mock prices from PRICE
        {
            mockAssetPrice(DAI_ADDRESS, 1e18);
        }

        // Mock ERC20 decimals
        {
            mockERC20Decimals(DAI_ADDRESS, 18);
            mockERC20Decimals(address(sDai), 18);
        }
    }

    // =========  HELPER METHODS ========= //

    function mockERC20Decimals(address asset_, uint8 decimals_) internal {
        vm.mockCall(asset_, abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
    }

    function mockAssetPrice(address asset_, uint256 price_) internal {
        mockPrice.setPrice(asset_, price_);
    }

    // ========= GET UNDERLYING PRICE ========= //

    // TODO
    // [ ] getPriceFromUnderlying
    //  [ ] output decimals within bounds
    //  [ ] output decimals out of bounds
    //  [ ] underlying asset decimals within bounds
    //  [ ] underlying asset decimals out of bounds
    //  [ ] asset decimals within bounds
    //  [ ] asset decimals out of bounds
    //  [ ] underlying asset not set
    //  [ ] underlying asset price not set
    //  [ ] asset price is calculated correctly

}