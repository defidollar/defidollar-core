pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {ICore} from "../../interfaces/ICore.sol";
import {aToken} from "../../interfaces/IAave.sol";
import {IConfigurableRightsPool} from "../../interfaces/IConfigurableRightsPool.sol";

import {StableIndexPeak} from './StableIndexPeak.sol';

contract StableIndexZap {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    // stablecoins and aTokens
    uint constant public index = 2; // No. of stablecoins in peak
    string constant ERR_SLIPPAGE = "ERR_SLIPPAGE";

    address[index] public reserveTokens = [
        0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
        0x57Ab1ec28D129707052df4dF418D58a2D46d5f51  // sUSD
    ];

    address[index] public interestTokens = [
        0xfC1E690f61EFd961294b3e1Ce3313fBD8aa4f85d, // aDAI
        0x625aE63000f46200499120B906716420bd059240  // aSUSD
    ];

    // Core addresses
    ICore core = ICore(0xE449Ca7d10b041255E7e989D158Bee355d8f88d3);
    IERC20 dusd = IERC20(0x5BC25f649fc4e26069dDF4cF4010F9f706c23831);

    // Stable Index Peak
    StableIndexPeak stableIndexPeak;

    constructor(
        StableIndexPeak _stableIndexPeak
    ) public {
        stableIndexPeak = _stableIndexPeak;
    }

    function mint(uint[] calldata inAmounts, uint minDusdAmount) external returns (uint dusdAmount) {
        // reserve => Zap
        address[index] memory _reserveTokens = reserveTokens;
        for (uint i = 0; i < index; i++) {
            if (inAmounts[i] > 0) {
                IERC20(_reserveTokens[i]).safeTransferFrom(msg.sender, address(this), inAmounts[i]);
            }
        }
        // Migrate liquidity + Mint DUSD
        dusdAmount = stableIndexPeak.mint(inAmounts);
        require(dusdAmount >= minDusdAmount, ERR_SLIPPAGE);
        return dusdAmount;
    }

    function calcMint(uint[index] memory inAmounts) public view returns (uint dusdAmount) {
        uint[] memory prices = stableIndexPeak.getPrices();
        for (uint i = 0; i < prices.length; i++) {
            dusdAmount.add(inAmounts[i].div(1e18).mul(stableIndexPeak.weiToUSD(prices[i].div(1e18))));
        }
        return dusdAmount;
    }

    function redeem(uint dusdAmount, uint[] calldata minAmounts) external {
        // Tranfer DUSD
        dusd.safeTransferFrom(msg.sender, address(this), dusdAmount);
        // aTokens (BPool -> Peak -> Zap)
        stableIndexPeak.redeem(dusdAmount); 
        // aTokens -> reserve swaps
        address[index] memory _interestTokens = interestTokens;
        address[index] memory _reserveTokens = reserveTokens;
        for (uint i = 0; i < index; i++) {
            uint amount = IERC20(_interestTokens[i]).balanceOf(address(this));
            require(amount >= minAmounts[i], ERR_SLIPPAGE);
            // Redeem aToken and transfer
            aToken(_interestTokens[i]).redeem(amount);
            IERC20(_reserveTokens[i]).safeTransfer(msg.sender, amount);
        }
        // Burn DUSD
        core.redeem(dusdAmount, msg.sender);
    }

    // Single reserve token functions 
    function mintWithSingleCoin(uint inAmount, uint minDusdAmount, uint j) external returns (uint dusdAmount) {
        // Transfer token to zap (Dai or sUSD)
        address[index] memory _reserveTokens = reserveTokens;
        IERC20 token = IERC20(_reserveTokens[j]);
        token.safeTransferFrom(msg.sender, address(this), inAmount);
        // Curve swap & DUSD Transfer
        dusdAmount = stableIndexPeak.mintSingleSwap(token, inAmount);
        require(dusdAmount >= minDusdAmount, ERR_SLIPPAGE);
        dusd.safeTransfer(msg.sender, dusdAmount);
        return dusdAmount;
    }

    function redeemInSingleCoin(uint dusdAmount, uint minAmount, uint j) external returns (uint amount){
        // Transfer DUSD
        dusd.safeTransferFrom(msg.sender, address(this), dusdAmount);
        // aTokens (BPool -> Peak -> Zap)
        IERC20 token = IERC20(reserveTokens[j]);
        amount = stableIndexPeak.redeemSingleSwap(token, dusdAmount, minAmount);
        // Transfer reserve asset to user
        token.safeTransfer(msg.sender, amount);
        // Burn DUSD
        core.redeem(dusdAmount, msg.sender);
    }

    // CALC FUNCTIONS 
    

    function calcMintSingleCoin(uint inAmount, uint i) public view returns (uint dusdAmount) {
        address[index] memory _reserveTokens = reserveTokens;
        uint price = stableIndexPeak.getPrice(_reserveTokens[i]);
        return inAmount.mul(stableIndexPeak.weiToUSD(price.div(1e18)));
    }

    function calcRedeem(uint dusdAmount) public view returns (uint[index] memory amounts) {
        uint usd = core.dusdToUsd(dusdAmount, true); // redeem fee
        uint[] memory prices = stableIndexPeak.getPrices();
        for (uint i = 0; i < prices.length; i++) {
            amounts[i] = usd.div(stableIndexPeak.weiToUSD(prices[i].div(1e18)));
            // Incorrect think about this more
        }
        return amounts;
    }   

    function calcRedeemInSingleCoin(uint dusdAmount, uint i) public view returns (uint amount) {
        uint usd = core.dusdToUsd(dusdAmount, true);
        uint price = stableIndexPeak.getPrice(reserveTokens[i]);
        amount = usd.div(stableIndexPeak.weiToUSD(price.div(1e18)));
        return amount;
    }

}
