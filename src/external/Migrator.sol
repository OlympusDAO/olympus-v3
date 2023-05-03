    /**
 *Submitted for verification at Etherscan.io on 2021-11-24
*/

// SPDX-License-Identifier: AGPL-3.0-or-later

// File: libraries/SafeMath.sol
pragma solidity >=0.7.5;

import "src/libraries/SafeMath.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IxGDAO.sol";
import "src/interfaces/IsGDAO.sol";

// File: interfaces/IOlympusAuthority.sol

interface IOlympusAuthority {
    /* ========== EVENTS ========== */
    
    event GovernorPushed(address indexed from, address indexed to, bool _effectiveImmediately);
    event GuardianPushed(address indexed from, address indexed to, bool _effectiveImmediately);    
    event PolicyPushed(address indexed from, address indexed to, bool _effectiveImmediately);    
    event VaultPushed(address indexed from, address indexed to, bool _effectiveImmediately);    

    event GovernorPulled(address indexed from, address indexed to);
    event GuardianPulled(address indexed from, address indexed to);
    event PolicyPulled(address indexed from, address indexed to);
    event VaultPulled(address indexed from, address indexed to);

    /* ========== VIEW ========== */
    
    function governor() external view returns (address);
    function guardian() external view returns (address);
    function policy() external view returns (address);
    function vault() external view returns (address);
}
// File: types/OlympusAccessControlled.sol

abstract contract OlympusAccessControlled {

    /* ========== EVENTS ========== */

    event AuthorityUpdated(IOlympusAuthority indexed authority);

    string UNAUTHORIZED = "UNAUTHORIZED"; // save gas

    /* ========== STATE VARIABLES ========== */

    IOlympusAuthority public authority;


    /* ========== Constructor ========== */

    constructor(IOlympusAuthority _authority) {
        authority = _authority;
        emit AuthorityUpdated(_authority);
    }
    

    /* ========== MODIFIERS ========== */
    
    modifier onlyGovernor() {
        require(msg.sender == authority.governor(), UNAUTHORIZED);
        _;
    }
    
    modifier onlyGuardian() {
        require(msg.sender == authority.guardian(), UNAUTHORIZED);
        _;
    }
    
    modifier onlyPolicy() {
        require(msg.sender == authority.policy(), UNAUTHORIZED);
        _;
    }

    modifier onlyVault() {
        require(msg.sender == authority.vault(), UNAUTHORIZED);
        _;
    }
    
    /* ========== GOV ONLY ========== */
    
    function setAuthority(IOlympusAuthority _newAuthority) external onlyGovernor {
        authority = _newAuthority;
        emit AuthorityUpdated(_newAuthority);
    }
}

// File: interfaces/ITreasuryV1.sol

interface ITreasuryV1 {
    function withdraw(uint256 amount, address token) external;
    function manage(address token, uint256 amount) external;
    function valueOf(address token, uint256 amount) external view returns (uint256);
    function excessReserves() external view returns (uint256);
}
// File: interfaces/IStakingV1.sol

interface IStakingV1 {
    function unstake(uint256 _amount, bool _trigger) external;

    function index() external view returns (uint256);
}
// File: interfaces/IUniswapV2Router.sol

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function addLiquidity(
        address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin, address to, uint deadline
        ) external returns (uint amountA, uint amountB, uint liquidity);
        
    function removeLiquidity(
        address tokenA, address tokenB, uint liquidity, uint amountAMin, uint amountBMin, address to, uint deadline
        ) external returns (uint amountA, uint amountB);
}
// File: interfaces/IOwnable.sol

interface IOwnable {
  function owner() external view returns (address);

  function renounceManagement() external;
  
  function pushManagement( address newOwner_ ) external;
  
  function pullManagement() external;
}
// File: interfaces/IStaking.sol

interface IStaking {
    function stake(
        address _to,
        uint256 _amount,
        bool _rebasing,
        bool _claim
    ) external returns (uint256);

    function claim(address _recipient, bool _rebasing) external returns (uint256);

    function forfeit() external returns (uint256);

    function toggleLock() external;

    function unstake(
        address _to,
        uint256 _amount,
        bool _trigger,
        bool _rebasing
    ) external returns (uint256);

    function wrap(address _to, uint256 _amount) external returns (uint256 gBalance_);

    function unwrap(address _to, uint256 _amount) external returns (uint256 sBalance_);

    function rebase() external;

    function index() external view returns (uint256);

    function contractBalance() external view returns (uint256);

    function totalStaked() external view returns (uint256);

    function supplyInWarmup() external view returns (uint256);
}

// File: interfaces/ITreasury.sol

interface ITreasury {
    function deposit(
        uint256 _amount,
        address _token,
        uint256 _profit
    ) external returns (uint256);

    function withdraw(uint256 _amount, address _token) external;

    function tokenValue(address _token, uint256 _amount) external view returns (uint256 value_);

    function mint(address _recipient, uint256 _amount) external;

    function manage(address _token, uint256 _amount) external;

    function incurDebt(uint256 amount_, address token_) external;

    function repayDebtWithReserve(uint256 amount_, address token_) external;

    function excessReserves() external view returns (uint256);
}

// File: libraries/SafeERC20.sol

/// @notice Safe IERC20 and ETH transfer library that safely handles missing return values.
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v3-periphery/blob/main/contracts/libraries/TransferHelper.sol)
/// Taken from Solmate
library SafeERC20 {
    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );

        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );

        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    function safeApprove(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(IERC20.approve.selector, to, amount)
        );

        require(success && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }

    function safeTransferETH(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}(new bytes(0));

        require(success, "ETH_TRANSFER_FAILED");
    }
}

// File: interfaces/IwsOHM.sol

// Old wsOHM interface
interface IwsOHM is IERC20 {
  function wrap(uint256 _amount) external returns (uint256);

  function unwrap(uint256 _amount) external returns (uint256);

  function wOHMTosOHM(uint256 _amount) external view returns (uint256);

  function sOHMTowOHM(uint256 _amount) external view returns (uint256);
}

contract GdaoTokenMigrator is OlympusAccessControlled {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IxGDAO;
    using SafeERC20 for IsGDAO;
    using SafeERC20 for IwsOHM;

    /* ========== MIGRATION ========== */

    event TimelockStarted(uint256 block, uint256 end);
    event Migrated(address staking, address treasury);
    event Funded(uint256 amount);
    event Defunded(uint256 amount);

    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable oldGDAO;
    IsGDAO public immutable oldsGDAO;
    IwsOHM public immutable oldwsOHM;
    ITreasuryV1 public immutable oldTreasury;
    IStakingV1 public immutable oldStaking;

    IUniswapV2Router public immutable sushiRouter;
    IUniswapV2Router public immutable uniRouter;

    IxGDAO public xGDAO;
    ITreasury public newTreasury;
    IStaking public newStaking;
    IERC20 public newGDAO;

    bool public gdaoMigrated;
    bool public shutdown;

    uint256 public immutable timelockLength;
    uint256 public timelockEnd;

    uint256 public oldSupply;

    constructor(
        address _oldGDAO,
        address _oldsGDAO,
        address _oldTreasury,
        address _oldStaking,
        address _oldwsOHM,
        address _sushi,
        address _uni,
        uint256 _timelock,
        address _authority
    ) OlympusAccessControlled(IOlympusAuthority(_authority)) {
        require(_oldGDAO != address(0), "Zero address: GDAO");
        oldGDAO = IERC20(_oldGDAO);
        require(_oldsGDAO != address(0), "Zero address: sGDAO");
        oldsGDAO = IsGDAO(_oldsGDAO);
        require(_oldTreasury != address(0), "Zero address: Treasury");
        oldTreasury = ITreasuryV1(_oldTreasury);
        require(_oldStaking != address(0), "Zero address: Staking");
        oldStaking = IStakingV1(_oldStaking);
        require(_oldwsOHM != address(0), "Zero address: wsOHM");
        oldwsOHM = IwsOHM(_oldwsOHM);
        require(_sushi != address(0), "Zero address: Sushi");
        sushiRouter = IUniswapV2Router(_sushi);
        require(_uni != address(0), "Zero address: Uni");
        uniRouter = IUniswapV2Router(_uni);
        timelockLength = _timelock;
    }

    /* ========== MIGRATION ========== */

    enum TYPE {
        UNSTAKED,
        STAKED,
        WRAPPED
    }

    // migrate OHMv1, sGDAOv1, or wsOHM for OHMv2, sGDAOv2, or xGDAO
    function migrate(
        uint256 _amount,
        TYPE _from,
        TYPE _to
    ) external {
        require(!shutdown, "Shut down");

        uint256 wAmount = oldwsOHM.sOHMTowOHM(_amount);

        if (_from == TYPE.UNSTAKED) {
            require(gdaoMigrated, "Only staked until migration");
            oldGDAO.safeTransferFrom(msg.sender, address(this), _amount);
        } else if (_from == TYPE.STAKED) {
            oldsGDAO.safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            oldwsOHM.safeTransferFrom(msg.sender, address(this), _amount);
            wAmount = _amount;
        }

        if (gdaoMigrated) {
            require(oldSupply >= oldGDAO.totalSupply(), "OHMv1 minted");
            _send(wAmount, _to);
        } else {
            xGDAO.mint(msg.sender, wAmount);
        }
    }

    // migrate all olympus tokens held
    function migrateAll(TYPE _to) external {
        require(!shutdown, "Shut down");

        uint256 gdaoBal = 0;
        uint256 sGDAOBal = oldsGDAO.balanceOf(msg.sender);
        uint256 wsOHMBal = oldwsOHM.balanceOf(msg.sender);

        if (oldGDAO.balanceOf(msg.sender) > 0 && gdaoMigrated) {
            gdaoBal = oldGDAO.balanceOf(msg.sender);
            oldGDAO.safeTransferFrom(msg.sender, address(this), gdaoBal);
        }
        if (sGDAOBal > 0) {
            oldsGDAO.safeTransferFrom(msg.sender, address(this), sGDAOBal);
        }
        if (wsOHMBal > 0) {
            oldwsOHM.safeTransferFrom(msg.sender, address(this), wsOHMBal);
        }

        uint256 wAmount = wsOHMBal.add(oldwsOHM.sOHMTowOHM(gdaoBal.add(sGDAOBal)));
        if (gdaoMigrated) {
            require(oldSupply >= oldGDAO.totalSupply(), "OHMv1 minted");
            _send(wAmount, _to);
        } else {
            xGDAO.mint(msg.sender, wAmount);
        }
    }

    // send preferred token
    function _send(uint256 wAmount, TYPE _to) internal {
        if (_to == TYPE.WRAPPED) {
            xGDAO.safeTransfer(msg.sender, wAmount);
        } else if (_to == TYPE.STAKED) {
            newStaking.unwrap(msg.sender, wAmount);
        } else if (_to == TYPE.UNSTAKED) {
            newStaking.unstake(msg.sender, wAmount, false, false);
        }
    }

    // bridge back to GDAO, sGDAO, or wsOHM
    function bridgeBack(uint256 _amount, TYPE _to) external {
        if (!gdaoMigrated) {
            xGDAO.burn(msg.sender, _amount);
        } else {
            xGDAO.safeTransferFrom(msg.sender, address(this), _amount);
        }

        uint256 amount = oldwsOHM.wOHMTosOHM(_amount);
        // error throws if contract does not have enough of type to send
        if (_to == TYPE.UNSTAKED) {
            oldGDAO.safeTransfer(msg.sender, amount);
        } else if (_to == TYPE.STAKED) {
            oldsGDAO.safeTransfer(msg.sender, amount);
        } else if (_to == TYPE.WRAPPED) {
            oldwsOHM.safeTransfer(msg.sender, _amount);
        }
    }

    /* ========== OWNABLE ========== */

    // halt migrations (but not bridging back)
    function halt() external onlyPolicy {
        require(!gdaoMigrated, "Migration has occurred");
        shutdown = !shutdown;
    }

    // withdraw backing of migrated OHM
    function defund(address reserve) external onlyGovernor {
        require(gdaoMigrated, "Migration has not begun");
        require(timelockEnd < block.number && timelockEnd != 0, "Timelock not complete");

        oldwsOHM.unwrap(oldwsOHM.balanceOf(address(this)));

        uint256 amountToUnstake = oldsGDAO.balanceOf(address(this));
        oldsGDAO.approve(address(oldStaking), amountToUnstake);
        oldStaking.unstake(amountToUnstake, false);

        uint256 balance = oldGDAO.balanceOf(address(this));

        if(balance > oldSupply) {
            oldSupply = 0;
        } else {
            oldSupply -= balance;
        }

        uint256 amountToWithdraw = balance.mul(1e9);
        oldGDAO.approve(address(oldTreasury), amountToWithdraw);
        oldTreasury.withdraw(amountToWithdraw, reserve);
        IERC20(reserve).safeTransfer(address(newTreasury), IERC20(reserve).balanceOf(address(this)));

        emit Defunded(balance);
    }

    // start timelock to send backing to new treasury
    function startTimelock() external onlyGovernor {
        require(timelockEnd == 0, "Timelock set");
        timelockEnd = block.number.add(timelockLength);

        emit TimelockStarted(block.number, timelockEnd);
    }

    // set xGDAO address
    function setxGDAO(address _xGDAO) external onlyGovernor {
        require(address(xGDAO) == address(0), "Already set");
        require(_xGDAO != address(0), "Zero address: xGDAO");

        xGDAO = IxGDAO(_xGDAO);
    }

    // call internal migrate token function
    function migrateToken(address token) external onlyGovernor {
        _migrateToken(token, false);
    }

    /**
     *   @notice Migrate LP and pair with new OHM
     */
    function migrateLP(
        address pair,
        bool sushi,
        address token,
        uint256 _minA,
        uint256 _minB
    ) external onlyGovernor {
        uint256 oldLPAmount = IERC20(pair).balanceOf(address(oldTreasury));
        oldTreasury.manage(pair, oldLPAmount);

        IUniswapV2Router router = sushiRouter;
        if (!sushi) {
            router = uniRouter;
        }

        IERC20(pair).approve(address(router), oldLPAmount);
        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            token, 
            address(oldGDAO), 
            oldLPAmount,
            _minA, 
            _minB, 
            address(this), 
            block.timestamp
        );

        newTreasury.mint(address(this), amountB);

        IERC20(token).approve(address(router), amountA);
        newGDAO.approve(address(router), amountB);

        router.addLiquidity(
            token, 
            address(newGDAO), 
            amountA, 
            amountB, 
            amountA, 
            amountB, 
            address(newTreasury), 
            block.timestamp
        );
    }

    // Failsafe function to allow owner to withdraw funds sent directly to contract in case someone sends non-ohm tokens to the contract
    function withdrawToken(
        address tokenAddress,
        uint256 amount,
        address recipient
    ) external onlyGovernor {
        require(tokenAddress != address(0), "Token address cannot be 0x0");
        require(tokenAddress != address(xGDAO), "Cannot withdraw: xGDAO");
        require(tokenAddress != address(oldGDAO), "Cannot withdraw: old-GDAO");
        require(tokenAddress != address(oldsGDAO), "Cannot withdraw: old-sGDAO");
        require(tokenAddress != address(oldwsOHM), "Cannot withdraw: old-wsOHM");
        require(amount > 0, "Withdraw value must be greater than 0");
        if (recipient == address(0)) {
            recipient = msg.sender; // if no address is specified the value will will be withdrawn to Owner
        }

        IERC20 tokenContract = IERC20(tokenAddress);
        uint256 contractBalance = tokenContract.balanceOf(address(this));
        if (amount > contractBalance) {
            amount = contractBalance; // set the withdrawal amount equal to balance within the account.
        }
        // transfer the token from address of this contract
        tokenContract.safeTransfer(recipient, amount);
    }

    // migrate contracts
    function migrateContracts(
        address _newTreasury,
        address _newStaking,
        address _newGDAO,
        address _newsGDAO,
        address _reserve
    ) external onlyGovernor {
        require(!gdaoMigrated, "Already migrated");
        gdaoMigrated = true;
        shutdown = false;

        require(_newTreasury != address(0), "Zero address: Treasury");
        newTreasury = ITreasury(_newTreasury);
        require(_newStaking != address(0), "Zero address: Staking");
        newStaking = IStaking(_newStaking);
        require(_newGDAO != address(0), "Zero address: OHM");
        newGDAO = IERC20(_newGDAO);

        oldSupply = oldGDAO.totalSupply(); // log total supply at time of migration

        xGDAO.migrate(_newStaking, _newsGDAO); // change xGDAO minter

        _migrateToken(_reserve, true); // will deposit tokens into new treasury so reserves can be accounted for

        _fund(oldsGDAO.circulatingSupply()); // fund with current staked supply for token migration

        emit Migrated(_newStaking, _newTreasury);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    // fund contract with xGDAO
    function _fund(uint256 _amount) internal {
        newTreasury.mint(address(this), _amount);
        newGDAO.approve(address(newStaking), _amount);
        newStaking.stake(address(this), _amount, false, true); // stake and claim xGDAO

        emit Funded(_amount);
    }

    /**
     *   @notice Migrate token from old treasury to new treasury
     */
    function _migrateToken(address token, bool deposit) internal {
        uint256 balance = IERC20(token).balanceOf(address(oldTreasury));

        uint256 excessReserves = oldTreasury.excessReserves();
        uint256 tokenValue = oldTreasury.valueOf(token, balance);

        if (tokenValue > excessReserves) {
            tokenValue = excessReserves;
            balance = excessReserves * 10**9;
        }

        oldTreasury.manage(token, balance);

        if (deposit) {
            IERC20(token).safeApprove(address(newTreasury), balance);
            newTreasury.deposit(balance, token, tokenValue);
        } else {
            IERC20(token).safeTransfer(address(newTreasury), balance);
        }
    }
}