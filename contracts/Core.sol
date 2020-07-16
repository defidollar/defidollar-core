pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/ownership/Ownable.sol";

import {Oracle} from "./oracle/Oracle.sol";
import {DUSD} from "./DUSD.sol";
import {IPool} from "./IPool.sol";
import "./StakeLPToken.sol";

contract Core is Ownable {
  using SafeERC20 for IERC20;
  using SafeMath for uint;

  uint constant MAX = uint(-1);
  uint constant PRECISION = 10 ** 18;

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

  function initialize(DUSD _dusd, StakeLPToken _stakeLPToken, Oracle _oracle)
    public
    onlyOwner
  {
    dusd = _dusd;
    oracle = _oracle;
    stakeLPToken = _stakeLPToken;
  }

  function mint(
    uint[] calldata delta,
    uint min_dusd_amount,
    address account
  ) external
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
    dusd_amount = get_real_value(dusd_amount);
    require(dusd_amount >= min_dusd_amount, "They see you slippin");
    dusd.mint(account, dusd_amount);
    emit Mint(account, dusd_amount);
  }

  function burn(
    uint[] calldata delta,
    uint max_dusd_amount,
    address account
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
    dusd_amount = get_real_value(dusd_amount);
    require(dusd_amount <= max_dusd_amount, "They see you slippin");
    dusd.burn(account, dusd_amount);
    emit Burn(account, dusd_amount);
  }

  function get_inventory() public view returns (uint inventory) {
    uint[] memory portfolio = new uint[](pools_addresses.length);
    for(uint i = 0; i < pools_addresses.length; i++) {
      uint[] memory pool_portfolio = IPool(pools_addresses[i]).portfolio();
      CurvePool memory pool = pools[pools_addresses[i]];
      for (uint j = 0; j < pool.system_coin_ids.length; j++) {
        portfolio[pool.system_coin_ids[j]] = portfolio[pool.system_coin_ids[j]].add(pool_portfolio[j]);
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
    uint supply = dusd.totalSupply();
    uint dusd_staked = stakeLPToken.totalSupply();
    if (dusd_staked > 0 && dusd_staked < supply) {
      supply = supply.sub(dusd_staked);
    }
    dusd_value = get_inventory().mul(PRECISION).div(supply);
    if (dusd_value > PRECISION) {
      dusd_value = PRECISION; // pegged at $1 :)
    }
    emit FeedUpdated(feed);
  }

  function mintReward(address account, uint dollar_amount) public {
    require(msg.sender == address(stakeLPToken), "Only stakeLPToken");
    dusd.mint(account, dollar_amount.mul(PRECISION).div(dusd_value));
  }

  function get_real_value(uint dusd_amount) public view returns(uint) {
    return dusd_amount.mul(PRECISION).div(dusd_value);
  }

  function getProtocolIncome() public view returns(uint) {
    return get_inventory().sub(dusd.totalSupply().mul(dusd_value).div(PRECISION));
  }

  // Admin functions
  event TokenWhiteListed(address token);
  event CurvePoolWhitelisted(address pool);

  function whitelistTokens(address[] calldata tokens, uint[] calldata decimals) external {
    for (uint i = 0; i < tokens.length; i++) {
      whitelistToken(tokens[i], decimals[i]);
    }
  }

  function whitelistToken(address token, uint decimals) public onlyOwner {
    system_coins.push(SystemCoin(token, 10 ** decimals, 0));
    emit TokenWhiteListed(token);
  }

  function whitelistPool(address pool, uint[] calldata _system_coins) external onlyOwner {
    uint num_system_coins = system_coins.length;
    for (uint i = 0; i < _system_coins.length; i++) {
      require(_system_coins[i] < num_system_coins, "Invalid system coin index");
    }
    pools_addresses.push(pool);
    pools[pool] = CurvePool(new uint[](0));
    pools[pool].system_coin_ids = _system_coins;
    emit CurvePoolWhitelisted(pool);
  }
}
