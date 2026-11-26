// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IERC20Errors} from "@openzeppelin-5.7.0/interfaces/draft-IERC6093.sol";
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {ISwapRouter} from "@uniswap-v3-periphery-1.4.2/interfaces/ISwapRouter.sol";
import {IBurnerLoansSwapAdapter} from "src/periphery/interfaces/IBurnerLoansSwapAdapter.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {BurnerLoansUniswapV3Adapter} from "src/periphery/adapters/BurnerLoansUniswapV3Adapter.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC20FeeOnTransfer} from "src/test/mocks/MockERC20FeeOnTransfer.sol";
import {CoreCallbackToken} from "src/test/policies/BurnerLoansCore/fixtures/CoreCallbackToken.sol";

contract BurnerLoansUniswapV3AdapterSwapTest is Test {
    MockERC20 internal _input;
    MockERC20 internal _intermediate;
    MockERC20 internal _output;
    BurnerLoansUniswapV3Adapter internal _adapter;
    address internal _caller;
    uint256 internal _spend;
    uint256 internal _protectedInputDebit;
    uint256 internal _deliver;
    uint256 internal _intermediateSpend;
    bool internal _reenter;
    bool internal _propagateRouterReentry;
    bytes4 internal _nestedError;

    function setUp() public {
        _input = new MockERC20("Input", "IN", 18);
        _intermediate = new MockERC20("Intermediate", "MID", 6);
        _output = new MockERC20("Output", "OUT", 6);
        _caller = makeAddr("caller");
        _adapter = new BurnerLoansUniswapV3Adapter(address(this));
        _fundInput(_caller, 100e18);
        _spend = 100e18;
        _deliver = 90e6;
    }

    // Scenarios: BLRSW-P03.
    function test_whenConstructedAdvertisesSwapInterface() public view {
        IERC165 adapter = IERC165(address(_adapter));
        assertTrue(
            adapter.supportsInterface(type(IBurnerLoansSwapAdapter).interfaceId),
            "Advertises the swap interface"
        );
        assertTrue(adapter.supportsInterface(type(IERC165).interfaceId), "Advertises ERC165");
        assertFalse(adapter.supportsInterface(0xffffffff), "Rejects the invalid interface ID");
    }

    // Scenarios: BLRSW-P08.
    function test_whenReadingRouteIntermediates() public view {
        assertEq(
            _adapter.intermediateTokens(_request().route).length,
            0,
            "Single hop has no intermediate"
        );
        bytes memory route = abi.encodePacked(
            address(_input),
            uint24(500),
            address(_intermediate),
            uint24(100),
            address(_input),
            uint24(3000),
            address(_output)
        );
        address[] memory tokens = _adapter.intermediateTokens(route);
        assertEq(tokens.length, 2, "Both intermediate positions listed");
        assertEq(tokens[0], address(_intermediate), "First intermediate in route order");
        assertEq(tokens[1], address(_input), "Repeated endpoint still listed as intermediate");
    }

    // Scenarios: BLRSW-P01, BLRSW-N02, BLRSW-N03, BLRSW-T02.
    function test_whenValidPath(address caller_) public {
        vm.assume(
            caller_ != address(0) && caller_ != address(this) && caller_ != address(_adapter)
        );
        if (caller_ != _caller) _fundInput(caller_, 100e18);
        _caller = caller_;
        IBurnerLoansSwapAdapter.ExactInputParams memory request = _request();
        _input.mint(address(_adapter), 7e18);
        _output.mint(address(_adapter), 8e6);
        vm.expectCall(
            address(this),
            abi.encodeCall(
                ISwapRouter.exactInput,
                (
                    ISwapRouter.ExactInputParams(
                        request.route,
                        address(_adapter),
                        request.deadline,
                        100e18,
                        90e6
                    )
                )
            )
        );
        vm.prank(_caller);
        assertEq(_adapter.swapExactInput(request), 90e6, "Actual output returned");
        assertEq(_output.balanceOf(_caller), 90e6, "Caller receives output");
        assertEq(_input.balanceOf(_caller), 0, "Exact input spent");
        assertEq(_input.balanceOf(address(_adapter)), 7e18, "Existing input preserved");
        assertEq(_output.balanceOf(address(_adapter)), 8e6, "Existing output preserved");
        assertEq(_input.allowance(address(_adapter), address(this)), 0, "Router approval cleared");
    }

    // Scenarios: BLRSW-A01.
    function test_whenCallerIsZero_reverts() public {
        IBurnerLoansSwapAdapter.ExactInputParams memory request = _request();
        _input.mint(address(_adapter), 7e18);
        _output.mint(address(_adapter), 8e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(_adapter),
                uint256(0),
                request.amountIn
            )
        );
        vm.prank(address(0));
        _adapter.swapExactInput(request);
        assertEq(_output.balanceOf(address(0)), 0, "Zero caller receives no output");
        assertEq(_input.balanceOf(address(_adapter)), 7e18, "Existing input preserved");
        assertEq(_output.balanceOf(address(_adapter)), 8e6, "Existing output preserved");
        assertEq(
            _input.allowance(address(_adapter), address(this)),
            0,
            "Router approval unchanged"
        );
    }

    // Scenarios: BLRSW-I02.
    function test_whenPathIsTooShort_reverts(uint8 length_) public {
        IBurnerLoansSwapAdapter.ExactInputParams memory request = _request();
        request.route = new bytes(bound(length_, 0, 42));
        vm.expectRevert(IBurnerLoansSwapAdapter.InvalidRoute.selector);
        _adapter.intermediateTokens(request.route);
        vm.expectRevert(IBurnerLoansSwapAdapter.InvalidRoute.selector);
        vm.prank(_caller);
        _adapter.swapExactInput(request);
    }

    // Scenarios: BLRSW-I02.
    function test_whenPathHasExtraBytesBetweenValidEndpoints_reverts(uint8 extra_) public {
        IBurnerLoansSwapAdapter.ExactInputParams memory request = _request();
        request.route = abi.encodePacked(
            address(_input),
            uint24(500),
            new bytes(bound(extra_, 1, 22)),
            address(_output)
        );
        vm.expectRevert(IBurnerLoansSwapAdapter.InvalidRoute.selector);
        _adapter.intermediateTokens(request.route);
        vm.expectRevert(IBurnerLoansSwapAdapter.InvalidRoute.selector);
        vm.prank(_caller);
        _adapter.swapExactInput(request);
        assertEq(_input.balanceOf(_caller), 100e18, "Invalid path collects no input");
    }

    // Scenarios: BLRSW-I04.
    function test_whenRouterHasNoCode_reverts(bool zero_) public {
        address candidate = zero_ ? address(0) : _caller;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansSwapAdapter.InvalidRouter.selector, candidate)
        );
        new BurnerLoansUniswapV3Adapter(candidate);
    }

    // Scenarios: BLRSW-I03.
    function test_whenPathEndpointDiffers_reverts(bool first_) public {
        IBurnerLoansSwapAdapter.ExactInputParams memory request = _request();
        request.route = abi.encodePacked(
            first_ ? address(2) : address(_input),
            uint24(500),
            first_ ? address(_output) : address(2)
        );
        vm.expectRevert(IBurnerLoansSwapAdapter.InvalidRoute.selector);
        vm.prank(_caller);
        _adapter.swapExactInput(request);
    }

    // Scenarios: BLRSW-N02, BLRSW-T01.
    function test_whenRouterReportsOutputAboveReceipt_reverts() public {
        _deliver = 90e6 - 1;
        _output.mint(address(_adapter), 90e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSwapAdapter.InsufficientOutput.selector,
                90e6,
                90e6 - 1
            )
        );
        vm.prank(_caller);
        _adapter.swapExactInput(_request());
        assertEq(_input.balanceOf(_caller), 100e18, "Caller input restored");
        assertEq(_output.balanceOf(address(_adapter)), 90e6, "Existing output restored");
    }

    // Scenarios: BLRSW-T08.
    function test_whenOutputTransferFeeReducesCallerReceiptBelowMinimum_reverts(
        bool exactOutput_
    ) public {
        MockERC20FeeOnTransfer output = new MockERC20FeeOnTransfer("Taxed", "TAX", makeAddr("fee"));
        IBurnerLoansSwapAdapter.ExactInputParams memory inputRequest = _request();
        inputRequest.tokenOut = address(output);
        inputRequest.route = abi.encodePacked(address(_input), uint24(500), address(output));
        IBurnerLoansSwapAdapter.ExactOutputParams memory outputRequest = _exactOutputRequest();
        outputRequest.tokenOut = address(output);
        outputRequest.route = abi.encodePacked(address(output), uint24(500), address(_input));

        // The token deducts 10% from the 90e6 sent, so the caller receives only 81e6.
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansSwapAdapter.InsufficientOutput.selector, 90e6, 81e6)
        );
        vm.prank(_caller);
        if (exactOutput_) _adapter.swapExactOutput(outputRequest);
        else _adapter.swapExactInput(inputRequest);

        assertEq(_input.balanceOf(_caller), 100e18, "Caller input restored");
        assertEq(output.balanceOf(_caller), 0, "Output transfer rolled back");
    }

    // Scenarios: BLRSW-P05.
    function test_whenRouterSpendsLessThanFundedInput() public {
        _spend = 100e18 - 1;
        vm.prank(_caller);
        assertEq(_adapter.swapExactInput(_request()), 90e6, "Output meets the minimum");
        assertEq(_input.balanceOf(_caller), 1, "Unspent input refunded");
        assertEq(_input.balanceOf(address(_adapter)), 0, "No input retained");
    }

    // Scenarios: BLRSW-P07.
    function test_whenRouteLeavesIntermediateRemainder() public {
        _intermediateSpend = 50e6;
        _intermediate.mint(address(_adapter), 7e6);
        _intermediate.mint(address(this), 8e6);
        IBurnerLoansSwapAdapter.ExactInputParams memory request = _request();
        bytes memory firstHop = abi.encodePacked(
            address(_input),
            uint24(500),
            address(_intermediate)
        );
        bytes memory lastHop = abi.encodePacked(
            address(_intermediate),
            uint24(100),
            address(_output)
        );
        request.route = abi.encodePacked(firstHop, uint24(100), address(_output));

        vm.expectCall(
            address(this),
            abi.encodeCall(
                ISwapRouter.exactInput,
                (
                    ISwapRouter.ExactInputParams(
                        lastHop,
                        address(_adapter),
                        request.deadline,
                        60e6,
                        90e6
                    )
                )
            )
        );
        vm.prank(_caller);
        assertEq(_adapter.swapExactInput(request), 90e6, "Final output meets the minimum");
        assertEq(_intermediate.balanceOf(_caller), 10e6, "Unused intermediate refunded");
        assertEq(
            _intermediate.balanceOf(address(_adapter)),
            7e6,
            "Adapter starting balance preserved"
        );
        assertEq(
            _intermediate.balanceOf(address(this)),
            58e6,
            "Router receives only the pool payment"
        );
        assertEq(
            _intermediate.allowance(address(_adapter), address(this)),
            0,
            "Intermediate approval cleared"
        );
    }

    // Scenarios: BLRSW-N03.
    function test_whenDeadlineHasPassed_reverts() public {
        IBurnerLoansSwapAdapter.ExactInputParams memory request = _request();
        vm.warp(request.deadline + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSwapAdapter.DeadlineExpired.selector,
                request.deadline
            )
        );
        vm.prank(_caller);
        _adapter.swapExactInput(request);
    }

    // Scenarios: BLRSW-C01.
    function test_whenRouterAttemptsNestedSwap() public {
        _fundInput(address(this), 100e18);
        _reenter = true;
        vm.prank(_caller);
        assertEq(_adapter.swapExactInput(_request()), 90e6, "Outer swap settles once");
        assertEq(
            _nestedError,
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "Nested request hits shared adapter lock"
        );
        assertEq(_output.balanceOf(address(this)), 0, "Nested caller receives no proceeds");
        assertEq(_output.balanceOf(_caller), 90e6, "Outer caller receives exact proceeds");
    }

    // Scenarios: BLRSW-C01.
    function test_whenRouterPropagatesNestedSwap_reverts() public {
        _fundInput(address(this), 100e18);
        _reenter = true;
        _propagateRouterReentry = true;
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vm.prank(_caller);
        _adapter.swapExactInput(_request());
        _assertSwapRestored();
    }

    // Scenarios: BLRSW-C01.
    function test_whenTokenCatchesNestedSwap(bool isInput_) public {
        CoreCallbackToken callbackToken = _armTokenCallback(isInput_, false);
        vm.prank(_caller);
        assertEq(_adapter.swapExactInput(_request()), 90e6, "Outer swap settles once");
        assertEq(
            callbackToken.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "Token callback reaches the shared guard"
        );
        assertEq(_output.balanceOf(address(callbackToken)), 0, "Nested caller receives no output");
        assertEq(_output.balanceOf(_caller), 90e6, "Outer caller receives actual output");
        assertEq(_input.balanceOf(address(this)), 100e18, "Router takes one input");
    }

    // Scenarios: BLRSW-C01, BLRSW-T03.
    function test_whenTokenPropagatesNestedSwap_reverts(bool isInput_) public {
        _armTokenCallback(isInput_, true);
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vm.prank(_caller);
        _adapter.swapExactInput(_request());
        _assertSwapRestored();
    }

    // Scenarios: BLRSW-I01.
    function test_whenEndpointIsZero_reverts(bool zeroInput_) public {
        IBurnerLoansSwapAdapter.ExactInputParams memory p = _request();
        if (zeroInput_) p.tokenIn = address(0);
        else p.tokenOut = address(0);
        _expectInvalidPair(p);
    }

    // Scenarios: BLRSW-I01.
    function test_whenEndpointsAreIdentical_reverts() public {
        IBurnerLoansSwapAdapter.ExactInputParams memory p = _request();
        p.tokenOut = p.tokenIn;
        _expectInvalidPair(p);
    }

    // Scenarios: BLRSW-N01.
    function test_whenInputIsZero_reverts() public {
        IBurnerLoansSwapAdapter.ExactInputParams memory p = _request();
        p.amountIn = 0;
        vm.expectRevert(IBurnerLoansSwapAdapter.InvalidAmount.selector);
        vm.prank(_caller);
        _adapter.swapExactInput(p);
    }

    // Scenarios: BLRSW-N01.
    function test_whenExactInputIsFunded(uint256 amount_) public {
        _assertExactInput(bound(amount_, 1, type(uint256).max));
    }

    // Scenarios: BLRSW-N01.
    function test_whenExactInputAtBoundaryIsFunded() public {
        uint256 snapshot = vm.snapshotState();
        _assertExactInput(1);
        assertTrue(vm.revertToState(snapshot), "Restore raw-unit input case");
        _assertExactInput(type(uint256).max);
    }

    // Scenarios: BLRSW-N01.
    function test_whenInputAllowanceIsShort_reverts() public {
        vm.prank(_caller);
        assertTrue(_input.approve(address(_adapter), 100e18 - 1), "Set one-unit short allowance");
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(_adapter),
                100e18 - 1,
                100e18
            )
        );
        vm.prank(_caller);
        _adapter.swapExactInput(_request());
        _assertSwapRestored();
    }

    // Scenarios: BLRSW-N01.
    function test_whenWalletInputIsShort_reverts() public {
        _input.burn(_caller, 1);
        _input.mint(address(_adapter), 7);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                _caller,
                100e18 - 1,
                100e18
            )
        );
        vm.prank(_caller);
        _adapter.swapExactInput(_request());
        assertEq(_input.balanceOf(address(_adapter)), 7, "Protected tokens cannot cover shortfall");
        assertEq(_input.balanceOf(_caller), 100e18 - 1, "Caller funds restored");
    }

    // Scenarios: BLRSW-N02.
    function test_whenMinimumIsZero_reverts() public {
        IBurnerLoansSwapAdapter.ExactInputParams memory p = _request();
        p.minAmountOut = 0;
        vm.expectRevert(IBurnerLoansSwapAdapter.InvalidAmount.selector);
        vm.prank(_caller);
        _adapter.swapExactInput(p);
    }

    // Scenarios: BLRSW-N02.
    function test_whenMinimumFitsOutput(uint256 minimum_) public {
        _assertMinimum(bound(minimum_, 1, 90e6));
    }

    // Scenarios: BLRSW-N02.
    function test_whenMinimumFitsOutputBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        _assertMinimum(1);
        assertTrue(vm.revertToState(snapshot), "Restore one-unit minimum");
        _assertMinimum(90e6 - 1);
    }

    // Scenarios: BLRSW-N02.
    function test_whenMinimumIsAboveOutput_reverts(uint256 minimum_) public {
        _expectShortOutput(bound(minimum_, 90e6 + 1, type(uint256).max));
    }

    // Scenarios: BLRSW-N02.
    function test_whenMinimumAtFailureBoundary_reverts() public {
        _expectShortOutput(90e6 + 1);
        _expectShortOutput(type(uint256).max);
    }

    // Scenarios: BLRSW-N03.
    function test_whenDeadlineIsInFuture(uint256 deadline_) public {
        _assertDeadline(bound(deadline_, vm.getBlockTimestamp() + 1, type(uint256).max));
    }

    // Scenarios: BLRSW-N03.
    function test_whenDeadlineIsAtFutureBoundary() public {
        uint256 snapshot = vm.snapshotState();
        _assertDeadline(vm.getBlockTimestamp() + 1);
        assertTrue(vm.revertToState(snapshot), "Restore adjacent deadline");
        _assertDeadline(type(uint256).max);
    }

    function _armTokenCallback(
        bool isInput_,
        bool bubble_
    ) private returns (CoreCallbackToken token) {
        token = new CoreCallbackToken();
        if (isInput_) {
            _input = token;
            _fundInput(_caller, 100e18);
        } else {
            _output = token;
        }
        _fundInput(address(token), 100e18);
        token.setCallbackFrom(
            address(_adapter),
            address(_adapter),
            abi.encodeCall(_adapter.swapExactInput, (_request()))
        );
        token.setCallbackPhases(!isInput_, isInput_);
        token.setBubbleCallbackFailure(bubble_);
    }

    function _fundInput(address account_, uint256 amount_) private {
        _input.mint(account_, amount_);
        vm.prank(account_);
        assertTrue(_input.approve(address(_adapter), amount_), "Funded account approves adapter");
    }

    function _assertSwapRestored() private view {
        assertEq(_input.balanceOf(_caller), 100e18, "Caller input restored");
        assertEq(_output.balanceOf(_caller), 0, "No caller output committed");
        assertEq(_input.balanceOf(address(_adapter)), 0, "No input retained");
        assertEq(_output.balanceOf(address(_adapter)), 0, "No output retained");
        assertEq(
            _input.allowance(address(_adapter), address(this)),
            0,
            "No router allowance survives"
        );
    }

    function _expectInvalidPair(IBurnerLoansSwapAdapter.ExactInputParams memory p_) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSwapAdapter.InvalidTokenPair.selector,
                p_.tokenIn,
                p_.tokenOut
            )
        );
        vm.prank(_caller);
        _adapter.swapExactInput(p_);
        _assertSwapRestored();
    }

    function _assertExactInput(uint256 amount_) private {
        _input.burn(_caller, 100e18);
        _fundInput(_caller, amount_);
        _spend = amount_;
        IBurnerLoansSwapAdapter.ExactInputParams memory p = _request();
        p.amountIn = amount_;
        vm.prank(_caller);
        assertEq(_adapter.swapExactInput(p), 90e6, "Actual output returned");
        assertEq(_input.balanceOf(_caller), 0, "Exact requested input consumed");
        assertEq(_input.balanceOf(address(this)), amount_, "Router received exact input");
        assertEq(_input.allowance(address(_adapter), address(this)), 0, "Exact allowance cleared");
    }

    function _assertMinimum(uint256 minimum_) private {
        IBurnerLoansSwapAdapter.ExactInputParams memory p = _request();
        p.minAmountOut = minimum_;
        vm.prank(_caller);
        assertEq(_adapter.swapExactInput(p), 90e6, "Actual receipt exceeds or equals minimum");
    }

    function _expectShortOutput(uint256 minimum_) private {
        IBurnerLoansSwapAdapter.ExactInputParams memory p = _request();
        p.minAmountOut = minimum_;
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSwapAdapter.InsufficientOutput.selector,
                minimum_,
                90e6
            )
        );
        vm.prank(_caller);
        _adapter.swapExactInput(p);
        _assertSwapRestored();
    }

    function _assertDeadline(uint256 deadline_) private {
        IBurnerLoansSwapAdapter.ExactInputParams memory p = _request();
        p.deadline = deadline_;
        vm.prank(_caller);
        assertEq(_adapter.swapExactInput(p), 90e6, "Future deadline accepts the swap");
    }

    function _request() private view returns (IBurnerLoansSwapAdapter.ExactInputParams memory) {
        return
            IBurnerLoansSwapAdapter.ExactInputParams(
                address(_input),
                address(_output),
                100e18,
                90e6,
                vm.getBlockTimestamp(),
                abi.encodePacked(address(_input), uint24(500), address(_output))
            );
    }

    // Scenarios: BLRSW-P04.
    function test_whenExactOutputUsesReversePathAndRefundsUnusedInput(bool multihop_) public {
        _spend = 80e18;
        _input.mint(address(_adapter), 7e18);
        _output.mint(address(_adapter), 8e6);
        IBurnerLoansSwapAdapter.ExactOutputParams memory request = _exactOutputRequest();
        if (multihop_) {
            _intermediate.mint(address(_adapter), 5e6);
            request.route = abi.encodePacked(
                address(_output),
                uint24(100),
                address(_intermediate),
                uint24(500),
                address(_input)
            );
        }
        vm.expectCall(
            address(this),
            abi.encodeCall(
                ISwapRouter.exactOutput,
                (
                    ISwapRouter.ExactOutputParams(
                        request.route,
                        address(_adapter),
                        request.deadline,
                        90e6,
                        100e18
                    )
                )
            )
        );
        vm.prank(_caller);
        assertEq(_adapter.swapExactOutput(request), 80e18, "Report actual input spend");
        assertEq(_output.balanceOf(_caller), 90e6, "Exact output received");
        assertEq(_input.balanceOf(_caller), 20e18, "Unused input returned");
        assertEq(_input.balanceOf(address(_adapter)), 7e18, "Input dust protected");
        assertEq(_output.balanceOf(address(_adapter)), 8e6, "Output dust protected");
        if (multihop_) {
            assertEq(_intermediate.balanceOf(_caller), 3e6, "Route remainder returned");
            assertEq(_intermediate.balanceOf(address(_adapter)), 5e6, "Early balance protected");
        }
        assertEq(_input.allowance(address(_adapter), address(this)), 0, "Router approval cleared");
    }

    // Scenarios: BLRSW-I05.
    function test_whenExactOutputUsesForwardPath_reverts() public {
        IBurnerLoansSwapAdapter.ExactOutputParams memory request = _exactOutputRequest();
        request.route = _request().route;
        vm.expectRevert(IBurnerLoansSwapAdapter.InvalidRoute.selector);
        vm.prank(_caller);
        _adapter.swapExactOutput(request);
        _assertSwapRestored();
    }

    // Scenarios: BLRSW-T05.
    function test_whenExactOutputReceiptIsShort_reverts() public {
        _deliver = 90e6 - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSwapAdapter.InsufficientOutput.selector,
                90e6,
                _deliver
            )
        );
        vm.prank(_caller);
        _adapter.swapExactOutput(_exactOutputRequest());
        _assertSwapRestored();
    }

    // Scenarios: BLRSW-N04.
    function test_whenExactOutputIncludesZeroAmount_reverts(bool zeroOutput_) public {
        IBurnerLoansSwapAdapter.ExactOutputParams memory request = _exactOutputRequest();
        if (zeroOutput_) request.amountOut = 0;
        else request.maxAmountIn = 0;
        vm.expectRevert(IBurnerLoansSwapAdapter.InvalidAmount.selector);
        vm.prank(_caller);
        _adapter.swapExactOutput(request);
        _assertSwapRestored();
    }

    // Scenarios: BLRSW-N04.
    function test_whenExactOutputUsesMaximumAmounts() public {
        IBurnerLoansSwapAdapter.ExactOutputParams memory request = _exactOutputRequest();
        request.amountOut = type(uint256).max;
        request.maxAmountIn = type(uint256).max;
        request.deadline = type(uint256).max;
        _input.mint(_caller, type(uint256).max - 100e18);
        vm.prank(_caller);
        _input.approve(address(_adapter), type(uint256).max);
        _spend = 1;
        _deliver = type(uint256).max;
        vm.prank(_caller);
        assertEq(_adapter.swapExactOutput(request), 1, "Actual debit is one raw input unit");
        assertEq(_input.balanceOf(_caller), type(uint256).max - 1, "Unused input returned");
        assertEq(_output.balanceOf(_caller), type(uint256).max, "Full output delivered");
    }

    // Scenarios: BLRSW-T06.
    function test_whenExactOutputSpendsProtectedInput_reverts() public {
        _input.mint(address(_adapter), 1);
        _protectedInputDebit = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSwapAdapter.InputLimitExceeded.selector,
                100e18,
                100e18 + 1
            )
        );
        vm.prank(_caller);
        _adapter.swapExactOutput(_exactOutputRequest());
        assertEq(_input.balanceOf(_caller), 100e18, "Caller input restored");
        assertEq(_input.balanceOf(address(_adapter)), 1, "Starting input restored");
        assertEq(_output.balanceOf(_caller), 0, "No output committed");
        assertEq(
            _input.allowance(address(_adapter), address(this)),
            0,
            "Router allowance restored"
        );
    }

    function _exactOutputRequest()
        private
        view
        returns (IBurnerLoansSwapAdapter.ExactOutputParams memory)
    {
        return
            IBurnerLoansSwapAdapter.ExactOutputParams(
                address(_input),
                address(_output),
                90e6,
                100e18,
                vm.getBlockTimestamp(),
                abi.encodePacked(address(_output), uint24(500), address(_input))
            );
    }

    function exactOutput(
        ISwapRouter.ExactOutputParams calldata params_
    ) external returns (uint256) {
        assertEq(msg.sender, address(_adapter), "Router called by configured adapter");
        assertTrue(_input.transferFrom(msg.sender, address(this), _spend), "Router pulls input");
        if (_protectedInputDebit != 0) _input.burn(msg.sender, _protectedInputDebit);
        MockERC20(address(bytes20(params_.path[:20]))).mint(params_.recipient, _deliver);
        if (params_.path.length > 43) _intermediate.mint(params_.recipient, 3e6);
        return 0;
    }

    /// @dev Acts as a controlled router. Output is minted independently of its reported result.
    function exactInput(ISwapRouter.ExactInputParams calldata params_) external returns (uint256) {
        assertEq(msg.sender, address(_adapter), "Router called by configured adapter");
        if (_reenter) {
            _reenter = false;
            if (_propagateRouterReentry) {
                _adapter.swapExactInput(_request());
                fail("Nested adapter call must fail");
            }
            try _adapter.swapExactInput(_request()) returns (uint256) {
                fail("Nested adapter call must fail");
            } catch (bytes memory reason) {
                _nestedError = bytes4(reason);
            }
        }
        bytes calldata path = params_.path;
        address tokenIn = address(bytes20(path[:20]));
        address tokenOut = address(bytes20(path[23:43]));
        uint256 spend = tokenIn == address(_intermediate) ? _intermediateSpend : _spend;
        assertTrue(
            MockERC20(tokenIn).transferFrom(msg.sender, address(this), spend),
            "Router pulls approved input"
        );
        MockERC20(tokenOut).mint(
            params_.recipient,
            tokenOut == address(_intermediate) ? 60e6 : _deliver
        );
        return type(uint256).max;
    }
}
