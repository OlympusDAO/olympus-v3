// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {FullMath} from "libraries/FullMath.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
// import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";
import "src/modules/PRICE/OlympusPrice.v2.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockUniV3Pair} from "test/mocks/MockUniV3Pair.sol";

import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";

import {BunniPrice} from "src/modules/PRICE/submodules/feeds/BunniPrice.sol";
import {BunniHub} from "src/external/bunni/BunniHub.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {BunniToken} from "src/external/bunni/BunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";
import {IBunniHub} from "src/external/bunni/interfaces/IBunniHub.sol";

import {UniswapV3Factory} from "test/lib/UniswapV3/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract BunniPriceTest is Test {
    using FullMath for uint256;
    // using ModuleTestFixtureGenerator for BunniPrice;

    Kernel internal kernel;
    MockPrice internal mockPrice;
    MockUniV3Pair internal uniswapPool;

    BunniPrice internal submoduleBunniPrice;

    MockERC20 internal ohmToken;
    MockERC20 internal usdcToken;
    address internal OHM;
    address internal USDC;
    uint8 internal constant OHM_DECIMALS = 9;
    uint8 internal constant USDC_DECIMALS = 6;

    BunniHub internal bunniHub;
    BunniLens internal bunniLens;
    BunniToken internal poolToken;
    BunniKey internal poolTokenKey;
    address internal bunniLensAddress;
    address internal poolTokenAddress;

    address internal policy;

    UserFactory public userFactory;

    uint128 internal constant POOL_LIQUIDITY = 349484367626548;
    uint160 internal constant POOL_SQRTPRICEX96 = 8467282393668682240084879204;

    uint8 internal constant PRICE_DECIMALS = 18;

    uint256 internal constant USDC_PRICE = 1 * 10 ** PRICE_DECIMALS;
    uint256 internal constant OHM_PRICE = 11 * 10 ** PRICE_DECIMALS;

    // Derived from the POOL_LIQUIDITY and POOL_SQRTPRICEX96 constants
    uint256 internal constant OHM_RESERVES = 3270117020688384;
    uint256 internal constant USDC_RESERVES = 37350138371995;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Tokens
        {
            ohmToken = new MockERC20("OHM", "OHM", OHM_DECIMALS);
            usdcToken = new MockERC20("USDC", "USDC", USDC_DECIMALS);

            OHM = address(ohmToken);
            USDC = address(usdcToken);
        }

        // Set up the submodule
        {
            kernel = new Kernel();
            mockPrice = new MockPrice(kernel, PRICE_DECIMALS, uint32(8 hours));
            mockPrice.setTimestamp(uint48(block.timestamp));

            submoduleBunniPrice = new BunniPrice(mockPrice);
        }

        // Locations
        {
            userFactory = new UserFactory();
            address[] memory users = userFactory.create(1);
            policy = users[0];
        }

        // Deploy BunniHub/BunniLens
        {
            UniswapV3Factory uniswapFactory = new UniswapV3Factory();
            bunniHub = new BunniHub(
                uniswapFactory,
                policy,
                0 // No protocol fee
            );
            bunniLens = new BunniLens(bunniHub);
            bunniLensAddress = address(bunniLens);
        }

        // Set up the mock UniV3 pool
        {
            (
                MockUniV3Pair uniswapPool_,
                BunniKey memory poolTokenKey_,
                BunniToken poolToken_
            ) = _setUpPool(OHM, USDC, POOL_LIQUIDITY, POOL_SQRTPRICEX96);

            uniswapPool = uniswapPool_;
            poolTokenKey = poolTokenKey_;
            poolToken = poolToken_;
            poolTokenAddress = address(poolToken);
        }

        // Mock prices from PRICE
        {
            mockAssetPrice(USDC, USDC_PRICE);
            mockAssetPrice(OHM, OHM_PRICE);
        }
    }

    // =========  HELPER METHODS ========= //

    function _setUpPool(
        address token0_,
        address token1_,
        uint128 liquidity_,
        uint160 sqrtPriceX96_
    ) internal returns (MockUniV3Pair, BunniKey memory, BunniToken) {
        MockUniV3Pair pool = new MockUniV3Pair();
        pool.setToken0(token0_);
        pool.setToken1(token1_);
        pool.setLiquidity(liquidity_);
        pool.setSqrtPrice(sqrtPriceX96_);

        BunniKey memory key = BunniKey({
            pool: IUniswapV3Pool(address(pool)),
            tickLower: -887272,
            tickUpper: 887272
        });

        BunniToken token = new BunniToken(bunniHub, key);

        return (pool, key, token);
    }

    function mockAssetPrice(address asset_, uint256 price_) internal {
        mockPrice.setPrice(asset_, price_);
    }

    function mockERC20Decimals(address asset_, uint8 decimals_) internal {
        vm.mockCall(asset_, abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
    }

    function _expectRevert_invalidBunniToken(address token_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniPrice.BunniPrice_Params_InvalidBunniToken.selector,
            token_
        );
        vm.expectRevert(err);
    }

    function _expectRevert_invalidBunniLens(address lens_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniPrice.BunniPrice_Params_InvalidBunniLens.selector,
            lens_
        );
        vm.expectRevert(err);
    }

    // ========= TESTS ========= //

    // [X] Submodule
    //  [X] Version
    //  [X] Subkeycode

    function test_submodule_version() public {
        uint8 major;
        uint8 minor;
        (major, minor) = submoduleBunniPrice.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_submodule_parent() public {
        assertEq(fromKeycode(submoduleBunniPrice.PARENT()), "PRICE");
    }

    function test_submodule_subkeycode() public {
        assertEq(fromSubKeycode(submoduleBunniPrice.SUBKEYCODE()), "PRICE.BNI");
    }

    // [X] Constructor
    //  [X] Incorrect parent

    function test_submodule_parent_notModule_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        // There's no error message, so just check that a revert happens when attempting to call the module
        vm.expectRevert();

        new BunniPrice(Module(newLocations[0]));
    }

    function test_submodule_parent_notPrice_reverts() public {
        // Create a non-PRICE module
        OlympusMinter MINTR = new OlympusMinter(kernel, OHM);

        bytes memory err = abi.encodeWithSignature("Submodule_InvalidParent()");
        vm.expectRevert(err);

        new BunniPrice(MINTR);
    }

    // [X] getBunniTokenPrice
    //  [X] Reverts if params.bunniLens is zero
    //  [X] Reverts if params.bunniLens is not a valid BunniLens
    //  [X] Reverts if bunniToken is zero
    //  [X] Reverts if bunniToken is not a valid BunniToken
    //  [X] Reverts if bunniToken and bunniLens do not have the same BunniHub
    //  [X] Reverts if any of the reserve assets are not defined as assets in PRICE
    //  [X] Correctly calculates balances for different decimal scale
    //  [X] Correctly handles different output decimals

    function test_getBunniTokenPrice_zeroBunniLensReverts() public {
        bytes memory params = abi.encode(BunniPrice.BunniParams({bunniLens: address(0)}));

        _expectRevert_invalidBunniLens(address(0));

        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_invalidBunniLensReverts() public {
        bytes memory params = abi.encode(BunniPrice.BunniParams({bunniLens: address(bunniHub)}));

        _expectRevert_invalidBunniLens(address(bunniHub));

        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_zeroBunniTokenReverts() public {
        bytes memory params = abi.encode(BunniPrice.BunniParams({bunniLens: bunniLensAddress}));

        _expectRevert_invalidBunniToken(address(0));

        submoduleBunniPrice.getBunniTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_invalidBunniTokenReverts() public {
        bytes memory params = abi.encode(BunniPrice.BunniParams({bunniLens: bunniLensAddress}));

        _expectRevert_invalidBunniToken(address(bunniHub));

        submoduleBunniPrice.getBunniTokenPrice(address(bunniHub), PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_hubMismatchReverts() public {
        // Deploy a new hub
        UniswapV3Factory uniswapFactory = new UniswapV3Factory();
        BunniHub newBunniHub = new BunniHub(
            uniswapFactory,
            policy,
            0 // No protocol fee
        );

        // Deploy a new lens
        BunniLens newBunniLens = new BunniLens(newBunniHub);

        bytes memory err = abi.encodeWithSelector(
            BunniPrice.BunniPrice_Params_HubMismatch.selector,
            address(bunniHub),
            address(newBunniHub)
        );
        vm.expectRevert(err);

        bytes memory params = abi.encode(
            BunniPrice.BunniParams({bunniLens: address(newBunniLens)})
        );

        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_zeroPriceReverts(uint256 tokenIndex_) public {
        uint8 tokenIndex = uint8(bound(tokenIndex_, 0, 1));

        // Mock the price of the token to be zero
        address zeroPriceAddress = tokenIndex == 0 ? OHM : USDC;
        mockAssetPrice(zeroPriceAddress, 0);

        // Expect a revert
        bytes memory err = abi.encodeWithSelector(
            PRICEv2.PRICE_PriceZero.selector,
            zeroPriceAddress
        );
        vm.expectRevert(err);

        bytes memory params = abi.encode(BunniPrice.BunniParams({bunniLens: bunniLensAddress}));

        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice() public {
        // Calculate the expected price
        uint256 ohmReserve = OHM_RESERVES.mulDiv(10 ** PRICE_DECIMALS, 10 ** OHM_DECIMALS);
        uint256 usdcReserve = USDC_RESERVES.mulDiv(10 ** PRICE_DECIMALS, 10 ** USDC_DECIMALS);
        uint256 expectedPrice = ohmReserve.mulDiv(OHM_PRICE, 1e18) +
            usdcReserve.mulDiv(USDC_PRICE, 1e18);

        // Call
        bytes memory params = abi.encode(BunniPrice.BunniParams({bunniLens: bunniLensAddress}));
        uint256 price = submoduleBunniPrice.getBunniTokenPrice(
            poolTokenAddress,
            PRICE_DECIMALS,
            params
        );

        // Check values
        assertTrue(price > 0, "should be non-zero");
        assertEq(price, expectedPrice);
    }

    function test_getBunniTokenPrice_outputDecimalsFuzz(uint256 outputDecimals_) public {
        uint8 outputDecimals = uint8(bound(outputDecimals_, 6, 30));

        uint256 ohmPrice = 11 * 10 ** outputDecimals;
        uint256 usdcPrice = 1 * 10 ** outputDecimals;

        // Mock the PRICE decimals
        mockPrice.setPriceDecimals(outputDecimals);
        mockAssetPrice(OHM, ohmPrice);
        mockAssetPrice(USDC, usdcPrice);

        // Calculate the expected price
        uint256 ohmReserve = OHM_RESERVES.mulDiv(10 ** outputDecimals, 10 ** OHM_DECIMALS);
        uint256 usdcReserve = USDC_RESERVES.mulDiv(10 ** outputDecimals, 10 ** USDC_DECIMALS);
        uint256 expectedPrice = ohmReserve.mulDiv(ohmPrice, 10 ** outputDecimals) +
            usdcReserve.mulDiv(usdcPrice, 10 ** outputDecimals);

        // Call
        bytes memory params = abi.encode(BunniPrice.BunniParams({bunniLens: bunniLensAddress}));
        uint256 price = submoduleBunniPrice.getBunniTokenPrice(
            poolTokenAddress,
            outputDecimals,
            params
        );

        // Check values
        assertTrue(price > 0, "should be non-zero");
        assertEq(price, expectedPrice);
    }
}
