pragma solidity ^0.5.12;

import "../../curve/ICurve.sol";
import "./MockSusdToken.sol";
import "../Reserve.sol";

contract MockCurveSusd is ICurve {
  uint constant N_COINS = 4;

  MockSusdToken token;
  address[] underlying_coins;

  constructor(
    MockSusdToken _token,
    address[] memory _underlying_coins
  ) public {
    token = _token;
    underlying_coins = _underlying_coins;
  }

  function balances(uint i) external view returns(uint) {
    return Reserve(underlying_coins[i]).balanceOf(address(this));
  }

  function add_liquidity(uint[] calldata uamounts, uint min_mint_amount) external {
    for (uint i = 0; i < N_COINS; i++) {
      Reserve _token = Reserve(underlying_coins[i]);
      _token.transferFrom(msg.sender, address(this), uamounts[i]);
    }
    token.mint(msg.sender, 10 ** 18);
  }

  function remove_liquidity_imbalance(uint[] calldata uamounts, uint max_burn_amount) external {
    for (uint i = 0; i < N_COINS; i++) {
      Reserve _token = Reserve(underlying_coins[i]);
      _token.transfer(msg.sender, uamounts[i]);
    }
    token.burn(msg.sender, max_burn_amount);
  }
}
