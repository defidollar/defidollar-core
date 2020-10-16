pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {aToken, LendingPool, LendingPoolAddressProvider} from "../../interfaces/IAave.sol";
import {ICurve} from "../../interfaces/ICurve.sol";

import {StableIndexPeak} from './StabelIndexPeak.sol';

contract StableIndexZap {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    // stablecoins and aTokens
    uint constant public index = 2; // No. of stablecoins in peak

    address[index] public reserveTokens = [
        0x6b175474e89094c44da98b954eedeac495271d0f, // DAI
        0x57Ab1ec28D129707052df4dF418D58a2D46d5f51  // sUSD
    ]

    address[index] public interestTokens = [
        0xfC1E690f61EFd961294b3e1Ce3313fBD8aa4f85d, // aDAI
        0x625aE63000f46200499120B906716420bd059240  // aSUSD
    ]

    ICurve curve;
    IERC20 dusd = IERC20(0x5BC25f649fc4e26069dDF4cF4010F9f706c23831);

    // Aave Lending Pools
    uint refferal = 0;
    LendingPoolAddressProvider provider;
    LendingPool lendingPool;

    // Stable Index Peak
    StableIndexPeak stableIndexPeak;

    constructor(
        StableIndexPeak _stableIndexPeak,
        ICurve _curve
    ) public {
        // Stable Index Peak
        stableIndexPeak = _stableIndexPeak;
        // Curve swap
        curve = _curve;
        // Lending Pool
        provider = LendingPoolAddressProvider(address(0x24a42fD28C976A61Df5D00D0599C34c4f90748c8));
        lendingPool = LendingPool(provider.getLendingPool());
    }

    function mint(uint[index] calldata inAmounts, uint minDusdAmount) external returns (uint dusdAmount) {
        /** 
        1 - Take in DAI and sUSD amounts 
            => safeTransfer(address(this), amount)
        2 - Deposit into correct lending pool
            => LendingPoolAddressesProvider + getLendingPool()
            => IERC20(DAI).approve(provider.getLendingPoolCore(), amount) x2
            => lendingPool.deposit(DAI, amount, referral) x2
        3 - Mint and transfer DUSD to msg.sender
            => core.mint()
            => dusd.safeTransfer()
        4 - Trigger peak contract joinPool() to LP BPool
            => approve() aDAI/aSUSD w/ CRP
            => crp.joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn)
        */

        // NOTE: aToken:stablecoin => 1:1 in value
        // NOTE: Ignore routing aTokens to BPool for now
        // NOTE: Keep track of peak portfolioValue()

        // 1 - Transfer DAI/sUSD to Zap
        // 2 - Deposit _reserve into Lending Pool
        address[index] memory _reserveTokens = reserveTokens;
        for (uint i = 0; i < index; i++) {
            if (inAmounts[i] > 0) {
                IERC20(_reserveTokens[i]).safeTransferFrom(msg.sender, address(this), inAmounts[i]);
                IERC20(_reserveTokens[i]).approve(provider.getLendingPoolCore(), inAmounts[i]); // safeApprove() depreciated OpenZeppelin
                lendingPool.deposit(_reserveTokens[i], inAmounts[i], referral);
            }
        }
        // 3 - Mint DUSD & transfer to owner based on deposit
        // 4 - Trigger aToken => BPool
        dusdAmount = stableIndexPeak.mint(inAmounts[i], minDusdAmount);
        dusd.safeTransfer(msg.sender, dusdAmount);
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
        4 - Transfer stablecoins to user
            => DAI.safeTransfer(address(this), msg.sender, dai_amount) x2
        5 - Burn dusd
        */

        // NOTE: Interest must be redirected from BPool + accounted for in redeem()
        
        // 1 - Transfer dusd to Zap
        dusd.safeTransferFrom(msg.sender, address(this), dusdAmount);

        // 2 - Begin Withdrawl process
        stableIndexPeak.redeem(); // This triggers removal of LP + interest

        // 3 - Convert aTokens to stablecoins
        address[index] memory _interestTokens = interestTokens;
        for (uint i = 0; i < index; i++) {
            aToken(_interestTokens[i]).redeem(minAmounts[i]); // Double check: Rewrite for interest
        }

        // 4 - Transfer stablecoins to user
        address[index] memory _reserveTokens = reserveTokens;
        for (uint i = 0; i < index; i++) {
            IERC20(_reserveTokens[i]).safeTransfer(msg.sender, minAmounts[i]); // Double check: Rewrite for interest
        }

        // 5 - Burn DUSD
        core.redeem(dusdAmount, msg.sender);
    }

    function reserveSwap() external {
        /** 
        Purpose: Allow single stablecoin minting of DUSD

        - Deposit either DAI or sUSD
        - Convert deposit into stablecoin ratio
        - Use that ratio to then convert to aTokens
        - LP thos aTokens
        */
    }

}
