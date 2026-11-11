// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions} from "src/Kernel.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigRescueTest is BurnerLoansConfigTest {
    // Scenarios: BLCRE-A01, BLCRE-I01, BLCRE-N02.
    function test_givenAuthorizedCaller_whenCoreRescued(
        address caller_,
        bool admin_,
        bool operator_,
        uint256 amount_
    ) public {
        _grantConfigCaller(caller_, admin_, operator_);
        amount_ = bound(amount_, 1, type(uint256).max);
        MockERC20 token = new MockERC20("Rescue", "R", 6);
        token.mint(address(_core), amount_);
        uint256 payoutBalance = _asset.balanceOf(address(_payout));
        vm.prank(caller_);
        assertEq(
            _config.previewRescue(address(token), _recipient),
            amount_,
            "Preview uses Config's selected Core authority"
        );
        vm.expectEmit(address(_core));
        emit IBurnerLoansCore.AssetRescued(address(token), _recipient, amount_);
        vm.prank(caller_);
        _config.rescue(address(token), _recipient);
        assertEq(token.balanceOf(address(_core)), 0, "Entire direct Core balance rescued");
        assertEq(token.balanceOf(_recipient), amount_, "Recipient paid exact balance");
        assertEq(_asset.balanceOf(address(_payout)), payoutBalance, "Payout balances untouched");
    }

    // Scenarios: BLCRE-A02.
    function test_whenCallerIsUnauthorized_thenPreviewSucceedsAndRescueReverts(
        address caller_
    ) public {
        _excludeConfigCallers(caller_);
        _asset.mint(address(_core), 7);
        vm.prank(caller_);
        assertEq(
            _config.previewRescue(address(_asset), _recipient),
            7,
            "Any caller can preview recovery through Config"
        );
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.rescue, (address(_asset), _recipient)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: BLCRE-L01.
    function test_givenConfigInactiveEnabled_whenRescued_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        vm.expectRevert(_inactiveError(address(_config)));
        vm.prank(_configurationCaller);
        _config.previewRescue(address(_asset), _recipient);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (address(_asset), _recipient)),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCRE-L02.
    function test_givenConfigInactiveDisabled_whenRescued_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _config.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        vm.expectRevert(_inactiveError(address(_config)));
        vm.prank(_configurationCaller);
        _config.previewRescue(address(_asset), _recipient);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (address(_asset), _recipient)),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCRE-L03.
    function test_givenConfigActiveDisabled_whenRescued_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _config.disable("");
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(_configurationCaller);
        _config.previewRescue(address(_asset), _recipient);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (address(_asset), _recipient)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCRE-I02.
    function test_givenCoreDisabled_whenRescued(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _core.disable("");
        _asset.mint(address(_core), 1);
        vm.prank(_configurationCaller);
        assertEq(
            _config.previewRescue(address(_asset), _recipient),
            1,
            "Core pause permits recovery quotes"
        );
        vm.prank(_configurationCaller);
        _config.rescue(address(_asset), _recipient);
        assertEq(_asset.balanceOf(_recipient), 1, "Recovery available during pause");
        assertEq(_asset.balanceOf(address(_core)), 0, "No balance retained");
    }

    // Scenarios: BLCRE-I03, BLCRE-I04.
    function test_givenCoreInactive_whenRescued_reverts(
        bool enabled_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, false, enabled_);
        vm.expectRevert(_inactiveError(address(_core)));
        vm.prank(_configurationCaller);
        _config.previewRescue(address(_asset), _recipient);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (address(_asset), _recipient)),
            _inactiveError(address(_core))
        );
    }

    // Scenarios: BLCRE-I05.
    function test_whenTokenIsZero_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        address token = address(0);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (token, _recipient)),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidAsset.selector, token)
        );
    }

    // Scenarios: BLCRE-I06.
    function test_whenTokenIsNoCode_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        address token = makeAddr("noTokenCode");
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (token, _recipient)),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidAsset.selector, token)
        );
    }

    // Scenarios: BLCRE-I07.
    function test_whenDestinationIsZero_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        address destination = address(0);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (address(_asset), destination)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                destination
            )
        );
    }

    // Scenarios: BLCRE-I08.
    function test_whenDestinationIsCore_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        address destination = address(_core);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (address(_asset), destination)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                destination
            )
        );
    }

    // Scenarios: BLCRE-I09.
    function test_whenDestinationIsPayout_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        address destination = address(_payout);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (address(_asset), destination)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                destination
            )
        );
    }

    // Scenarios: BLCRE-I10.
    function test_whenDestinationIsToken_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        address destination = address(_asset);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (address(_asset), destination)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                destination
            )
        );
    }

    // Scenarios: BLCRE-I11.
    function test_whenDestinationIsConfig_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        address destination = address(_config);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (address(_asset), destination)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                destination
            )
        );
    }

    // Scenarios: BLCRE-I12.
    function test_whenDestinationIsKernel_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        address destination = address(_kernel);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (address(_asset), destination)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                destination
            )
        );
    }

    // Scenarios: BLCRE-N01.
    function test_givenZeroCoreBalance_whenRescued(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSelector(IERC20.transfer.selector),
            abi.encodeWithSignature("UnexpectedTransfer()")
        );
        vm.recordLogs();
        vm.prank(_configurationCaller);
        _config.rescue(address(_asset), _recipient);
        assertEq(vm.getRecordedLogs().length, 0, "Zero balance emits no rescue event");
        assertEq(_asset.balanceOf(address(_core)), 0, "Zero remains zero");
    }

    // Scenarios: BLCRE-N02.
    function test_whenMaximumBalanceRescued() public {
        MockERC20 token = new MockERC20("Maximum", "MAX", 6);
        token.mint(address(_core), type(uint256).max);
        vm.prank(_configurationCaller);
        _config.rescue(address(token), _recipient);
        assertEq(token.balanceOf(_recipient), type(uint256).max, "Full-width amount transferred");
        assertEq(token.balanceOf(address(_core)), 0, "Core fully drained");
    }

    // Scenarios: BLCRE-D01.
    function test_givenTokenTransferFails_whenRescued(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        MockRevertingTransferToken token = new MockRevertingTransferToken(6);
        token.mint(address(_core), 100);
        token.setTransferReverts(_recipient, true);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (address(token), _recipient)),
            abi.encodeWithSelector(MockRevertingTransferToken.TransferReverted.selector, _recipient)
        );
        assertEq(token.balanceOf(address(_core)), 100, "Core retains rejected transfer");
        assertEq(token.balanceOf(_recipient), 0, "Recipient receives nothing");
    }

    // Scenarios: BLCRE-D02.
    function test_givenCoreSelectsAnotherConfig_whenRescued_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _risk.setConfigOperator(_recipient);
        _core.setConfigOperator(_recipient);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.rescue, (address(_asset), _recipient)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: BLCRE-C01, BLCRE-D03.
    function test_givenRescueCallback_whenNestedRecoveryCaught(
        bool admin_,
        bool operator_,
        address tokenDeployer_
    ) public {
        ReentrantFeeToken token = _armConfigurationCallback(
            abi.encodeCall(_config.rescue, (address(_asset), _recipient)),
            admin_,
            operator_,
            tokenDeployer_
        );
        token.mint(address(_core), 100);
        _config.rescue(address(token), _recipient);
        assertFalse(token.callbackSucceeded(), "Nested recovery rejected");
        assertEq(
            token.callbackRevertData(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
            "Authorized nested call reaches guard"
        );
        assertEq(token.balanceOf(_recipient), 100, "Outer recovery paid once");
        assertEq(token.balanceOf(address(_core)), 0, "Only outer recovery consumed balance");
    }

    // Scenarios: BLCRE-C02, BLCRE-D03.
    function test_givenRescueCallback_whenNestedRecoveryPropagated(
        bool admin_,
        bool operator_,
        address tokenDeployer_
    ) public {
        ReentrantFeeToken token = _armConfigurationCallback(
            abi.encodeCall(_config.rescue, (address(_asset), _recipient)),
            admin_,
            operator_,
            tokenDeployer_
        );
        token.mint(address(_core), 100);
        token.setBubbleCallbackFailure(true);
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.rescue, (address(token), _recipient)),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
        );
        assertEq(token.balanceOf(address(_core)), 100, "Outer transfer rolled back");
        assertEq(token.balanceOf(_recipient), 0, "No partial recovery");
    }

    // Scenarios: BLCRE-A03.
    function test_givenConfigDeselected_whenAnyViewerQuotesRecovery(address viewer_) public {
        _core.setConfigOperator(makeAddr("anotherConfig"));
        _asset.mint(address(_core), 7);
        vm.prank(viewer_);
        assertEq(
            _config.previewRescue(address(_asset), _recipient),
            7,
            "economic quote does not authenticate its forwarding Config"
        );
        assertEq(_asset.balanceOf(address(_core)), 7, "quote transfers nothing");
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.rescue, (address(_asset), _recipient)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: BLCRE-L01, BLCRE-L02.
    function test_givenInactive_whenUnauthorizedAndInvalid_reverts(
        address caller_,
        bool enabled_
    ) public {
        _excludeConfigCallers(caller_);
        if (!enabled_) _config.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_config)
            )
        );
        vm.prank(caller_);
        _config.rescue(address(0), address(0));
    }
}
