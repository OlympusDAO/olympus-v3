// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansSwapAdapter} from "src/periphery/interfaces/IBurnerLoansSwapAdapter.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {BurnerLoansCompositesGrantModesTest} from "./fixtures/BurnerLoansCompositesGrantModesTest.sol";
import {MockCompositesMigrator} from "./fixtures/MockCompositesMigrator.sol";
import {MockCompositesFlashLender} from "./fixtures/MockCompositesFlashLender.sol";
import {MockCompositesSwapAdapter} from "./fixtures/MockCompositesSwapAdapter.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract BurnerLoansCompositesExecuteSwapsTest is BurnerLoansCompositesGrantModesTest {
    error UnexpectedAuthRead();

    MockERC20 internal _dai;
    MockERC20 internal _usds;
    MockCompositesMigrator internal _migrator;
    MockCompositesSwapAdapter internal _adapter;

    function _integrations() internal override returns (IExecutor.Integrations memory) {
        _dai = new MockERC20("DAI", "DAI", 18);
        _usds = new MockERC20("USDS", "USDS", 18);
        _migrator = new MockCompositesMigrator(_dai, _usds);
        _adapter = new MockCompositesSwapAdapter();
        return
            IExecutor.Integrations(
                address(_migrator),
                address(_adapter),
                address(new MockCompositesFlashLender(_dai))
            );
    }

    function setUp() public override {
        super.setUp();
        _dai.mint(_borrower, 100e18);
        vm.prank(_borrower);
        _dai.approve(address(_executor), 100e18);
        vm.prank(_borrower);
        _asset.approve(address(_executor), type(uint256).max);
    }

    // Scenarios: BLREX-P08, BLREX-N13.
    function test_whenConvertingDaiToUsds() public {
        _assertConversion(_dai, _usds);
    }

    // Scenarios: BLREX-P32.
    function test_whenConvertingUsdsToDai() public {
        _usds.mint(_borrower, 100e18);
        vm.prank(_borrower);
        _usds.approve(address(_executor), 100e18);
        _assertConversion(_usds, _dai);
    }

    function _assertConversion(MockERC20 tokenIn_, MockERC20 tokenOut_) private {
        uint48 deadline = 100;
        vm.warp(deadline);
        _blockAuthReads();
        tokenIn_.mint(address(_executor), 7e18);
        tokenOut_.mint(address(_executor), 11e18);
        uint256 walletOutBefore = tokenOut_.balanceOf(_borrower);
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(tokenIn_), 100e18),
            _single(_convertDaiUsds(address(tokenIn_), address(tokenOut_), 90e18)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            deadline
        );
        // Both tokens have 18 decimals. Spending 90 from 100 returns 10, and the migrator pays 1:1.
        assertEq(abi.decode(results[0], (uint256)), 90e18, "Exact converted amount reported");
        assertEq(tokenIn_.balanceOf(_borrower), 10e18, "Unused input returned");
        assertEq(
            tokenOut_.balanceOf(_borrower),
            walletOutBefore + 90e18,
            "Converted output returned"
        );
        assertEq(tokenIn_.balanceOf(address(_executor)), 7e18, "Protected input retained");
        assertEq(tokenOut_.balanceOf(address(_executor)), 11e18, "Protected output retained");
        assertEq(
            tokenIn_.allowance(address(_executor), address(_migrator)),
            0,
            "Migrator allowance cleared"
        );
    }

    // Scenarios: BLREX-P33.
    function test_whenConvertingInBothDirections() public {
        uint48 deadline = 100;
        vm.warp(deadline);
        _blockAuthReads();
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _convertDaiUsds(address(_dai), address(_usds), 100e18);
        operations[1] = _convertDaiUsds(address(_usds), address(_dai), 90e18);
        _dai.mint(address(_executor), 7e18);
        _usds.mint(address(_executor), 11e18);
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(_dai), 100e18),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            deadline
        );
        assertEq(abi.decode(results[0], (uint256)), 100e18, "Exact USDS receipt");
        assertEq(abi.decode(results[1], (uint256)), 90e18, "Exact DAI receipt");
        assertEq(_dai.balanceOf(_borrower), 90e18, "DAI returned");
        assertEq(_usds.balanceOf(_borrower), 10e18, "Unused USDS returned");
        assertEq(_dai.balanceOf(address(_executor)), 7e18, "Protected DAI retained");
        assertEq(_usds.balanceOf(address(_executor)), 11e18, "Protected USDS retained");
        assertEq(
            _dai.allowance(address(_executor), address(_migrator)),
            0,
            "DAI allowance cleared"
        );
        assertEq(
            _usds.allowance(address(_executor), address(_migrator)),
            0,
            "USDS allowance cleared"
        );
    }

    // Scenarios: BLREX-N13, BLREX-P24, BLREX-P25.
    function test_whenSwappingWithoutGrant(bytes calldata route_) public {
        _assertSwappingWithoutGrant(route_, 90e6);
    }

    // Scenarios: BLREX-P24, BLREX-P25.
    function test_whenRouteMatchesBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        _assertSwappingWithoutGrant("", 90e6 + 1);
        assertTrue(vm.revertToState(snapshot), "Restore empty route case");
        _assertSwappingWithoutGrant(hex"ab", 90e6 + 1);
        assertTrue(vm.revertToState(snapshot), "Restore single byte case");
        _assertSwappingWithoutGrant(
            abi.encodePacked(
                address(_dai),
                uint24(500),
                address(_usds),
                uint24(100),
                address(_asset)
            ),
            90e6 + 1
        );
    }

    // Scenarios: BLREX-P09, BLREX-P25.
    function test_whenSwapOutputFundsDeposit(
        bool inlineGrant_,
        bool multiple_,
        bytes calldata route_
    ) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _adapter.setOutput(address(_asset), 90e6 + 1);
        _expectSwap(route_, type(uint48).max);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _swapExactInput(route_);
        operations[1] = _deposit(90e6);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_dai), 100e18),
            operations,
            new IExecutor.Output[](0)
        );
        assertEq(
            abi.decode(results[0], (uint256)),
            90e6 + 1,
            "Swap result reflects actual receipt"
        );
        _assertSettled(90e6, 0);
        assertEq(
            _asset.balanceOf(_borrower),
            10_000e6 + 1,
            "Surplus returned after funding deposit"
        );
        assertEq(_dai.balanceOf(address(_adapter)), 100e18, "Adapter receives exact DAI input");
        assertEq(
            _dai.allowance(address(_executor), address(_adapter)),
            0,
            "Adapter approval cleared"
        );
    }

    // Scenarios: BLREX-T09, BLREX-T13, BLREX-T14.
    function test_whenExchangeCannotSettleAfterDeposit_reverts(
        bool inlineGrant_,
        bool multiple_,
        uint8 failure_
    ) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](2);
        funding[0] = IExecutor.Funding(address(_asset), 10e6);
        funding[1] = IExecutor.Funding(address(_dai), 100e18);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _deposit(10e6);
        operations[1] = _swapExactInput(hex"ab");

        uint8 failure = failure_ % 3;
        bytes memory reason;
        if (failure == 0) {
            _adapter.setOutput(address(_asset), 90e6 - 1);
            reason = abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientOutput.selector,
                90e6,
                90e6 - 1
            );
        } else if (failure == 1) {
            _migrator.setOutputShortfall(1);
            operations[1] = _convertDaiUsds(address(_dai), address(_usds), 100e18);
            reason = abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientOutput.selector,
                100e18,
                100e18 - 1
            );
        } else {
            reason = abi.encodeWithSelector(IBurnerLoansSwapAdapter.InvalidRoute.selector);
            vm.mockCallRevert(
                address(_adapter),
                abi.encodeWithSelector(IBurnerLoansSwapAdapter.swapExactInput.selector),
                reason
            );
        }
        vm.expectRevert(reason);
        _executeGrantMode(inlineGrant_, signed, funding, operations, new IExecutor.Output[](0));
        _assertSettled(0, 0);
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Earlier collateral funding restored");
        assertEq(_dai.balanceOf(_borrower), 100e18, "Exchange input restored");
        assertEq(_dai.balanceOf(address(_adapter)), 0, "Adapter retains no input");
        assertEq(_usds.totalSupply(), 0, "Unsettled conversion mint rolled back");
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    function _assertSwappingWithoutGrant(bytes memory route_, uint256 amountOut_) private {
        _blockAuthReads();
        _adapter.setOutput(address(_asset), amountOut_);
        _dai.mint(address(_executor), 10e18);
        uint48 deadline = type(uint48).max - 1;
        _expectSwap(route_, deadline);
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(_dai), 100e18),
            _single(_swapExactInput(route_)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            deadline
        );
        assertEq(
            abi.decode(results[0], (uint256)),
            amountOut_,
            "Reported result derived from actual receipt"
        );
        assertEq(_asset.balanceOf(_borrower), 10_000e6 + amountOut_, "Swap output refunded");
        assertEq(_dai.balanceOf(address(_executor)), 10e18, "Protected swap input retained");
        assertEq(
            _dai.allowance(address(_executor), address(_adapter)),
            0,
            "Adapter approval cleared"
        );
    }

    function _expectSwap(bytes memory route_, uint48 deadline_) private {
        vm.expectCall(
            address(_adapter),
            abi.encodeCall(
                IBurnerLoansSwapAdapter.swapExactInput,
                (
                    IBurnerLoansSwapAdapter.ExactInputParams(
                        address(_dai),
                        address(_asset),
                        100e18,
                        90e6,
                        deadline_,
                        route_
                    )
                )
            )
        );
    }

    // Scenarios: BLREX-T13.
    function test_givenReusableGrant_whenLaterSwapOutputIsShort_reverts()
        public
        givenReusableGrant
    {
        _adapter.setOutput(address(_asset), 90e6 - 1);
        _asset.mint(address(_executor), 90e6);
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](2);
        funding[0] = IExecutor.Funding(address(_dai), 100e18);
        funding[1] = IExecutor.Funding(address(_asset), 10e6);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _deposit(10e6);
        operations[1] = _swapExactInput(hex"ab");
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientOutput.selector,
                90e6,
                90e6 - 1
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            funding,
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_position().depositedCollateral, 0, "Earlier deposit restored");
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Collateral funding restored");
        assertEq(_dai.balanceOf(_borrower), 100e18, "DAI funding restored");
        assertEq(
            _asset.balanceOf(address(_executor)),
            90e6,
            "Protected output cannot mask shortfall"
        );
    }

    // Scenarios: BLREX-P35.
    function test_whenAdapterReturnsUnusedInputAndRouteToken() public {
        _adapter.setUnspent(1);
        _adapter.setOutput(address(_asset), 90e6);
        _adapter.setRouteRefund(address(_usds), 3e18);
        _usds.mint(address(_executor), 5e18);
        IExecutor.Output[] memory outputs = new IExecutor.Output[](1);
        outputs[0] = IExecutor.Output(address(_usds), 3e18);
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(_dai), 100e18),
            _single(_swapExactInput(hex"ab")),
            outputs,
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(abi.decode(results[0], (uint256)), 90e6, "Output meets the swap minimum");
        assertEq(_dai.balanceOf(_borrower), 1, "Unused input refunded to borrower");
        assertEq(_usds.balanceOf(_borrower), 3e18, "Intermediate refunded to borrower");
        assertEq(_usds.balanceOf(address(_executor)), 5e18, "Starting balance preserved");
        assertEq(
            _dai.allowance(address(_executor), address(_adapter)),
            0,
            "Adapter allowance cleared"
        );
    }

    // Scenarios: BLREX-T21.
    function test_whenAdapterDebitsAboveExactInputFunding_reverts() public {
        _dai.mint(address(_executor), 1);
        _adapter.setExcessDebit(1);
        _adapter.setOutput(address(_asset), 90e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_ExchangeInputLimitExceeded.selector,
                address(_dai),
                100e18,
                100e18 + 1
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_dai), 100e18),
            _single(_swapExactInput(hex"ab")),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_dai.balanceOf(_borrower), 100e18, "Funding restored");
        assertEq(_dai.balanceOf(address(_executor)), 1, "Starting balance restored");
    }

    // Scenarios: BLREX-N13.
    function test_whenExchangeBatchDeadlineHasPassed_reverts() public {
        uint48 deadline = 100;
        IExecutor.Operation[] memory operations = _single(
            _convertDaiUsds(address(_dai), address(_usds), 100e18)
        );
        vm.warp(deadline + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IExecutor.BurnerLoansComposites_BatchExpired.selector, deadline)
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_dai), 100e18),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            deadline
        );
        assertEq(_dai.balanceOf(_borrower), 100e18, "Expired exchange collects no input");
    }

    // Scenarios: BLREX-I05.
    function test_whenExchangeMinimumIsZero_reverts(bool convert_) public {
        IExecutor.Operation memory operation = convert_
            ? IExecutor.Operation(
                IExecutor.OperationKind.ConvertDaiUsds,
                abi.encode(IExecutor.ConvertDaiUsds(address(_dai), address(_usds), 100e18, 0))
            )
            : IExecutor.Operation(
                IExecutor.OperationKind.SwapExactInput,
                abi.encode(
                    IExecutor.SwapExactInput(address(_dai), address(_asset), 100e18, 0, hex"ab")
                )
            );
        vm.expectRevert(IExecutor.BurnerLoansComposites_InvalidExchangeAmount.selector);
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_dai), 100e18),
            _single(operation),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_dai.balanceOf(_borrower), 100e18, "Invalid minimum collects no funding");
    }

    // Scenarios: BLREX-I14.
    function test_whenExactInputTokenEndpointsMatch_reverts() public {
        IExecutor.Operation memory operation = IExecutor.Operation(
            IExecutor.OperationKind.SwapExactInput,
            abi.encode(
                IExecutor.SwapExactInput(address(_dai), address(_dai), 100e18, 90e18, hex"ab")
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InvalidExchangePair.selector,
                address(_dai),
                address(_dai)
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_dai), 100e18),
            _single(operation),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_dai.balanceOf(_borrower), 100e18, "Invalid pair collects no funding");
    }

    // Scenarios: BLREX-P26.
    function test_givenOlderDebt_whenExactOutputFundsExtension()
        public
        givenOlderDebt
        givenReusableGrant
    {
        _usds.mint(_borrower, 20e18);
        vm.prank(_borrower);
        _usds.approve(address(_executor), 20e18);
        _adapter.setOutput(address(_asset), 10e6);
        _adapter.setUnspent(2e18);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(uint256(7e6), uint256(0))
        );
        uint48 oldMaturity = _position().maturity;
        uint256 beforeAsset = _asset.balanceOf(_borrower);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _exactOutput(address(_usds), IExecutor.OutputTarget.Amount, 10e6, 12e18);
        operations[1] = IExecutor.Operation(
            IExecutor.OperationKind.Extend,
            abi.encode(IExecutor.Extend(address(_asset), 1, 10e6, address(0)))
        );
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(_usds), 20e18),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(abi.decode(results[0], (uint256)), 10e18, "Actual USDS spend");
        assertEq(_usds.balanceOf(_borrower), 10e18, "Unused USDS returned");
        assertEq(
            _asset.balanceOf(_borrower),
            beforeAsset + 3e6,
            "Purchased collateral less actual fee returned"
        );
        assertEq(_position().maturity, oldMaturity + 30 days, "Extension applies to caller");
        assertEq(_asset.allowance(address(_executor), address(_core)), 0, "Fee approval cleared");
    }

    // Scenarios: BLREX-P31.
    function test_whenExactOutputInputCapExceedsAvailableFunds() public {
        _dai.mint(address(_executor), 7e18);
        _usds.mint(address(_executor), 5e18);
        _adapter.setOutput(address(_asset), 7e6);
        _adapter.setUnspent(1e18);
        _adapter.setRouteRefund(address(_usds), 3e18);
        vm.expectCall(
            address(_adapter),
            abi.encodeCall(
                IBurnerLoansSwapAdapter.swapExactOutput,
                (
                    IBurnerLoansSwapAdapter.ExactOutputParams(
                        address(_dai),
                        address(_asset),
                        7e6,
                        4e18,
                        type(uint48).max,
                        hex"ab"
                    )
                )
            )
        );
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(_dai), 4e18),
            _single(_exactOutput(address(_dai), IExecutor.OutputTarget.Amount, 7e6, 10e18)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        // The cap is 4 DAI and the unused input is 1 DAI, so the adapter spends 3 DAI.
        assertEq(abi.decode(results[0], (uint256)), 3e18, "Report actual input debit");
        assertEq(_dai.balanceOf(_borrower), 97e18, "Unspent DAI returned");
        assertEq(_asset.balanceOf(_borrower), 10_007e6, "Exact collateral output returned");
        assertEq(_dai.balanceOf(address(_executor)), 7e18, "Protected DAI remains intact");
        assertEq(_usds.balanceOf(_borrower), 3e18, "Intermediate returned");
        assertEq(_usds.balanceOf(address(_executor)), 5e18, "Protected USDS remains intact");
        assertEq(
            _dai.allowance(address(_executor), address(_adapter)),
            0,
            "Clears adapter allowance"
        );
    }

    // Scenarios: BLREX-T20.
    function test_whenExactOutputInputBalanceIsEntirelyProtected_reverts() public {
        _dai.mint(address(_executor), 7e18);
        vm.expectCall(
            address(_adapter),
            abi.encodeWithSelector(IBurnerLoansSwapAdapter.swapExactOutput.selector),
            uint64(0)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientFunds.selector,
                address(_dai),
                1,
                0
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            new IExecutor.Funding[](0),
            _single(_exactOutput(address(_dai), IExecutor.OutputTarget.Amount, 7e6, 10e18)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_dai.balanceOf(address(_executor)), 7e18, "Protected DAI remains intact");
    }

    // Scenarios: BLREX-N13, BLREX-P27.
    function test_whenTargetBalanceBuysOnlyTheShortfall() public {
        uint256 beforeCollateral = _asset.balanceOf(_borrower);
        _asset.mint(address(_executor), 99e6);
        _adapter.setOutput(address(_asset), 7e6);
        _adapter.setUnspent(3e18);
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](2);
        funding[0] = IExecutor.Funding(address(_dai), 100e18);
        funding[1] = IExecutor.Funding(address(_asset), 3e6);
        uint48 deadline = type(uint48).max - 1;
        vm.expectCall(
            address(_adapter),
            abi.encodeCall(
                IBurnerLoansSwapAdapter.swapExactOutput,
                (
                    IBurnerLoansSwapAdapter.ExactOutputParams(
                        address(_dai),
                        address(_asset),
                        7e6,
                        10e18,
                        deadline,
                        hex"ab"
                    )
                )
            )
        );
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            funding,
            _single(_exactOutput(address(_dai), IExecutor.OutputTarget.Balance, 10e6, 10e18)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            deadline
        );
        assertEq(abi.decode(results[0], (uint256)), 7e18, "Report actual input debit");
        assertEq(
            _asset.balanceOf(address(_executor)),
            99e6,
            "Protected output excluded from target"
        );
        assertEq(_dai.balanceOf(_borrower), 93e18, "Unspent DAI returned");
        // The caller recovers 3e6 funded units and receives the 7e6 purchased units.
        assertEq(
            _asset.balanceOf(_borrower),
            beforeCollateral + 7e6,
            "Collateral surplus returned"
        );
    }

    // Scenarios: BLREX-P27.
    function test_whenTargetBalanceIsAlreadyMetSkipsAdapter() public {
        vm.expectCall(
            address(_adapter),
            abi.encodePacked(IBurnerLoansSwapAdapter.swapExactOutput.selector),
            0
        );
        uint256 beforeAsset = _asset.balanceOf(_borrower);
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(_asset), 10e6),
            _single(_exactOutput(address(_dai), IExecutor.OutputTarget.Balance, 10e6, 10e18)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(abi.decode(results[0], (uint256)), 0, "Satisfied target needs no exchange");
        assertEq(_asset.balanceOf(_borrower), beforeAsset, "Funded output asset returned");
    }

    // Scenarios: BLREX-T18.
    function test_whenExactOutputAdapterDeliversLessThanRequested_reverts() public {
        _adapter.setOutput(address(_asset), 10e6 - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientOutput.selector,
                10e6,
                10e6 - 1
            )
        );
        _executeFixedBuy();
        assertEq(_dai.balanceOf(_borrower), 100e18, "Wallet debit rolled back");
    }

    // Scenarios: BLREX-T18.
    function test_whenExactOutputAdapterDebitsMoreThanTheCap_reverts() public {
        _adapter.setOutput(address(_asset), 10e6);
        _adapter.setExcessDebit(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_ExchangeInputLimitExceeded.selector,
                address(_dai),
                10e18,
                10e18 + 1
            )
        );
        _executeFixedBuy();
        assertEq(_dai.balanceOf(_borrower), 100e18, "Wallet debit rolled back");
    }

    function _executeFixedBuy() private {
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_dai), 100e18),
            _single(_exactOutput(address(_dai), IExecutor.OutputTarget.Amount, 10e6, 10e18)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
    }

    function _exactOutput(
        address tokenIn_,
        IExecutor.OutputTarget target_,
        uint256 amountOut_,
        uint256 maxAmountIn_
    ) private view returns (IExecutor.Operation memory) {
        return
            IExecutor.Operation(
                IExecutor.OperationKind.SwapExactOutput,
                abi.encode(
                    IExecutor.SwapExactOutput(
                        tokenIn_,
                        address(_asset),
                        target_,
                        amountOut_,
                        maxAmountIn_,
                        hex"ab"
                    )
                )
            );
    }

    function _swapExactInput(
        bytes memory route_
    ) private view returns (IExecutor.Operation memory) {
        return
            IExecutor.Operation(
                IExecutor.OperationKind.SwapExactInput,
                abi.encode(
                    IExecutor.SwapExactInput(address(_dai), address(_asset), 100e18, 90e6, route_)
                )
            );
    }

    function _blockAuthReads() private {
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(IBurnerLoansCore.authConfig, ()),
            abi.encodeWithSelector(UnexpectedAuthRead.selector)
        );
    }
}
