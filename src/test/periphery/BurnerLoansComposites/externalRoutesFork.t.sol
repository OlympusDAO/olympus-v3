// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansSwapAdapter} from "src/periphery/interfaces/IBurnerLoansSwapAdapter.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {BURNER_LOANS_INVENTORY_PROVIDER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansUniswapV3Adapter} from "src/periphery/adapters/BurnerLoansUniswapV3Adapter.sol";
import {BurnerLoansCompositesTest} from "./fixtures/BurnerLoansCompositesTest.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @dev Exercises fixed routes against deployed contracts on a pinned Ethereum mainnet fork.
contract BurnerLoansCompositesExternalRoutesForkTest is BurnerLoansCompositesTest {
    uint256 internal constant _FORK_BLOCK = 26_447_690;
    uint256 internal constant _FORK_SIGNER_KEY =
        uint256(keccak256("Burner Loans Composites fork fixture"));
    address internal constant _DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant _USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address internal constant _USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address internal constant _USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant _OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address internal constant _WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant _ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant _MIGRATOR = 0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A;
    address internal constant _LENDER = 0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA;
    BurnerLoansUniswapV3Adapter internal _adapter;

    function setUp() public override {
        assertEq(block.chainid, 1, "Fork must use Ethereum mainnet");
        vm.rollFork(_FORK_BLOCK);
        _borrower = vm.addr(_FORK_SIGNER_KEY);
        assertEq(_borrower.code.length, 0, "Fork borrower is an undelegated EOA");
        super.setUp();
        _price.setPrice(_OHM, 15.5e18);
        _price.setPrice(_USDS, 1e18);
        _price.setPrice(_USDE, 1e18);
        _admit(_USDS);
        _admit(_USDE);
        address inventoryProvider = makeAddr("inventoryProvider");
        _grantFixtureRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, inventoryProvider);
        deal(_OHM, inventoryProvider, 20e9);
        vm.startPrank(inventoryProvider);
        assertTrue(IERC20(_OHM).approve(address(_inventory), 20e9), "Approve supplied OHM");
        _inventory.supply(20e9);
        vm.stopPrank();
    }

    function _fixtureOhm() internal pure override returns (MockERC20) {
        return MockERC20(_OHM);
    }

    function _integrations() internal override returns (IExecutor.Integrations memory) {
        _adapter = new BurnerLoansUniswapV3Adapter(_ROUTER);
        return IExecutor.Integrations(_MIGRATOR, address(_adapter), _LENDER);
    }

    // Scenarios: BLREX-P08.
    function test_whenRealMigrationConvertsDaiToUsds() public {
        _assertRealMigration(_DAI, _USDS);
    }

    // Scenarios: BLREX-P32.
    function test_whenRealMigrationConvertsUsdsToDai() public {
        _assertRealMigration(_USDS, _DAI);
    }

    function _assertRealMigration(address tokenIn_, address tokenOut_) private {
        deal(tokenIn_, _borrower, 100e18);
        uint256 walletOutBefore = IERC20(tokenOut_).balanceOf(_borrower);
        vm.prank(_borrower);
        assertTrue(IERC20(tokenIn_).approve(address(_executor), 100e18), "Approve migrator input");
        vm.prank(_borrower);
        _executor.execute(
            _funding(tokenIn_, 100e18),
            _single(_convertDaiUsds(tokenIn_, tokenOut_, 90e18)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        // Migration spends 90 of 100 input tokens and returns output at 1:1 (18 decimals).
        assertEq(IERC20(tokenIn_).balanceOf(_borrower), 10e18, "Unused input returned");
        assertEq(
            IERC20(tokenOut_).balanceOf(_borrower),
            walletOutBefore + 90e18,
            "Converted output returned"
        );
    }

    // Scenarios: BLREX-P33.
    function test_whenRealMigrationRunsInBothDirections() public {
        deal(_DAI, _borrower, 100e18);
        vm.prank(_borrower);
        assertTrue(IERC20(_DAI).approve(address(_executor), 100e18), "Approve DAI input");
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _convertDaiUsds(_DAI, _USDS, 100e18);
        operations[1] = _convertDaiUsds(_USDS, _DAI, 90e18);
        vm.prank(_borrower);
        _executor.execute(
            _funding(_DAI, 100e18),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(IERC20(_DAI).balanceOf(_borrower), 90e18, "Reverse output refunded");
        assertEq(IERC20(_USDS).balanceOf(_borrower), 10e18, "Unused forward output refunded");
    }

    // Scenarios: BLRSW-P02.
    function test_whenRealExactInputUsesUsdcRoute() public {
        _assertRealExactInput(false);
    }

    // Scenarios: BLRSW-P02.
    function test_whenRealExactInputUsesWethRoute() public {
        _assertRealExactInput(true);
    }

    function _assertRealExactInput(bool viaWeth_) private {
        _fundDaiSwap(100e18);
        IBurnerLoansSwapAdapter.ExactInputParams memory params = IBurnerLoansSwapAdapter
            .ExactInputParams(_DAI, _USDE, 100e18, 99e18, block.timestamp, _daiToUsde(viaWeth_));
        vm.prank(_borrower);
        uint256 received = _adapter.swapExactInput(params);
        assertGe(received, 99e18, "Pinned path clears slippage bound");
        assertEq(IERC20(_USDE).balanceOf(_borrower), received, "Actual recipient balance agrees");
        assertEq(IERC20(_DAI).balanceOf(_borrower), 0, "Exact DAI spent");
    }

    // Scenarios: BLRSW-T03.
    function test_whenUsdcRouteCannotMeetMinimum_reverts() public {
        _expectExactInputBelowMinimum(false);
    }

    // Scenarios: BLRSW-T03.
    function test_whenWethRouteCannotMeetMinimum_reverts() public {
        _expectExactInputBelowMinimum(true);
    }

    function _expectExactInputBelowMinimum(bool viaWeth_) private {
        _fundDaiSwap(100e18);
        IBurnerLoansSwapAdapter.ExactInputParams memory params = IBurnerLoansSwapAdapter
            .ExactInputParams(_DAI, _USDE, 100e18, 200e18, block.timestamp, _daiToUsde(viaWeth_));
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Too little received"));
        vm.prank(_borrower);
        _adapter.swapExactInput(params);
        assertEq(IERC20(_DAI).balanceOf(_borrower), 100e18, "Input restored");
        assertEq(IERC20(_USDE).balanceOf(_borrower), 0, "No output committed");
        assertEq(
            IERC20(_DAI).allowance(address(_adapter), _ROUTER),
            0,
            "Router allowance restored"
        );
    }

    // Scenarios: BLREX-P10.
    function test_whenRealFlashFundsUsdsCollateral() public {
        _runCreditRoundTrip(_USDS, _convertDaiUsds(_DAI, _USDS, 100e18));
    }

    // Scenarios: BLREX-P11.
    function test_whenRealFlashFundsUsdeCollateral() public {
        _runCreditRoundTrip(_USDE, _swapExactInput(_DAI, _USDE, 100e18, 99e18, _daiToUsde(false)));
    }

    // Scenarios: BLRSW-P06.
    function test_whenRealExactOutputUsesUsdcRoute() public {
        _assertRealExactOutput(false);
    }

    // Scenarios: BLRSW-P06.
    function test_whenRealExactOutputUsesWethRoute() public {
        _assertRealExactOutput(true);
    }

    function _assertRealExactOutput(bool viaWeth_) private {
        _fundDaiSwap(100e18);
        deal(_DAI, address(_adapter), 7e18);
        deal(_USDE, address(_adapter), 11e18);
        vm.prank(_borrower);
        uint256 spent = _adapter.swapExactOutput(
            IBurnerLoansSwapAdapter.ExactOutputParams(
                _DAI,
                _USDE,
                10e18,
                100e18,
                block.timestamp,
                _reverseDaiToUsde(viaWeth_)
            )
        );
        assertEq(IERC20(_USDE).balanceOf(_borrower), 10e18, "Exact USDe delivered");
        assertGt(spent, 0, "Router must debit input");
        assertLt(spent, 100e18, "Router spends less than the cap");
        assertEq(IERC20(_DAI).balanceOf(_borrower), 100e18 - spent, "Unused DAI returned");
        assertEq(IERC20(_DAI).balanceOf(address(_adapter)), 7e18, "Protected DAI retained");
        assertEq(IERC20(_USDE).balanceOf(address(_adapter)), 11e18, "Protected USDe retained");
        assertEq(IERC20(_DAI).allowance(address(_adapter), _ROUTER), 0, "Router allowance cleared");
    }

    // Scenarios: BLRSW-T07.
    function test_whenUsdcRouteExceedsInputCap_reverts() public {
        _expectExactOutputAboveInputCap(false);
    }

    // Scenarios: BLRSW-T07.
    function test_whenWethRouteExceedsInputCap_reverts() public {
        _expectExactOutputAboveInputCap(true);
    }

    function _expectExactOutputAboveInputCap(bool viaWeth_) private {
        _fundDaiSwap(1e18);
        IBurnerLoansSwapAdapter.ExactOutputParams memory params = IBurnerLoansSwapAdapter
            .ExactOutputParams(
                _DAI,
                _USDE,
                10e18,
                1e18,
                block.timestamp,
                _reverseDaiToUsde(viaWeth_)
            );
        // The router tries to collect payment before checking its input cap.
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "STF"));
        vm.prank(_borrower);
        _adapter.swapExactOutput(params);
        assertEq(IERC20(_DAI).balanceOf(_borrower), 100e18, "Input restored");
        assertEq(IERC20(_USDE).balanceOf(_borrower), 0, "No output committed");
        assertEq(
            IERC20(_DAI).allowance(_borrower, address(_adapter)),
            1e18,
            "Caller allowance restored"
        );
        assertEq(
            IERC20(_DAI).allowance(address(_adapter), _ROUTER),
            0,
            "Router allowance restored"
        );
    }

    function _fundDaiSwap(uint256 allowance_) private {
        deal(_DAI, _borrower, 100e18);
        vm.prank(_borrower);
        assertTrue(IERC20(_DAI).approve(address(_adapter), allowance_), "Approve DAI input");
    }

    function _runCreditRoundTrip(address asset_, IExecutor.Operation memory exchange_) private {
        // 100 DAI flash principal plus about 100 collateral from conversion/swap, with
        // 110 collateral of explicit equity. Deposit 200 and pay less than 1 in fees.
        // Borrow 10 OHM (9 decimals), swap for at least 150 DAI and repay 100 DAI.
        deal(asset_, _borrower, 110e18);
        vm.prank(_borrower);
        assertTrue(IERC20(asset_).approve(address(_executor), 110e18), "Approve collateral equity");
        IOperatorAuth.Grant memory grant = _operatorGrantForAsset(
            _borrower,
            address(_executor),
            type(uint48).max,
            asset_
        );
        grant.multiple = false;
        IExecutor.SignedGrant memory signed = _signedGrantWithKey(grant, _FORK_SIGNER_KEY);
        uint256 loanFee = IERC3156FlashLender(_LENDER).flashFee(_DAI, 100e18);
        assertEq(loanFee, 0, "Expected fee at pinned block");
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](4);
        operations[0] = exchange_;
        operations[1] = IExecutor.Operation(
            IExecutor.OperationKind.Deposit,
            abi.encode(IExecutor.Deposit(asset_, 200e18))
        );
        operations[2] = IExecutor.Operation(
            IExecutor.OperationKind.Borrow,
            abi.encode(IExecutor.Borrow(asset_, 10e9, address(_executor), 1e18, address(0)))
        );
        operations[3] = _swapExactInput(
            _OHM,
            _DAI,
            10e9,
            150e18,
            abi.encodePacked(_OHM, uint24(3000), _WETH, uint24(3000), _DAI)
        );
        IExecutor.Output[] memory outputs = new IExecutor.Output[](1);
        outputs[0] = IExecutor.Output(_DAI, 50e18);
        uint256 custodyBefore = IERC20(asset_).balanceOf(address(_depositManager));
        uint256 activeDebtBefore = _core.totalActiveDebtOhm();
        vm.prank(_borrower);
        _executor.executeWithGrant(
            _funding(asset_, 110e18),
            operations,
            outputs,
            IExecutor.FlashLoan(100e18, loanFee),
            type(uint48).max,
            signed
        );
        assertEq(
            _lens.getPosition(asset_, _borrower).depositedCollateral,
            200e18,
            "Canonical collateral"
        );
        assertEq(_lens.getPosition(asset_, _borrower).debtOhm, 10e9, "Canonical principal");
        assertEq(
            IERC20(asset_).balanceOf(address(_depositManager)),
            custodyBefore + 200e18,
            "Deposit increases custody by the credited collateral"
        );
        assertEq(
            _core.totalActiveDebtOhm(),
            activeDebtBefore + 10e9,
            "Aggregate principal increases"
        );
        assertEq(_inventory.activePrincipalOhm(), 10e9, "Provider liquidity lent");
        assertGe(IERC20(_DAI).balanceOf(_borrower), 50e18, "DAI surplus delivered after repayment");
        assertEq(IERC20(_DAI).balanceOf(address(_executor)), 0, "Executor DAI fully settled");
        assertEq(
            IERC20(asset_).balanceOf(address(_executor)),
            0,
            "Executor collateral fully settled"
        );
        assertEq(IERC20(_OHM).balanceOf(address(_executor)), 0, "Executor OHM fully settled");
        assertEq(
            IERC20(_DAI).allowance(address(_executor), _LENDER),
            0,
            "Lender allowance cleared"
        );
    }

    function _swapExactInput(
        address input_,
        address output_,
        uint256 amount_,
        uint256 minimum_,
        bytes memory route_
    ) private pure returns (IExecutor.Operation memory) {
        return
            IExecutor.Operation(
                IExecutor.OperationKind.SwapExactInput,
                abi.encode(IExecutor.SwapExactInput(input_, output_, amount_, minimum_, route_))
            );
    }

    function _daiToUsde(bool viaWeth_) private pure returns (bytes memory) {
        if (viaWeth_) {
            return
                abi.encodePacked(_DAI, uint24(3000), _WETH, uint24(500), _USDC, uint24(100), _USDE);
        }
        return abi.encodePacked(_DAI, uint24(100), _USDC, uint24(100), _USDE);
    }

    function _reverseDaiToUsde(bool viaWeth_) private pure returns (bytes memory) {
        if (viaWeth_) {
            return
                abi.encodePacked(_USDE, uint24(100), _USDC, uint24(500), _WETH, uint24(3000), _DAI);
        }
        return abi.encodePacked(_USDE, uint24(100), _USDC, uint24(100), _DAI);
    }
}
