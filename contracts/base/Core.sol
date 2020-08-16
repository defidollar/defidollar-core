pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {IOracle} from "../interfaces/IOracle.sol";
import {IStakeLPToken} from "../interfaces/IStakeLPToken.sol";
import {IPeak} from "../interfaces/IPeak.sol";
import {IDUSD} from "../interfaces/IDUSD.sol";
import {ICore} from "../interfaces/ICore.sol";

import {Initializable} from "../common/Initializable.sol";
import {Ownable} from "../common/Ownable.sol";


contract Core is Ownable, Initializable, ICore {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    uint constant REDEEM_FACTOR_PRECISION = 10000;

    IDUSD public dusd;
    IStakeLPToken public stakeLPToken;
    IOracle public oracle;
    address[] public systemCoins;

    uint public redeemFactor;
    uint public totalAssets;
    uint public unclaimedRewards;
    bool public inDeficit;

    // Interface contracts for third-party protocol integrations
    enum PeakState { Extinct, Active, Dormant }
    struct Peak {
        uint[] systemCoinIds; // system indices of the coins accepted by the peak
        PeakState state;
    }
    mapping(address => Peak) peaks;
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
        uint _redeemFactor
    )   public
        notInitialized
    {
        require(
            address(_dusd) != address(0) &&
            address(_stakeLPToken) != address(0) &&
            address(_oracle) != address(0),
            "0 address during initialization"
        );
        require(
            _redeemFactor <= REDEEM_FACTOR_PRECISION,
            "Contract will end up giving a premium"
        );
        dusd = _dusd;
        stakeLPToken = _stakeLPToken;
        oracle = _oracle;
        redeemFactor = _redeemFactor;
    }

    /**
    * @notice Mint DUSD
    * @dev Only whitelisted peaks can call this function
    * @param dusdAmount DUSD amount to mint
    * @param account Account to mint DUSD to
    * @return dusdAmount DUSD amount minted
    */
    function mint(uint dusdAmount, address account)
        external
        // doesn't need checkAndNotifyDeficit because supply and assets increase by the same amount
    {
        require(dusdAmount > 0, "Minting 0");
        Peak memory peak = peaks[msg.sender];
        require(
            peak.state == PeakState.Active,
            "Peak is inactive"
        );
        // always assumed pegged while minting, even if dusd is devalued
        // this is required to avoid creating additional deficit
        dusd.mint(account, dusdAmount);
        totalAssets = totalAssets.add(dusdAmount);
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
        require(dusdAmount > 0, "Redeeming 0");
        Peak memory peak = peaks[msg.sender];
        require(
            peak.state != PeakState.Extinct,
            "Peak is extinct"
        );
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
        external
        checkAndNotifyDeficit
    {
        _updateFeed();
        totalAssets = totalSystemAssets();
    }

    function rewardDistributionCheckpoint(bool shouldDistribute)
        external
        onlyStakeLPToken
        checkAndNotifyDeficit
        returns(uint periodIncome)
    {
        (totalAssets, periodIncome) = lastPeriodIncome();
        if (periodIncome > 0) {
            if (shouldDistribute) {
                dusd.mint(address(stakeLPToken), periodIncome);
            } else {
                // stakers don't get these, will act as extra volatility cushion
                unclaimedRewards = unclaimedRewards.add(periodIncome);
            }
        }
    }

    /* ##### View functions ##### */

    function lastPeriodIncome()
        public
        view
        returns(uint _totalAssets, uint periodIncome)
    {
        _totalAssets = totalSystemAssets();
        uint supply = dusd.totalSupply().add(unclaimedRewards);
        if (_totalAssets > supply) {
            periodIncome = _totalAssets.sub(supply);
        }
    }

    /**
    * @notice Returns the net system assets across all peaks
    * @return _totalAssets system assets denominated in dollars
    */
    function totalSystemAssets()
        public
        view
        returns (uint _totalAssets)
    {
        for (uint i = 0; i < peaksAddresses.length; i++) {
            Peak memory peak = peaks[peaksAddresses[i]];
            if (peak.state == PeakState.Extinct) {
                continue;
            }
            _totalAssets = _totalAssets.add(IPeak(peaksAddresses[i]).portfolioValue());
        }
    }

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
            usd = usd.mul(redeemFactor).div(REDEEM_FACTOR_PRECISION);
        }
        return usd;
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
        peaks[peak] = Peak(_systemCoins, PeakState.Active);
        if (shouldUpdateFeed) {
            _updateFeed();
        }
        emit PeakWhitelisted(peak);
    }

    /**
    * @notice Change a peaks status
    */
    function setPeakStatus(address peak, PeakState state)
        external
        onlyOwner
    {
        require(
            peaks[peak].state != PeakState.Extinct,
            "Peak is extinct"
        );
        peaks[peak].state = state;
    }

    /* ##### Internal functions ##### */

    function _updateFeed()
        internal
    {
        uint[] memory feed = oracle.getPriceFeed();
        require(feed.length == systemCoins.length, "Invalid system state");
        uint[] memory prices;
        Peak memory peak;
        for (uint i = 0; i < peaksAddresses.length; i++) {
            peak = peaks[peaksAddresses[i]];
            prices = new uint[](peak.systemCoinIds.length);
            if (peak.state == PeakState.Extinct) {
                continue;
            }
            for (uint j = 0; j < prices.length; j++) {
                prices[j] = feed[peak.systemCoinIds[j]];
            }
            IPeak(peaksAddresses[i]).updateFeed(prices);
        }
        emit FeedUpdated(feed);
    }

    function _whitelistToken(address token)
        internal
    {
        for (uint i = 0; i < systemCoins.length; i++) {
            require(systemCoins[i] != token, "Adding a duplicate token");
        }
        systemCoins.push(token);
        emit TokenWhiteListed(token);
    }
}
