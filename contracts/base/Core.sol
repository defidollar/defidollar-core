pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {Oracle} from "../stream/Oracle.sol";
import {StakeLPToken} from "../valley/StakeLPToken.sol";
import {IPeak} from "../peaks/IPeak.sol";
import {DUSD} from "./DUSD.sol";
import {Initializable} from "../common/Initializable.sol";
import {Ownable} from "../common/Ownable.sol";


contract Core is Initializable, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    DUSD public dusd;
    StakeLPToken public stakeLPToken;
    Oracle public oracle;
    address[] public systemCoins;

    uint public redeemFee;
    uint public totalAssets;
    uint public claimedRewards;
    uint public totalRewards;
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

    event Mint(address account, uint amount);
    event Redeem(address account, uint amount);
    event FeedUpdated(uint[] feed);
    event TokenWhiteListed(address token);
    event PeakWhitelisted(address peak);

    modifier checkAndNotifyDeficit() {
        _;
        uint supply = dusd.totalSupply();
        if (supply > totalAssets) {
            inDeficit = true;
            stakeLPToken.notify(supply.sub(totalAssets));
        } else if (inDeficit) {
            inDeficit = false;
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
        DUSD _dusd,
        StakeLPToken _stakeLPToken,
        Oracle _oracle,
        uint _redeemFee
    )   public
        notInitialized
    {
        dusd = _dusd;
        stakeLPToken = _stakeLPToken;
        oracle = _oracle;
        redeemFee = _redeemFee;
    }

    /**
    * @notice Mint DUSD
    * @dev Only whitelisted peaks can call this function
    * @param usdDelta Delta of system coins added to the system through a peak
    * @param account Account to mint DUSD to
    * @return dusdAmount DUSD amount minted
    */
    function mint(uint usdDelta, address account)
        external
        checkAndNotifyDeficit
        returns (uint dusdAmount)
    {
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
    * @notice Mint staking rewards
    * @param account Account to mint rewards to
    * @param usdDelta Reward amount denominated in dollars
    */
    function mintReward(address account, uint usdDelta)
        onlyStakeLPToken
        checkAndNotifyDeficit
        external
    {
        claimedRewards = claimedRewards.add(usdDelta);
        dusd.mint(account, usdToDusd(usdDelta));
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

    function rewardDistributionCheckpoint()
        external
        onlyStakeLPToken
        checkAndNotifyDeficit
        returns(uint periodIncome)
    {
        totalAssets = totalSystemAssets();
        uint _totalAssets = totalAssets;
        if (totalRewards > claimedRewards) {
            _totalAssets = _totalAssets.sub(totalRewards.sub(claimedRewards));
        }
        uint supply = dusd.totalSupply();
        if (_totalAssets > supply) {
            periodIncome = _totalAssets.sub(supply);
            totalRewards = totalRewards.add(periodIncome);
        }
    }

    /* ##### View functions ##### */

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

    function lastPeriodIncome() public view returns(uint) {
        uint supply = dusd.totalSupply();
        uint _totalAssets = totalSystemAssets();
        uint unclaimedRewards;
        if (totalRewards > claimedRewards) {
            unclaimedRewards = totalRewards.sub(claimedRewards);
        }
        _totalAssets = _totalAssets.sub(unclaimedRewards);
        uint periodIncome;
        if (_totalAssets > supply) {
            periodIncome = _totalAssets.sub(supply);
        }
        return periodIncome;
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
            uint perceivedSupply = supply.sub(stakeLPToken.totalSupply());
            // staked funds make up for the deficit
            if (perceivedSupply <= totalAssets) {
                usd = _dusd;
            } else {
                usd = _dusd.mul(totalAssets).div(perceivedSupply);
            }
        }
        if (fee) {
            usd = usd.mul(10000).div(redeemFee);
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
