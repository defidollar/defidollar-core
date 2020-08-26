pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {IOracle} from "../interfaces/IOracle.sol";
import {IStakeLPToken} from "../interfaces/IStakeLPToken.sol";
import {IPeak} from "../interfaces/IPeak.sol";
import {IDUSD} from "../interfaces/IDUSD.sol";
import {ICore} from "../interfaces/ICore.sol";

import {Initializable} from "../common/Initializable.sol";
import {OwnableProxy} from "../common/OwnableProxy.sol";


contract Core is OwnableProxy, Initializable, ICore {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Math for uint;

    uint constant FEE_PRECISION = 10000;

    IDUSD public dusd;
    IStakeLPToken public stakeLPToken;
    IOracle public oracle;
    address[] public systemCoins;
    uint[] public feed;

    uint public totalAssets;
    uint public unclaimedRewards;
    bool public inDeficit;
    uint public redeemFactor;
    uint public colBuffer;

    // Interface contracts for third-party protocol integrations
    enum PeakState { Extinct, Active, Dormant }
    struct Peak {
        uint[] systemCoinIds; // system indices of the coins accepted by the peak
        uint amount;
        uint ceiling;
        PeakState state;
    }
    mapping(address => Peak) public peaks;
    address[] public peaksAddresses;

    // END OF STORAGE VARIABLES

    event Mint(address indexed account, uint amount);
    event Redeem(address indexed account, uint amount);
    event FeedUpdated(uint[] feed);
    event TokenWhiteListed(address indexed token);
    event PeakWhitelisted(address indexed peak);
    event UpdateDeficitState(bool inDeficit);

    modifier checkAndNotifyDeficit() {
        _;
        uint supply = dusd.totalSupply();
        if (supply > totalAssets) {
            if (!inDeficit) {
                emit UpdateDeficitState(true);
                inDeficit = true;
            }
            stakeLPToken.notify(supply.sub(totalAssets));
        } else if (inDeficit) {
            inDeficit = false;
            emit UpdateDeficitState(false);
            stakeLPToken.notify(0);
        }
    }

    modifier onlyStakeLPToken() {
        require(
            msg.sender == address(stakeLPToken),
            "Only stakeLPToken"
        );
        _;
    }

    /**
    * @dev Used to initialize contract state from the proxy
    */
    function initialize(
        IDUSD _dusd,
        IStakeLPToken _stakeLPToken,
        IOracle _oracle,
        uint _redeemFactor,
        uint _colBuffer
    )   public
        notInitialized
    {
        require(
            address(_dusd) != address(0) &&
            address(_stakeLPToken) != address(0) &&
            address(_oracle) != address(0),
            "0 address during initialization"
        );
        dusd = _dusd;
        stakeLPToken = _stakeLPToken;
        oracle = _oracle;
        require(
            _redeemFactor <= FEE_PRECISION && _colBuffer <= FEE_PRECISION,
            "Incorrect upper bound for fee"
        );
        redeemFactor = _redeemFactor;
        colBuffer = _colBuffer;
    }

    /**
    * @notice Mint DUSD
    * @dev Only whitelisted peaks can call this function
    * @param dusdAmount DUSD amount to mint
    * @param account Account to mint DUSD to
    * @return dusdAmount DUSD amount minted
    */
    function mint(uint usdDelta, address account)
        external
        checkAndNotifyDeficit
        returns(uint dusdAmount)
    {
        Peak memory peak = peaks[msg.sender];
        dusdAmount = usdDelta;
        uint tvl = peak.amount.add(dusdAmount);
        require(
            usdDelta > 0
            && peak.state == PeakState.Active
            && tvl <= peak.ceiling,
            "ERR_MINT"
        );
        peaks[msg.sender].amount = tvl;
        dusd.mint(account, dusdAmount);
        totalAssets = totalAssets.add(usdDelta);
        emit Mint(account, dusdAmount);
    }

    /**
    * @notice Redeem DUSD
    * @dev Only whitelisted peaks can call this function
    * @param dusdAmount DUSD amount to redeem.
    * @param account Account to burn DUSD from
    */
    function redeem(uint dusdAmount, address account)
        external
        checkAndNotifyDeficit
        returns(uint usd)
    {
        Peak memory peak = peaks[msg.sender];
        require(
            dusdAmount > 0 && peak.state != PeakState.Extinct,
            "ERR_REDEEM"
        );
        peaks[msg.sender].amount = peak.amount.sub(peak.amount.min(dusdAmount));
        usd = dusdToUsd(dusdAmount, true);
        dusd.burn(account, dusdAmount);
        totalAssets = totalAssets.sub(usd);
        emit Redeem(account, dusdAmount);
    }

    /**
    * @notice Pull prices from the oracle and update system stats
    * @dev Anyone can call this
    */
    function syncSystem()
        public
        checkAndNotifyDeficit
    {
        _updateFeed(false);
    }

    function rewardDistributionCheckpoint(bool shouldDistribute)
        external
        onlyStakeLPToken
        checkAndNotifyDeficit
        returns(uint periodIncome)
    {
        _updateFeed(false); // totalAssets was updated
        uint _colBuffer;
        (periodIncome, _colBuffer) = _lastPeriodIncome(totalAssets);
        if (periodIncome == 0) {
            return 0;
        }
        // note that we do not account for devalued dusd here
        if (shouldDistribute) {
            dusd.mint(address(stakeLPToken), periodIncome);
        } else {
            // stakers don't get these, will act as extra volatility cushion
            unclaimedRewards = unclaimedRewards.add(periodIncome);
        }
        if (_colBuffer > 0) {
            unclaimedRewards = unclaimedRewards.add(_colBuffer);
        }
    }

    /* ##### View functions ##### */
    function dusdToUsd(uint _dusd, bool fee)
        public
        view
        returns(uint usd)
    {
        // system is healthy. Pegged at $1
        if (!inDeficit) {
            usd = _dusd;
        } else {
        // system is in deficit, see if staked funds can make up for it
            uint supply = dusd.totalSupply();
            // do not perform a dusd.balanceOf(stakeLPToken) because that includes the reward tokens
            uint perceivedSupply = supply.sub(stakeLPToken.totalSupply());
            // staked funds make up for the deficit
            if (perceivedSupply <= totalAssets) {
                usd = _dusd;
            } else {
                usd = _dusd.mul(totalAssets).div(perceivedSupply);
            }
        }
        if (fee) {
            usd = usd.mul(redeemFactor).div(FEE_PRECISION);
        }
        return usd;
    }

    function currentSystemState()
        public view
        returns (uint _totalAssets, uint _deficit, uint _deficitPercent)
    {
        _totalAssets = totalSystemAssets();
        uint supply = dusd.totalSupply();
        if (supply > _totalAssets) {
            _deficit = supply.sub(_totalAssets);
            _deficitPercent = _deficit.mul(1e7).div(supply); // 5 decimal precision
        }
    }

    /* ##### Following are just helper functions, not being used anywhere ##### */
    function lastPeriodIncome()
        public view
        returns(uint _totalAssets, uint _periodIncome, uint _colBuffer)
    {
        _totalAssets = totalSystemAssets();
        (_periodIncome, _colBuffer) = _lastPeriodIncome(_totalAssets);
    }

    function totalSystemAssets()
        public view
        returns (uint _totalAssets)
    {
        uint[] memory _feed = oracle.getPriceFeed();
        for (uint i = 0; i < peaksAddresses.length; i++) {
            Peak memory peak = peaks[peaksAddresses[i]];
            if (peak.state == PeakState.Extinct) {
                continue;
            }
            _totalAssets = _totalAssets.add(
                IPeak(peaksAddresses[i]).portfolioValueWithFeed(_feed)
            );
        }
    }

    /* ##### Admin functions ##### */

    /**
    * @notice Whitelist new tokens supported by the peaks.
    * These are vanilla coins like DAI, USDC, USDT etc.
    * @dev onlyOwner ACL is provided by the whitelistToken call
    * @param tokens Token addresses to whitelist
    */
    function whitelistTokens(address[] calldata tokens)
        external
        onlyOwner
    {
        for (uint i = 0; i < tokens.length; i++) {
            _whitelistToken(tokens[i]);
        }
    }

    /**
    * @notice Whitelist a new peak
    * @param peak Address of the contract that interfaces with the 3rd-party protocol
    * @param _systemCoins Indices of the system coins, the peak supports
    */
    function whitelistPeak(
        address peak,
        uint[] calldata _systemCoins,
        uint ceiling,
        bool shouldUpdateFeed
    )   external
        onlyOwner
    {
        uint numSystemCoins = systemCoins.length;
        for (uint i = 0; i < _systemCoins.length; i++) {
            require(_systemCoins[i] < numSystemCoins, "Invalid system coin index");
        }
        require(
            peaks[peak].state == PeakState.Extinct,
            "Peak already exists"
        );
        peaksAddresses.push(peak);
        peaks[peak] = Peak(_systemCoins, 0, ceiling, PeakState.Active);
        if (shouldUpdateFeed) {
            _updateFeed(true);
        }
        emit PeakWhitelisted(peak);
    }

    /**
    * @notice Change a peaks status
    */
    function setPeakStatus(address peak, uint ceiling, PeakState state)
        external
        onlyOwner
    {
        require(
            peaks[peak].state != PeakState.Extinct,
            "Peak is extinct"
        );
        peaks[peak].ceiling = ceiling;
        peaks[peak].state = state;
    }

    function setFee(uint _redeemFactor, uint _colBuffer)
        external
        onlyOwner
    {
        require(
            _redeemFactor <= FEE_PRECISION && _colBuffer <= FEE_PRECISION,
            "Incorrect upper bound for fee"
        );
        redeemFactor = _redeemFactor;
        colBuffer = _colBuffer;
    }

    /* ##### Internal functions ##### */

    function _updateFeed(bool forceUpdate) internal {
        uint[] memory _feed = oracle.getPriceFeed();
        require(_feed.length == systemCoins.length, "Invalid system state");
        bool changed = false;
        for (uint i = 0; i < _feed.length; i++) {
            if (feed[i] != _feed[i]) {
                feed[i] = _feed[i];
                changed = true;
            }
        }
        if (changed) {
            emit FeedUpdated(_feed);
        }
        Peak memory peak;
        uint _totalAssets;
        for (uint i = 0; i < peaksAddresses.length; i++) {
            peak = peaks[peaksAddresses[i]];
            if (peak.state == PeakState.Extinct) {
                continue;
            }
            if (!changed && !forceUpdate) {
                _totalAssets = _totalAssets.add(IPeak(peaksAddresses[i]).portfolioValue());
                continue;
            }
            uint[] memory prices = new uint[](peak.systemCoinIds.length);
            for (uint j = 0; j < prices.length; j++) {
                prices[j] = _feed[peak.systemCoinIds[j]];
            }
            _totalAssets = _totalAssets.add(IPeak(peaksAddresses[i]).updateFeed(prices));
        }
        totalAssets = _totalAssets;
    }

    function _lastPeriodIncome(uint _totalAssets)
        internal view
        returns(uint _periodIncome, uint _colBuffer)
    {
        uint supply = dusd.totalSupply().add(unclaimedRewards);
        if (_totalAssets > supply) {
            _periodIncome = _totalAssets.sub(supply);
            if (colBuffer > 0) {
                _colBuffer = _periodIncome.mul(colBuffer).div(FEE_PRECISION);
                _periodIncome = _periodIncome.sub(_colBuffer);
            }
        }
    }

    function _whitelistToken(address token)
        internal
    {
        for (uint i = 0; i < systemCoins.length; i++) {
            require(systemCoins[i] != token, "Adding a duplicate token");
        }
        systemCoins.push(token);
        feed.push(0);
        emit TokenWhiteListed(token);
    }
}
