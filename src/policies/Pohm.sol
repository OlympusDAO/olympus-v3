// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Import system dependencies
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {ROLESv1, RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import "src/Kernel.sol";

// Import interfaces
// import {IPohm} from "policies/interfaces/IPohm.sol";
import {IgOHM} from "interfaces/IgOHM.sol";

// Import types
import {ERC20} from "solmate/tokens/ERC20.sol";

// Import libraries
import {TransferHelper} from "libraries/TransferHelper.sol";

interface IpOHM {
    function terms(address account_) external view returns (Pohm.Term memory);
}

contract Pohm is Policy, RolesConsumer {
    using TransferHelper for ERC20;

    // ========= ERRORS ========= //

    error POHM_NoClaim();
    error POHM_AlreadyHasClaim();
    error POHM_NoWalletChange();
    error POHM_AllocationLimitViolation();
    error POHM_ClaimMoreThanVested();
    error POHM_ClaimMoreThanMax();

    // ========= EVENTS ========= //

    event Claim(address indexed account, uint256 amount, bool stake);

    // ========= DATA STRUCTURES ========= //

    struct Term {
        uint256 percent; // PRECISION = 1_000_000 (i.e. 5000 = 0.5%)
        uint256 gClaimed; // Rebase agnostic # of tokens claimed
        uint256 max; // Maximum nominal OHM amount claimable
    }

    // ========= STATE VARIABLES ========= //

    // Modules
    MINTRv1 public MINTR;
    TRSRYv1 public TRSRY;

    // Olympus Contracts
    IpOHM public previous; // TODO wrap in some interface

    // Tokens
    ERC20 public OHM;
    IgOHM public gOHM;
    ERC20 public DAI;

    // Addresses
    address public dao;

    // Accounting
    mapping(address => Term) public terms;
    mapping(address => address) public walletChange;
    uint256 public totalAllocated; // PRECISION = 1_000_000 (i.e. 5000 = 0.5%)
    uint256 public maximumAllocated; // PRECISION = 1_000_000 (i.e. 5000 = 0.5%)

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address previous_,
        address ohm_,
        address gohm_,
        address dai_,
        address dao_,
        uint256 maximumAllocated_
    ) Policy(kernel_) {
        previous = IpOHM(previous_);
        OHM = ERC20(ohm_);
        gOHM = IgOHM(gohm_);
        DAI = ERC20(dai_);
        dao = dao_;
        maximumAllocated = maximumAllocated_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("TRSRY");
        dependencies[2] = toKeycode("ROLES");

        MINTR = MINTRv1(getModuleAddress((dependencies[0])));
        TRSRY = TRSRYv1(getModuleAddress((dependencies[1])));
        ROLES = ROLESv1(getModuleAddress((dependencies[2])));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode mintrKeycode = MINTR.KEYCODE();

        permissions = new Permissions[](2);
        permissions[0] = Permissions(mintrKeycode, MINTR.mintOhm.selector);
        permissions[1] = Permissions(mintrKeycode, MINTR.increaseMintApproval.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    function claim(address to_, uint256 amount_) external {
        uint256 ohmAmount = _claim(amount_);
        MINTR.increaseMintApproval(address(this), ohmAmount);
        MINTR.mintOhm(to_, ohmAmount);
    }

    //============================================================================================//
    //                                   MANAGEMENT FUNCTIONS                                     //
    //============================================================================================//

    function transfer(address to_, uint256 amount_) external {
        if (terms[msg.sender].percent == 0) revert POHM_NoClaim();

        Term memory accountTerms = terms[msg.sender];

        uint256 percentTransfered = (amount_ * 1e6) / accountTerms.percent;
        uint256 gTransfered = (accountTerms.gClaimed * percentTransfered) / 1e6;
        uint256 maxTransfered = (accountTerms.max * percentTransfered) / 1e6;

        accountTerms.percent -= amount_;
        accountTerms.gClaimed -= gTransfered;
        accountTerms.max -= maxTransfered;
        terms[msg.sender] = accountTerms;

        terms[to_].percent += amount_;
        terms[to_].gClaimed += gTransfered;
        terms[to_].max += maxTransfered;
    }

    function pushWalletChange(address newAddress_) external {
        if (terms[msg.sender].percent == 0) revert POHM_NoClaim();
        walletChange[msg.sender] = newAddress_;
    }

    function pullWalletChange(address oldAddress_) external {
        // TODO: Do we need to check that the old address had a non-zero percent claim?
        if (walletChange[oldAddress_] != msg.sender) revert POHM_NoWalletChange();
        if (terms[msg.sender].percent != 0) revert POHM_AlreadyHasClaim();

        walletChange[oldAddress_] = address(0);
        terms[msg.sender] = terms[oldAddress_];
        delete terms[oldAddress_];
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    function redeemableFor(address account_) public view returns (uint256) {
        Term memory accountTerms = terms[account_];

        uint256 circulatingSupply = getCirculatingSupply();
        uint256 accountClaimed = getAccountClaimed(account_);

        uint256 max = (circulatingSupply * accountTerms.percent) / 1e6;
        max = max > accountTerms.max ? accountTerms.max : max;

        return max - accountClaimed;
    }

    // Note: This is not the true circulating supply, but it matches that of the previous pOHM contracts
    function getCirculatingSupply() public view returns (uint256) {
        return OHM.totalSupply() - OHM.balanceOf(dao);
    }

    function getAccountClaimed(address account_) public view returns (uint256) {
        Term memory accountTerms = terms[account_];
        return gOHM.balanceFrom(accountTerms.gClaimed);
    }

    //============================================================================================//
    //                                       ADMIN FUNCTIONS                                      //
    //============================================================================================//

    function migrate(address[] calldata accounts_) external onlyRole("pohm_admin") {
        uint256 length = accounts_.length;
        for (uint256 i; i < length; ) {
            Term memory accountTerm = previous.terms(accounts_[i]);
            setTerms(accounts_[i], accountTerm.percent, accountTerm.gClaimed, accountTerm.max);

            unchecked {
                ++i;
            }
        }
    }

    function setTerms(
        address account_,
        uint256 percent_,
        uint256 gClaimed_,
        uint256 max_
    ) public onlyRole("pohm_admin") {
        if (terms[account_].percent != 0) revert POHM_AlreadyHasClaim();
        if (totalAllocated + percent_ > maximumAllocated) revert POHM_AllocationLimitViolation();

        terms[account_] = Term(percent_, gClaimed_, max_);
        totalAllocated += percent_;
    }

    //============================================================================================//
    //                                     INTERNAL FUNCTIONS                                     //
    //============================================================================================//

    function _claim(uint256 amount_) internal returns (uint256 toSend) {
        Term memory accountTerms = terms[msg.sender];

        toSend = (amount_ * 1e9) / 1e18;

        if (redeemableFor(msg.sender) < toSend) revert POHM_ClaimMoreThanVested();
        if ((accountTerms.max - getAccountClaimed(msg.sender)) < toSend)
            revert POHM_ClaimMoreThanMax(); // TODO this is actually redundant since redeemableFor limits to max

        terms[msg.sender].gClaimed += gOHM.balanceTo(toSend);

        DAI.safeTransferFrom(msg.sender, address(TRSRY), amount_);
    }
}
