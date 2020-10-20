pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {ICore} from "../../interfaces/ICore.sol";
import {aToken, LendingPool, LendingPoolAddressProvider} from "../../interfaces/IAave.sol";
import {ICurve} from "../../interfaces/ICurve.sol";

import {StableIndexPeak} from './StableIndexPeak.sol';

contract StableIndexZap {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    // stablecoins and aTokens
    uint constant public index = 2; // No. of stablecoins in peak

    address[index] public reserveTokens = [
        0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
        0x57Ab1ec28D129707052df4dF418D58a2D46d5f51  // sUSD
    ];

    address[index] public interestTokens = [
        0xfC1E690f61EFd961294b3e1Ce3313fBD8aa4f85d, // aDAI
        0x625aE63000f46200499120B906716420bd059240  // aSUSD
    ];

    ICore core = ICore(0xE449Ca7d10b041255E7e989D158Bee355d8f88d3);
    IERC20 dusd = IERC20(0x5BC25f649fc4e26069dDF4cF4010F9f706c23831);

    ICurve curve;
    
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
        // Deposit => aToken conversion
        address[index] memory _reserveTokens = reserveTokens;
        for (uint i = 0; i < index; i++) {
            if (inAmounts[i] > 0) {
                IERC20(_reserveTokens[i]).safeTransferFrom(msg.sender, address(this), inAmounts[i]);
                IERC20(_reserveTokens[i]).approve(provider.getLendingPoolCore(), inAmounts[i]); // safeApprove() depreciated OpenZeppelin
                lendingPool.deposit(_reserveTokens[i], inAmounts[i], refferal);
            }
        }
        stableIndexPeak.mint(inAmounts, minDusdAmount);
    }

    function redeem(uint dusdAmount, uint[] calldata minAmounts) external {
        // 1 - Transfer dusd to Zap
        dusd.safeTransferFrom(msg.sender, address(this), dusdAmount);
        // 2 - Begin Withdrawl process
        stableIndexPeak.redeem(dusdAmount); // This triggers removal of LP + interest
        // 3 - Convert aTokens to stablecoins
        address[index] memory _interestTokens = interestTokens;
        uint aDai = aToken(interestTokens[0]).balanceOf(address(this));
        uint aSusd = aToken(interestTokens[1]).balanceOf(address(this));
        aToken(interestTokens[0]).redeem(aDai);
        aToken(interestTokens[1]).redeem(aSusd);
        // 4 - Transfer stablecoins to user
        IERC20(reserveTokens[0]).safeTransfer(msg.sender, aDai); // 1:1
        IERC20(reserveTokens[1]).safeTransfer(msg.sender, aSusd);
        // 5 - Burn DUSD
        core.redeem(dusdAmount, msg.sender);
    }


    // Single reserve token functions
    function mintWithSingleCoin(uint inAmount, uint minDusdAmount) external returns (uint dusdAmount) {
        /** 
        Is it DAI or is it sUSD
        Get ratio swap based on pool weights
        Make curve pool swap and record balances
        */
        uint daiBalance = IERC20(reserveTokens[0]).balanceOf(address(this));
        uint susdBalance = IERC20(reserveTokens[1]).balanceOf(address(this));
        // Make Aave swap
        IERC20(reserveTokens[0]).approve(provider.getLendingPoolCore(), daiBalance);
        IERC20(reserveTokens[1]).approve(provider.getLendingPoolCore(), susdBalance);
        lendingPool.deposit(reserveTokens[0], daiBalance, refferal);
        lendingPool.deposit(reserveTokens[1], susdBalance, refferal);
        // Mint DUSD
        address[] memory inAmounts = new address[](2);
        inAmounts[0] = IERC20(interestTokens[0]).balanceOf(address(this));
        inAmounts[1] = IERC20(interestTokens[1]).balanceOf(address(this));
        stableIndexPeak.mint(inAmounts, minDusdAmount);
    }

    function redeemInSingleCoin() external {

    }

    function calcMint() external {

    }

    function calcRedeem() external {

    }

    function calcMintSingleCoin() external {

    }

    
    function calcRedeemInSingleCoin() external {

    }

}
