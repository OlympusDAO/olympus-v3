// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCompositesToken} from "./IBurnerLoansCompositesToken.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";

// Contracts
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {toKeycode} from "src/Kernel.sol";
import {BurnerLoansComposites} from "src/periphery/BurnerLoansComposites.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

// Test vectors fit their fixed-width types; setup calls are checked through action assertions.
// forge-lint: disable-start(unused-return,unsafe-typecast)
abstract contract BurnerLoansCompositesTest is BurnerLoansModularTest {
    uint48 internal constant _AUTHORIZATION_DURATION = 1 days;
    bytes32 internal constant _AUTHORIZATION_TYPEHASH =
        keccak256(
            "Authorization(address account,address authorized,uint48 authorizationDeadline,uint256 nonce,uint48 signatureDeadline)"
        );
    uint128 internal constant _COLLATERAL = 2_000e6;
    uint128 internal constant _BORROW = 100e9;
    uint256 internal constant _MAX_FEE = 10e6;

    BurnerLoansComposites internal composites;
    address internal recipient;
    address internal _treasury;

    function setUp() public virtual override {
        super.setUp();
        _price.setPrice(address(_ohm), 10e18);
        _treasury = address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
        composites = new BurnerLoansComposites(address(_core), address(_ohm), _collateral, _debt);
        recipient = makeAddr("recipient");
    }

    function _emptyAuthorization()
        internal
        pure
        returns (IOperatorAuth.Authorization memory authorization)
    {
        return authorization;
    }

    function _emptySignature() internal pure returns (IOperatorAuth.Signature memory signature) {
        return signature;
    }

    function _authorize(address account_) internal {
        vm.prank(account_);
        _core.setAuthorization(
            address(composites),
            uint48(block.timestamp + _AUTHORIZATION_DURATION)
        );
    }

    function _signedAuthorization(
        address account_,
        uint256 privateKey_
    )
        internal
        view
        returns (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        )
    {
        authorization = IOperatorAuth.Authorization(
            account_,
            address(composites),
            uint48(block.timestamp + _AUTHORIZATION_DURATION),
            _core.authorizationNonces(account_),
            uint48(block.timestamp + 1 hours)
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _core.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(_AUTHORIZATION_TYPEHASH, authorization))
            )
        );
        (signature.v, signature.r, signature.s) = vm.sign(privateKey_, digest);
    }

    function _depositParams(
        address asset_,
        address recipient_
    ) internal pure returns (IBurnerLoansComposites.DepositAndBorrowParams memory) {
        return
            IBurnerLoansComposites.DepositAndBorrowParams(
                asset_,
                _COLLATERAL,
                _BORROW,
                recipient_,
                _MAX_FEE,
                address(0)
            );
    }

    function _fundAndApproveCollateral(address asset_, address account_, uint256 amount_) internal {
        deal(asset_, account_, amount_);
        vm.prank(account_);
        IBurnerLoansCompositesToken(asset_).approve(address(composites), amount_);
    }

    function _openPosition()
        internal
        returns (IBurnerLoansComposites.DepositAndBorrowResult memory result)
    {
        _authorize(_borrower);
        _fundAndApproveCollateral(address(_asset), _borrower, _COLLATERAL + _MAX_FEE);
        vm.prank(_borrower);
        result = composites.depositAndBorrow(
            _emptyAuthorization(),
            _emptySignature(),
            _depositParams(address(_asset), _borrower)
        );
        vm.roll(block.number + 1);
    }

    function _assertCompositeBalances(address collateralAsset_) internal view {
        assertEq(
            IBurnerLoansCompositesToken(collateralAsset_).balanceOf(address(composites)),
            0,
            "composite collateral"
        );
        assertEq(_ohm.balanceOf(address(composites)), 0, "composite OHM");
    }

    function _configurePrice(address token_, uint256 price_) internal {
        _price.setPrice(token_, price_);
    }

    function _configureDepositManagerAsset(address token_) internal {
        _depositManager.addAsset(IERC20(token_), IERC4626(address(0)), type(uint256).max, 0);
        _depositManager.addAssetPeriod(
            IERC20(token_),
            LoanParameters._DEPOSIT_PERIOD,
            address(_core)
        );
    }

    function _defaultAssetDebtCap() internal pure returns (uint128) {
        return 100_000e9;
    }

    function _defaultAssetRiskConfigInput()
        internal
        pure
        returns (IBurnerLoansRisk.AssetRiskConfigInput memory)
    {
        return IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 30 days, 90 days, 1000e18);
    }

    function _defaultAssetFeeConfig()
        internal
        pure
        returns (IBurnerLoansRisk.AssetFeeConfig memory)
    {
        return IBurnerLoansRisk.AssetFeeConfig(25, 8000, 100, 900);
    }

    function _addVaultAssetForTest() internal returns (MockERC20 asset, MockERC4626 vault) {
        asset = new MockERC20("Vault Collateral", "vCOLL", 18);
        vault = new MockERC4626(ERC20(address(asset)), "Vault", "VAULT");
        _price.setPrice(address(asset), 1e18);
        _depositManager.addAsset(
            IERC20(address(asset)),
            IERC4626(address(vault)),
            type(uint256).max,
            0
        );
        _depositManager.addAssetPeriod(
            IERC20(address(asset)),
            LoanParameters._DEPOSIT_PERIOD,
            address(_core)
        );
        _config.addAsset(
            address(asset),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig(),
            false
        );
    }

    function _makeVaultAsynchronous(MockERC4626 vault_) internal {
        vm.mockCallRevert(
            address(vault_),
            abi.encodeWithSelector(IERC4626.redeem.selector),
            abi.encodeWithSignature("AsyncRedemption()")
        );
    }
}
// forge-lint: disable-end(unused-return,unsafe-typecast)
