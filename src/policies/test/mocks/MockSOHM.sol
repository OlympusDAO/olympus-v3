// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

interface IgOHM {
    function balanceFrom(uint256 amount_) external view returns (uint256);
}

interface IStaking {
    function supplyInWarmup() external view returns (uint256);
}

interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

abstract contract ERC20 is IERC20 {
    // TODO comment actual hash value.
    bytes32 private constant ERC20TOKEN_ERC1820_INTERFACE_ID =
        keccak256("ERC20Token");

    mapping(address => uint256) internal _balances;

    mapping(address => mapping(address => uint256)) internal _allowances;

    uint256 internal _totalSupply;

    string internal _name;

    string internal _symbol;

    uint8 internal immutable _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender] - subtractedValue
        );
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + amount;
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");
        _beforeTokenTransfer(address(0), account, amount);
        _totalSupply = _totalSupply + amount;
        _balances[account] = _balances[account] + amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account] - amount;
        _totalSupply = _totalSupply - amount;
        emit Transfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(
        address from_,
        address to_,
        uint256 amount_
    ) internal virtual {}
}

contract MockSOHM is ERC20 {
    struct Rebase {
        uint256 epoch;
        uint256 rebase; // 18 decimals
        uint256 totalStakedBefore;
        uint256 totalStakedAfter;
        uint256 amountRebased;
        uint256 index;
        uint256 blockNumberOccured;
    }

    address internal initializer;

    uint256 internal INDEX;

    address public stakingContract;

    IgOHM public gOHM;

    Rebase[] public rebases;

    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 5_000_000 * 10**9;

    uint256 private constant TOTAL_GONS =
        type(uint256).max - (type(uint256).max % INITIAL_FRAGMENTS_SUPPLY);

    uint256 private constant MAX_SUPPLY = ~uint128(0);

    uint256 private _gonsPerFragment;
    mapping(address => uint256) private _gonBalances;

    mapping(address => mapping(address => uint256)) private _allowedValue;

    address public treasury;
    mapping(address => uint256) public debtBalances;

    constructor() ERC20("Staked OHM", "sOHM", 9) {
        initializer = msg.sender;
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonsPerFragment = TOTAL_GONS / INITIAL_FRAGMENTS_SUPPLY;
    }

    /// Setters

    function setInitializer(address initializer_) public {
        initializer = initializer_;
    }

    function setIndex(uint256 index_) public {
        INDEX = gonsForBalance(index_);
    }

    function setStakingContract(address stakingContract_) public {
        stakingContract = stakingContract_;
    }

    function setgOHM(address gohm_) public {
        gOHM = IgOHM(gohm_);
    }

    function setTreasury(address treasury_) public {
        treasury = treasury_;
    }

    function initialize(address stakingContract_, address treasury_) external {
        stakingContract = stakingContract_;
        _gonBalances[stakingContract] = TOTAL_GONS;

        treasury = treasury_;
    }

    /// Interaction Functions

    function transfer(address to, uint256 value)
        public
        override(ERC20)
        returns (bool)
    {
        uint256 gonValue = value * _gonsPerFragment;

        _gonBalances[msg.sender] = _gonBalances[msg.sender] - gonValue;
        _gonBalances[to] = _gonBalances[to] + gonValue;

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override(ERC20) returns (bool) {
        _allowedValue[from][msg.sender] =
            _allowedValue[from][msg.sender] -
            value;

        uint256 gonValue = gonsForBalance(value);
        _gonBalances[from] = _gonBalances[from] - gonValue;
        _gonBalances[to] = _gonBalances[to] + gonValue;

        return true;
    }

    function approve(address spender, uint256 value)
        public
        override(ERC20)
        returns (bool)
    {
        _approve(msg.sender, spender, value);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        override(ERC20)
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            _allowedValue[msg.sender][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        override(ERC20)
        returns (bool)
    {
        uint256 oldValue = _allowedValue[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _approve(msg.sender, spender, 0);
        } else {
            _approve(msg.sender, spender, oldValue - subtractedValue);
        }
        return true;
    }

    function changeDebt(
        uint256 amount,
        address debtor,
        bool add
    ) external {
        require(msg.sender == treasury, "Only treasury");
        if (add) {
            debtBalances[debtor] = debtBalances[debtor] + amount;
        } else {
            debtBalances[debtor] = debtBalances[debtor] - amount;
        }
        require(
            debtBalances[debtor] <= balanceOf(debtor),
            "sOHM: insufficient balance"
        );
    }

    function rebase(uint256 profit_, uint256 epoch_) public returns (uint256) {
        uint256 rebaseAmount;
        uint256 circulatingSupply_ = circulatingSupply();

        if (profit_ == 0) {
            return _totalSupply;
        } else if (circulatingSupply_ > 0) {
            rebaseAmount = (profit_ * _totalSupply) / circulatingSupply_;
        } else {
            rebaseAmount = profit_;
        }

        _totalSupply = _totalSupply + rebaseAmount;

        if (_totalSupply > MAX_SUPPLY) _totalSupply = MAX_SUPPLY;

        _gonsPerFragment = TOTAL_GONS / _totalSupply;

        _storeRebase(circulatingSupply_, profit_, epoch_);

        return _totalSupply;
    }

    /// Internal Functions

    function _approve(
        address owner,
        address spender,
        uint256 value
    ) internal virtual override(ERC20) {
        _allowedValue[owner][spender] = value;
    }

    function _storeRebase(
        uint256 previousCirculating_,
        uint256 profit_,
        uint256 epoch_
    ) internal {
        uint256 rebasePercent = (profit_ * 1e18) / previousCirculating_;
        rebases.push(
            Rebase({
                epoch: epoch_,
                rebase: rebasePercent, // 18 decimals
                totalStakedBefore: previousCirculating_,
                totalStakedAfter: circulatingSupply(),
                amountRebased: profit_,
                index: index(),
                blockNumberOccured: block.number
            })
        );
    }

    /// View Functions

    function balanceOf(address who)
        public
        view
        virtual
        override(ERC20)
        returns (uint256)
    {
        return _gonBalances[who] / _gonsPerFragment;
    }

    function gonsForBalance(uint256 amount) public view returns (uint256) {
        return amount * _gonsPerFragment;
    }

    function balanceForGons(uint256 gons) public view returns (uint256) {
        return gons / _gonsPerFragment;
    }

    function circulatingSupply() public view returns (uint256) {
        return
            _totalSupply -
            balanceOf(stakingContract) +
            gOHM.balanceFrom(ERC20(address(gOHM)).totalSupply()) +
            IStaking(stakingContract).supplyInWarmup();
    }

    function index() public view returns (uint256) {
        return balanceForGons(INDEX);
    }

    function allowance(address owner_, address spender)
        public
        view
        override(ERC20)
        returns (uint256)
    {
        return _allowedValue[owner_][spender];
    }
}
