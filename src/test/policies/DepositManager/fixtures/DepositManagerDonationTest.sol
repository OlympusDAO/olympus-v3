// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IERC20 as OZIERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {DepositManagerTest} from "../DepositManagerTest.sol";
import {DepositManagerDonationVault} from "./DepositManagerDonationActors.sol";

abstract contract DepositManagerDonationTest is DepositManagerTest {
    address internal _donor;
    address internal _otherOperator;

    event AssetDeposited(
        address indexed asset,
        address indexed depositor,
        address indexed operator,
        uint256 amount,
        uint256 shares
    );
    event AssetDonated(
        address indexed asset,
        address indexed donor,
        address indexed operator,
        uint256 amount,
        uint256 actualAmount,
        uint256 shares
    );

    function setUp() public virtual override {
        super.setUp();
        _donor = makeAddr("donor");
        _otherOperator = makeAddr("otherOperator");
        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "don");
        depositManager.setOperatorName(_otherOperator, "oth");
        rolesAdmin.grantRole("deposit_operator", _otherOperator);
        vm.stopPrank();
    }

    function _freshAsset() internal {
        asset = new MockERC20("Donation asset", "DNT", 18);
        iAsset = IERC20(address(asset));
    }

    function _configureIdle() internal {
        _freshAsset();
        _configureRoute(address(0));
    }

    function _configureVault() internal {
        _freshAsset();
        vault = new MockERC4626(asset, "Donation vault", "DV");
        iVault = IERC4626(address(vault));
        _configureRoute(address(vault));
    }

    function _configureRoute(address vault_) internal {
        vm.startPrank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(vault_), type(uint256).max, 0);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();
    }

    function _fundDonor(address donor_, uint256 amount_) internal {
        asset.mint(donor_, amount_);
        vm.prank(donor_);
        asset.approve(address(depositManager), amount_);
    }

    function _donate(
        address donor_,
        address operator_,
        uint256 amount_
    ) internal returns (uint256 actualAmount, uint256 shares) {
        vm.prank(donor_);
        return IDepositManagerV1_1(address(depositManager)).donate(iAsset, operator_, amount_);
    }

    function _seedDeposit(uint256 amount_) internal returns (uint256 credit) {
        asset.mint(DEPOSITOR, amount_);
        _approveSpendingAsset(DEPOSITOR, amount_);
        vm.prank(DEPOSIT_OPERATOR);
        (, credit) = depositManager.deposit(
            IDepositManager.DepositParams(iAsset, DEPOSIT_PERIOD, DEPOSITOR, amount_, false)
        );
    }

    function _configureFaultVault(
        bool async_
    ) internal returns (DepositManagerDonationVault faultVault) {
        _freshAsset();
        faultVault = new DepositManagerDonationVault(OZIERC20(address(asset)));
        faultVault.setAsyncRedeem(async_);
        vault = MockERC4626(address(faultVault));
        iVault = IERC4626(address(faultVault));
        _configureRoute(address(faultVault));
    }

    function _seedExternalVault(uint256 amount_, uint256 gift_) internal {
        asset.mint(address(this), amount_ + gift_);
        asset.approve(address(vault), amount_);
        vault.deposit(amount_, address(this));
        asset.transfer(address(vault), gift_);
    }

    function _lossFixture() internal {
        _configureVault();
        _seedDeposit(100);
        asset.burn(address(vault), 20);
    }

    function _roundingRepairFixture() internal {
        _configureVault();
        _seedExternalVault(1, 2);
        assertEq(_seedDeposit(100), 99, "Rounded initial receipt credit");
        asset.burn(address(vault), 2);
        _assertNamespace(DEPOSIT_OPERATOR, 33, 98, 99, 0);
    }

    function _borrow(uint256 amount_) internal {
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams(iAsset, RECIPIENT, amount_)
        );
    }

    function _claim(uint256 amount_) internal returns (uint256) {
        vm.prank(DEPOSIT_OPERATOR);
        return depositManager.claimYield(iAsset, RECIPIENT, amount_);
    }

    function _assertNamespace(
        address operator_,
        uint256 shares_,
        uint256 assets_,
        uint256 liabilities_,
        uint256 borrowed_
    ) internal view {
        (uint256 shares, uint256 assets) = depositManager.getOperatorAssets(iAsset, operator_);
        assertEq(shares, shares_, "Recorded custody shares");
        assertEq(assets, assets_, "Recorded custody asset value");
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, operator_),
            liabilities_,
            "Receipt liabilities unchanged"
        );
        assertEq(
            depositManager.getBorrowedAmount(iAsset, operator_),
            borrowed_,
            "Borrowed principal unchanged"
        );
    }

    function _principalState() internal view returns (bytes32) {
        uint256 id = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        return
            keccak256(
                abi.encode(
                    depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
                    depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
                    depositManager.getAssetDepositCapStatus(iAsset),
                    receiptTokenManager.balanceOf(DEPOSITOR, id),
                    receiptTokenManager.balanceOf(_donor, id),
                    depositManager.getAssetPeriods(),
                    depositManager.getReceiptTokenIds()
                )
            );
    }

    function _custodyState() internal view returns (bytes32) {
        address custody = depositManager.getAssetConfiguration(iAsset).vault;
        IERC20 shareToken = custody == address(0)
            ? iAsset
            : depositManager.getAssetWithdrawalToken(iAsset, true);
        (uint256 targetShares, ) = depositManager.getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        (uint256 otherShares, ) = depositManager.getOperatorAssets(iAsset, _otherOperator);
        return
            keccak256(
                abi.encode(
                    _principalState(),
                    targetShares,
                    otherShares,
                    asset.totalSupply(),
                    asset.balanceOf(_donor),
                    asset.balanceOf(DEPOSITOR),
                    asset.balanceOf(address(depositManager)),
                    asset.balanceOf(custody),
                    asset.allowance(_donor, address(depositManager)),
                    asset.allowance(address(depositManager), custody),
                    shareToken.balanceOf(address(depositManager)),
                    shareToken.totalSupply()
                )
            );
    }

    function _assertDonation(uint256 amount_, uint256 credit_, uint256 shares_) internal {
        bytes32 principalBefore = _principalState();
        (uint256 beforeShares, ) = depositManager.getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        uint256 balanceBefore = asset.balanceOf(_donor);
        vm.expectEmit(true, true, true, true, address(depositManager));
        emit AssetDeposited(address(iAsset), _donor, DEPOSIT_OPERATOR, credit_, shares_);
        vm.expectEmit(true, true, true, true, address(depositManager));
        emit AssetDonated(address(iAsset), _donor, DEPOSIT_OPERATOR, amount_, credit_, shares_);
        vm.recordLogs();
        (uint256 credit, uint256 shares) = _donate(_donor, DEPOSIT_OPERATOR, amount_);
        _assertIncomingEventCounts(vm.getRecordedLogs());
        assertEq(credit, credit_, "Donation actual credit");
        assertEq(shares, shares_, "Donation actual shares");
        (uint256 afterShares, ) = depositManager.getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        assertEq(afterShares - beforeShares, shares_, "Target ledger receives shares once");
        assertEq(balanceBefore - asset.balanceOf(_donor), amount_, "Donor pays nominal input");
        assertEq(
            _principalState(),
            principalBefore,
            "Donation preserves principal, receipts, cap and periods"
        );
    }

    function _assertIncomingEventCounts(Vm.Log[] memory logs_) internal view {
        uint256 custodyEvents;
        uint256 donationEvents;
        for (uint256 i; i < logs_.length; ++i) {
            if (logs_[i].emitter != address(depositManager) || logs_[i].topics.length == 0)
                continue;
            if (
                logs_[i].topics[0] ==
                keccak256("AssetDeposited(address,address,address,uint256,uint256)")
            ) ++custodyEvents;
            if (
                logs_[i].topics[0] ==
                keccak256("AssetDonated(address,address,address,uint256,uint256,uint256)")
            ) ++donationEvents;
        }
        assertEq(custodyEvents, 1, "One incoming custody event");
        assertEq(donationEvents, 1, "One donation event");
    }

    function _expectInsolvent(uint256 liabilities_, uint256 assets_, uint256 borrowed_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_Insolvent.selector,
                address(iAsset),
                liabilities_,
                assets_,
                borrowed_
            )
        );
    }
}
