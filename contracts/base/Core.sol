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

    uint constant FEE_PRECISION = 10000;

    IDUSD public dusd;
    IStakeLPToken public stakeLPToken;
    IOracle public oracle;
    address[] public systemCoins;

    uint public totalAssets;
    uint public unclaimedRewards;
    bool public inDeficit;
    uint public redeemFactor;
    uint public adminFee;

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
        uint _redeemFactor,
        uint _adminFee
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
            _redeemFactor <= FEE_PRECISION && _adminFee <= FEE_PRECISION,
            "Incorrect upper bound for fee"
        );
        redeemFactor = _redeemFactor;
        adminFee = _adminFee;
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
        require(usdDelta > 0, "Minting 0");
        Peak memory peak = peaks[msg.sender];
        require(
            peak.state == PeakState.Active,
            "Peak is inactive"
        );
        dusdAmount = usdToDusd(usdDelta);
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
        public
        checkAndNotifyDeficit
    {
        _syncSystem();
    }

    function rewardDistributionCheckpoint(bool shouldDistribute)
        external
        onlyStakeLPToken
        checkAndNotifyDeficit
        returns(uint periodIncome)
    {
        _syncSystem(); // totalAssets was updated
        uint _adminFee;
        (periodIncome, _adminFee) = _lastPeriodIncome(totalAssets);
        if (periodIncome == 0) {
            return 0;
        }
        // note that we do not account for devalued dusd here
        if (shouldDistribute) {
            dusd.mint(address(stakeLPToken), periodIncome);
            if (_adminFee > 0) {
                dusd.mint(address(this), _adminFee);
            }
        } else {
            // stakers don't get these, will act as extra volatility cushion
            unclaimedRewards = unclaimedRewards.add(periodIncome).add(_adminFee);
        }
    }

    /* ##### View functions ##### */

    function lastPeriodIncome()
        public view
        returns(uint _totalAssets, uint periodIncome, uint _adminFee)
    {
        _totalAssets = totalSystemAssets();
        (periodIncome, _adminFee) = _lastPeriodIncome(_totalAssets);
    }

    /**
    * @notice Returns the net system assets across all peaks
    * @return _totalAssets system assets denominated in dollars
    */
    function currentSystemState()
        public view
        returns (uint _totalAssets, uint deficit)
    {
        _totalAssets = totalSystemAssets();
        uint supply = dusd.totalSupply();
        if (supply > _totalAssets) {
            deficit = supply.sub(_totalAssets);
        }
    }

    function totalSystemAssets()
        public view
        returns (uint _totalAssets)
    {
        uint[] memory feed = oracle.getPriceFeed();
        for (uint i = 0; i < peaksAddresses.length; i++) {
            Peak memory peak = peaks[peaksAddresses[i]];
            if (peak.state == PeakState.Extinct) {
                continue;
            }
            _totalAssets = _totalAssets.add(IPeak(peaksAddresses[i]).portfolioValueWithFeed(feed));
        }
    }

    function usdToDusd(uint usd)
        public
        view
        returns(uint)
    {
        // system is healthy. Pegged at $1
        if (!inDeficit) {
            return usd;
        }
        // system is in deficit, see if staked funds can make up for it
        uint supply = dusd.totalSupply();
        uint perceivedSupply = supply.sub(stakeLPToken.totalSupply());
        // staked funds make up for the deficit
        if (perceivedSupply <= totalAssets) {
            return usd;
        }
        return usd.mul(perceivedSupply).div(totalAssets);
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
            usd = usd.mul(redeemFactor).div(FEE_PRECISION);
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

    function setFee(uint _redeemFactor, uint _adminFee)
        external
        onlyOwner
    {
        require(
            _redeemFactor <= FEE_PRECISION && _adminFee <= FEE_PRECISION,
            "Incorrect upper bound for fee"
        );
        redeemFactor = _redeemFactor;
        adminFee = _adminFee;
    }

    function withdrawAdminFee(address destination)
        external
        onlyOwner
    {
        IERC20 _dusd = IERC20(address(dusd));
        _dusd.safeTransfer(destination, _dusd.balanceOf(address(this)));
    }

    /* ##### Internal functions ##### */

    function _updateFeed()
        internal
        returns(uint _totalAssets)
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
            _totalAssets = _totalAssets.add(
                IPeak(peaksAddresses[i]).updateFeed(prices)
            );
        }
        emit FeedUpdated(feed);
    }

    function _lastPeriodIncome(uint _totalAssets)
        internal view
        returns(uint _periodIncome, uint _adminFee)
    {
        uint supply = dusd.totalSupply().add(unclaimedRewards);
        if (_totalAssets > supply) {
            _periodIncome = _totalAssets.sub(supply);
            if (adminFee > 0) {
                _adminFee = _periodIncome.mul(adminFee).div(FEE_PRECISION);
                _periodIncome = _periodIncome.sub(_adminFee);
            }
        }
    }

    function _syncSystem()
        internal
    {
        totalAssets = _updateFeed();
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
