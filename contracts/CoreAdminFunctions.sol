pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DUSD} from "./DUSD.sol";
import {Core} from "./Core.sol";

contract CoreAdminFunctions is Core {


  // function addSupportedPool(
  //   address curve_deposit,
  //   address curve,
  //   address curve_token,
  //   uint[] calldata system_coin_ids
  // ) external
  //   onlyOwner
  // {
  //   emit CurvePoolWhitelisted(pools.length);
  //   pools.push(CurvePool(
  //     ICurveDeposit(curve_deposit),
  //     ICurve(curve),
  //     IERC20(curve_token),
  //     system_coin_ids
  //   ));
  // }

  // function mintFromIncome(uint dusd_amount, address destination)
  //   external
  //   onlyOwner
  // {
  //   CurvePool[] memory _pools = pools;
  //   SystemCoin[] memory _system_coins = system_coins;
  //   uint[] memory coin_delta = new uint[](_system_coins.length);

  //   {
  //     uint lp_amount;
  //     uint lp_supply;
  //     CurvePool memory pool;
  //     for (uint i = 0; i < _pools.length; i++) {
  //       pool = _pools[i];
  //       lp_amount = pool.curve_token.balanceOf(address(this));
  //       if (lp_amount == 0) continue;
  //       lp_supply = pool.curve_token.totalSupply();
  //       uint[] memory pool_sizes = _getPoolBalances(pool);
  //       for (uint j = 0; j < pool.system_coin_ids.length; j++) {
  //         uint delta = pool_sizes[j].mul(lp_amount).div(lp_supply);
  //         coin_delta[pool.system_coin_ids[j]] = coin_delta[pool.system_coin_ids[j]].add(delta);
  //       }
  //     }
  //   }

  //   uint net_worth;
  //   for (uint i = 0; i < _system_coins.length; i++) {
  //     if (coin_delta[i] == 0) continue;
  //     SystemCoin memory coin = _system_coins[i];
  //     net_worth = net_worth.add(coin_delta[i].mul(coin.price).div(coin.precision));
  //   }
  //   dusd.mint(destination, dusd_amount);
  //   require(
  //     net_worth >= dusd.totalSupply().mul(collateralization_ratio).div(100),
  //     "System will become under collateralized"
  //   );
  //   emit Mint(destination, dusd_amount);
  // }

  // function execute(address target, bytes calldata data) external onlyOwner {
  //   (bool success, /* bytes memory returnData */) = target.call(data);
  //   require(success, "execution failed");
  // }
}
