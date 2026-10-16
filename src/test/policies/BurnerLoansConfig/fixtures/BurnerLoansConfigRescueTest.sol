// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";
import {BurnerLoansSurplusRescueTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansSurplusRescueTest.sol";

/// @dev BLC forwarding uses fixed raw debts 10/20/30 and surplus 19. Numeric exploration belongs to BL.
abstract contract BurnerLoansConfigRescueTestBase is BurnerLoansSurplusRescueTestBase {
    uint256 internal constant _FORWARDING_SURPLUS = 19;
    ReentrantPayoutToken internal _asset;

    function setUp() public virtual override {
        super.setUp();
        _setDefaultConfigOperator();
        _asset = _createFixedRescueToken(_ALL_BUCKETS);
        _asset.mint(address(burnerLoans), _FORWARDING_SURPLUS);
        _asset.mint(_destination, _DESTINATION_BALANCE);
    }

    function _executeSurplusRescue(
        address asset_,
        address destination_,
        address caller_
    ) internal override {
        vm.prank(caller_);
        burnerLoansConfig.rescue(asset_, destination_);
    }
}
