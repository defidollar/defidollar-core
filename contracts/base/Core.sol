pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/ownership/Ownable.sol";

import {Oracle} from "../stream/Oracle.sol";
import {StakeLPToken} from "../valley/StakeLPToken.sol";
import {IPeak} from "../peaks/IPeak.sol";
import {DUSD} from "./DUSD.sol";

contract Core is Ownable {
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
    SystemCoin[] public system_coins;

    DUSD public dusd;
    StakeLPToken public stakeLPToken;
    Oracle public oracle;

    enum SystemHealth { GREEN, YELLOW, RED }
    SystemHealth public health;

    uint public dusd_value = PRECISION;
    uint public fee_factor;
    uint public lastIncomeUpdate;
    uint public lastProtocolIncome;

    struct Peak {
        uint[] system_coin_ids; // system indices of the coins accepted by the curve peak
    }
    mapping(address => Peak) peaks;
    address[] public peaks_addresses;

    event Mint(address account, uint amount);
    event Redeem(address account, uint amount);
    event FeedUpdated(uint[] feed);

    constructor() public {
        lastIncomeUpdate = block.timestamp;
    }

    function initialize(
        DUSD _dusd,
        StakeLPToken _stakeLPToken,
        Oracle _oracle,
        uint _fee_factor
    )
        public
        onlyOwner
    {
        dusd = _dusd;
        stakeLPToken = _stakeLPToken;
        oracle = _oracle;
        fee_factor = _fee_factor;
    }

    function mint(
        uint[] calldata delta,
        uint min_dusd_amount,
        address account
    )
        external
        returns (uint dusd_amount)
    {
        Peak memory peak = peaks[msg.sender];
        require(
            peak.system_coin_ids.length > 0,
            "Pool is not whitelisted"
        );
        SystemCoin[] memory coins = system_coins;
        for (uint i = 0; i < peak.system_coin_ids.length; i++) {
            SystemCoin memory coin = coins[peak.system_coin_ids[i]];
            dusd_amount = dusd_amount.add(delta[i].mul(coin.price).div(coin.precision));
        }
        dusd_amount = get_real_value(dusd_amount);
        require(dusd_amount >= min_dusd_amount, "They see you slippin");
        dusd.mint(account, dusd_amount);
        emit Mint(account, dusd_amount);
    }

    function redeem(
        uint[] calldata delta,
        uint max_dusd_amount,
        address account
    )
        external
        returns(uint dusd_amount)
    {
        Peak memory peak = peaks[msg.sender];
        require(
            peak.system_coin_ids.length > 0,
            "Pool is not whitelisted"
        );

        SystemCoin[] memory coins = system_coins;
        for (uint i = 0; i < peak.system_coin_ids.length; i++) {
            SystemCoin memory coin = coins[peak.system_coin_ids[i]];
            dusd_amount = dusd_amount.add(delta[i].mul(coin.price).div(coin.precision));
        }
        dusd_amount = get_real_value(dusd_amount).mul(fee_factor).div(10000);
        require(dusd_amount <= max_dusd_amount, "They see you slippin");
        dusd.redeem(account, dusd_amount);
        emit Redeem(account, dusd_amount);
    }

    /**
    * @dev Pull prices from the Oracle contract
    */
    function sync_system() external {
        _update_feed();
        update_system_stats();
    }

    function _update_feed() internal {
        uint[] memory feed = oracle.getPriceFeed();
        require(
            feed.length == system_coins.length,
            "Invalid system state"
        );
        for (uint i = 0; i < feed.length; i++) {
            system_coins[i].price = feed[i];
        }
        emit FeedUpdated(feed);
    }

    function update_system_stats() public returns(uint protocol_income) {
        uint inventory = get_inventory(); // denominated in $s
        uint supply = dusd.totalSupply();
        // if supply <= inventory, system is healthy
        if (supply <= inventory) {
            // income is only what is available after accounting for DUSD at $1
            protocol_income = inventory.sub(supply);
            health = SystemHealth.GREEN;
            dusd_value = PRECISION; // pegged at $1 :)
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
                dusd_value = inventory.mul(PRECISION).div(supply);
                health = SystemHealth.RED;
            }
        }

        uint notifyIncome;
        if (protocol_income > lastProtocolIncome) {
            notifyIncome = protocol_income.sub(lastProtocolIncome);
            stakeLPToken.notifyProtocolIncomeAmount(notifyIncome
                .div(block.timestamp.sub(lastIncomeUpdate))
            );
        }
        lastProtocolIncome = protocol_income;
        lastIncomeUpdate = block.timestamp;
    }

    function mintReward(address account, uint dollar_amount) public {
        require(msg.sender == address(stakeLPToken), "Only stakeLPToken");
        dusd.mint(account, dollar_amount.mul(PRECISION).div(dusd_value));
    }

    // View functions
    function get_real_value(uint dusd_amount) public view returns(uint) {
        if (health == SystemHealth.RED) {
            return dusd_amount.mul(PRECISION).div(dusd_value);
        }
        return dusd_amount;
    }

    function get_inventory() public view returns (uint inventory) {
        SystemCoin[] memory coins = system_coins;
        uint[] memory portfolio = new uint[](coins.length);
        for(uint i = 0; i < peaks_addresses.length; i++) {
            uint[] memory peak_portfolio = IPeak(peaks_addresses[i]).portfolio();
            Peak memory peak = peaks[peaks_addresses[i]];
            for (uint j = 0; j < peak.system_coin_ids.length; j++) {
                portfolio[peak.system_coin_ids[j]] = portfolio[peak.system_coin_ids[j]]
                    .add(peak_portfolio[j]);
            }
        }

        for(uint i = 0; i < coins.length; i++) {
            SystemCoin memory coin = coins[i];
            inventory = inventory.add(portfolio[i].mul(coin.price).div(coin.precision));
        }
    }

    // Admin functions
    event TokenWhiteListed(address token);
    event PeakWhitelisted(address peak);

    function whitelist_tokens(
        address[] calldata tokens,
        uint[] calldata decimals,
        uint[] calldata initial_prices
    )
        external
    {
        for (uint i = 0; i < tokens.length; i++) {
            whitelistToken(tokens[i], decimals[i], initial_prices[i]);
        }
    }

    function whitelistToken(address token, uint decimals, uint initial_price) public onlyOwner {
        system_coins.push(SystemCoin(token, 10 ** decimals, initial_price));
        emit TokenWhiteListed(token);
    }

    function whitelist_peak(address peak, uint[] calldata _system_coins)
        external
        onlyOwner
    {
        uint num_system_coins = system_coins.length;
        for (uint i = 0; i < _system_coins.length; i++) {
            require(_system_coins[i] < num_system_coins, "Invalid system coin index");
        }
        peaks_addresses.push(peak);
        peaks[peak] = Peak(new uint[](0));
        peaks[peak].system_coin_ids = _system_coins;
        emit PeakWhitelisted(peak);
    }
}
