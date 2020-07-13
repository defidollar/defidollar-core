pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/ownership/Ownable.sol";

import {Oracle} from "./oracle/Oracle.sol";
import {DUSD} from "./DUSD.sol";
import {SDUSD} from "./SDUSD.sol";
import {IPool} from "./IPool.sol";

contract Core is Ownable {
  using SafeERC20 for IERC20;
  using SafeMath for uint;

  uint constant MAX = 2**256 - 1;
  uint constant PRECISION = 10 ** 18;

  // All coins supported by the DefiDollar system
  struct SystemCoin {
    address token;
    uint precision;
    uint price; // feed from oracle
  }
  SystemCoin[] public system_coins;

  DUSD public dusd; // DefiDollar token
  SDUSD public sDUSD; // Stake receipt

  Oracle public oracle;
  uint public staked_supply;
  uint public dusd_value;

  struct CurvePool {
    uint[] system_coin_ids; // system indices of the coins accepted by the curve pool
  }
  mapping(address => CurvePool) pools;
  address[] public pools_addresses;

  event Mint(address account, uint amount);
  event Burn(address account, uint amount);
  event FeedUpdated(uint[] feed);

  function initialize(DUSD _dusd, SDUSD _sDUSD, Oracle _oracle)
    public
    onlyOwner
  {
    require(
      address(dusd) == address(0x0) && address(oracle) == address(0x0),
      "Already initialized"
    );
    dusd = _dusd;
    sDUSD = _sDUSD;
    oracle = _oracle;
  }

  function mint(uint[] calldata delta, uint min_dusd_amount)
    external
    returns (uint dusd_amount)
  {
    CurvePool memory pool = pools[msg.sender];
    require(
      pool.system_coin_ids.length > 0,
      "Pool is not whitelisted"
    );
    SystemCoin[] memory coins = system_coins;
    for (uint i = 0; i < pool.system_coin_ids.length; i++) {
      SystemCoin memory coin = coins[pool.system_coin_ids[i]];
      dusd_amount = dusd_amount.add(delta[i].mul(coin.price).div(coin.precision));
    }
    require(dusd_amount >= min_dusd_amount, "They see you slippin");
    dusd.mint(msg.sender, dusd_amount);
    emit Mint(msg.sender, dusd_amount);
  }

  function burn(
    uint[] calldata delta,
    uint max_dusd_amount
  ) external
    returns(uint dusd_amount)
  {
    CurvePool memory pool = pools[msg.sender];
    require(
      pool.system_coin_ids.length > 0,
      "Pool is not whitelisted"
    );
    SystemCoin[] memory coins = system_coins;
    for (uint i = 0; i < pool.system_coin_ids.length; i++) {
      SystemCoin memory coin = coins[pool.system_coin_ids[i]];
      dusd_amount = dusd_amount.add(delta[i].mul(coin.price).div(coin.precision));
    }
    require(dusd_amount <= max_dusd_amount, "They see you slippin");
    dusd.burn(msg.sender, dusd_amount);
    emit Burn(msg.sender, dusd_amount);
  }

  function stake(uint amount) external {
    require(
      dusd.transferFrom(msg.sender, address(this), amount),
      "Transfer failed"
    );
    uint exchange_rate = get_non_circulating_inventory()
      .mul(PRECISION)
      .div(sDUSD.totalSupply());
    sDUSD.mint(msg.sender, exchange_rate.mul(amount).div(PRECISION));
  }

  function unstake(uint sdusd_amount) external {
    uint exchange_rate = get_non_circulating_inventory()
      .mul(PRECISION)
      .div(sDUSD.totalSupply());
    sDUSD.burn(msg.sender, sdusd_amount);
    uint dusd_amount = sdusd_amount.mul(exchange_rate).div(dusd_value);
    uint balance = dusd.balanceOf(address(this));
    if (balance < dusd_amount) {
      dusd.mint(address(this), dusd_amount.sub(balance));
    }
    require(
      dusd.transfer(msg.sender, dusd_amount),
      "Transfer Failed"
    );
  }

  function get_non_circulating_inventory() public view returns(uint) {
    uint staked_value = get_staked_supply().mul(dusd_value);
    return get_inventory().sub(staked_value);
  }

  function get_staked_supply() public view returns(uint) {
    // @todo dusd.balanceOf(this) to get the staked supply might not be the best way - Think about it
    return dusd.totalSupply().sub(dusd.balanceOf(address(this)));
  }

  function get_inventory() public view returns (uint inventory) {
    uint[] memory portfolio = new uint[](pools_addresses.length);
    for(uint i = 0; i < pools_addresses.length; i++) {
      uint[] memory pool_portfolio = IPool(pools_addresses[i]).portfolio();
      CurvePool memory pool = pools[pools_addresses[i]];
      for (uint j = 0; j < pool.system_coin_ids.length; j++) {
        portfolio[pool.system_coin_ids[j]] += pool_portfolio[j];
      }
    }

    SystemCoin[] memory coins = system_coins;
    for(uint i = 0; i < coins.length; i++) {
      SystemCoin memory coin = coins[i];
      inventory = inventory.add(portfolio[i].mul(coin.price).div(coin.precision));
    }
  }

  /**
  * @dev Pull prices from the Oracle contract
  */
  function updatePrices() external {
    uint[] memory feed = oracle.getPriceFeed();
    require(
      feed.length == system_coins.length,
      "Invalid system state"
    );
    for (uint i = 0; i < feed.length; i++) {
      system_coins[i].price = feed[i];
    }
    dusd_value = get_inventory()
      .mul(PRECISION)
      .div(dusd.totalSupply().sub(get_staked_supply()));
    emit FeedUpdated(feed);
  }

  // Admin functions
  event TokenWhiteListed(address token);
  event CurvePoolWhitelisted(uint pool_id);

  function whitelistTokens(address[] calldata tokens, uint[] calldata decimals) external {
    for (uint i = 0; i < tokens.length; i++) {
      whitelistToken(tokens[i], decimals[i]);
    }
  }

  function whitelistToken(address token, uint decimals) public onlyOwner {
    system_coins.push(SystemCoin(token, 10 ** decimals, 0));
    emit TokenWhiteListed(token);
  }
}
