pragma solidity 0.5.17;

import {ERC20Detailed as IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";

import "../ICurve.sol";
import "./MockSusdToken.sol";

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
    return IERC20(underlying_coins[i]).balanceOf(address(this));
  }

  function add_liquidity(uint[] calldata uamounts, uint min_mint_amount) external {
    uint to_mint;
    for (uint i = 0; i < N_COINS; i++) {
      IERC20 _token = IERC20(underlying_coins[i]);
      _token.transferFrom(msg.sender, address(this), uamounts[i]);
      to_mint += uamounts[i] * (10 ** (uint(18) - _token.decimals()));
    }
    require(to_mint >= min_mint_amount, "Slippage");
    token.mint(msg.sender, to_mint);
  }

  function remove_liquidity_imbalance(uint[] calldata uamounts, uint max_burn_amount) external {
    for (uint i = 0; i < N_COINS; i++) {
      IERC20 _token = IERC20(underlying_coins[i]);
      _token.transfer(msg.sender, uamounts[i]);
    }
    token.redeem(msg.sender, max_burn_amount);
  }
}
