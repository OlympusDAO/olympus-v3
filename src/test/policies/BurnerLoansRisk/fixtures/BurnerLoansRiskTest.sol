// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {LoanMarket} from "src/policies/burnerloans/libraries/LoanMarket.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusFixedTermLoan} from "src/modules/FLOAN/OlympusFixedTermLoan.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockBackingOracle} from "src/test/mocks/MockBackingOracle.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";

/// @dev Risk's actual dependency graph. No Core, Inventory, custody or actions are deployed.
abstract contract BurnerLoansRiskTest is Test {
    Kernel internal _kernel;
    OlympusRoles internal _roles;
    RolesAdmin internal _rolesAdmin;
    OlympusFixedTermLoan internal _floan;
    MockPrice internal _price;
    MockERC20 internal _ohm;
    MockERC20 internal _asset;
    MockBackingOracle internal _oracle;
    MockPriceCache internal _cache;
    BurnerLoansRisk internal _risk;
    IFLOANv1.Market internal _market;
    LoanMarket.Data internal _data;
    uint32 internal constant _MARKET = 7;
    address internal _operator = address(0xC0F1C);
    error DependencyReadFailed();

    function setUp() public virtual {
        vm.warp(100 days);
        _kernel = new Kernel();
        _roles = new OlympusRoles(_kernel);
        _floan = new OlympusFixedTermLoan(_kernel);
        _price = new MockPrice(_kernel, 18, 8 hours);
        _rolesAdmin = new RolesAdmin(_kernel);
        _kernel.executeAction(Actions.InstallModule, address(_roles));
        _kernel.executeAction(Actions.InstallModule, address(_floan));
        _kernel.executeAction(Actions.InstallModule, address(_price));
        _kernel.executeAction(Actions.ActivatePolicy, address(_rolesAdmin));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(this));
        _ohm = new MockERC20("OHM", "OHM", 9);
        _asset = new MockERC20("Collateral", "COL", 6);
        _oracle = new MockBackingOracle(1e18);
        _cache = new MockPriceCache(address(_kernel));
        _cache.setUsdPrice(address(_ohm), 3e18);
        _cache.setUsdPrice(address(_asset), 4e18);
        _price.setPrice(address(_ohm), 1e18);
        _price.setPrice(address(_asset), 2e18);
        _risk = new BurnerLoansRisk(
            _kernel,
            IERC20(address(_ohm)),
            address(_oracle),
            address(0),
            60,
            address(this)
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(_risk));
        _risk.enable("");
        _market.debtToken = address(_ohm);
        _market.collateralToken = address(_asset);
        _market.configId = LoanMarket.CONFIG_ID;
        _market.principalCap = 100e9;
        _market.termLength = 30 days;
        _market.maxMaturityHorizon = 90 days;
        _market.maxLtvBps = 10000;
        _market.baseFeeBps = 100;
        _market.collateralDecimals = 6;
        _market.debtDecimals = 9;
        _market.originationsEnabled = true;
        _data = LoanMarket.Data(false, 100, 10000, 100, 0, 0, 0);
        _mockMarket();
        _mockDebt(0);
    }

    modifier givenDisabled() {
        _risk.disable("");
        _;
    }
    modifier givenInactive() {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_risk));
        _;
    }
    modifier givenReEnabled() {
        _risk.disable("");
        _risk.reEnable();
        _;
    }
    modifier givenOperator() {
        _risk.setConfigOperator(_operator);
        _;
    }
    modifier givenAdmin(address caller_) {
        _grantAdmin(caller_);
        vm.startPrank(caller_);
        _;
        vm.stopPrank();
    }

    function _grantAdmin(address caller_) internal {
        vm.assume(caller_ != address(0));
        if (!_roles.hasRole(caller_, ADMIN_ROLE)) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
    }

    modifier givenCache() {
        _risk.setPriceCache(address(_cache));
        _cache.cachePrice(address(_ohm), address(_asset));
        // This mock is not a Kernel Policy. Inject only authoritative membership at the boundary.
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(true)
        );
        _;
    }

    function _mockMarket() internal {
        vm.mockCall(
            address(_floan),
            abi.encodeCall(IFLOANv1.getMarket, (_MARKET)),
            abi.encode(_market)
        );
        vm.mockCall(
            address(_floan),
            abi.encodeCall(IFLOANv1.getMarketConfigData, (_MARKET)),
            abi.encode(abi.encode(_data))
        );
    }

    function _mockDebt(uint256 debt_) internal {
        vm.mockCall(
            address(_floan),
            abi.encodeCall(IFLOANv1.getMarketPrincipalDue, (_MARKET)),
            abi.encode(debt_)
        );
    }

    function _prices() internal pure returns (IBurnerLoansCore.PriceSnapshot memory) {
        return IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18);
    }

    function _expectInactive() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_risk)
            )
        );
    }

    function _mockDirectPrice(address asset_, uint256 price_, uint48 timestamp_) internal {
        vm.mockCall(
            address(_price),
            abi.encodeWithSignature("getPrice(address,uint8)", asset_, IPRICEv2.Variant.CURRENT),
            abi.encode(price_, timestamp_)
        );
    }

    function _assertSnapshot(
        IBurnerLoansCore.PriceSnapshot memory p_,
        uint256 ohm_,
        uint256 asset_,
        uint256 backing_
    ) internal pure {
        assertEq(p_.ohmUsdPrice, ohm_, "OHM price");
        assertEq(p_.collateralUsdPrice, asset_, "collateral price");
        assertEq(p_.backingPerOhmUsd, backing_, "backing price");
    }

    function _configurationHash() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _risk.configOperator(),
                    _risk.backingOracle(),
                    _risk.priceCache(),
                    _risk.priceCacheMaxAge(),
                    _risk.gracePeriod(),
                    _ohm.totalSupply(),
                    _asset.totalSupply()
                )
            );
    }
}
