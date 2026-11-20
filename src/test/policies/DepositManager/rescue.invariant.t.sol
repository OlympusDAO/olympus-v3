// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.27;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Contracts
import {DepositManagerRescueHandler} from "./fixtures/DepositManagerRescueHandler.sol";
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {Actions} from "src/Kernel.sol";
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

/// @notice Models two operators across idle and synchronous-vault custody during recovery sequences.
contract DepositManagerRescueInvariantTest is DepositManagerTest {
    MockERC20 internal _secondAsset;
    MockERC4626 internal _secondVault;
    address internal _secondOperator;
    DepositManagerRescueHandler internal _handler;

    function setUp() public override {
        super.setUp();
        _secondOperator = makeAddr("second operator");
        _secondAsset = new MockERC20("Second asset", "A2", 18);
        _secondVault = new MockERC4626(ERC20(address(_secondAsset)), "Second vault", "V2");
        MockERC20 firstStray = new MockERC20("First stray", "S1", 6);
        MockERC20 secondStray = new MockERC20("Second stray", "S2", 9);

        vm.startPrank(ADMIN);
        depositManager.enable("");
        rolesAdmin.grantRole("deposit_operator", _secondOperator);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "one");
        depositManager.setOperatorName(_secondOperator, "two");
        depositManager.addAsset(iAsset, IERC4626(address(0)), type(uint256).max, 0);
        depositManager.addAsset(
            IERC20(address(_secondAsset)),
            IERC4626(address(_secondVault)),
            type(uint256).max,
            0
        );
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, _secondOperator);
        depositManager.addAssetPeriod(
            IERC20(address(_secondAsset)),
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        depositManager.addAssetPeriod(
            IERC20(address(_secondAsset)),
            DEPOSIT_PERIOD,
            _secondOperator
        );
        DepositManagerConfigTimelock timelock = new DepositManagerConfigTimelock(
            kernel,
            IDepositManager(address(depositManager))
        );
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));
        depositManager.setConfigOperator(address(timelock));
        timelock.enable("");
        vm.stopPrank();

        _handler = new DepositManagerRescueHandler(
            depositManager,
            timelock,
            kernel,
            ADMIN,
            EMERGENCY,
            DEPOSIT_MANAGER_ADMIN,
            address(trsry),
            [DEPOSIT_OPERATOR, _secondOperator],
            [asset, _secondAsset],
            [firstStray, secondStray],
            IERC20(address(_secondVault))
        );
        // Seed all four modeled positions and both recovery routes, preventing a vacuous campaign.
        _handler.deposit(0, 0, 100);
        _handler.deposit(0, 1, 200);
        _handler.deposit(1, 0, 300);
        _handler.deposit(1, 1, 400);
        _handler.donate(0, 10);
        _handler.rescue(0, 0, address(0));
        _handler.donate(1, 20);
        _handler.queueRescue(1);
        _handler.executeRescue();

        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = _handler.deposit.selector;
        selectors[1] = _handler.withdraw.selector;
        selectors[2] = _handler.borrow.selector;
        selectors[3] = _handler.repay.selector;
        selectors[4] = _handler.donate.selector;
        selectors[5] = _handler.rescue.selector;
        selectors[6] = _handler.queueRescue.selector;
        selectors[7] = _handler.executeRescue.selector;
        selectors[8] = _handler.cancelRescue.selector;
        selectors[9] = _handler.setPolicyActive.selector;
        selectors[10] = _handler.setEnabled.selector;
        selectors[11] = _handler.setController.selector;
        selectors[12] = _handler.toggleRoute.selector;
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));
        targetContract(address(_handler));
    }

    // Scenarios: DM-RESCUE-P03.
    function invariant_rescuePreservesProtectedAccountingAndAuthority() public view {
        assertEq(
            _handler.violations(),
            0,
            "rescue, preview and queue preserve authority and protected accounting"
        );
        assertGt(_handler.successfulDirectRescues(), 0, "direct recovery was exercised");
        assertGt(_handler.successfulQueuedRescues(), 0, "queued recovery was exercised");
    }

    // Scenarios: DM-RESCUE-P03.
    function invariant_receiptPrincipalAndBorrowingMatchIndependentModels() public view {
        _assertAssetModel(0, iAsset, IERC20(address(0)));
        _assertAssetModel(1, IERC20(address(_secondAsset)), IERC20(address(_secondVault)));
    }

    function _assertAssetModel(uint256 index_, IERC20 token_, IERC20 shareToken_) private view {
        uint256 aggregatePrincipal;
        uint256 aggregateCustody;
        address[2] memory operators = [DEPOSIT_OPERATOR, _secondOperator];
        for (uint256 o; o < 2; ++o) {
            uint256 modeledPrincipal = _handler.principal(index_, o);
            uint256 modeledBorrowed = _handler.borrowed(index_, o);
            assertEq(
                depositManager.getOperatorLiabilities(token_, operators[o]),
                modeledPrincipal,
                "liability equals independently modeled receipt principal"
            );
            assertEq(
                depositManager.getBorrowedAmount(token_, operators[o]),
                modeledBorrowed,
                "debt equals independently modeled borrowing"
            );
            (uint256 shares, uint256 assets) = depositManager.getOperatorAssets(
                token_,
                operators[o]
            );
            // The fixture's idle and vault routes both convert one raw asset to one raw share.
            assertEq(
                shares + modeledBorrowed,
                modeledPrincipal,
                "custody plus borrowed principal backs receipts"
            );
            assertEq(assets, shares, "fixed one-to-one fixture valuation");
            uint256 receiptId = depositManager.getReceiptTokenId(
                token_,
                DEPOSIT_PERIOD,
                operators[o]
            );
            assertEq(
                receiptTokenManager.balanceOf(operators[o], receiptId),
                modeledPrincipal,
                "receipt balance matches principal model"
            );
            aggregatePrincipal += modeledPrincipal;
            aggregateCustody += shares;
        }
        assertEq(
            _assetDepositCapUtilization(token_),
            aggregatePrincipal,
            "aggregate utilization equals sum of modeled liabilities"
        );
        if (address(shareToken_) == address(0)) {
            assertEq(
                token_.balanceOf(address(depositManager)),
                aggregateCustody,
                "idle managed custody is never swept"
            );
        } else {
            assertEq(
                shareToken_.balanceOf(address(depositManager)),
                aggregateCustody,
                "managed share custody is never swept"
            );
        }
    }
}
