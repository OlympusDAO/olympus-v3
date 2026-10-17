// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {Test} from "@forge-std-1.16.2/Test.sol";

import {
    CCIPFeeBudgetLib,
    ICCIPFeeOnRamp15,
    ICCIPFeeOnRampConfig,
    ICCIPFeeQuoter20,
    ICCIPFeeRouter,
    ICCIPFeeTypeAndVersion
} from "src/scripts/ops/lib/CCIPFeeBudgetLib.sol";
import {CCIPFeeBudgetLibHarness} from "src/test/scripts/ops/lib/mocks/CCIPFeeBudgetLibHarness.sol";
import {MockSelectorReturns} from "src/test/scripts/ops/lib/mocks/MockSelectorReturns.sol";

/// @notice Shared rig of the `CCIPFeeBudgetLib` suites: a router, an on-ramp and a fee quoter
///         whose `typeAndVersion` strings and raw return data every test controls word by word,
///         behind a harness that exposes the library's internal functions as external calls.
abstract contract CCIPFeeBudgetLibTest is Test {
    // =======================================================================
    // Constants
    // =======================================================================

    string internal constant LOCAL_CHAIN = "local";
    string internal constant REMOTE_CHAIN = "remote";
    string internal constant LANE = "local -> remote";
    uint64 internal constant REMOTE_SELECTOR = 4949039107694359620;
    uint32 internal constant MIN_BUDGET = 175_000;

    string internal constant ON_RAMP_20 = "OnRamp 2.0.0";
    string internal constant ON_RAMP_16 = "OnRamp 1.6.0";
    string internal constant LEGACY_ON_RAMP_15 = "EVM2EVMOnRamp 1.5.0";
    string internal constant FEE_QUOTER_20 = "FeeQuoter 2.0.0";

    bytes32 internal constant EVM_FAMILY_WORD = bytes32(bytes4(0x2812d52c));
    bytes32 internal constant SVM_FAMILY_WORD = bytes32(bytes4(0x1e10bdc4));

    /// @notice The dest-config default written by `_setDestConfig20`, the live 90000.
    uint32 internal constant CHAIN_DEFAULT = 90_000;

    // =======================================================================
    // State
    // =======================================================================

    CCIPFeeBudgetLibHarness internal harness;
    MockSelectorReturns internal router;
    MockSelectorReturns internal onRamp;
    MockSelectorReturns internal feeQuoter;
    address internal ohm;
    string internal env;

    // =======================================================================
    // setUp
    // =======================================================================

    function setUp() public virtual {
        harness = new CCIPFeeBudgetLibHarness();
        vm.label(address(harness), "CCIPFeeBudgetLibHarness");
        router = new MockSelectorReturns();
        vm.label(address(router), "router");
        onRamp = new MockSelectorReturns();
        vm.label(address(onRamp), "onRamp");
        feeQuoter = new MockSelectorReturns();
        vm.label(address(feeQuoter), "feeQuoter");
        ohm = makeAddr("ohm");

        env = string.concat(
            '{"current":{"local":{"external":{"ccip":{"Router":"',
            vm.toString(address(router)),
            '"}},"olympus":{"legacy":{"OHM":"',
            vm.toString(ohm),
            '"}}},"remote":{"external":{"ccip":{"ChainSelector":',
            vm.toString(uint256(REMOTE_SELECTOR)),
            "}}}}}"
        );

        // The router names the on-ramp for the remote chain
        router.setReturn(ICCIPFeeRouter.getOnRamp.selector, abi.encode(address(onRamp)));
    }

    // =======================================================================
    // Helpers: versions and raw returns
    // =======================================================================

    function _setVersion(MockSelectorReturns target_, string memory version_) internal {
        target_.setReturn(ICCIPFeeTypeAndVersion.typeAndVersion.selector, abi.encode(version_));
    }

    /// @notice Sets the on-ramp's `getDynamicConfig()` return to `words_` raw words.
    function _setOnRampConfig(uint256[] memory words_) internal {
        onRamp.setReturn(ICCIPFeeOnRampConfig.getDynamicConfig.selector, _packWords(words_));
    }

    /// @notice Sets the on-ramp's `getDynamicConfig()` return to `wordCount_` words naming the
    ///         rig's fee quoter in word zero.
    function _setOnRampConfigNamingQuoter(uint256 wordCount_) internal {
        uint256[] memory words = new uint256[](wordCount_);
        words[0] = uint256(uint160(address(feeQuoter)));
        _setOnRampConfig(words);
    }

    /// @notice Sets the fee quoter's four-word token entry from raw words, so that a test can
    ///         write values that do not fit their types.
    function _setTokenEntry20Raw(
        uint256 feeUSDCents_,
        uint256 destGasOverhead_,
        uint256 destBytesOverhead_,
        uint256 isEnabled_
    ) internal {
        uint256[] memory words = new uint256[](4);
        words[0] = feeUSDCents_;
        words[1] = destGasOverhead_;
        words[2] = destBytesOverhead_;
        words[3] = isEnabled_;
        feeQuoter.setReturn(
            ICCIPFeeQuoter20.getTokenTransferFeeConfig.selector,
            _packWords(words)
        );
    }

    /// @notice Sets an enabled fee quoter token entry with `destGasOverhead_`.
    function _setTokenEntry20(uint32 destGasOverhead_) internal {
        _setTokenEntry20Raw(10, destGasOverhead_, 32, 1);
    }

    /// @notice Sets a disabled fee quoter token entry, the live shape of a lane without one.
    function _setNoTokenEntry20() internal {
        _setTokenEntry20Raw(0, 0, 0, 0);
    }

    /// @notice Sets the fee quoter's eleven-word destination config with the live mainnet to
    ///         Arbitrum values, the family word given, and `defaultTokenDestGasOverhead_`.
    function _setDestConfig20(bytes32 familyWord_, uint256 defaultTokenDestGasOverhead_) internal {
        uint256[] memory words = new uint256[](11);
        words[0] = 1; // isEnabled
        words[1] = 32_000; // maxDataBytes
        words[2] = 15_000_000; // maxPerMsgGasLimit
        words[3] = 300_000; // destGasOverhead
        words[4] = 100; // destGasPerPayloadByteBase
        words[5] = uint256(familyWord_); // chainFamilySelector
        words[6] = 0; // defaultTokenFeeUSDCents
        words[7] = defaultTokenDestGasOverhead_;
        words[8] = 200_000; // defaultTxGasLimit
        words[9] = 50; // networkFeeUSDCents
        words[10] = 90; // linkFeeMultiplierPercent
        feeQuoter.setReturn(ICCIPFeeQuoter20.getDestChainConfig.selector, _packWords(words));
    }

    /// @notice Sets the fee quoter's destination config return to `wordCount_` zero words.
    function _setDestConfig20Words(uint256 wordCount_) internal {
        feeQuoter.setReturn(
            ICCIPFeeQuoter20.getDestChainConfig.selector,
            _packWords(new uint256[](wordCount_))
        );
    }

    /// @notice Sets the fee quoter's token entry return to `wordCount_` zero words.
    function _setTokenEntry20Words(uint256 wordCount_) internal {
        feeQuoter.setReturn(
            ICCIPFeeQuoter20.getTokenTransferFeeConfig.selector,
            _packWords(new uint256[](wordCount_))
        );
    }

    /// @notice Sets the 1.5 on-ramp's seven-word token entry from raw words.
    function _setTokenEntry15Raw(uint256 destGasOverhead_, uint256 isEnabled_) internal {
        uint256[] memory words = new uint256[](7);
        words[0] = 0; // minFeeUSDCents
        words[1] = 0; // maxFeeUSDCents
        words[2] = 0; // deciBps
        words[3] = destGasOverhead_;
        words[4] = 32; // destBytesOverhead
        words[5] = 0; // aggregateRateLimitEnabled
        words[6] = isEnabled_;
        onRamp.setReturn(ICCIPFeeOnRamp15.getTokenTransferFeeConfig.selector, _packWords(words));
    }

    /// @notice Sets the 1.5 on-ramp's token entry return to `wordCount_` zero words.
    function _setTokenEntry15Words(uint256 wordCount_) internal {
        onRamp.setReturn(
            ICCIPFeeOnRamp15.getTokenTransferFeeConfig.selector,
            _packWords(new uint256[](wordCount_))
        );
    }

    /// @notice Sets the 1.5 on-ramp's thirteen-word dynamic config with
    ///         `defaultTokenDestGasOverhead_` in word eleven.
    function _setDynamicConfig15(uint256 defaultTokenDestGasOverhead_) internal {
        uint256[] memory words = new uint256[](13);
        words[0] = uint256(uint160(address(router)));
        words[1] = 1; // maxNumberOfTokensPerMsg
        words[2] = 300_000; // destGasOverhead
        words[7] = uint256(uint160(makeAddr("priceRegistry")));
        words[8] = 30_000; // maxDataBytes
        words[9] = 3_000_000; // maxPerMsgGasLimit
        words[11] = defaultTokenDestGasOverhead_;
        _setOnRampConfig(words);
    }

    function _packWords(uint256[] memory words_) internal pure returns (bytes memory packed) {
        for (uint256 i; i < words_.length; ++i) {
            packed = abi.encodePacked(packed, words_[i]);
        }
    }

    // =======================================================================
    // Helpers: calls and reverts
    // =======================================================================

    function _read() internal view returns (uint32 overhead, bool isTokenEntry, string memory source) {
        return harness.readOhmDestGasOverhead(env, LOCAL_CHAIN, REMOTE_CHAIN);
    }

    function _requireBudget() internal view {
        harness.requireOhmFeeBudget(env, LOCAL_CHAIN, REMOTE_CHAIN);
    }

    /// @notice Expects an `Error(string)` revert with exactly `message_`. The library reverts
    ///         with `require` strings by design (a script library), so the message is the data.
    function _expectRevertMessage(string memory message_) internal {
        vm.expectRevert(bytes(message_));
    }

    function _expectRevertUnsupportedOnRamp(string memory version_) internal {
        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: unsupported on-ramp version '",
                version_,
                "' on the lane ",
                LANE
            )
        );
    }

    function _expectRevertUnsupportedFeeQuoter(string memory version_) internal {
        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: unsupported fee quoter version '",
                version_,
                "' on the lane ",
                LANE
            )
        );
    }

    function _expectRevertWords(
        string memory call_,
        uint256 returned_,
        uint256 expected_
    ) internal {
        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: ",
                call_,
                " on the lane ",
                LANE,
                " returned ",
                vm.toString(returned_),
                " words, expected ",
                vm.toString(expected_)
            )
        );
    }

    function _expectRevertDoesNotFit(string memory field_) internal {
        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: ",
                field_,
                " on the lane ",
                LANE,
                " does not fit its type; the layout differs from the supported one"
            )
        );
    }

    // =======================================================================
    // Assertions
    // =======================================================================

    function _assertParsed(
        string memory raw_,
        string memory family_,
        uint256 major_,
        uint256 minor_
    ) internal view {
        (CCIPFeeBudgetLib.TypeAndVersion memory version, bool ok) = harness.parseTypeAndVersion(
            raw_
        );
        assertTrue(ok, string.concat("should parse: ", raw_));
        assertEq(version.raw, raw_, "raw should be kept");
        assertEq(version.family, family_, "family");
        assertEq(version.major, major_, "major");
        assertEq(version.minor, minor_, "minor");
    }

    function _assertNotParsed(string memory raw_) internal view {
        (, bool ok) = harness.parseTypeAndVersion(raw_);
        assertFalse(ok, string.concat("should not parse: ", raw_));
    }

    // =======================================================================
    // State modifiers
    // =======================================================================

    /// @notice A live 2.0.0 lane: `OnRamp 2.0.0` with the three-word dynamic config naming a
    ///         `FeeQuoter 2.0.0`.
    modifier givenOnRamp20Lane() {
        _setVersion(onRamp, ON_RAMP_20);
        _setOnRampConfigNamingQuoter(3);
        _setVersion(feeQuoter, FEE_QUOTER_20);
        _;
    }

    /// @notice A live 1.6 lane: `OnRamp 1.6.0` with the five-word dynamic config naming a
    ///         `FeeQuoter 2.0.0`.
    modifier givenOnRamp16Lane() {
        _setVersion(onRamp, ON_RAMP_16);
        _setOnRampConfigNamingQuoter(5);
        _setVersion(feeQuoter, FEE_QUOTER_20);
        _;
    }

    /// @notice A live 1.5 lane: a dedicated `EVM2EVMOnRamp 1.5.0`.
    modifier givenLegacyLane() {
        _setVersion(onRamp, LEGACY_ON_RAMP_15);
        _;
    }

    /// @notice The fee quoter carries an enabled OHM entry with the given budget.
    modifier givenTokenEntry(uint32 destGasOverhead_) {
        _setTokenEntry20(destGasOverhead_);
        _;
    }

    /// @notice The fee quoter carries no OHM entry and an EVM destination config with the live
    ///         90000 default.
    modifier givenNoTokenEntry() {
        _setNoTokenEntry20();
        _setDestConfig20(EVM_FAMILY_WORD, CHAIN_DEFAULT);
        _;
    }

    /// @notice The 1.5 on-ramp carries an enabled OHM entry with the given budget.
    modifier givenLegacyTokenEntry(uint32 destGasOverhead_) {
        _setTokenEntry15Raw(destGasOverhead_, 1);
        _;
    }

    /// @notice The 1.5 on-ramp carries no OHM entry and the live 90000 default.
    modifier givenLegacyNoTokenEntry() {
        _setTokenEntry15Raw(0, 0);
        _setDynamicConfig15(CHAIN_DEFAULT);
        _;
    }
}
