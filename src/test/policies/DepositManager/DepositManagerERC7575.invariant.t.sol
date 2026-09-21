// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.27;

// The handler intentionally catches invalid state-machine actions so arbitrary sequences continue.
// Tuple components not relevant to aggregate custody are intentionally ignored.
// forge-lint: disable-start(literal-instead-of-constant, multi-contract-file, unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";

// Contracts
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";
import {MockSharedERC7575ShareToken, MockSharedERC7575Vault} from "src/test/policies/DepositManager/fixtures/MockERC7575Vault.sol";

contract DepositManagerERC7575Handler {
    IDepositManagerV1_1 internal immutable _DEPOSIT_MANAGER;
    IReceiptTokenManager internal immutable _RECEIPT_TOKEN_MANAGER;
    MockERC20 internal immutable _FIRST_ASSET;
    MockERC20 internal immutable _SECOND_ASSET;
    MockSharedERC7575Vault internal immutable _FIRST_VAULT;
    MockSharedERC7575Vault internal immutable _SECOND_VAULT;
    uint8 internal immutable _DEPOSIT_PERIOD;
    address internal immutable _RECIPIENT;

    constructor(
        IDepositManagerV1_1 depositManager_,
        IReceiptTokenManager receiptTokenManager_,
        MockERC20 firstAsset_,
        MockERC20 secondAsset_,
        MockSharedERC7575Vault firstVault_,
        MockSharedERC7575Vault secondVault_,
        uint8 depositPeriod_,
        // The invariant suite constructs each handler with a nonzero makeAddr recipient.
        // forge-lint: disable-next-line(missing-zero-check)
        address recipient_
    ) {
        _DEPOSIT_MANAGER = depositManager_;
        _RECEIPT_TOKEN_MANAGER = receiptTokenManager_;
        _FIRST_ASSET = firstAsset_;
        _SECOND_ASSET = secondAsset_;
        _FIRST_VAULT = firstVault_;
        _SECOND_VAULT = secondVault_;
        _DEPOSIT_PERIOD = depositPeriod_;
        _RECIPIENT = recipient_;
    }

    function deposit(uint8 routeSeed_, uint128 amountSeed_) external {
        (MockERC20 asset, ) = _route(routeSeed_);
        uint256 amount = _bound(amountSeed_, 1, 1_000_000e18);
        asset.mint(address(this), amount);
        asset.approve(address(_DEPOSIT_MANAGER), amount);

        try
            _DEPOSIT_MANAGER.deposit(
                IDepositManager.DepositParams({
                    asset: IERC20(address(asset)),
                    depositPeriod: _DEPOSIT_PERIOD,
                    depositor: address(this),
                    amount: amount,
                    shouldWrap: false
                })
            )
        returns (uint256 receiptTokenId, uint256) {
            _RECEIPT_TOKEN_MANAGER.approve(
                address(_DEPOSIT_MANAGER),
                receiptTokenId,
                _RECEIPT_TOKEN_MANAGER.balanceOf(address(this), receiptTokenId)
            );
        } catch {}
    }

    function withdrawAsShares(uint8 routeSeed_, uint128 amountSeed_) external {
        (MockERC20 asset, ) = _route(routeSeed_);
        IERC20 iAsset = IERC20(address(asset));
        if (_DEPOSIT_MANAGER.getBorrowedAmount(iAsset, address(this)) != 0) return;

        uint256 liabilities = _DEPOSIT_MANAGER.getOperatorLiabilities(iAsset, address(this));
        if (liabilities == 0) return;
        uint256 amount = _bound(amountSeed_, 1, liabilities);
        uint256 receiptTokenId = _DEPOSIT_MANAGER.getReceiptTokenId(
            iAsset,
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
                    asset: iAsset,
                    depositPeriod: _DEPOSIT_PERIOD,
                    depositor: address(this),
                    recipient: _RECIPIENT,
                    amount: amount,
                    isWrapped: false
                }),
                true
            )
        returns (IERC20, uint256) {} catch {}
    }

    function borrowingWithdrawAsShares(uint8 routeSeed_, uint128 amountSeed_) external {
        (MockERC20 asset, ) = _route(routeSeed_);
        IERC20 iAsset = IERC20(address(asset));
        uint256 capacity = _DEPOSIT_MANAGER.getBorrowingCapacity(iAsset, address(this));
        if (capacity == 0) return;
        uint256 amount = _bound(amountSeed_, 1, capacity);

        try
            _DEPOSIT_MANAGER.borrowingWithdraw(
                IDepositManager.BorrowingWithdrawParams({
                    asset: iAsset,
                    recipient: _RECIPIENT,
                    amount: amount
                }),
                true
            )
        returns (IERC20, uint256) {} catch {}
    }

    function repayBorrowing(uint8 routeSeed_, uint128 amountSeed_) external {
        (MockERC20 asset, ) = _route(routeSeed_);
        IERC20 iAsset = IERC20(address(asset));
        uint256 borrowed = _DEPOSIT_MANAGER.getBorrowedAmount(iAsset, address(this));
        if (borrowed == 0) return;
        uint256 amount = _bound(amountSeed_, 1, borrowed);
        asset.mint(address(this), amount);
        asset.approve(address(_DEPOSIT_MANAGER), amount);

        try
            _DEPOSIT_MANAGER.borrowingRepay(
                IDepositManager.BorrowingRepayParams({
                    asset: iAsset,
                    payer: address(this),
                    amount: amount,
                    maxAmount: amount
                })
            )
        returns (uint256) {} catch {}
    }

    function defaultBorrowing(uint8 routeSeed_, uint128 amountSeed_) external {
        (MockERC20 asset, ) = _route(routeSeed_);
        IERC20 iAsset = IERC20(address(asset));
        uint256 borrowed = _DEPOSIT_MANAGER.getBorrowedAmount(iAsset, address(this));
        uint256 receiptTokenId = _DEPOSIT_MANAGER.getReceiptTokenId(
            iAsset,
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
                    asset: iAsset,
                    depositPeriod: _DEPOSIT_PERIOD,
                    payer: address(this),
                    amount: amount
                })
            )
        {} catch {}
    }

    function donateCustody(uint8 routeSeed_, uint128 amountSeed_) external {
        (MockERC20 asset, MockSharedERC7575Vault vault) = _route(routeSeed_);
        uint256 amount = _bound(amountSeed_, 1, 1_000_000e18);
        asset.mint(address(this), amount);
        asset.approve(address(vault), amount);
        vault.deposit(amount, address(_DEPOSIT_MANAGER));
    }

    function _route(
        uint8 routeSeed_
    ) private view returns (MockERC20 asset, MockSharedERC7575Vault vault) {
        if (routeSeed_ % 2 == 0) return (_FIRST_ASSET, _FIRST_VAULT);
        return (_SECOND_ASSET, _SECOND_VAULT);
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

contract DepositManagerERC7575InvariantTest is StdInvariant, DepositManagerTest {
    MockERC20 internal _secondAsset;
    MockSharedERC7575ShareToken internal _firstShareToken;
    MockSharedERC7575ShareToken internal _secondShareToken;
    MockSharedERC7575Vault internal _firstVault;
    MockSharedERC7575Vault internal _secondVault;
    DepositManagerERC7575Handler internal _firstHandler;
    DepositManagerERC7575Handler internal _secondHandler;

    function setUp() public override {
        super.setUp();
        _secondAsset = new MockERC20("Second Asset", "ASSET2", 18);
        _firstShareToken = new MockSharedERC7575ShareToken();
        _secondShareToken = new MockSharedERC7575ShareToken();
        _firstVault = new MockSharedERC7575Vault(asset, _firstShareToken);
        _secondVault = new MockSharedERC7575Vault(ERC20(address(_secondAsset)), _secondShareToken);
        _firstShareToken.authorizeVault(address(_firstVault));
        _secondShareToken.authorizeVault(address(_secondVault));

        _firstHandler = _newHandler("firstOperator", "firstRecipient");
        _secondHandler = _newHandler("secondOperator", "secondRecipient");

        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(_firstVault)), type(uint256).max, 0);
        depositManager.addAsset(
            IERC20(address(_secondAsset)),
            IERC4626(address(_secondVault)),
            type(uint256).max,
            0
        );
        _configureHandler(_firstHandler, "op1");
        _configureHandler(_secondHandler, "op2");
        vm.stopPrank();

        _firstHandler.deposit(0, 100e18);
        _firstHandler.deposit(1, 200e18);
        _secondHandler.deposit(0, 300e18);
        _secondHandler.deposit(1, 400e18);

        targetContract(address(_firstHandler));
        targetContract(address(_secondHandler));
    }

    function invariant_eachExternalShareTokenCoversItsRoute() public view {
        uint256 firstAttributedShares = _operatorShares(iAsset, address(_firstHandler));
        firstAttributedShares += _operatorShares(iAsset, address(_secondHandler));
        IERC20 secondIAsset = IERC20(address(_secondAsset));
        uint256 secondAttributedShares = _operatorShares(secondIAsset, address(_firstHandler));
        secondAttributedShares += _operatorShares(secondIAsset, address(_secondHandler));

        assertGe(
            _firstShareToken.balanceOf(address(depositManager)),
            firstAttributedShares,
            "first external token custody is below route attribution"
        );
        assertGe(
            _secondShareToken.balanceOf(address(depositManager)),
            secondAttributedShares,
            "second external token custody is below route attribution"
        );
    }

    function invariant_eachOperatorRemainsSolventAcrossBothRoutes() public view {
        _assertSolvent(iAsset, address(_firstHandler));
        _assertSolvent(iAsset, address(_secondHandler));
        IERC20 secondIAsset = IERC20(address(_secondAsset));
        _assertSolvent(secondIAsset, address(_firstHandler));
        _assertSolvent(secondIAsset, address(_secondHandler));
    }

    function _newHandler(
        string memory operatorName_,
        string memory recipientName_
    ) private returns (DepositManagerERC7575Handler handler) {
        handler = new DepositManagerERC7575Handler(
            IDepositManagerV1_1(address(depositManager)),
            receiptTokenManager,
            asset,
            _secondAsset,
            _firstVault,
            _secondVault,
            DEPOSIT_PERIOD,
            makeAddr(recipientName_)
        );
        vm.label(address(handler), operatorName_);
    }

    function _configureHandler(
        DepositManagerERC7575Handler handler_,
        string memory operatorName_
    ) private {
        rolesAdmin.grantRole("deposit_operator", address(handler_));
        depositManager.setOperatorName(address(handler_), operatorName_);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, address(handler_));
        depositManager.addAssetPeriod(
            IERC20(address(_secondAsset)),
            DEPOSIT_PERIOD,
            address(handler_)
        );
    }

    function _operatorShares(
        IERC20 asset_,
        address operator_
    ) private view returns (uint256 shares) {
        (shares, ) = depositManager.getOperatorAssets(asset_, operator_);
    }

    function _assertSolvent(IERC20 asset_, address operator_) private view {
        (, uint256 assets) = depositManager.getOperatorAssets(asset_, operator_);
        uint256 liabilities = depositManager.getOperatorLiabilities(asset_, operator_);
        uint256 borrowed = depositManager.getBorrowedAmount(asset_, operator_);
        assertGe(assets + borrowed, liabilities, "operator is insolvent");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, multi-contract-file, unused-return)
