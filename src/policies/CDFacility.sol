// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {RolesConsumer, ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

import {IConvertibleDepositToken} from "src/policies/interfaces/IConvertibleDepositToken.sol";

import {FullMath} from "src/libraries/FullMath.sol";

contract CDFacility is Policy, RolesConsumer {
    using FullMath for uint256;

    struct CD {
        uint256 deposit;
        uint256 convertable;
        uint256 expiry;
    }

    // ========== EVENTS ========== //

    event CreatedCD(address user, uint48 expiry, uint256 deposit, uint256 convert);
    event ConvertedCD(address user, uint256 deposit, uint256 convert);
    event ReclaimedCD(address user, uint256 deposit);
    event SweptYield(address receiver, uint256 amount);

    // ========== STATE VARIABLES ========== //

    // Constants
    uint256 public constant DECIMALS = 1e18;

    // Modules
    TRSRYv1 public TRSRY;
    MINTRv1 public MINTR;

    // Tokens
    ERC20 public reserve;
    ERC4626 public sReserve;
    IConvertibleDepositToken public cdUSDS;

    // State variables
    uint256 public totalDeposits;
    uint256 public totalShares;
    mapping(address => CD[]) public cdInfo;
    uint256 public redeemRate;

    // ========== ERRORS ========== //

    error CDFacility_InvalidParams(string reason);

    error Misconfigured();

    // ========== SETUP ========== //

    constructor(
        Kernel kernel_,
        address reserve_,
        address sReserve_,
        address cdUSDS_
    ) Policy(kernel_) {
        if (reserve_ == address(0)) revert CDFacility_InvalidParams("Reserve address cannot be 0");
        if (sReserve_ == address(0))
            revert CDFacility_InvalidParams("sReserve address cannot be 0");
        if (cdUSDS_ == address(0)) revert CDFacility_InvalidParams("cdUSDS address cannot be 0");

        reserve = ERC20(reserve_);
        sReserve = ERC4626(sReserve_);

        // TODO shift to module and dependency injection
        cdUSDS = IConvertibleDepositToken(cdUSDS_);
    }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
    }

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode mintrKeycode = toKeycode("MINTR");

        permissions = new Permissions[](2);
        permissions[0] = Permissions(mintrKeycode, MINTR.increaseMintApproval.selector);
        permissions[1] = Permissions(mintrKeycode, MINTR.mintOhm.selector);
    }

    // ========== EMISSIONS MANAGER ========== //

    /// @notice allow emissions manager to create new convertible debt
    /// @param  user owner of the convertible debt
    /// @param  amount amount of reserve tokens deposited
    /// @param  convertable amount of OHM that can be converted into
    /// @param  expiry timestamp when conversion expires
    function addNewCD(
        address user,
        uint256 amount,
        uint256 convertable,
        uint256 expiry
    ) external onlyRole("CD_Auctioneer") {
        // transfer in debt token
        reserve.transferFrom(user, address(this), amount);

        // deploy debt token into vault
        totalShares += sReserve.deposit(amount, address(this));

        // add mint approval for conversion
        MINTR.increaseMintApproval(address(this), convertable);

        // store convertable deposit info and mint cdUSDS
        cdInfo[user].push(CD(amount, convertable, expiry));

        // TODO consider if the ERC20 should custody the deposit token
        cdUSDS.mint(user, amount);
    }

    // ========== CD Position Owner ========== //

    /// @notice allow user to convert their convertible debt before expiration
    /// @param  cds CD indexes to convert
    /// @param  amounts CD token amounts to convert
    function convertCD(
        uint256[] memory cds,
        uint256[] memory amounts
    ) external returns (uint256 converted) {
        if (cds.length != amounts.length) revert Misconfigured();

        uint256 totalDeposit;

        // iterate through and burn CD tokens, adding deposit and conversion amounts to running totals
        for (uint256 i; i < cds.length; ++i) {
            CD storage cd = cdInfo[msg.sender][i];
            if (cd.expiry < block.timestamp) continue;

            uint256 amount = amounts[i];
            uint256 converting = ((cd.convertable * amount) / cd.deposit);

            // increment running totals
            totalDeposit += amount;
            converted += converting;

            // decrement deposit info
            cd.convertable -= converting; // reverts on overflow
            cd.deposit -= amount;
        }

        // compute and account for shares to send to treasury
        uint256 shares = sReserve.previewWithdraw(totalDeposit);
        totalShares -= shares;

        // burn cdUSDS
        cdUSDS.burn(msg.sender, totalDeposit);

        // mint ohm and send underlying debt token to treasury
        MINTR.mintOhm(msg.sender, converted);
        sReserve.transfer(address(TRSRY), shares);

        emit ConvertedCD(msg.sender, totalDeposit, converted);
    }

    /// @notice allow user to reclaim their convertible debt deposits after expiration
    /// @param  cds CD indexes to return
    /// @param  amounts amounts of CD tokens to burn
    /// @return returned total reserve tokens returned
    function returnDeposit(
        uint256[] memory cds,
        uint256[] memory amounts
    ) external returns (uint256 returned) {
        if (cds.length != amounts.length) revert Misconfigured();

        uint256 unconverted;

        // iterate through and burn CD tokens, adding deposit and conversion amounts to running totals
        for (uint256 i; i < cds.length; ++i) {
            CD memory cd = cdInfo[msg.sender][cds[i]];
            if (cd.expiry >= block.timestamp) continue;

            uint256 amount = amounts[i];
            uint256 convertable = ((cd.convertable * amount) / cd.deposit);

            returned += amount;
            unconverted += convertable;

            // decrement deposit info
            cd.deposit -= amount;
            cd.convertable -= convertable; // reverts on overflow
        }

        // burn cdUSDS
        cdUSDS.burn(msg.sender, returned);

        // compute shares to redeem
        uint256 shares = sReserve.previewWithdraw(returned);
        totalShares -= shares;

        // return debt token to user
        sReserve.redeem(shares, msg.sender, address(this));

        // decrease mint approval to reflect tokens that will not convert
        MINTR.decreaseMintApproval(address(this), unconverted);

        emit ReclaimedCD(msg.sender, returned);
    }

    // ========== cdUSDS ========== //

    /// @notice allow user to mint cdUSDS
    /// @notice redeeming without a CD may be at a discount
    /// @param  amount of reserve token
    /// @return tokensOut cdUSDS out (1:1 with USDS in)
    function mint(uint256 amount) external returns (uint256 tokensOut) {
        tokensOut = amount;

        reserve.transferFrom(msg.sender, address(this), amount);
        totalShares += sReserve.deposit(amount, msg.sender);

        cdUSDS.mint(msg.sender, amount);
    }

    /// @notice allow non cd holder to sell cdUSDS for USDS
    /// @notice the amount of USDS per cdUSDS is not 1:1
    /// @notice convertible depositors should use returnDeposit() for 1:1
    function redeem(uint256 amount) external returns (uint256 tokensOut) {
        // burn cdUSDS
        cdUSDS.burn(msg.sender, amount);

        // compute shares to redeem
        tokensOut = redeemOutput(amount);
        uint256 shares = sReserve.previewWithdraw(tokensOut);
        totalShares -= shares;

        // return debt token to user
        sReserve.redeem(shares, msg.sender, address(this));
    }

    // ========== YIELD MANAGER ========== //

    /// @notice allow yield manager to sweep yield accrued on reserves
    /// @return yield yield in reserve token terms
    /// @return shares yield in sReserve token terms
    function sweepYield()
        external
        onlyRole("CD_Yield_Manager")
        returns (uint256 yield, uint256 shares)
    {
        yield = sReserve.previewRedeem(totalShares) - cdUSDS.totalSupply();
        shares = sReserve.previewWithdraw(yield);
        totalShares -= shares;
        sReserve.transfer(msg.sender, shares);

        emit SweptYield(msg.sender, yield);
    }

    // ========== GOVERNOR ========== //

    /// @notice allow admin to change redeem rate
    /// @dev    redeem rate must be lower than or equal to 1:1
    function setRedeemRate(uint256 newRate) external onlyRole("CD_Admin") {
        if (newRate > DECIMALS) revert Misconfigured();
        redeemRate = newRate;
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice get yield accrued on deposited reserve tokens
    /// @return yield in reserve token terms
    function yieldAccrued() external view returns (uint256) {
        return sReserve.previewRedeem(totalShares) - totalDeposits;
    }

    /// @notice amount of deposit tokens out for amount of cdUSDS redeemed
    /// @param  amount of cdUSDS in
    /// @return output amount of USDS out
    function redeemOutput(uint256 amount) public view returns (uint256) {
        return (amount * redeemRate) / DECIMALS;
    }
}
