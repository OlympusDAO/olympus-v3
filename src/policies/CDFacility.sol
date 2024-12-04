// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {RolesConsumer, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";

import {FullMath} from "libraries/FullMath.sol";

interface CDRC20 {
    function mint(address to, uint256 amount) external;
    function convertFor(uint256 amount) external view returns (uint256);
}

contract CDFacility is Policy, RolesConsumer {
    using FullMath for uint256;

    // ========== EVENTS ========== //

    event CreatedCD(address user, uint48 expiry, uint256 deposit, uint256 convert);
    event ConvertedCD(address user, uint256 deposit, uint256 convert);
    event ReclaimedCD(address user, uint256 deposit);
    event SweptYield(address receiver, uint256 amount);

    // ========== DATA STRUCTURES ========== //

    struct ConvertibleDebt {
        uint256 deposit;
        uint256 convert;
        uint256 expiry;
    }

    // ========== STATE VARIABLES ========== //

    // Modules
    TRSRYv1 public TRSRY;
    MINTRv1 public MINTR;

    // Tokens
    ERC20 public reserve;
    ERC4626 public sReserve;

    // State variables
    mapping(address => ConvertibleDebt[]) public cdsFor;
    uint256 public totalDeposits;
    uint256 public totalShares;

    // ========== SETUP ========== //

    constructor(Kernel kernel_, address reserve_, address sReserve_) Policy(kernel_) {
        reserve = ERC20(reserve_);
        sReserve = ERC4626(sReserve_);
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
    /// @param user owner of the convertible debt
    /// @param amount amount of reserve tokens deposited
    /// @param token CD Token with terms for deposit
    function addNewCD(
        address user,
        uint256 amount,
        CDRC20 token
    ) external onlyRole("Emissions_Manager") {
        // transfer in debt token
        reserve.transferFrom(user, address(this), amount);

        // deploy debt token into vault
        totalShares += sReserve.deposit(amount, address(this));

        // add mint approval for conversion
        MINTR.increaseMintApproval(address(this), token.convertFor(amount));

        // mint CD token
        token.mint(user, amount);
    }

    // ========== CD Position Owner ========== //

    /// @notice allow user to convert their convertible debt before expiration
    /// @param ids IDs of convertible debts to convert
    /// @return totalDeposit total reserve tokens relinquished
    /// @return totalConvert total convert tokens sent
    function convertCD(
        CDRC20[] memory tokens,
        uint256[] memory amounts
    ) external returns (uint256 totalDeposit, uint256 totalConvert) {
        // iterate through list of ids, add to totals, and delete cd entries
        for (uint256 i; i < ids.length; ++i) {
            ConvertibleDebt memory cd = cdsFor[msg.sender][i];
            if (cd.convert > 0 && cd.expiry <= block.timestamp) {
                totalDeposit += cd.deposit;
                totalConvert += cd.convert;
                delete cdsFor[msg.sender][i];
            }
        }

        // compute shares to send
        uint256 shares = sReserve.previewWithdraw(totalDeposit);
        totalShares -= shares;

        // mint convert token, and send wrapped debt token to treasury
        MINTR.mintOhm(msg.sender, totalConvert);
        sReserve.transfer(address(TRSRY), shares);

        emit ConvertedCD(msg.sender, totalDeposit, totalConvert);
    }

    /// @notice allow user to reclaim their convertible debt deposits after expiration
    /// @param ids IDs of convertible debts to reclaim
    /// @return totalDeposit total reserve tokens relinquished
    function reclaimDeposit(uint256[] memory ids) external returns (uint256 totalDeposit) {
        // iterate through list of ids, add to total, and delete cd entries
        for (uint256 i; i < ids.length; ++i) {
            ConvertibleDebt memory cd = cdsFor[msg.sender][i];
            if (cd.expiry > block.timestamp) {
                // reduce mint approval
                MINTR.decreaseMintApproval(address(this), cd.convert);

                totalDeposit += cd.deposit;
                delete cdsFor[msg.sender][i];
            }
        }

        // compute shares to redeem
        uint256 shares = sReserve.previewWithdraw(totalDeposit);
        totalShares -= shares;

        // undeploy and return debt token to user
        sReserve.redeem(shares, msg.sender, address(this));

        emit ReclaimedCD(msg.sender, totalDeposit);
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
        yield = sReserve.previewRedeem(totalShares) - totalDeposits;
        shares = sReserve.previewWithdraw(yield);
        sReserve.transfer(msg.sender, shares);

        emit SweptYield(msg.sender, yield);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice get yield accrued on deposited reserve tokens
    /// @return yield in reserve token terms
    function yieldAccrued() external view returns (uint256) {
        return sReserve.previewRedeem(totalShares) - totalDeposits;
    }

    /// @notice return all existing CD IDs for user
    /// @param user to search for
    /// @return ids for user
    function idsForUser(address user) external view returns (uint256[] memory ids) {
        uint256 j;
        for (uint256 i; i < cdsFor[user].length; ++i) {
            ConvertibleDebt memory cd = cdsFor[user][i];
            if (cd.deposit > 0) ids[j] = i;
            ++j;
        }
    }

    /// @notice query whether a given CD ID is expired
    /// @param user who holds the CD
    /// @param id of the CD to query
    /// @return status whether the CD is expired
    function idExpired(address user, uint256 id) external view returns (bool status) {
        status = cdsFor[user][id].expiry > block.timestamp;
    }
}
