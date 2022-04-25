// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {Auth, Authority} from "solmate/auth/Auth.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {TransferHelper} from "../libraries/TransferHelper.sol";

import {IERC20} from "../interfaces/IERC20.sol";

import {Kernel, Module} from "../Kernel.sol";

import "../OlympusErrors.sol";

// TODO Staking contract to hold staked token state. Holds all rebasing
// logic and state. Also holds indexed and non-indexed supply and balances.
/// @title  OlympusStaking
/// @notice Contract to hold staked token state. Holds all rebasing logic
///         and state. Also holds indexed and non-indexed supply and balances.
/// @dev    gons = internal denomination for rebasing units
///         nominal = ohm-denominated amount
///         indexed = nominal / index
/// @dev    Rebases act on the nominal supply. Indexed supply is generated
///         from nominal amounts when users convert their OHM/sOHM to gOHM.
contract OlympusStaking is Module, Auth {
    using TransferHelper for IERC20;
    using FixedPointMathLib for uint256;

    /* ======== STATE VARIABLES AND CONSTANTS ======== */

    // MAX_SUPPLY = maximum integer < (sqrt(4*TOTAL_GONS + 1) - 1) / 2
    uint256 private constant MAX_SUPPLY = ~uint128(0); // (2^128) - 1
    uint256 private constant MAX_UINT256 = type(uint256).max;
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 5_000_000 * 1e9;

    // TOTAL_GONS is a multiple of INITIAL_FRAGMENTS_SUPPLY so that gonsPerFragment is an integer.
    // Use the highest value that fits in a uint256 for max granularity.
    uint256 private constant TOTAL_GONS =
        MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    uint256 public constant INDEXED_UNITS = 1e18;

    IERC20 public immutable ohm;

    /// @dev Index gons. Used for tracking rebase growth.
    uint256 public indexGons;

    /// @dev Internal accounting unit for rebasing tokens. Balances are
    ///      represented as gons.
    uint256 public gonsPerFragment;

    uint256 public dormantNominalSupply;
    uint256 public nominalSupply;
    uint256 public indexedSupply;

    // Both balances in gons
    mapping(address => uint256) public nominalGonsBalance;
    mapping(address => uint256) public indexedGonsBalance;

    mapping(address => mapping(address => uint256)) private _gonsAllowances;

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        uint256 initialIndex_,
        address auth_,
        Authority authority_
    ) Module(kernel_) Auth(auth_, authority_) {
        ohm = ohm_;
        nominalSupply = INITIAL_FRAGMENTS_SUPPLY;
        gonsPerFragment = TOTAL_GONS / INITIAL_FRAGMENTS_SUPPLY;
        indexGons = _nominalToGons(initialIndex_);
        nominalGonsBalance[address(this)] = TOTAL_GONS;
    }

    function KEYCODE() external pure override returns (bytes3) {
        return "STK";
    }

    /// @notice Initialize index and send all possible sOHM to minter, and set the debt module.
    //function initializeState(uint256 initialIndex_) external {
    //    if (indexGons != 0) revert AlreadyInitialized();

    //    indexGons = _nominalToGons(initialIndex_);
    //    nominalGonsBalance[address(this)] = TOTAL_GONS;
    //}

    /// @notice Stake OHM by taking in OHM and returning equivalent sOHM.
    /// @dev Can alternatively use gOHM deposit to get equivalent gOHM.
    // TODO warmup logic?
    function stakeIndexed(
        address from_,
        address to_,
        uint256 amount_
    ) external returns (uint256) {
        IERC20(ohm).safeTransferFrom(from_, address(this), amount_);
        convertToIndexed(address(this), to_, amount_);
    }

    /// @notice Unstake OHM by taking in gOHM and returning equivalent OHM.
    // TODO probably not necessary. can unstake and convert inside the gVault
    function unstakeIndexed(
        address from_,
        address to_,
        uint256 amount_
    ) external returns (uint256 nominalAmount) {
        nominalAmount = convertToNominal(from_, address(this), amount_);
        IERC20(ohm).safeTransfer(to_, nominalAmount);
    }

    /* ======== REBASE LOGIC ======== */

    /// @notice Increase the nominal supply given some rebase amount. Called during rebase.
    /// @dev We increase nominal supply because it shares the same unit as OHM. Indexed
    ///      supply is generated from nominal.
    function rebaseSupply(uint256 toDistribute_) external requiresAuth {
        if (toDistribute_ == 0) revert AmountMustBeNonzero(toDistribute_);

        uint256 totalStakedSupply = getTotalStakedSupply();
        uint256 circSupply = totalStakedSupply -
            _gonsToNominal(nominalGonsBalance[address(this)]);

        uint256 rebaseAmount = circSupply > 0
            ? (toDistribute_ * totalStakedSupply) / circSupply
            : toDistribute_;

        nominalSupply += rebaseAmount;
        if (nominalSupply > MAX_SUPPLY) {
            nominalSupply = MAX_SUPPLY;
        }

        gonsPerFragment = TOTAL_GONS / getTotalStakedSupply();
    }

    function transferNominal(
        address from_,
        address to_,
        uint256 nominal_
    ) public {
        if (from_ == to_) return;
        //if (nominal_ > nominalBalance[from_]) revert InsufficientBalance(from_, nominal_);

        // Will revert if insufficient balance
        uint256 gonsValue = _nominalToGons(nominal_);

        // TODO verify this
        // If not sender and allowance from spender
        if (
            to_ == msg.sender &&
            _gonsAllowances[from_][msg.sender] != type(uint256).max
        ) {
            _gonsAllowances[from_][to_] -= gonsValue;
        }

        nominalGonsBalance[from_] -= gonsValue;
        nominalGonsBalance[to_] += gonsValue;
    }

    function transferIndexed(
        address from_,
        address to_,
        uint256 indexed_
    ) public {
        //if (indexed_ == 0) revert AmountMustBeNonzero(indexed_);
        if (from_ == to_) return;
        //if (indexed_ > indexedBalance[from_]) revert InsufficientBalance(from_, nominal_);

        // Will revert if insufficient balance
        uint256 gonsValue = _indexedToGons(indexed_);

        // TODO verify this
        if (
            from_ != msg.sender &&
            _gonsAllowances[from_][to_] != type(uint256).max
        ) {
            _gonsAllowances[from_][to_] -= gonsValue;
        }

        indexedGonsBalance[from_] -= gonsValue;
        indexedGonsBalance[to_] += gonsValue;
    }

    /// @notice Converts to indexed and transfers if from_ and to_ differ
    function convertToIndexed(
        address from_,
        address to_,
        uint256 nominal_
    ) public returns (uint256 amountConverted) {
        uint256 gonsValue = _nominalToGons(nominal_);

        nominalGonsBalance[from_] -= gonsValue;
        indexedGonsBalance[to_] += gonsValue;

        return getIndexedValue(nominal_);
    }

    /// @notice Converts indexed to nominal and transfers if from_ and to_ differ
    function convertToNominal(
        address from_,
        address to_,
        uint256 indexed_
    ) public returns (uint256 amountConverted) {
        uint256 gonsValue = _indexedToGons(indexed_);

        indexedGonsBalance[from_] -= gonsValue;
        nominalGonsBalance[to_] += gonsValue;

        return getNominalValue(indexed_);
    }

    /*///////////////////////////////////////////////////////////////
                        Approvals/Allowances
    //////////////////////////////////////////////////////////////*/

    /// @dev Assumes input is nominal
    function approveNominal(address spender_, uint256 nominal_)
        public
        returns (bool)
    {
        uint256 gonsValue = _nominalToGons(nominal_);
        _gonsAllowances[msg.sender][spender_] = gonsValue;
        emit Approval(msg.sender, spender_, nominal_);
        return true;
    }

    /// @dev Assumes input is indexed
    function approveIndexed(address spender_, uint256 indexed_)
        public
        returns (bool)
    {
        uint256 gonsValue = _indexedToGons(indexed_);
        _gonsAllowances[msg.sender][spender_] = gonsValue;
        emit Approval(msg.sender, spender_, indexed_);
        return true;
    }

    function getAllowanceNominal(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return _gonsToNominal(_gonsAllowances[owner][spender]);
    }

    function getAllowanceIndexed(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return _gonsToIndexed(_gonsAllowances[owner][spender]);
    }

    function index() public view returns (uint256) {
        return _gonsToNominal(indexGons);
    }

    /// @notice Get total staked supply as nominal value
    function getTotalStakedSupply() public view returns (uint256) {
        return nominalSupply + getNominalValue(indexedSupply);
    }

    /// @notice Get amount of OHM to rebase for next epoch
    function getNextDistribution()
        external
        view
        returns (uint256 nextDistribution)
    {
        uint256 ohmBalance = IERC20(ohm).balanceOf(address(this));
        uint256 circSupply = getTotalStakedSupply() -
            _gonsToNominal(nominalGonsBalance[address(this)]);

        if (ohmBalance > circSupply) {
            nextDistribution = ohmBalance - circSupply;
        }
    }

    function getNominalBalance(address who_) external view returns (uint256) {
        return _gonsToNominal(nominalGonsBalance[who_]);
    }

    function getIndexedBalance(address who_) external view returns (uint256) {
        return _gonsToIndexed(indexedGonsBalance[who_]);
    }

    // TODO What decimals to use?? 9 or 18??
    /// @dev Assumes input is indexed. Using 18 decimals for precision.
    function getNominalValue(uint256 indexed_) public view returns (uint256) {
        return indexed_.mulDivDown(index(), INDEXED_UNITS);
    }

    /// @dev Assumes input is nominal. Using 18 decimals for precision.
    function getIndexedValue(uint256 nominal_) public view returns (uint256) {
        return nominal_.mulDivDown(INDEXED_UNITS, index());
    }

    function _nominalToGons(uint256 nominal_) internal view returns (uint256) {
        return nominal_ * gonsPerFragment;
    }

    function _gonsToNominal(uint256 gons_) internal view returns (uint256) {
        return gons_ / gonsPerFragment;
    }

    function _indexedToGons(uint256 indexed_) internal view returns (uint256) {
        return (indexed_ / INDEXED_UNITS) * indexGons;
    }

    function _gonsToIndexed(uint256 gons_) internal view returns (uint256) {
        return (gons_ / indexGons) * INDEXED_UNITS;
    }
}
