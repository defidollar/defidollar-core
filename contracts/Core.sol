pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/ownership/Ownable.sol";

import {ICurveDeposit, ICurve} from "./curve/ICurve.sol";
import {Oracle} from "./oracle/Oracle.sol";
import {DUSD} from "./DUSD.sol";

contract Core is Ownable {
  using SafeERC20 for IERC20;
  using SafeMath for uint;

  uint constant MAX = 2**256 - 1;

  // All coins supported by the DefiDollar system
  struct SystemCoin {
    address token;
    uint precision;
    uint price; // feed from oracle
  }
  SystemCoin[] public system_coins;

  // The DefiDollar token
  DUSD public dusd;
  Oracle public oracle;
  uint collateralization_ratio;

  struct CurvePool {
    ICurveDeposit curve_deposit; // deposit contract
    ICurve curve; // swap contract
    IERC20 curve_token; // LP token contract
    uint[] system_coin_ids; // system indices of the coins accepted by the curve pool
  }
  CurvePool[] public pools;

  struct LPShareInfo {
    uint old_lp_amount;
    uint old_lp_supply;
    uint new_lp_amount;
    uint new_lp_supply;
  }

  event Mint(address account, uint amount);
  event Burn(address account, uint amount);
  event FeedUpdated(uint[] feed);

  function initialize(DUSD _dusd, Oracle _oracle, uint _collateralization_ratio)
    public
    onlyOwner
  {
    require(
      address(dusd) == address(0x0) && address(oracle) == address(0x0),
      "Already initialized"
    );
    dusd = _dusd;
    oracle = _oracle;
    collateralization_ratio = _collateralization_ratio;
  }

  /**
  * @dev Mint DUSD
  * @param pool_id Curve pool ID defined by the defidollar system
  * @param in_amounts Exact in_amounts in the same order as required by the curve pool
  * @param min_dusd_amount Minimum DUSD to mint, used for capping slippage
  */
  function mint(
    uint pool_id,
    uint[] calldata in_amounts,
    uint min_dusd_amount
  ) external
    returns (uint dusd_amount)
  {
    CurvePool memory pool = pools[pool_id];
    SystemCoin[] memory _system_coins = system_coins;

    // pull user funds
    for (uint i = 0; i < in_amounts.length; i++) {
      if (in_amounts[i] == 0) continue;
      SystemCoin memory coin = _system_coins[pool.system_coin_ids[i]];
      IERC20(coin.token).safeTransferFrom(msg.sender, address(this), in_amounts[i]);
    }

    // gather current info about pool sizes and shares
    LPShareInfo memory info;
    info.old_lp_amount = pool.curve_token.balanceOf(address(this));
    info.old_lp_supply = pool.curve_token.totalSupply();
    uint[] memory pool_sizes = _getPoolBalances(pool);

    // add liquidity to curve pool
    pool.curve_deposit.add_liquidity(in_amounts, 0);

    // gather current info about new pool sizes and shares
    info.new_lp_amount = pool.curve_token.balanceOf(address(this));
    info.new_lp_supply = pool.curve_token.totalSupply();

    // determine the # of dusd the system should mint using:
    // 1. share in the curve pool
    // 2. the oracle price for the underlying coin
    for (uint i = 0; i < in_amounts.length; i++) {
      if (in_amounts[i] == 0) continue;
      SystemCoin memory coin = _system_coins[pool.system_coin_ids[i]];
      uint delta = _calcDelta(info, pool_sizes[i], in_amounts[i], true);
      // Share of token received times the price of the coin
      dusd_amount = dusd_amount.add(delta.mul(coin.price).div(coin.precision));
    }

    require(dusd_amount >= min_dusd_amount, "They see you slippin");
    dusd.mint(msg.sender, dusd_amount);
    emit Mint(msg.sender, dusd_amount);
  }

  /**
  * @dev Burn DUSD
  * @param pool_id Curve pool ID defined by the defidollar system
  * @param out_amounts Exact out_amounts in the same order as required by the curve pool
  * @param max_dusd_amount Max DUSD to burn, used for capping slippage
  */
  function burn(
    uint pool_id,
    uint[] calldata out_amounts,
    uint max_dusd_amount
  ) external
    returns(uint dusd_amount)
  {
    CurvePool memory pool = pools[pool_id];

    // gather current info about pool sizes and shares
    LPShareInfo memory info; // to avoid stack too deep
    info.old_lp_amount = pool.curve_token.balanceOf(address(this));
    info.old_lp_supply = pool.curve_token.totalSupply();
    uint[] memory pool_sizes = _getPoolBalances(pool);

    // remove liquidity from pools
    pool.curve_deposit.remove_liquidity_imbalance(out_amounts, MAX);

    // gather current info about new pool sizes and shares
    info.new_lp_amount = pool.curve_token.balanceOf(address(this));
    info.new_lp_supply = pool.curve_token.totalSupply();

    // determine the # of dusd the system should urn using:
    // 1. share in the curve pool
    // 2. the oracle price for the underlying coin
    SystemCoin[] memory _system_coins = system_coins;
    for (uint i = 0; i < out_amounts.length; i++) {
      if (out_amounts[i] == 0) continue;
      SystemCoin memory coin = _system_coins[pool.system_coin_ids[i]];
      IERC20(coin.token).safeTransfer(msg.sender, out_amounts[i]);
      uint delta = _calcDelta(info, pool_sizes[i], out_amounts[i], false);
      dusd_amount = dusd_amount.add(delta.mul(coin.price).div(coin.precision));
    }

    require(dusd_amount <= max_dusd_amount, "They see you slippin");
    dusd.burn(msg.sender, dusd_amount);
    emit Burn(msg.sender, dusd_amount);
  }

  /**
  * @dev Mint DUSD while depositing in more than 1 curve pools
  * @param in_amounts Exact in_amounts that the user wants to supply. Ordered as system_coins.
  * @param pool_ids Curve pool IDs defined by the defidollar system
  * @param distribution distribution[i] is the list of coins that will be supplied to pool at pool_ids[i]
  * @param min_dusd_amount Minimum DUSD to mint, used for capping slippage
  */
  function mintBatch(
    uint[] calldata in_amounts,
    uint[] calldata pool_ids,
    uint[][] calldata distribution,
    uint min_dusd_amount
  ) external
    returns (uint dusd_amount)
  {
    SystemCoin[] memory _system_coins = system_coins;

    // pull user funds
    for (uint i = 0; i < _system_coins.length; i++) {
      if (in_amounts[i] == 0) continue;
      IERC20(_system_coins[i].token).safeTransferFrom(msg.sender, address(this), in_amounts[i]);
    }

    // add liquidity to curve pools
    uint[] memory coin_delta = new uint[](_system_coins.length);
    { // scoped to avoid stack too deep
      LPShareInfo memory info;
      CurvePool memory pool;
      for (uint i = 0; i < pool_ids.length; i++) {
        pool = pools[pool_ids[i]];
        info.old_lp_amount = pool.curve_token.balanceOf(address(this));
        info.old_lp_supply = pool.curve_token.totalSupply();
        uint[] memory pool_sizes = _getPoolBalances(pool);
        pool.curve_deposit.add_liquidity(distribution[i], 0);
        info.new_lp_amount = pool.curve_token.balanceOf(address(this));
        info.new_lp_supply = pool.curve_token.totalSupply();
        for (uint j = 0; j < pool.system_coin_ids.length; j++) {
          if (distribution[i][j] == 0) continue;
          uint delta = _calcDelta(info, pool_sizes[j], distribution[i][j], true);
          coin_delta[pool.system_coin_ids[j]] = coin_delta[pool.system_coin_ids[j]].add(delta);
        }
      }
    }

    // mint DUSD
    for (uint i = 0; i < _system_coins.length; i++) {
      if (coin_delta[i] == 0) continue;
      SystemCoin memory coin = _system_coins[i];
      dusd_amount = dusd_amount.add(coin_delta[i].mul(coin.price).div(coin.precision));
    }
    require(dusd_amount >= min_dusd_amount, "They see you slippin");
    dusd.mint(msg.sender, dusd_amount);
    emit Mint(msg.sender, dusd_amount);
  }

  /**
  * @dev Burn DUSD while withdrawing from more than 1 curve pools
  * @param out_amounts Exact out_amounts that the user wants to withdraw. Ordered as system_coins.
  * @param pool_ids Curve pool IDs defined by the defidollar system
  * @param distribution distribution[i] is the list of coins that will be withdrawn from the pool at pool_ids[i]
  * @param max_dusd_amount Miximum DUSD to burn, used for capping slippage
  */
  function burnBatch(
    uint[] calldata out_amounts,
    uint[] calldata pool_ids,
    uint[][] calldata distribution,
    uint max_dusd_amount
  ) external
    returns (uint dusd_amount)
  {
    SystemCoin[] memory _system_coins = system_coins;

    // Remove liquidity from pools
    uint[] memory coin_delta = new uint[](_system_coins.length);
    { // scoped to avoid stack too deep
      LPShareInfo memory info;
      CurvePool memory pool;
      for (uint i = 0; i < pool_ids.length; i++) {
        pool = pools[pool_ids[i]];
        info.old_lp_amount = pool.curve_token.balanceOf(address(this));
        info.old_lp_supply = pool.curve_token.totalSupply();
        uint[] memory pool_sizes = _getPoolBalances(pool);
        pool.curve_deposit.remove_liquidity_imbalance(distribution[i], MAX);
        info.new_lp_amount = pool.curve_token.balanceOf(address(this));
        info.new_lp_supply = pool.curve_token.totalSupply();
        for (uint j = 0; j < pool.system_coin_ids.length; j++) {
          uint delta = _calcDelta(info, pool_sizes[j], distribution[i][j], false);
          coin_delta[pool.system_coin_ids[j]] = coin_delta[pool.system_coin_ids[j]].add(delta);
        }
      }
    }

    // Transfer withdrawn coins to user and calculate dusd to burn
    for (uint i = 0; i < _system_coins.length; i++) {
      if (out_amounts[i] == 0) continue;
      SystemCoin memory coin = _system_coins[i];
      // solves a dual purpose of reverting if enough balance has not been accumulated
      IERC20(coin.token).safeTransfer(msg.sender, out_amounts[i]);
      dusd_amount = dusd_amount.add(coin_delta[i].mul(coin.price).div(coin.precision));
    }

    // Burn DUSD
    require(dusd_amount <= max_dusd_amount, "They see you slippin");
    dusd.burn(msg.sender, dusd_amount);
    emit Burn(msg.sender, dusd_amount);
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
    emit FeedUpdated(feed);
  }

  // This is risky (Bancor Hack scenario). Think about if we need strict token approvals during the actions at the cost of higher gas.
  function replenish_approvals() external {
    CurvePool[] memory _pools = pools;
    SystemCoin[] memory _system_coins = system_coins;
    for (uint i = 0; i < _pools.length; i++) {
      CurvePool memory pool = _pools[i];
      pool.curve_token.approve(address(pool.curve_deposit), MAX);
      for (uint j = 0; j < pool.system_coin_ids.length; j++) {
        SystemCoin memory coin = _system_coins[pool.system_coin_ids[j]];
        IERC20(coin.token).approve(address(pool.curve_deposit), MAX);
      }
    }
  }

  // internal functions
  function _getPoolBalances(CurvePool memory pool) internal view returns(uint[] memory) {
    uint num_pool_tokens = pool.system_coin_ids.length;
    uint[] memory portfolio = new uint[](num_pool_tokens);
    for (uint i = 0; i < num_pool_tokens; i++) {
      portfolio[i] = pool.curve.balances(i);
    }
    return portfolio;
  }

  function _calcDelta(
    LPShareInfo memory info,
    uint old_pool_size,
    uint amount,
    bool deposit
  ) internal pure returns (uint /* delta */) {
    uint old_balance;
    if (info.old_lp_supply > 0) {
      old_balance = old_pool_size.mul(info.old_lp_amount).div(info.old_lp_supply);
    }
    uint new_balance;
    if (deposit) {
      if (info.new_lp_supply > 0) {
        new_balance = old_pool_size.add(amount).mul(info.new_lp_amount).div(info.new_lp_supply);
      }
      return new_balance.sub(old_balance);
    }
    if (info.new_lp_supply > 0) {
      new_balance = old_pool_size.sub(amount).mul(info.new_lp_amount).div(info.new_lp_supply);
    }
    return old_balance.sub(new_balance);
  }
}
