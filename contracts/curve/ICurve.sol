pragma solidity ^0.5.12;

interface ICurveDeposit {
  function add_liquidity(uint[] calldata uamounts, uint min_mint_amount) external;
  function remove_liquidity_imbalance(uint[] calldata uamounts, uint max_burn_amount) external;
}

interface ICurve {
  function add_liquidity(uint[] calldata uamounts, uint min_mint_amount) external;
  function remove_liquidity_imbalance(uint[] calldata uamounts, uint max_burn_amount) external;
  function balances(uint i) external view returns(uint);
}
