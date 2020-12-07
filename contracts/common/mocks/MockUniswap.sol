pragma solidity ^0.5.12;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/Uni.sol";
import "./Reserve.sol";

contract MockUniswap is Uni {
  /**
  * Receive an exact amount of output tokens for as few input tokens as possible, along the route determined by the path.
  * The first element of path is the input token, the last is the output token, and any intermediate elements represent intermediate pairs to trade through (if, for example, a direct pair does not exist).
  */
  function swapTokensForExactTokens(
    uint amountOut,
    uint, // amountInMax,
    address[] calldata path,
    address to,
    uint // deadline
  ) external returns (uint[] memory amounts)
  {
    uint amountIn = amountOut / 2; // dummy exchange rate
    amounts = new uint[](2);
    amounts[0] = amountIn;
    amounts[1] = amountOut;
    IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
    Reserve(path[1]).mint(to, amountOut);
  }

  /**
  * Swaps an exact amount of input tokens for as many output tokens as possible, along the route determined by the path.
  * The first element of path is the input token, the last is the output token, and any intermediate elements represent intermediate pairs to trade through (if, for example, a direct pair does not exist).
  */
  function swapExactTokensForTokens(
    uint amountIn,
    uint, // amountOutMin,
    address[] calldata path,
    address to,
    uint // deadline
  ) external returns (uint[] memory amounts)
  {
    uint amountOut = 2 * amountIn; // dummy exchange rate
    amounts = new uint[](2);
    amounts[0] = amountIn;
    amounts[1] = amountOut;
    IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
    Reserve(path[1]).mint(to, amountOut);
  }

  function getAmountsOut(uint amountIn, address[] memory /* path */) public pure returns (uint[] memory amounts) {
    amounts = new uint[](2);
    amounts[0] = amountIn;
    amounts[1] = 2 * amountIn; // dummy exchange rate
  }
}
