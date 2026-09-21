// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Scenario-specific literals remain inline for auditability. The caller fixture, handler, and
// invariant contract are tightly coupled to this suite and clearer when kept together. Setup calls
// and tuple destructuring intentionally ignore return values that the invariants do not use. Exact
// equality distinguishes the zero-output path whose custody behavior the invariant measures.
// forge-lint: disable-start(incorrect-strict-equality, literal-instead-of-constant, multi-contract-file, unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";

// Contracts
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";
import {MockERC7540ExternalShareToken, MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";

contract DepositManagerUnauthorizedConfigCaller {
    function attempt(
        IDepositManager depositManager_,
        bytes calldata callData_
    ) external returns (bool success) {
        /// Reason: the invariant must preserve the arbitrary selector and caller boundary.
        /// forge-lint: disable-next-line(low-level-calls)
        (success, ) = address(depositManager_).call(callData_);
    }
}

contract DepositManagerShareHandler {
    IDepositManagerV1_1 internal immutable _DEPOSIT_MANAGER;
    IReceiptTokenManager internal immutable _RECEIPT_TOKEN_MANAGER;
    MockERC20 internal immutable _ASSET;
    MockERC7540ExternalShareVault internal immutable _VAULT;
    MockERC7540ExternalShareToken internal immutable _SHARE_TOKEN;
    uint8 internal immutable _DEPOSIT_PERIOD;
    address internal immutable _RECIPIENT;
    DepositManagerUnauthorizedConfigCaller internal immutable _UNAUTHORIZED_CALLER;

    uint256 public overDeliveryViolations;
    uint256 public zeroOutputShareMutationViolations;
    uint256 public unauthorizedConfigSuccesses;
    uint256 public disabledDepositSuccesses;
    uint256 public disabledServicingFailures;
    uint256 public disabledRepaymentFailures;
    uint256 public disabledDefaultFailures;

    constructor(
        IDepositManagerV1_1 depositManager_,
        IReceiptTokenManager receiptTokenManager_,
        MockERC20 asset_,
        MockERC7540ExternalShareVault vault_,
        MockERC7540ExternalShareToken shareToken_,
        uint8 depositPeriod_,
        // The invariant suite constructs the handler with a nonzero makeAddr recipient.
        // forge-lint: disable-next-line(missing-zero-check)
        address recipient_
    ) {
        _DEPOSIT_MANAGER = depositManager_;
        _RECEIPT_TOKEN_MANAGER = receiptTokenManager_;
        _ASSET = asset_;
        _VAULT = vault_;
        _SHARE_TOKEN = shareToken_;
        _DEPOSIT_PERIOD = depositPeriod_;
        _RECIPIENT = recipient_;
        _UNAUTHORIZED_CALLER = new DepositManagerUnauthorizedConfigCaller();
    }

    function deposit(uint128 amountSeed_) external {
        uint256 amount = _bound(amountSeed_, 1, 1_000_000e18);
        _ASSET.mint(address(this), amount);
        _ASSET.approve(address(_DEPOSIT_MANAGER), amount);
        bool periodEnabled = _assetPeriodEnabled();
        try
            _DEPOSIT_MANAGER.deposit(
                IDepositManager.DepositParams({
                    asset: IERC20(address(_ASSET)),
                    depositPeriod: _DEPOSIT_PERIOD,
                    depositor: address(this),
                    amount: amount,
                    shouldWrap: false
                })
            )
        returns (uint256 receiptTokenId, uint256) {
            if (!periodEnabled) ++disabledDepositSuccesses;
            _RECEIPT_TOKEN_MANAGER.approve(
                address(_DEPOSIT_MANAGER),
                receiptTokenId,
                _RECEIPT_TOKEN_MANAGER.balanceOf(address(this), receiptTokenId)
            );
        } catch {}
    }

    function withdrawAsShares(uint128 amountSeed_) external {
        // Exercise voluntary withdrawals only when custody has not been reduced by borrowing.
        // Repayment and default exercise the outstanding-borrowing lifecycle separately below.
        if (_DEPOSIT_MANAGER.getBorrowedAmount(IERC20(address(_ASSET)), address(this)) != 0) return;

        uint256 liabilities = _DEPOSIT_MANAGER.getOperatorLiabilities(
            IERC20(address(_ASSET)),
            address(this)
        );
        if (liabilities == 0) return;
        uint256 minimumAmount = _VAULT.convertToAssets(1);
        if (minimumAmount == 0) minimumAmount = 1;
        if (liabilities < minimumAmount) return;
        uint256 amount = _bound(amountSeed_, minimumAmount, liabilities);
        uint256 expectedShares = _VAULT.convertToShares(amount);
        uint256 custodySharesBefore = _SHARE_TOKEN.balanceOf(address(_DEPOSIT_MANAGER));
        uint256 receiptTokenId = _DEPOSIT_MANAGER.getReceiptTokenId(
            IERC20(address(_ASSET)),
            _DEPOSIT_PERIOD,
            address(this)
        );
        _RECEIPT_TOKEN_MANAGER.approve(
            address(_DEPOSIT_MANAGER),
            receiptTokenId,
            _RECEIPT_TOKEN_MANAGER.balanceOf(address(this), receiptTokenId)
        );

        try
            _DEPOSIT_MANAGER.withdraw(
                IDepositManager.WithdrawParams({
                    asset: IERC20(address(_ASSET)),
                    depositPeriod: _DEPOSIT_PERIOD,
                    depositor: address(this),
                    recipient: _RECIPIENT,
                    amount: amount,
                    isWrapped: false
                }),
                true
            )
        returns (IERC20, uint256 amountOut) {
            if (amountOut > expectedShares) ++overDeliveryViolations;
            if (
                amountOut == 0 &&
                _SHARE_TOKEN.balanceOf(address(_DEPOSIT_MANAGER)) != custodySharesBefore
            ) ++zeroOutputShareMutationViolations;
        } catch (bytes memory revertData) {
            if (_isDisabledPeriodRevert(revertData)) ++disabledServicingFailures;
        }
    }

    function claimYieldAsShares(uint128 amountSeed_) external {
        // Keep this action focused on share-mode yield accounting. Active borrowing can make an
        // otherwise valid gross claim exceed the shares currently held in custody.
        if (_DEPOSIT_MANAGER.getBorrowedAmount(IERC20(address(_ASSET)), address(this)) != 0) return;

        uint256 claimable = _DEPOSIT_MANAGER.maxClaimYield(IERC20(address(_ASSET)), address(this));
        if (claimable == 0) return;
        uint256 amount = _bound(amountSeed_, 1, claimable);
        uint256 expectedShares = _VAULT.convertToShares(amount);
        uint256 custodySharesBefore = _SHARE_TOKEN.balanceOf(address(_DEPOSIT_MANAGER));

        try _DEPOSIT_MANAGER.claimYield(IERC20(address(_ASSET)), _RECIPIENT, amount, true) returns (
            IERC20,
            uint256 amountOut
        ) {
            if (amountOut > expectedShares) ++overDeliveryViolations;
            if (
                amountOut == 0 &&
                _SHARE_TOKEN.balanceOf(address(_DEPOSIT_MANAGER)) != custodySharesBefore
            ) ++zeroOutputShareMutationViolations;
        } catch (bytes memory revertData) {
            if (_isDisabledPeriodRevert(revertData)) ++disabledServicingFailures;
        }
    }

    function borrowingWithdrawAsShares(uint128 amountSeed_) external {
        uint256 capacity = _DEPOSIT_MANAGER.getBorrowingCapacity(
            IERC20(address(_ASSET)),
            address(this)
        );
        uint256 minimumAmount = _VAULT.convertToAssets(1);
        if (minimumAmount == 0) minimumAmount = 1;
        if (capacity < minimumAmount) return;
        uint256 amount = _bound(amountSeed_, minimumAmount, capacity);

        try
            _DEPOSIT_MANAGER.borrowingWithdraw(
                IDepositManager.BorrowingWithdrawParams({
                    asset: IERC20(address(_ASSET)),
                    recipient: _RECIPIENT,
                    amount: amount
                }),
                true
            )
        returns (IERC20, uint256 amountOut) {
            if (amountOut > _VAULT.convertToShares(amount)) ++overDeliveryViolations;
        } catch {}
    }

    function repayBorrowing(uint128 amountSeed_) external {
        uint256 borrowed = _DEPOSIT_MANAGER.getBorrowedAmount(
            IERC20(address(_ASSET)),
            address(this)
        );
        uint256 minimumAmount = _VAULT.convertToAssets(1);
        if (minimumAmount == 0) minimumAmount = 1;
        if (borrowed < minimumAmount) return;
        uint256 amount = _bound(amountSeed_, minimumAmount, borrowed);
        _ASSET.mint(address(this), amount);
        _ASSET.approve(address(_DEPOSIT_MANAGER), amount);

        try
            _DEPOSIT_MANAGER.borrowingRepay(
                IDepositManager.BorrowingRepayParams({
                    asset: IERC20(address(_ASSET)),
                    payer: address(this),
                    amount: amount,
                    maxAmount: amount
                })
            )
        returns (uint256) {} catch (bytes memory revertData) {
            if (_isDisabledPeriodRevert(revertData)) ++disabledRepaymentFailures;
        }
    }

    function defaultBorrowing(uint128 amountSeed_) external {
        uint256 borrowed = _DEPOSIT_MANAGER.getBorrowedAmount(
            IERC20(address(_ASSET)),
            address(this)
        );
        uint256 receiptTokenId = _DEPOSIT_MANAGER.getReceiptTokenId(
            IERC20(address(_ASSET)),
            _DEPOSIT_PERIOD,
            address(this)
        );
        uint256 receiptBalance = _RECEIPT_TOKEN_MANAGER.balanceOf(address(this), receiptTokenId);
        uint256 maximumDefault = borrowed < receiptBalance ? borrowed : receiptBalance;
        if (maximumDefault == 0) return;
        uint256 amount = _bound(amountSeed_, 1, maximumDefault);
        _RECEIPT_TOKEN_MANAGER.approve(address(_DEPOSIT_MANAGER), receiptTokenId, receiptBalance);

        try
            _DEPOSIT_MANAGER.borrowingDefault(
                IDepositManager.BorrowingDefaultParams({
                    asset: IERC20(address(_ASSET)),
                    depositPeriod: _DEPOSIT_PERIOD,
                    payer: address(this),
                    amount: amount
                })
            )
        {} catch (bytes memory revertData) {
            if (_isDisabledPeriodRevert(revertData)) ++disabledDefaultFailures;
        }
    }

    function addYield(uint128 amountSeed_) external {
        _ASSET.mint(address(_VAULT), _bound(amountSeed_, 1, 1_000_000e18));
    }

    function setAsyncRedeem(bool asyncRedeem_) external {
        _VAULT.setCapabilities(false, asyncRedeem_, true, true);
    }

    function setDepositCap(uint256 capSeed_) external {
        IDepositManager.AssetConfiguration memory configuration = _DEPOSIT_MANAGER
            .getAssetConfiguration(IERC20(address(_ASSET)));
        uint256 cap = capSeed_ < configuration.minimumDeposit
            ? configuration.minimumDeposit
            : capSeed_;
        _DEPOSIT_MANAGER.setAssetDepositCap(IERC20(address(_ASSET)), cap);
    }

    function setMinimumDeposit(uint256 minimumSeed_) external {
        uint256 cap = _DEPOSIT_MANAGER.getAssetConfiguration(IERC20(address(_ASSET))).depositCap;
        uint256 minimum = cap == type(uint256).max ? minimumSeed_ : minimumSeed_ % (cap + 1);
        _DEPOSIT_MANAGER.setAssetMinimumDeposit(IERC20(address(_ASSET)), minimum);
    }

    function toggleAssetPeriod() external {
        if (_assetPeriodEnabled()) {
            _DEPOSIT_MANAGER.disableAssetPeriod(
                IERC20(address(_ASSET)),
                _DEPOSIT_PERIOD,
                address(this)
            );
        } else {
            _DEPOSIT_MANAGER.enableAssetPeriod(
                IERC20(address(_ASSET)),
                _DEPOSIT_PERIOD,
                address(this)
            );
        }
    }

    function attemptUnauthorizedConfig(uint8 actionSeed_, uint256 valueSeed_) external {
        bytes memory callData;
        uint8 action = actionSeed_ % 4;
        if (action == 0) {
            callData = abi.encodeCall(
                IDepositManager.setAssetDepositCap,
                (IERC20(address(_ASSET)), valueSeed_)
            );
        } else if (action == 1) {
            callData = abi.encodeCall(
                IDepositManager.setAssetMinimumDeposit,
                (IERC20(address(_ASSET)), valueSeed_)
            );
        } else if (action == 2) {
            callData = abi.encodeCall(
                IDepositManager.enableAssetPeriod,
                (IERC20(address(_ASSET)), _DEPOSIT_PERIOD, address(this))
            );
        } else {
            callData = abi.encodeCall(
                IDepositManager.disableAssetPeriod,
                (IERC20(address(_ASSET)), _DEPOSIT_PERIOD, address(this))
            );
        }

        if (_UNAUTHORIZED_CALLER.attempt(_DEPOSIT_MANAGER, callData)) {
            ++unauthorizedConfigSuccesses;
        }
    }

    function _assetPeriodEnabled() private view returns (bool) {
        return
            _DEPOSIT_MANAGER
                .isAssetPeriod(IERC20(address(_ASSET)), _DEPOSIT_PERIOD, address(this))
                .isEnabled;
    }

    function _isDisabledPeriodRevert(bytes memory revertData_) private pure returns (bool) {
        // Only the leading four-byte selector is relevant; longer revert data is intentionally
        // truncated for this comparison.
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes4(revertData_) == IDepositManager.DepositManager_AssetPeriodDisabled.selector;
    }

    function _bound(
        uint256 value_,
        uint256 minimum_,
        uint256 maximum_
    ) private pure returns (uint256) {
        if (value_ < minimum_) return minimum_;
        if (value_ > maximum_) return minimum_ + (value_ % (maximum_ - minimum_ + 1));
        return value_;
    }
}

contract DepositManagerShareInvariantTest is StdInvariant, DepositManagerTest {
    DepositManagerShareHandler internal _handler;
    DepositManagerShareHandler internal _secondHandler;
    MockERC7540ExternalShareVault internal _externalVault;
    MockERC7540ExternalShareToken internal _externalShareToken;

    function setUp() public override {
        super.setUp();
        _externalVault = new MockERC7540ExternalShareVault(asset, false, true, true);
        _externalShareToken = MockERC7540ExternalShareToken(_externalVault.share());
        _handler = new DepositManagerShareHandler(
            IDepositManagerV1_1(address(depositManager)),
            receiptTokenManager,
            asset,
            _externalVault,
            _externalShareToken,
            DEPOSIT_PERIOD,
            makeAddr("shareRecipient")
        );
        _secondHandler = new DepositManagerShareHandler(
            IDepositManagerV1_1(address(depositManager)),
            receiptTokenManager,
            asset,
            _externalVault,
            _externalShareToken,
            DEPOSIT_PERIOD,
            makeAddr("secondShareRecipient")
        );

        vm.startPrank(ADMIN);
        depositManager.enable("");
        rolesAdmin.grantRole("deposit_operator", address(_handler));
        rolesAdmin.grantRole("deposit_operator", address(_secondHandler));
        depositManager.setOperatorName(address(_handler), "inv");
        depositManager.setOperatorName(address(_secondHandler), "in2");
        depositManager.addAsset(iAsset, IERC4626(address(_externalVault)), type(uint256).max, 0);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, address(_handler));
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, address(_secondHandler));
        depositManager.setConfigOperator(address(_handler));
        vm.stopPrank();

        // Start every stateful run with live liabilities and borrowing while the period is
        // disabled, so servicing actions cannot be vacuous until a deposit happens to succeed.
        _handler.deposit(100e18);
        _handler.addYield(10e18);
        _handler.borrowingWithdrawAsShares(10e18);
        _handler.toggleAssetPeriod();
        _secondHandler.deposit(50e18);

        targetContract(address(_handler));
        targetContract(address(_secondHandler));
    }

    function invariant_operatorSharesEqualExternalTokenCustody() public view {
        (uint256 operatorShares, ) = depositManager.getOperatorAssets(iAsset, address(_handler));
        (uint256 secondOperatorShares, ) = depositManager.getOperatorAssets(
            iAsset,
            address(_secondHandler)
        );
        assertEq(
            operatorShares + secondOperatorShares,
            _externalShareToken.balanceOf(address(depositManager)),
            "aggregate operator shares differ from custody"
        );
    }

    function invariant_operatorRemainsSolvent() public view {
        _assertOperatorSolvent(address(_handler));
        _assertOperatorSolvent(address(_secondHandler));
    }

    function invariant_assetCapUtilizationEqualsAggregateLiabilities() public view {
        uint256 aggregateLiabilities = depositManager.getOperatorLiabilities(
            iAsset,
            address(_handler)
        ) + depositManager.getOperatorLiabilities(iAsset, address(_secondHandler));
        assertEq(
            _assetDepositCapUtilization(iAsset),
            aggregateLiabilities,
            "asset cap utilization differs from aggregate liabilities"
        );
    }

    function invariant_shareOutputNeverExceedsConversion() public view {
        assertEq(_handler.overDeliveryViolations(), 0, "share output exceeded conversion");
    }

    function invariant_zeroOutputDoesNotMoveShares() public view {
        assertEq(
            _handler.zeroOutputShareMutationViolations(),
            0,
            "zero output changed share custody"
        );
    }

    function invariant_unprivilegedCallersCannotMutateConfiguration() public view {
        assertEq(
            _handler.unauthorizedConfigSuccesses(),
            0,
            "unprivileged configuration call succeeded"
        );
    }

    function invariant_minimumDepositNeverExceedsDepositCap() public view {
        IDepositManager.AssetConfiguration memory configuration = depositManager
            .getAssetConfiguration(iAsset);
        assertLe(
            configuration.minimumDeposit,
            configuration.depositCap,
            "minimum deposit exceeds cap"
        );
    }

    function invariant_disabledPeriodRejectsDepositsAndPermitsServicing() public view {
        assertEq(_handler.disabledDepositSuccesses(), 0, "deposit succeeded while period disabled");
        assertEq(
            _handler.disabledServicingFailures(),
            0,
            "disabled period prevented withdrawal or yield claim"
        );
        assertEq(
            _handler.disabledRepaymentFailures(),
            0,
            "disabled period prevented borrowing repayment"
        );
        assertEq(
            _handler.disabledDefaultFailures(),
            0,
            "disabled period prevented borrowing default"
        );
    }

    function _assertOperatorSolvent(address operator_) internal view {
        (, uint256 assets) = depositManager.getOperatorAssets(iAsset, operator_);
        uint256 liabilities = depositManager.getOperatorLiabilities(iAsset, operator_);
        uint256 borrowed = depositManager.getBorrowedAmount(iAsset, operator_);
        assertGe(assets + borrowed, liabilities, "share operator is insolvent");
    }
}

// forge-lint: disable-end(incorrect-strict-equality, literal-instead-of-constant, multi-contract-file, unused-return)
