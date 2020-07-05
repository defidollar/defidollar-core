pragma solidity ^0.5.12;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DUSD} from "./DUSD.sol";
import {Core} from "./Core.sol";

contract CoreBatch is Core {

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
    address[] memory _system_coins = system_coins;
    uint num_system_coins = _system_coins.length;

    // pull user funds
    for (uint i = 0; i < num_system_coins; i++) {
      if (in_amounts[i] == 0) continue;
      IERC20 token = IERC20(_system_coins[i]);
      token.safeTransferFrom(msg.sender, address(this), in_amounts[i]);
    }

    // add liquidity to curve pools
    uint[] memory coin_delta = new uint[](num_system_coins);
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
    for (uint i = 0; i < num_system_coins; i++) {
      if (coin_delta[i] == 0) continue;
      dusd_amount = dusd_amount.add(coin_delta[i].mul(prices[i]));
    }
    require(dusd_amount >= min_dusd_amount, "They see you slippin");
    dusd.mint(msg.sender, dusd_amount);
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
    address[] memory _system_coins = system_coins;
    uint num_system_coins = _system_coins.length;


    // Remove liquidity from pools
    uint[] memory coin_delta = new uint[](num_system_coins);
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
    for (uint i = 0; i < num_system_coins; i++) {
      if (out_amounts[i] == 0) continue;
      IERC20 token = IERC20(system_coins[i]);
      // solves a dual purpose of reverting if enough balance has not been accumulated
      token.safeTransfer(msg.sender, out_amounts[i]);
      dusd_amount = dusd_amount.add(coin_delta[i].mul(prices[i]));
    }

    // Burn DUSD
    require(dusd_amount <= max_dusd_amount, "They see you slippin");
    dusd.burn(msg.sender, dusd_amount);
  }
}
