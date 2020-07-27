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

    uint constant MAX = uint(-1);
    uint constant PRECISION = 1e18;

    // All coins supported by the DefiDollar system
    struct SystemCoin {
        address token;
        uint precision;
        uint price; // feed from oracle
    }
    SystemCoin[] public systemCoins;

    DUSD public dusd;
    StakeLPToken public stakeLPToken;
    Oracle public oracle;

    uint public redeemFee;
    uint public lastOverCollateralizationAmount;
    uint public totalAssets;
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
        stakeLPToken.notifyProtocolIncome(0);
    }

    /**
    * @notice Mint DUSD
    * @dev Only whitelisted peaks can call this function
    * @param delta Delta of system coins added to the system through a peak
    * @param minDusdAmount Min DUSD amount to mint. Used to cap slippage
    * @param account Account to mint DUSD to
    * @return dusdAmount DUSD amount actually minted
    */
    function mint(
        uint[] calldata delta,
        uint minDusdAmount,
        address account
    )   external
        checkAndNotifyDeficit
        returns (uint dusdAmount)
    {
        Peak memory peak = peaks[msg.sender];
        require(
            peak.state == PeakState.Active,
            "Peak is inactive"
        );
        uint usdDelta;
        SystemCoin[] memory coins = systemCoins;
        for (uint i = 0; i < peak.systemCoinIds.length; i++) {
            SystemCoin memory coin = coins[peak.systemCoinIds[i]];
            usdDelta = usdDelta.add(
                delta[i].mul(coin.price).div(coin.precision)
            );
        }
        dusdAmount = usdToDusd(usdDelta);
        require(dusdAmount >= minDusdAmount, "They see you slippin");
        dusd.mint(account, dusdAmount);
        totalAssets = totalAssets.add(usdDelta);
        emit Mint(account, dusdAmount);
    }

    /**
    * @notice Redeem DUSD
    * @dev Only whitelisted peaks can call this function
    * @param delta Delta of system coins removed from the system through a peak
    * @param maxDusdAmount Max DUSD amount to burn. Used to cap slippage
    * @param account Account to mint DUSD to
    * @return dusdAmount DUSD amount actually redeemed
    */
    function redeem(
        uint[] calldata delta,
        uint maxDusdAmount,
        address account
    )   external
        checkAndNotifyDeficit
        returns(uint dusdAmount)
    {
        Peak memory peak = peaks[msg.sender];
        require(
            peak.state != PeakState.Extinct,
            "Peak is extinct"
        );
        uint usdDelta;
        SystemCoin[] memory coins = systemCoins;
        for (uint i = 0; i < peak.systemCoinIds.length; i++) {
            if (delta[i] == 0) continue;
            SystemCoin memory coin = coins[peak.systemCoinIds[i]];
            usdDelta = usdDelta.add(
                delta[i].mul(coin.price).div(coin.precision)
            );
        }
        // burn a little more dusd
        dusdAmount = usdToDusd(usdDelta).mul(redeemFee).div(10000);
        require(dusdAmount <= maxDusdAmount, "They see you slippin");
        dusd.burn(account, dusdAmount);
        totalAssets = totalAssets.sub(usdDelta);
        emit Redeem(account, dusdAmount);
    }

    /**
    * @notice Mint staking rewards
    * @param account Account to mint rewards to
    * @param usdDelta Reward amount denominated in dollars
    */
    function mintReward(address account, uint usdDelta)
        checkAndNotifyDeficit
        external
    {
        require(
            msg.sender == address(stakeLPToken),
            "Only stakeLPToken"
        );
        dusd.mint(account, usdToDusd(usdDelta));
    }

    /**
    * @notice Pull prices from the oracle and update system stats
    * @dev Anyone can call this
    */
    function syncSystem()
        external
    {
        _updateFeed();
        notifyProtocolIncomeAndDeficit();
    }

    event DebugUint(uint indexed a);
    /**
    * @notice Updates the
    *   Notifies stakeLPToken about the protocol income so that rewards become claimable.
    * @dev Anyone can call this anytime they like. For instance,
    *   if the user thinks they have accrued a large reward, they should call notifyProtocolIncomeAndDeficit and then claim reward.
    * @return overCollateralizationAmount
    */
    function notifyProtocolIncomeAndDeficit()
        checkAndNotifyDeficit
        public
    {
        totalAssets = totalSystemAssets(); // denominated in dollars
        uint supply = dusd.totalSupply();
        // supply >= totalAssets means no income
        if (supply < totalAssets) {
            uint overCollateralizationAmount = totalAssets.sub(supply);
            if (overCollateralizationAmount > lastOverCollateralizationAmount) {
                emit DebugUint(overCollateralizationAmount - lastOverCollateralizationAmount);
                stakeLPToken.notifyProtocolIncome(
                    overCollateralizationAmount.sub(lastOverCollateralizationAmount)
                );
                lastOverCollateralizationAmount = overCollateralizationAmount;
            }
        }
    }

    // View functions

    /**
    * @notice Returns the net system assets across all peaks
    * @return inventory system assets denominated in dollars
    */
    function totalSystemAssets()
        public
        view
        returns (uint _totalAssets)
    {
        SystemCoin[] memory coins = systemCoins;
        uint[] memory portfolio = new uint[](coins.length);
        // retrieve assets accross all peaks
        for(uint i = 0; i < peaksAddresses.length; i++) {
            uint[] memory peakPortfolio = IPeak(peaksAddresses[i]).portfolio();
            Peak memory peak = peaks[peaksAddresses[i]];
            for (uint j = 0; j < peak.systemCoinIds.length; j++) {
                if (peak.state != PeakState.Extinct) {
                    portfolio[peak.systemCoinIds[j]] = portfolio[peak.systemCoinIds[j]].add(peakPortfolio[j]);
                }
            }
        }

        // multiply retrieved asset amounts with the oracle price
        for(uint i = 0; i < coins.length; i++) {
            SystemCoin memory coin = coins[i];
            _totalAssets = _totalAssets.add(
                portfolio[i].mul(coin.price).div(coin.precision)
            );
        }
    }

    // Admin functions

    /**
    * @notice Whitelist new tokens supported by the peaks.
    * These are vanilla coins like DAI, USDC, USDT etc.
    * @dev onlyOwner ACL is provided by the whitelistToken call
    * @param tokens Token addresses to whitelist
    * @param decimals Token Precision
    * @param initialPrices Intialize prices akin to retieving from an oracle
    */
    function whitelistTokens(
        address[] calldata tokens,
        uint[] calldata decimals,
        uint[] calldata initialPrices
    )   external
        onlyOwner
    {
        for (uint i = 0; i < tokens.length; i++) {
            _whitelistToken(tokens[i], decimals[i], initialPrices[i]);
        }
    }

    /**
    * @notice Whitelist a new peak
    * @param peak Address of the contract that interfaces with the 3rd-party protocol
    * @param _systemCoins Indices of the system coins, the peak supports
    */
    function whitelistPeak(
        address peak,
        uint[] calldata _systemCoins
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

    // Internal functions

    function usdToDusd(uint usd) public view returns(uint) {
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

    function _updateFeed()
        internal
    {
        uint[] memory feed = oracle.getPriceFeed();
        require(
            feed.length == systemCoins.length,
            "Invalid system state"
        );
        for (uint i = 0; i < feed.length; i++) {
            systemCoins[i].price = feed[i];
        }
        emit FeedUpdated(feed);
    }

    function _whitelistToken(address token, uint decimals, uint initialPrice)
        internal
    {
        require(decimals > 0, "Using a 0 decimal coin can break the system");
        systemCoins.push(SystemCoin(token, 10 ** decimals, initialPrice));
        emit TokenWhiteListed(token);
    }
}
