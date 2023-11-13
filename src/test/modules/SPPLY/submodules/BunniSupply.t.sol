// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {MockUniV3Pair} from "test/mocks/MockUniV3Pair.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/modules/SPPLY/OlympusSupply.sol";
import {BunniSupply} from "src/modules/SPPLY/submodules/BunniSupply.sol";
import {BunniHub} from "src/external/bunni/BunniHub.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {BunniToken} from "src/external/bunni/BunniToken.sol";
import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";

import {UniswapV3Factory} from "test/lib/UniswapV3/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {OlympusPricev2} from "modules/PRICE/OlympusPrice.v2.sol";

contract BunniSupplyTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusSupply;

    MockERC20 internal ohm;
    MockERC20 internal usdc;
    MockGohm internal gOhm;
    address internal ohmAddress;
    address internal usdcAddress;

    Kernel internal kernel;

    OlympusSupply internal moduleSupply;

    BunniSupply internal submoduleBunniSupply;

    MockUniV3Pair internal uniswapPool;
    BunniHub internal bunniHub;
    BunniLens internal bunniLens;
    IBunniToken internal poolToken;
    BunniKey internal poolTokenKey;
    address internal bunniLensAddress;
    address internal poolTokenAddress;

    address internal writer;
    address internal policy;

    UserFactory public userFactory;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant INITIAL_CROSS_CHAIN_SUPPLY = 0; // 0 OHM

    uint128 internal constant POOL_LIQUIDITY = 349484367626548;
    uint160 internal constant POOL_SQRTPRICEX96 = 8467282393668682240084879204;

    // Events
    event BunniTokenAdded(address token_, address bunniLens_);
    event BunniTokenRemoved(address token_);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Tokens
        {
            ohm = new MockERC20("OHM", "OHM", 9);
            usdc = new MockERC20("USDC", "USDC", 6);
            gOhm = new MockGohm(GOHM_INDEX);

            ohmAddress = address(ohm);
            usdcAddress = address(usdc);
        }

        // Locations
        {
            userFactory = new UserFactory();
            address[] memory users = userFactory.create(1);
            policy = users[0];
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

        // Deploy Bunni submodule
        {
            submoduleBunniSupply = new BunniSupply(moduleSupply);
        }

        // Initialize
        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(moduleSupply));
            kernel.executeAction(Actions.ActivatePolicy, address(writer));

            // Install submodules on SPPLY module
            vm.prank(writer);
            moduleSupply.installSubmodule(submoduleBunniSupply);
        }

        // Deploy Uniswap V3 pool and tokens
        {
            (
                MockUniV3Pair uniswapPool_,
                BunniKey memory poolTokenKey_,
                BunniToken poolToken_
            ) = _setUpPool(ohmAddress, usdcAddress, POOL_LIQUIDITY, POOL_SQRTPRICEX96);

            uniswapPool = uniswapPool_;
            poolTokenKey = poolTokenKey_;
            poolToken = poolToken_;
            poolTokenAddress = address(poolToken);
        }
    }

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

    function _getOhmReserves(
        BunniKey memory key_,
        BunniLens lens_
    ) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1) = lens_.getReserves(key_);
        if (key_.pool.token0() == ohmAddress) {
            return reserve0;
        } else {
            return reserve1;
        }
    }

    function _getReserves(
        BunniKey memory key_,
        BunniLens lens_
    ) internal view returns (uint256, uint256) {
        (uint112 reserve0, uint112 reserve1) = lens_.getReserves(key_);
        return (reserve0, reserve1);
    }

    function _expectRevert_invalidBunniToken(address token_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniToken.selector,
            token_
        );
        vm.expectRevert(err);
    }

    function _expectRevert_invalidBunniLens(address lens_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniLens.selector,
            lens_
        );
        vm.expectRevert(err);
    }

    // =========  TESTS ========= //

    // =========  Module Information ========= //

    // [X] Submodule
    //  [X] Version
    //  [X] Subkeycode

    function test_submodule_version() public {
        uint8 major;
        uint8 minor;
        (major, minor) = submoduleBunniSupply.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_submodule_parent() public {
        assertEq(fromKeycode(submoduleBunniSupply.PARENT()), "SPPLY");
    }

    function test_submodule_subkeycode() public {
        assertEq(fromSubKeycode(submoduleBunniSupply.SUBKEYCODE()), "SPPLY.BNI");
    }

    // [X] Constructor
    //  [X] Incorrect parent

    function test_submodule_parent_notModule_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        // There's no error message, so just check that a revert happens when attempting to call the module
        vm.expectRevert();

        new BunniSupply(Module(newLocations[0]));
    }

    function test_submodule_parent_notSpply_reverts() public {
        // Pass the PRICEv2 module as the parent
        OlympusPricev2 modulePrice = new OlympusPricev2(kernel, 18, 8 hours);

        bytes memory err = abi.encodeWithSignature("Submodule_InvalidParent()");
        vm.expectRevert(err);

        new BunniSupply(modulePrice);
    }

    // =========  getCollateralizedOhm ========= //

    // [X] getCollateralizedOhm

    function test_getCollateralizedOhm() public {
        // Register the pool with the submodule
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        // Will always be zero
        assertEq(submoduleBunniSupply.getCollateralizedOhm(), 0);
    }

    // =========  getProtocolOwnedBorrowableOhm ========= //

    // [X] getProtocolOwnedBorrowableOhm

    function test_getProtocolOwnedBorrowableOhm() public {
        // Register the pool with the submodule
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        // Will always be zero
        assertEq(submoduleBunniSupply.getProtocolOwnedBorrowableOhm(), 0);
    }

    // =========  getProtocolOwnedLiquidityOhm ========= //

    // [X] getProtocolOwnedLiquidityOhm
    //  [X] no tokens
    //  [X] single token
    //  [X] multiple tokens

    function test_getProtocolOwnedLiquidityOhm_noTokens() public {
        // Don't add the token

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), 0);
    }

    function test_getProtocolOwnedLiquidityOhm_singleToken() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        // Determine the amount of OHM in the pool, which should be consistent with the lens value
        uint256 ohmReserves = _getOhmReserves(poolTokenKey, bunniLens);

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), ohmReserves);
    }

    function test_getProtocolOwnedLiquidityOhm_multipleToken() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        // Set up a second pool and token
        MockERC20 wETH = new MockERC20("wETH", "wETH", 18);
        uint128 liquidityTwo = 602219599341335870;
        uint160 sqrtPriceX96Two = 195181081174522229204497247535278;
        (, BunniKey memory poolTokenKeyTwo, BunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wETH),
            liquidityTwo,
            sqrtPriceX96Two
        );
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(address(poolTokenTwo), bunniLensAddress);

        // Determine the amount of OHM in the pool, which should be consistent with the lens value
        uint256 ohmReserves = _getOhmReserves(poolTokenKey, bunniLens);
        uint256 ohmReservesTwo = _getOhmReserves(poolTokenKeyTwo, bunniLens);

        // Call
        uint256 polo = submoduleBunniSupply.getProtocolOwnedLiquidityOhm();

        assertTrue(polo > 0, "should be non-zero");
        assertEq(polo, ohmReserves + ohmReservesTwo);
    }

    // =========  getProtocolOwnedLiquidityReserves ========= //

    // [X] getProtocolOwnedLiquidityReserves
    //  [X] no tokens
    //  [X] single token
    //  [X] multiple tokens

    function test_getProtocolOwnedLiquidityReserves_noTokens() public {
        // Don't add the token

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply.getProtocolOwnedLiquidityReserves();
        
        assertEq(reserves.length, 0);
    }

    function test_getProtocolOwnedLiquidityReserves_singleToken() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply.getProtocolOwnedLiquidityReserves();
        
        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, poolTokenAddress);
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], ohmAddress);
        assertEq(reserves[0].tokens[1], usdcAddress);
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], ohmReserves_);
        assertEq(reserves[0].balances[1], usdcReserves_);
    }

    function test_getProtocolOwnedLiquidityReserves_multipleToken() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        // Set up a second pool and token
        MockERC20 wETH = new MockERC20("wETH", "wETH", 18);
        uint128 liquidityTwo = 602219599341335870;
        uint160 sqrtPriceX96Two = 195181081174522229204497247535278;
        (, BunniKey memory poolTokenKeyTwo, BunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wETH),
            liquidityTwo,
            sqrtPriceX96Two
        );
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(address(poolTokenTwo), bunniLensAddress);

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);
        (uint256 ohmReservesTwo_, uint256 wethReservesTwo_) = _getReserves(poolTokenKeyTwo, bunniLens);

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply.getProtocolOwnedLiquidityReserves();
        
        assertEq(reserves.length, 2);

        assertEq(reserves[0].source, poolTokenAddress);
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], ohmAddress);
        assertEq(reserves[0].tokens[1], usdcAddress);
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], ohmReserves_);
        assertEq(reserves[0].balances[1], usdcReserves_);

        assertEq(reserves[1].source, poolTokenAddress);
        assertEq(reserves[1].tokens.length, 2);
        assertEq(reserves[1].tokens[0], ohmAddress);
        assertEq(reserves[1].tokens[1], address(wETH));
        assertEq(reserves[1].balances.length, 2);
        assertEq(reserves[1].balances[0], ohmReservesTwo_);
        assertEq(reserves[1].balances[1], wethReservesTwo_);
    }

    // =========  addBunniToken ========= //

    // [X] addBunniToken
    //  [X] reverts if not parent
    //  [X] reverts if token is address(0)
    //  [X] reverts if lens is address(0)
    //  [X] reverts if token already added
    //  [X] reverts if invalid token
    //  [X] reverts if invalid lens
    //  [X] reverts if token and lens hub addresses don't match
    //  [X] single token
    //  [X] multiple tokens, single lens
    //  [X] multiple tokens, multiple lenses

    function test_addBunniToken_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);
    }

    function test_addBunniToken_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writer)
        );
        vm.expectRevert(err);

        vm.prank(writer);
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);
    }

    function test_addBunniToken_tokenAddressZero_reverts() public {
        _expectRevert_invalidBunniToken(address(0));

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(address(0), bunniLensAddress);
    }

    function test_addBunniToken_lensAddressZero_reverts() public {
        _expectRevert_invalidBunniLens(address(0));

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, address(0));
    }

    function test_addBunniToken_alreadyAdded_reverts() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        _expectRevert_invalidBunniToken(poolTokenAddress);

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);
    }

    function test_addBunniToken_invalidTokenReverts() public {
        _expectRevert_invalidBunniToken(ohmAddress);

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(ohmAddress, bunniLensAddress);
    }

    function test_addBunniToken_invalidLensReverts() public {
        _expectRevert_invalidBunniLens(ohmAddress);

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, ohmAddress);
    }

    function test_addBunniToken_hubMismatchReverts() public {
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
            BunniSupply.BunniSupply_Params_HubMismatch.selector,
            address(bunniHub),
            address(newBunniHub)
        );
        vm.expectRevert(err);

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, address(newBunniLens));
    }

    function test_addBunniToken() public {
        // Expect an event
        vm.expectEmit(true, true, false, true);
        emit BunniTokenAdded(poolTokenAddress, bunniLensAddress);

        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        // Check that the token was added
        assertEq(address(submoduleBunniSupply.bunniTokens(0)), poolTokenAddress);
        assertEq(address(submoduleBunniSupply.bunniLenses(0)), bunniLensAddress);
        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);
        assertEq(submoduleBunniSupply.bunniLensCount(), 1);
    }

    function test_addBunniToken_multipleTokens_singleLens() public {
        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        // Set up a second pool and token
        MockERC20 wETH = new MockERC20("wETH", "wETH", 18);
        uint128 liquidityTwo = 602219599341335870;
        uint160 sqrtPriceX96Two = 195181081174522229204497247535278;
        (, , BunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wETH),
            liquidityTwo,
            sqrtPriceX96Two
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Expect an event
        vm.expectEmit(true, true, false, true);
        emit BunniTokenAdded(poolTokenTwoAddress, bunniLensAddress);

        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenTwoAddress, bunniLensAddress);

        // Check that the token was added
        assertEq(address(submoduleBunniSupply.bunniTokens(0)), poolTokenAddress);
        assertEq(address(submoduleBunniSupply.bunniTokens(1)), poolTokenTwoAddress);
        assertEq(address(submoduleBunniSupply.bunniLenses(0)), bunniLensAddress);
        assertEq(address(submoduleBunniSupply.bunniLenses(1)), bunniLensAddress);
        assertEq(submoduleBunniSupply.bunniTokenCount(), 2);
        assertEq(submoduleBunniSupply.bunniLensCount(), 2);
    }

    function test_addBunniToken_multipleTokens_multipleLenses() public {
        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        // Set up a second pool and token
        MockERC20 wETH = new MockERC20("wETH", "wETH", 18);
        uint128 liquidityTwo = 602219599341335870;
        uint160 sqrtPriceX96Two = 195181081174522229204497247535278;
        (, , BunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wETH),
            liquidityTwo,
            sqrtPriceX96Two
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Set up a new Lens
        BunniLens bunniLensTwo = new BunniLens(bunniHub);
        address bunniLensTwoAddress = address(bunniLensTwo);

        // Expect an event
        vm.expectEmit(true, true, false, true);
        emit BunniTokenAdded(poolTokenTwoAddress, bunniLensTwoAddress);

        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenTwoAddress, bunniLensTwoAddress);

        // Check that the token was added
        assertEq(address(submoduleBunniSupply.bunniTokens(0)), poolTokenAddress);
        assertEq(address(submoduleBunniSupply.bunniTokens(1)), poolTokenTwoAddress);
        assertEq(address(submoduleBunniSupply.bunniLenses(0)), bunniLensAddress);
        assertEq(address(submoduleBunniSupply.bunniLenses(1)), bunniLensTwoAddress);
        assertEq(submoduleBunniSupply.bunniTokenCount(), 2);
        assertEq(submoduleBunniSupply.bunniLensCount(), 2);
    }

    // =========  removeBunniToken ========= //

    // [X] removeBunniToken
    //  [X] reverts if not parent
    //  [X] reverts if address(0)
    //  [X] reverts if not added
    //  [X] single token
    //  [X] multiple tokens, single lens
    //  [X] multiple tokens, multiple lenses

    function test_removeBunniToken_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleBunniSupply.removeBunniToken(poolTokenAddress);
    }

    function test_removeBunniToken_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writer)
        );
        vm.expectRevert(err);

        vm.prank(writer);
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);
    }

    function test_removeBunniToken_addressZero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniToken.selector,
            address(0)
        );
        vm.expectRevert(err);

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.removeBunniToken(address(0));
    }

    function test_removeBunniToken_notAdded_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniToken.selector,
            poolTokenAddress
        );
        vm.expectRevert(err);

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);
    }

    function test_removeBunniToken() public {
        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        vm.expectEmit(true, false, false, true);
        emit BunniTokenRemoved(poolTokenAddress);

        // Remove token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);

        // Check that the token was removed
        assertEq(submoduleBunniSupply.bunniTokenCount(), 0);
        assertEq(submoduleBunniSupply.bunniLensCount(), 0);
        assertEq(submoduleBunniSupply.getCollateralizedOhm(), 0);
    }

    function test_removeBunniToken_multipleTokens_singleLens() public {
        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        // Set up a second pool and token
        MockERC20 wETH = new MockERC20("wETH", "wETH", 18);
        uint128 liquidityTwo = 602219599341335870;
        uint160 sqrtPriceX96Two = 195181081174522229204497247535278;
        (, , BunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wETH),
            liquidityTwo,
            sqrtPriceX96Two
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenTwoAddress, bunniLensAddress);

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit BunniTokenRemoved(poolTokenAddress);

        // Remove one of the tokens
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);

        // Check that the token was removed
        assertEq(address(submoduleBunniSupply.bunniTokens(0)), poolTokenTwoAddress);
        assertEq(address(submoduleBunniSupply.bunniLenses(0)), bunniLensAddress);
        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);
        assertEq(submoduleBunniSupply.bunniLensCount(), 1);
    }

    function test_removeBunniToken_multipleTokens_multipleLenses() public {
        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        // Set up a second pool and token
        MockERC20 wETH = new MockERC20("wETH", "wETH", 18);
        uint128 liquidityTwo = 602219599341335870;
        uint160 sqrtPriceX96Two = 195181081174522229204497247535278;
        (, , BunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wETH),
            liquidityTwo,
            sqrtPriceX96Two
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Set up a new Lens
        BunniLens bunniLensTwo = new BunniLens(bunniHub);
        address bunniLensTwoAddress = address(bunniLensTwo);

        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenTwoAddress, bunniLensTwoAddress);

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit BunniTokenRemoved(poolTokenAddress);

        // Remove one of the tokens
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);

        // Check that the token was removed
        assertEq(address(submoduleBunniSupply.bunniTokens(0)), poolTokenTwoAddress);
        assertEq(address(submoduleBunniSupply.bunniLenses(0)), bunniLensTwoAddress);
        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);
        assertEq(submoduleBunniSupply.bunniLensCount(), 1);
    }

    // =========  hasBunniToken ========= //

    // [X] hasBunniToken
    //  [X] false if address(0)
    //  [X] false if not added
    //  [X] true if added

    function test_hasBunniToken_addressZero() public {
        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        // Call
        bool hasToken = submoduleBunniSupply.hasBunniToken(address(0));

        // Check
        assertFalse(hasToken);
    }

    function test_hasBunniToken_differentAddress() public {
        // Do NOT add Bunni Token to BunniSupply

        // Call
        bool hasToken = submoduleBunniSupply.hasBunniToken(poolTokenAddress);

        // Check
        assertFalse(hasToken);
    }

    function test_hasBunniToken() public {
        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(poolTokenAddress, bunniLensAddress);

        // Call
        bool hasToken = submoduleBunniSupply.hasBunniToken(poolTokenAddress);

        // Check
        assertTrue(hasToken);
    }
}
