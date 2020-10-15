pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {aToken} from "../../interfaces/IAave.sol";
import {LendingPool} from "../../interfaces/IAave.sol";
import {LendingPoolAddressProvider} from "../../interfaces/IAave.sol";
// Balancer interface (BPool)

contract StableIndexZap {

    using SafeMath for uint;
    using SafeERC20 for IERC20;

    // Tokens
    IERC20 DAI;
    IERC20 sUSD;
    aToken aDAI;
    aToken aSUSD;

    // Aave Lending Pools
    LendingPoolAddressProvider provider;
    LendingPool lendingPool;

    function initialize() public {
        // Lending Pool Address Provider
        provider = LendingPoolAddressProvider(address(0x24a42fD28C976A61Df5D00D0599C34c4f90748c8));
        lendingPool = LendingPool(provider.getLendingPool());
        // stablecoins
        DAI = IERC20(0x6b175474e89094c44da98b954eedeac495271d0f); // mainnet
        sUSD = IERC20(0x57Ab1ec28D129707052df4dF418D58a2D46d5f51); // mainnet
        // aTokens
        aDAI = aToken(0xfC1E690f61EFd961294b3e1Ce3313fBD8aa4f85d); // mainnet
        aSUSD = aToken(0x625aE63000f46200499120B906716420bd059240); // mainnet
    }

    function mint(uint[] calldata inAmounts, uint mintDusdAmount) external {
        /** 
        1 - Take in DAI and sUSD amounts 
            => safeTransfer(address(this), amount)
        2 - Deposit into correct lending pool
            => LendingPoolAddressesProvider + getLendingPool()
            => IERC20(DAI).approve(provider.getLendingPoolCore(), amount) x2
            => lendingPool.deposit(DAI, amount, referral) x2
        3 - Trigger peak contract joinPool() to LP BPool
            => approve() aDAI/aSUSD w/ CRP
            => crp.joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn)
        4 - Mint and transfer DUSD to msg.sender
            => core.mint()
            => dusd.safeTransfer()
        */

        // NOTE: aToken:stablecoin => 1:1 in value
    }

    function redeem(uint dusdAmount, uint[] calldata minAmounts) external {
        /** 
        1 - Transfer dusd to Zap
            => safeTransfer(msg.sender, address(this), dusdAmount)
        2 - Trigger peak contract to exit BPool
            => crp.exitPool(uint poolAmountIn, uint[] calldata minAmountsOut)
            => *peak => Aave or Zap => Aave*
            => How is interest from aTokens directed???
        3 - Convert aTokens_deposits + interest => stablecoins
            => aToken.redeem(uint256 _amount) (amount = deposit + interest)
        4 - Transfer stablecoiins to user
            => DAI.safeTransfer(address(this), msg.sender, dai_amount) x2
        5 - Burn dusd
        */

        // NOTE: Interest must be redirected from BPool + accounted for in redeem()
    }

}
