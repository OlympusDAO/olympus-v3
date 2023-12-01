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

// Libraries
import {FullMath} from "libraries/FullMath.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

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

    // OHM-USDC Uni V3 pool, based on: 0x893f503fac2ee1e5b78665db23f9c94017aae97d
    // token0: OHM, token1: USDC
    uint128 internal constant POOL_LIQUIDITY = 349484367626548;
    // Current tick: -44579
    uint160 internal constant POOL_SQRTPRICEX96 = 8529245188595251053303005012; // From OHM-USDC, 1 OHM = 11.5897 USDC
    // NOTE: these numbers are fudged to match the current tick and default observation window from BunniManager
    int56 internal constant OHM_USDC_TICK_CUMULATIVE_0 = -2463052984970;
    int56 internal constant OHM_USDC_TICK_CUMULATIVE_1 = -2463079732370;

    uint8 internal constant PRICE_DECIMALS = 18;

    uint256 internal constant USDC_PRICE = 1 * 10 ** PRICE_DECIMALS;
    uint256 internal constant OHM_PRICE = 11 * 10 ** PRICE_DECIMALS;

    // DO NOT change these salt values, as they are used to ensure that the addresses are deterministic, and the SQRTPRICEX96 values depend on the ordering
    bytes32 private constant OHM_SALT =
        0x0000000000000000000000000000000000000000000000000000000000000001;
    bytes32 private constant USDC_SALT =
        0x0000000000000000000000000000000000000000000000000000000000000002;

    uint16 internal constant TWAP_MAX_DEVIATION_BPS = 100; // 1%
    uint32 internal constant TWAP_OBSERVATION_WINDOW = 600;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Tokens
        {
            ohmToken = new MockERC20{salt: OHM_SALT}("OHM", "OHM", OHM_DECIMALS);
            usdcToken = new MockERC20{salt: USDC_SALT}("USDC", "USDC", USDC_DECIMALS);

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
            ) = _setUpPool(
                    OHM,
                    USDC,
                    POOL_LIQUIDITY,
                    POOL_SQRTPRICEX96,
                    OHM_USDC_TICK_CUMULATIVE_0,
                    OHM_USDC_TICK_CUMULATIVE_1
                );

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
        uint160 sqrtPriceX96_,
        int56 sqrtPriceX96Cumulative0_,
        int56 sqrtPriceX96Cumulative1_
    ) internal returns (MockUniV3Pair, BunniKey memory, BunniToken) {
        MockUniV3Pair pool = new MockUniV3Pair();
        pool.setToken0(token0_);
        pool.setToken1(token1_);
        pool.setLiquidity(liquidity_);
        pool.setSqrtPrice(sqrtPriceX96_);

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = sqrtPriceX96Cumulative0_;
        tickCumulatives[1] = sqrtPriceX96Cumulative1_;
        pool.setTickCumulatives(tickCumulatives);

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

    function _getReserves(
        BunniKey memory key_,
        BunniLens lens_
    ) internal view returns (uint256, uint256) {
        (uint112 reserve0, uint112 reserve1) = lens_.getReserves(key_);
        return (reserve0, reserve1);
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
    //  [X] Reverts if the reserves deviate from the TWAP
    //  [X] Correctly calculates balances for different decimal scale
    //  [X] Correctly handles different output decimals

    function test_getBunniTokenPrice_zeroBunniLensReverts() public {
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: address(0),
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );

        _expectRevert_invalidBunniLens(address(0));

        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_invalidBunniLensReverts() public {
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: address(bunniHub),
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );

        _expectRevert_invalidBunniLens(address(bunniHub));

        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_zeroBunniTokenReverts() public {
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );

        _expectRevert_invalidBunniToken(address(0));

        submoduleBunniPrice.getBunniTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_invalidBunniTokenReverts() public {
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );

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
            BunniPrice.BunniParams({
                bunniLens: address(newBunniLens),
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
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

        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );

        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice() public {
        // Calculate the expected price
        (uint256 ohmReserve_, uint256 usdcReserve_) = _getReserves(poolTokenKey, bunniLens);
        uint256 ohmReserve = ohmReserve_.mulDiv(10 ** PRICE_DECIMALS, 10 ** OHM_DECIMALS);
        uint256 usdcReserve = usdcReserve_.mulDiv(10 ** PRICE_DECIMALS, 10 ** USDC_DECIMALS);
        uint256 expectedPrice = ohmReserve.mulDiv(OHM_PRICE, 1e18) +
            usdcReserve.mulDiv(USDC_PRICE, 1e18);

        // Call
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );
        uint256 price = submoduleBunniPrice.getBunniTokenPrice(
            poolTokenAddress,
            PRICE_DECIMALS,
            params
        );

        // Check values
        assertTrue(price > 0, "should be non-zero");
        assertEq(price, expectedPrice);
    }

    function test_getBunniTokenPrice_twapDeviationReverts() public {
        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);
        // 11421651 = 11.42 USD/OHM
        uint256 reservesRatio = usdcReserves_.mulDiv(1e9, ohmReserves_); // USDC decimals: 6

        // Mock the pool returning a TWAP that deviates enough to revert
        int56 tickCumulative0_ = -2416639538393;
        int56 tickCumulative1_ = -2416640880953;
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumulative0_;
        tickCumulatives[1] = tickCumulative1_;
        uniswapPool.setTickCumulatives(tickCumulatives);

        // Calculate the expected TWAP price
        int56 timeWeightedTick = (tickCumulative1_ - tickCumulative0_) /
            int32(TWAP_OBSERVATION_WINDOW);
        uint256 twapRatio = OracleLibrary.getQuoteAtTick(
            int24(timeWeightedTick),
            uint128(10 ** 9), // token0 (OHM) decimals
            OHM,
            USDC
        ); // USDC decimals: 6

        // Set up revert
        // Will revert as the TWAP deviates from the reserves ratio
        bytes memory err = abi.encodeWithSelector(
            BunniPrice.BunniPrice_PriceMismatch.selector,
            address(uniswapPool),
            twapRatio,
            reservesRatio
        );
        vm.expectRevert(err);

        // Call
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );
        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
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
        (uint256 ohmReserve_, uint256 usdcReserve_) = _getReserves(poolTokenKey, bunniLens);
        uint256 ohmReserve = ohmReserve_.mulDiv(10 ** outputDecimals, 10 ** OHM_DECIMALS);
        uint256 usdcReserve = usdcReserve_.mulDiv(10 ** outputDecimals, 10 ** USDC_DECIMALS);
        uint256 expectedPrice = ohmReserve.mulDiv(ohmPrice, 10 ** outputDecimals) +
            usdcReserve.mulDiv(usdcPrice, 10 ** outputDecimals);

        // Call
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );
        uint256 price = submoduleBunniPrice.getBunniTokenPrice(
            poolTokenAddress,
            outputDecimals,
            params
        );

        // Check values
        assertTrue(price > 0, "should be non-zero");
        assertEq(price, expectedPrice);
    }

    function test_getBunniTokenPrice_reentrancyReverts() public {
        // Set the UniV3 pair to be locked, which indicates re-entrancy
        uniswapPool.setUnlocked(false);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniLens.BunniLens_Reentrant.selector,
            address(uniswapPool)
        );
        vm.expectRevert(err);

        // Call
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );
        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }
}
