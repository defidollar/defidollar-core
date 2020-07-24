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

    enum SystemHealth { GREEN, YELLOW, RED }
    SystemHealth public health;

    uint public dusdValue = PRECISION;
    uint public redeemFee;
    uint public lastIncomeUpdate;
    uint public lastProtocolIncome;

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
        lastIncomeUpdate = block.timestamp;
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
        returns (uint dusdAmount)
    {
        Peak memory peak = peaks[msg.sender];
        require(
            peak.state == PeakState.Active,
            "Peak is inactive"
        );
        SystemCoin[] memory coins = systemCoins;
        for (uint i = 0; i < peak.systemCoinIds.length; i++) {
            SystemCoin memory coin = coins[peak.systemCoinIds[i]];
            dusdAmount = dusdAmount.add(
                delta[i].mul(coin.price).div(coin.precision)
            );
        }
        dusdAmount = getRealValue(dusdAmount);
        require(dusdAmount >= minDusdAmount, "They see you slippin");
        dusd.mint(account, dusdAmount);
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
        returns(uint dusdAmount)
    {
        Peak memory peak = peaks[msg.sender];
        require(
            peak.state != PeakState.Extinct,
            "Peak is extinct"
        );
        SystemCoin[] memory coins = systemCoins;
        for (uint i = 0; i < peak.systemCoinIds.length; i++) {
            SystemCoin memory coin = coins[peak.systemCoinIds[i]];
            dusdAmount = dusdAmount.add(
                delta[i].mul(coin.price).div(coin.precision)
            );
        }
        dusdAmount = getRealValue(dusdAmount).mul(redeemFee).div(10000);
        require(dusdAmount <= maxDusdAmount, "They see you slippin");
        dusd.redeem(account, dusdAmount);
        emit Redeem(account, dusdAmount);
    }

    /**
    * @notice Pull prices from the oracle and update system stats
    * @dev Anyone can call this
    */
    function sync_system() external {
        _updateFeed();
        updateSystemState();
    }

    /**
    *
    */
    function updateSystemState()
        public
        returns(uint protocolIncome)
    {
        uint inventory = getInventory(); // denominated in $s
        uint supply = dusd.totalSupply();
        // if supply <= inventory, system is healthy
        if (supply <= inventory) {
            // income is only what is available after accounting for DUSD at $1
            protocolIncome = inventory.sub(supply);
            health = SystemHealth.GREEN;
            dusdValue = PRECISION; // pegged at $1 :)
        } else {
            // try to maintain the collateralization ratio using staked funds
            uint dusd_staked = stakeLPToken.totalSupply();
            if (dusd_staked > 0 && dusd_staked < supply) {
                supply = supply.sub(dusd_staked);
            }
            if (supply <= inventory) {
                health = SystemHealth.YELLOW;
            } else {
                // if not even the staked funds can make up for it, we devalue dusd
                dusdValue = inventory.mul(PRECISION).div(supply);
                health = SystemHealth.RED;
            }
        }

        uint notifyIncome;
        if (protocolIncome > lastProtocolIncome) {
            notifyIncome = protocolIncome.sub(lastProtocolIncome);
            stakeLPToken.notifyProtocolIncomeAmount(notifyIncome
                .div(block.timestamp.sub(lastIncomeUpdate))
            );
        }
        lastProtocolIncome = protocolIncome;
        lastIncomeUpdate = block.timestamp;
    }

    /**
    * @notice Mint staking rewards
    * @param account Account to mint rewards to
    * @param dollarAmount Reward amount denominated in dollars
    */
    function mintReward(address account, uint dollarAmount)
        external
    {
        require(msg.sender == address(stakeLPToken), "Only stakeLPToken");
        dusd.mint(account, dollarAmount.mul(PRECISION).div(dusdValue));
    }

    // View functions

    /**
    * @notice Real dollar amount based on the fact that DUSD could be under-collateralized
    */
    function getRealValue(uint dollarAmount)
        public
        view
        returns(uint)
    {
        if (health == SystemHealth.RED) {
            return dollarAmount.mul(PRECISION).div(dusdValue);
        }
        return dollarAmount;
    }

    /**
    * @notice Returns the net system assets across all peaks
    * @return inventory system assets denominated in dollars
    */
    function getInventory()
        public
        view
        returns (uint inventory)
    {
        SystemCoin[] memory coins = systemCoins;
        uint[] memory portfolio = new uint[](coins.length);
        // retrieve assets accross all peaks
        for(uint i = 0; i < peaksAddresses.length; i++) {
            uint[] memory peakPortfolio = IPeak(peaksAddresses[i]).portfolio();
            Peak memory peak = peaks[peaksAddresses[i]];
            for (uint j = 0; j < peak.systemCoinIds.length; j++) {
                portfolio[peak.systemCoinIds[j]] = portfolio[peak.systemCoinIds[j]].add(peakPortfolio[j]);
            }
        }

        // multiply retrieved assets from with the price
        for(uint i = 0; i < coins.length; i++) {
            SystemCoin memory coin = coins[i];
            inventory = inventory.add(
                portfolio[i].mul(coin.price).div(coin.precision)
            );
        }
    }

    // onlyOwner functions

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
