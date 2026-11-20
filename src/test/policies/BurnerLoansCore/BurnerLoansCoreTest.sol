// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {StdStorage, stdStorage} from "@forge-std-1.16.2/StdStorage.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansModularTest} from "./fixtures/BurnerLoansModularTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {CoreService} from "./fixtures/CoreService.sol";
import {Actions, Policy} from "src/Kernel.sol";

abstract contract BurnerLoansCoreTest is BurnerLoansModularTest {
    using stdStorage for StdStorage;
    error DependencyFailed();
    uint256 internal constant _SIGNER_KEY = 0xA11CE;

    function _service() internal returns (CoreService service) {
        service = new CoreService(_kernel, address(_core), address(_ohm), address(_config));
        _kernel.executeAction(Actions.ActivatePolicy, address(service));
    }

    function _grantRole(bytes32 role_, address caller_) internal {
        vm.assume(caller_ != address(0));
        if (!_roles.hasRole(caller_, role_)) _rolesAdmin.grantRole(role_, caller_);
    }

    function _grantAdmin(address caller_) internal {
        _grantRole(ADMIN_ROLE, caller_);
    }

    function _grantLifecycleCaller(
        address caller_,
        bytes32 secondaryRole_,
        bool admin_,
        bool overlap_
    ) internal {
        vm.assume(caller_ != address(0));
        if (!admin_) vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        if (admin_ && !overlap_) vm.assume(!_roles.hasRole(caller_, secondaryRole_));
        if (admin_) _grantAdmin(caller_);
        if (!admin_ || overlap_) _grantRole(secondaryRole_, caller_);
    }

    function _expectDependencyKernelMismatch(address candidate_, address reported_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                candidate_,
                address(_kernel),
                reported_
            )
        );
    }

    function _setCoreLifecycle(bool active_, bool enabled_) internal {
        _setPolicyLifecycle(_core, active_, enabled_);
    }

    /// @dev Starts from an active, enabled policy prepared by this fixture.
    function _setPolicyLifecycle(Policy policy_, bool active_, bool enabled_) internal {
        if (!enabled_) IEnabler(address(policy_)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(policy_));
    }

    function _restoreCore(bool active_, bool enabled_) internal {
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_core));
        if (!enabled_) _core.enable("");
    }

    function _deposit(uint128 amount_) internal {
        _asset.mint(_borrower, amount_);
        vm.prank(address(_collateral));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: amount_,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
    }

    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function _borrow(uint128 amount_) internal {
        vm.prank(address(_debt));
        _core.settleBorrow(
            IBurnerLoansCore.BorrowRequest(
                address(_asset),
                _borrower,
                _borrower,
                _recipient,
                amount_,
                uint48(vm.getBlockTimestamp() + 30 days),
                0,
                address(0),
                0
            ),
            _borrower,
            _ownerAuthContext()
        );
    }

    // forge-lint: disable-end(unsafe-typecast)

    function _position() internal view returns (IBurnerLoansCore.Position memory) {
        return _lens.getPosition(address(_asset), _borrower);
    }

    function _rawPosition() internal view returns (IFLOANv1.Position memory) {
        (, uint64 id) = _floan.getPositionIdForMarketAndBorrowerAt(
            _core.marketId(address(_asset)),
            _borrower,
            0
        );
        return _floan.getPosition(id);
    }

    function _state() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _core.configOperator(),
                    _core.risk(),
                    _core.inventory(),
                    _core.payout(),
                    _core.isEnabled(),
                    _core.lastTransitionAt(),
                    _core.gracePeriod(),
                    _ledger()
                )
            );
    }

    function _ledger() internal view returns (bytes32) {
        (uint256 shares, uint256 assets) = _depositManager.getOperatorAssets(
            IERC20(address(_asset)),
            address(_core)
        );
        bytes32 custody = keccak256(
            abi.encode(
                shares,
                assets,
                _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
                _asset.balanceOf(address(_core)),
                _asset.balanceOf(address(_depositManager)),
                _asset.balanceOf(address(_payout)),
                _asset.balanceOf(_borrower),
                _asset.balanceOf(_recipient)
            )
        );
        uint32 market = _core.marketId(address(_asset));
        bytes32 indexes = keccak256(
            abi.encode(
                _floan.getPositionCount(),
                _floan.getPositionIdsForMarket(market),
                _floan.getPositionIdsForBorrower(_borrower),
                _floan.getActiveBorrowers(market),
                _floan.getMarketCollateral(market),
                _floan.getMarketPrincipalDue(market),
                _floan.getMarketInterestDue(market),
                _floan.getMarketPrincipalDefaulted(market)
            )
        );
        (uint256 fee, , uint256 seized, , uint256 reserved) = _payout.pendingAmounts(
            address(_asset)
        );
        bytes32 payouts = keccak256(
            abi.encode(
                fee,
                seized,
                reserved,
                _payout.getPendingPayoutTokens(),
                _payout.getPendingKeepers(address(_asset)),
                _payout.getPendingPayoutRecipients(address(_asset)),
                _referralReservesDigest(address(_asset)),
                _asset.allowance(_borrower, address(_core)),
                _asset.allowance(address(_core), address(_depositManager)),
                _ohm.allowance(_recipient, address(_core))
            )
        );
        return
            keccak256(
                abi.encode(
                    custody,
                    indexes,
                    payouts,
                    _position(),
                    _core.totalActiveDebtOhm(),
                    _inventory.activePrincipalOhm(),
                    _inventory.suppliedOhm(),
                    _inventory.suppliedIdleOhm(),
                    _ohm.balanceOf(address(_inventory)),
                    _ohm.balanceOf(_recipient)
                )
            );
    }

    function _setPairEpoch(address account_, address operator_, uint256 epoch_) internal {
        stdstore
            .target(address(_auth))
            .sig(IOperatorAuth.pairEpochs.selector)
            .with_key(account_)
            .with_key(operator_)
            .checked_write(epoch_);
    }

    function _sign(
        IOperatorAuth.Grant memory grant_,
        uint256 key_,
        bytes32 domain_
    ) internal pure returns (bytes memory) {
        bytes32 typeHash = keccak256(
            "Grant(address account,address operator,uint256 accountEpoch,uint256 pairEpoch,uint48 deadline,bool multiple,uint8 actions,bytes32 context,bytes32 permissionsHash,bytes32 signatureDataHash)"
        );
        bytes32 hash = keccak256(
            abi.encode(
                typeHash,
                grant_.account,
                grant_.operator,
                grant_.accountEpoch,
                grant_.pairEpoch,
                grant_.deadline,
                grant_.multiple,
                grant_.actions,
                grant_.context,
                keccak256(grant_.permissions),
                keccak256("")
            )
        );
        (uint8 v, bytes32 r, bytes32 ss) = vm.sign(
            key_,
            keccak256(abi.encodePacked("\x19\x01", domain_, hash))
        );
        return abi.encodePacked(r, ss, v);
    }

    function _grant() internal view returns (IOperatorAuth.Grant memory grant, bytes memory sig) {
        grant = _operatorGrant(vm.addr(_SIGNER_KEY), _recipient, type(uint48).max);
        sig = _sign(grant, _SIGNER_KEY, _auth.DOMAIN_SEPARATOR());
    }

    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function _bounds48(uint48 value_, uint48 min_, uint48 max_) internal pure returns (uint48) {
        return uint48(bound(value_, min_, max_));
    }

    // forge-lint: disable-end(unsafe-typecast)

    function _armRescue(
        bytes memory data_,
        bool propagate_
    ) internal returns (CoreCallbackToken token) {
        token = new CoreCallbackToken();
        token.mint(address(_core), 1);
        _rolesAdmin.grantRole(ADMIN_ROLE, address(token));
        token.setCallbackFrom(address(_core), address(_core), data_);
        token.setCallbackPhases(true, false);
        token.setBubbleCallbackFailure(propagate_);
    }

    function _callbackAsset() internal returns (CoreCallbackToken token) {
        token = new CoreCallbackToken();
        _asset = token;
        _price.setPrice(address(token), 1e18);
        _admit(address(token));
        token.mint(_borrower, 10000);
        vm.prank(_borrower);
        token.approve(address(_core), type(uint256).max);
    }

    function _authorizeCollateralCallback(CoreService actor_) internal {
        vm.prank(_recipient);
        _approveOperator(_recipient, address(actor_), type(uint48).max);
        _asset.mint(address(actor_), 1);
        vm.prank(address(actor_));
        _asset.approve(address(_core), 1);
    }
}
// forge-lint: disable-end(unused-return)
