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

contract Pohm is Policy, RolesConsumer {
    using TransferHelper for ERC20;

    // ========= ERRORS ========= //

    error POHM_NoClaim();
    error POHM_AlreadyHasClaim();
    error POHM_NoWalletChange();
    error POHM_AllocationLimitViolation();

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
    MINTRv1 public mintr;
    TRSRYv1 public trsry;

    // Tokens
    ERC20 public OHM;
    IgOHM public gOHM;
    ERC20 public DAI;

    // Accounting
    mapping(address => Term) public terms;
    mapping(address => address) public walletChange;
    uint256 public totalAllocated; // PRECISION = 1_000_000 (i.e. 5000 = 0.5%)
    uint256 public maximumAllocated; // PRECISION = 1_000_000 (i.e. 5000 = 0.5%)

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(address _kernel) Kernel(_kernel) {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = Keycode.MINTR;
        dependencies[1] = Keycode.ROLES;

        MINTR = MINTRv1(getModuleAddress((dependencies[0])));
        ROLES = ROLESv1(getModuleAddress((dependencies[1])));
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
        permissions[1] = Permissions(mintrKeycode, MINTR.increaseMintApproval);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    function claim(address to_, uint256 amount_, bool stake_) external {
        uint256 ohmAmount = _claim(amount_);

        if (stake_) {
            // TODO: Switch OHM to OlympusERC20Token and approve the staking contract
            _stake(ohmAmount);
        } else {
            OHM.safeTransfer(to_, ohmAmount);
        }
    }

    //============================================================================================//
    //                                   MANAGEMENT FUNCTIONS                                     //
    //============================================================================================//

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

        return (max - accountClaimed) * 1e9;
    }

    function getCirculatingSupply() public view returns (uint256) {
        // TODO
        return 0;
    }

    function getAccountClaimed(address account_) public view returns (uint256) {
        Term memory accountTerms = terms[account_];
        return gOHM.balanceFrom(terms.gClaimed);
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    function migrate(address[] calldata accounts_) external onlyRole("pohm_admin") {
        uint256 length = accounts_.length;
        for (uint256 i; i < length; ) {
            Term memory accountTerm = previous.terms(accounts_[i]);
            setTerms(accounts_[i], accountTerm.percent, accountTerm.gClaimed, accountTerm.max);
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
}
