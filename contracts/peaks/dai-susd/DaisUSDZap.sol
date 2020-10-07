pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Aave interface (aTokens + LendingPool)
// Balancer interface (BPool)

contract DaisUSDZap {

    using SafeMath for uint;
    using SafeERC20 for IERC20;

    // 1 - option 1: Mint DUSD from DAI and sUSD deposits

    // 2 - Convert DAI/sUSD => aDAI/aSUSD

    // 3 - option 2: Mint DUSD from aDAI and aSUSD

    // 4 - Redeem DUSD for DAI and sUSD

    // 5 - Convert aDAI/aSUSD => DAI/sUSD

    // Note: DaisUSDPeak.sol will handle liquidity migration to and from pool
}