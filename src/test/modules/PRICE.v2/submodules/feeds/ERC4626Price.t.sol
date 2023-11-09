// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {FullMath} from "libraries/FullMath.sol";

import {ERC4626Price} from "modules/PRICE/submodules/feeds/ERC4626Price.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";

contract ERC4626Test is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for ERC4626Price;

    MockPrice internal mockPrice;
    ERC4626Price internal submodule;

    MockERC20 internal dai;
    uint8 internal constant DAI_DECIMALS = 18;

    MockERC4626 internal sDai;
    uint8 internal constant SDAI_DECIMALS = 18;

    uint8 internal constant MAX_DECIMALS = 38;

    uint8 internal constant PRICE_DECIMALS = 18;

    address internal alice = address(0xABCD);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Set up the submodule
        {
            Kernel kernel = new Kernel();
            mockPrice = new MockPrice(kernel, PRICE_DECIMALS, uint32(8 hours));
            mockPrice.setPriceDecimals(PRICE_DECIMALS);
            mockPrice.setTimestamp(uint48(block.timestamp));
            submodule = new ERC4626Price(mockPrice);
        }

        // Set up tokens
        {
            dai = new MockERC20("DAI", "DAI", DAI_DECIMALS);
            sDai = new MockERC4626(dai, "Savings DAI", "sDAI");
        }

        // Deposit into the ERC4626 asset (so that there is a conversion rate)
        {
            dai.mint(alice, 1e18);

            vm.prank(alice);
            dai.approve(address(sDai), 1e18);

            vm.prank(alice);
            sDai.deposit(1e18, alice);
        }

        // Simulate yield being deposited in the vault
        {
            mintDaiYield(1e18); // 2e18 DAI in the vault for 1e18 shares
        }

        // Mock prices from PRICE
        {
            mockAssetPrice(address(dai), 1e18);
        }
    }

    // =========  HELPER METHODS ========= //

    function mockAssetPrice(address asset_, uint256 price_) internal {
        mockPrice.setPrice(asset_, price_);
    }

    /// @notice         Mints DAI into the sDai vault, which will update the conversion rate
    /// @param amount_  The amount of DAI to mint (in DAI decimals)
    function mintDaiYield(uint256 amount_) internal {
        dai.mint(address(sDai), amount_);
    }

    // ========= GET UNDERLYING PRICE ========= //

    // [X] getPriceFromUnderlying
    //  [X] output decimals within bounds
    //  [X] output decimals out of bounds
    //  [X] underlying asset decimals mismatch
    //  [X] asset decimals within bounds
    //  [X] asset decimals out of bounds
    //  [X] underlying asset not set
    //  [X] underlying asset price not set
    //  [X] asset price is calculated correctly

    function test_outputDecimals_fuzz(uint8 outputDecimals_) public {
        uint8 outputDecimals = uint8(bound(outputDecimals_, 0, MAX_DECIMALS));

        // Update PRICE
        mockPrice.setPriceDecimals(outputDecimals);
        mockAssetPrice(address(dai), 10 ** outputDecimals); // DAI = 1

        // Determine the share - asset conversion rate
        uint256 sDaiRate = sDai.convertToAssets(10 ** SDAI_DECIMALS);

        // Call the function
        uint256 assetPrice = submodule.getPriceFromUnderlying(address(sDai), outputDecimals, "");

        uint256 expectedPrice = sDaiRate.mulDiv(10 ** outputDecimals, 10 ** PRICE_DECIMALS);

        assertEq(assetPrice, expectedPrice);
    }

    function test_outputDecimals_maximum_reverts(uint8 outputDecimals_) public {
        uint8 outputDecimals = uint8(bound(outputDecimals_, MAX_DECIMALS + 1, 60));

        // Update PRICE
        mockPrice.setPriceDecimals(outputDecimals);
        mockAssetPrice(address(dai), 10 ** outputDecimals); // DAI = 1

        // Call the function
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Price.ERC4626_OutputDecimalsOutOfBounds.selector,
                outputDecimals,
                MAX_DECIMALS
            )
        );
        submodule.getPriceFromUnderlying(address(sDai), outputDecimals, "");
    }

    function test_assetDecimalsDifferent_reverts() public {
        // Mock the asset having a different number of decimals to the underlying
        vm.mockCall(
            address(sDai),
            abi.encodeWithSignature("decimals()"),
            abi.encode(DAI_DECIMALS + 1)
        );

        // Call the function
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Price.ERC4626_AssetDecimalsMismatch.selector,
                DAI_DECIMALS + 1,
                DAI_DECIMALS
            )
        );
        submodule.getPriceFromUnderlying(address(sDai), PRICE_DECIMALS, "");
    }

    function test_assetDecimals_fuzz(uint8 assetDecimals_) public {
        uint8 assetDecimals = uint8(bound(assetDecimals_, 0, MAX_DECIMALS));

        // Create new set of tokens
        MockERC20 newUnderlying = new MockERC20("New Token", "NEW", assetDecimals);
        MockERC4626 newAsset = new MockERC4626(newUnderlying, "Savings New Token", "sNEW");
        mockAssetPrice(address(newUnderlying), 10 ** assetDecimals); // NEW = 1

        // Issue shares
        newUnderlying.mint(alice, 10 ** assetDecimals);
        vm.prank(alice);
        newUnderlying.approve(address(newAsset), 10 ** assetDecimals);
        vm.prank(alice);
        newAsset.mint(10 ** assetDecimals, alice);

        // Determine the share - asset conversion rate
        uint256 assetRate = newAsset.convertToAssets(10 ** assetDecimals);

        // Call the function
        uint256 assetPrice = submodule.getPriceFromUnderlying(
            address(newAsset),
            PRICE_DECIMALS,
            ""
        );

        uint256 expectedPrice = assetRate.mulDiv(10 ** PRICE_DECIMALS, 10 ** PRICE_DECIMALS);

        assertEq(assetPrice, expectedPrice);
    }

    function test_assetDecimals_maximum_reverts(uint8 assetDecimals_) public {
        uint8 assetDecimals = uint8(bound(assetDecimals_, MAX_DECIMALS + 1, 60));

        // Create new set of tokens
        MockERC20 newUnderlying = new MockERC20("New Token", "NEW", assetDecimals);
        MockERC4626 newAsset = new MockERC4626(newUnderlying, "Savings New Token", "sNEW");
        mockAssetPrice(address(newUnderlying), 10 ** assetDecimals); // NEW = 1

        // Issue shares
        newUnderlying.mint(alice, 10 ** assetDecimals);
        vm.prank(alice);
        newUnderlying.approve(address(newAsset), 10 ** assetDecimals);
        vm.prank(alice);
        newAsset.mint(10 ** assetDecimals, alice);

        // Call the function
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Price.ERC4626_AssetDecimalsOutOfBounds.selector,
                assetDecimals,
                MAX_DECIMALS
            )
        );
        submodule.getPriceFromUnderlying(address(newAsset), PRICE_DECIMALS, "");
    }

    function test_underlyingAssetUnset_reverts() public {
        // Mock the underlying asset not being set
        vm.mockCall(address(sDai), abi.encodeWithSignature("asset()"), abi.encode(0x0));

        // Call the function
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626Price.ERC4626_UnderlyingNotSet.selector, address(sDai))
        );
        submodule.getPriceFromUnderlying(address(sDai), PRICE_DECIMALS, "");
    }

    function test_underlyingAssetPriceUnset_reverts() public {
        // No price set for DAI
        mockAssetPrice(address(dai), 0);

        // Call the function
        vm.expectRevert(abi.encodeWithSelector(PRICEv2.PRICE_PriceZero.selector, address(dai)));
        submodule.getPriceFromUnderlying(address(sDai), PRICE_DECIMALS, "");
    }

    function test_correctPrice_fuzz(uint256 daiMintAmount_) public {
        uint256 daiMintAmount = bound(daiMintAmount_, 1e9, 10e18);

        // Mint DAI and sDAI
        dai.mint(alice, daiMintAmount);
        vm.prank(alice);
        dai.approve(address(sDai), daiMintAmount);
        vm.prank(alice);
        sDai.deposit(daiMintAmount, alice);

        // Determine the share - asset conversion rate
        uint256 sDaiRate = sDai.convertToAssets(10 ** SDAI_DECIMALS);

        // Call the function
        uint256 assetPrice = submodule.getPriceFromUnderlying(address(sDai), PRICE_DECIMALS, "");

        uint256 expectedPrice = sDaiRate.mulDiv(10 ** PRICE_DECIMALS, 10 ** PRICE_DECIMALS);

        assertEq(assetPrice, expectedPrice);
    }
}
