// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Import system dependencies
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {ROLESv1, RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import "src/Kernel.sol";

// Import interfaces
import {IPohm, IPreviousPohm} from "policies/interfaces/IPohm.sol";
import {IgOHM} from "interfaces/IgOHM.sol";

// Import types
import {ERC20} from "solmate/tokens/ERC20.sol";

// Import libraries
import {TransferHelper} from "libraries/TransferHelper.sol";

contract Pohm is IPohm, Policy, RolesConsumer {
    using TransferHelper for ERC20;

    // ========= STATE VARIABLES ========= //

    // Modules
    MINTRv1 public MINTR;
    TRSRYv1 public TRSRY;

    // Olympus Contracts
    IPreviousPohm public previous;

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
        previous = IPreviousPohm(previous_);
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

    /// @inheritdoc IPohm
    function claim(address to_, uint256 amount_) external {
        // Calculate OHM amount to mint based on DAI amount, current circulating supply, and previously claimed OHM
        uint256 ohmAmount = _claim(amount_);

        // Mint OHM to user
        MINTR.increaseMintApproval(address(this), ohmAmount);
        MINTR.mintOhm(to_, ohmAmount);
    }

    //============================================================================================//
    //                                   MANAGEMENT FUNCTIONS                                     //
    //============================================================================================//

    /// @inheritdoc IPohm
    function transfer(address to_, uint256 amount_) external {
        if (terms[msg.sender].percent == 0) revert POHM_NoClaim();

        // Cache storage variables
        Term memory accountTerms = terms[msg.sender];

        // Calculate pro-rata portion of sender's claim terms to transfer
        uint256 percentTransfered = (amount_ * 1e6) / accountTerms.percent;
        uint256 gTransfered = (accountTerms.gClaimed * percentTransfered) / 1e6;
        uint256 maxTransfered = (accountTerms.max * percentTransfered) / 1e6;

        // Reduce sender's claim terms
        accountTerms.percent -= amount_;
        accountTerms.gClaimed -= gTransfered;
        accountTerms.max -= maxTransfered;
        terms[msg.sender] = accountTerms;

        // Increase receiver's claim terms
        terms[to_].percent += amount_;
        terms[to_].gClaimed += gTransfered;
        terms[to_].max += maxTransfered;
    }

    /// @inheritdoc IPohm
    function pushWalletChange(address newAddress_) external {
        if (terms[msg.sender].percent == 0) revert POHM_NoClaim();
        walletChange[msg.sender] = newAddress_;
    }

    /// @inheritdoc IPohm
    function pullWalletChange(address oldAddress_) external {
        if (walletChange[oldAddress_] != msg.sender) revert POHM_NoWalletChange();
        if (terms[msg.sender].percent != 0) revert POHM_AlreadyHasClaim();

        walletChange[oldAddress_] = address(0);
        terms[msg.sender] = terms[oldAddress_];
        delete terms[oldAddress_];
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc IPohm
    function redeemableFor(address account_) public view returns (uint256) {
        // Cache storage variables
        Term memory accountTerms = terms[account_];

        uint256 circulatingSupply = getCirculatingSupply();
        uint256 accountClaimed = getAccountClaimed(account_);

        // Calculate max amount of OHM that can be claimed based on user's percentage term and current circulating supply
        // Make sure that this does not exceed the user's max term
        uint256 max = (circulatingSupply * accountTerms.percent) / 1e6;
        max = max > accountTerms.max ? accountTerms.max : max;

        // Return the difference between the max and the amount already claimed
        return max - accountClaimed;
    }

    /// Note: This is not the true circulating supply, but it matches that of the previous pOHM contracts
    /// @inheritdoc IPohm
    function getCirculatingSupply() public view returns (uint256) {
        return OHM.totalSupply() - OHM.balanceOf(dao);
    }

    /// @inheritdoc IPohm
    function getAccountClaimed(address account_) public view returns (uint256) {
        Term memory accountTerms = terms[account_];
        return gOHM.balanceFrom(accountTerms.gClaimed);
    }

    //============================================================================================//
    //                                       ADMIN FUNCTIONS                                      //
    //============================================================================================//

    /// @inheritdoc IPohm
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

    /// @inheritdoc IPohm
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

        // Value OHM at 1 DAI. So convert 18 decimal DAI value to 9 decimal OHM value
        toSend = (amount_ * 1e9) / 1e18;

        // Make sure user isn't violating claim terms
        if (redeemableFor(msg.sender) < toSend) revert POHM_ClaimMoreThanVested();
        if ((accountTerms.max - getAccountClaimed(msg.sender)) < toSend)
            revert POHM_ClaimMoreThanMax();

        // Increment user's claimed amount based on rebase-agnostic gOHM value
        terms[msg.sender].gClaimed += gOHM.balanceTo(toSend);

        // Pull DAI from user
        DAI.safeTransferFrom(msg.sender, address(TRSRY), amount_);
    }
}
