pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {ICore} from "../../interfaces/ICore.sol";
import {aToken} from "../../interfaces/IAave.sol";
import {ICurve} from "../../interfaces/ICurve.sol";
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

    ICore core = ICore(0xE449Ca7d10b041255E7e989D158Bee355d8f88d3);
    IERC20 dusd = IERC20(0x5BC25f649fc4e26069dDF4cF4010F9f706c23831);
    ICurve curve;
    IConfigurableRightsPool crp;

    // Stable Index Peak
    StableIndexPeak stableIndexPeak;

    constructor(
        StableIndexPeak _stableIndexPeak,
        IConfigurableRightsPool _crp,
        ICurve _curve
    ) public {
        // Stable Index Peak
        stableIndexPeak = _stableIndexPeak;
        // Configurable Rights Pool
        crp = _crp;
        // Curve susd pool swap
        curve = _curve;
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
        require(dusdAmount >= minDusdAmount, "Error: Insufficient DUSD");
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
        // Get weights of CRP
        address[index] memory _interestTokens = interestTokens;
        uint daiDenorm = crp.getDenormalizedWeight(_interestTokens[0]); // 23.2
        uint susdDenorm = crp.getDenormalizedWeight(_interestTokens[1]); // 16.8
        uint totalDenorm = daiDenorm.add(susdDenorm);
        // Faciliate curve swap (Assume just Dai/sUSD in peak)
        if (address(token) == _reserveTokens[0]) {
            uint daiRatio = daiDenorm.mul(100).div(totalDenorm);
            uint dai = inAmount.mul(daiRatio).div(100);
            token.safeApprove(address(curve), 0);
            token.safeApprove(address(curve), dai);
            curve.exchange_underlying(int128(0), int128(3), dai, 0);
        }
        else if (address(token) == _reserveTokens[1]) {
            uint susdRatio = susdDenorm.mul(100).div(totalDenorm);
            uint susd = inAmount.mul(susdRatio).div(100); 
            token.safeApprove(address(curve), 0);
            token.safeApprove(address(curve), susd);
            curve.exchange_underlying(int128(3), int128(0), susd, 0);
        }
        // Make Aave swap
        for (uint i = 0; i < index; i++) {
            uint swapAmount = IERC20(_reserveTokens[i]).balanceOf(address(this));
            // IERC20(_reserveTokens[i]).safeApprove(provider.getLendingPoolCore(), swapAmount);
            // lendingPool.deposit(_reserveTokens[i], swapAmount, refferal);
        }
        // mint DUSD
        uint256[] memory inAmounts = new uint256[](2);
        inAmounts[0] = IERC20(_interestTokens[0]).balanceOf(address(this));
        inAmounts[1] = IERC20(_interestTokens[1]).balanceOf(address(this));
        uint256[] memory prices = stableIndexPeak.getPrices();
        uint value;
        for(uint i = 0; i < index; i++) {
            value.add(inAmounts[i].div(1e18).mul(stableIndexPeak.weiToUSD(prices[i].div(1e18))));
        }
        dusdAmount = core.mint(value, msg.sender);
        require(dusdAmount >= minDusdAmount, "Error: Insufficient DUSD");
        // Migrate liquidity
        // stableIndexPeak.mint(inAmounts);
        // Transfer DUSD
        dusd.safeTransfer(msg.sender, dusdAmount);
        return dusdAmount;
    }

    function redeemInSingleCoin(uint dusdAmount, uint minAmount, uint j) external {
        // Transfer DUSD
        dusd.safeTransferFrom(msg.sender, address(this), dusdAmount);
        // aTokens (BPool -> Peak -> Zap)
        stableIndexPeak.redeem(dusdAmount);
        // Redeem aTokens
        address[index] memory _interestTokens = interestTokens;
        for (uint i = 0; i < index; i++) {
            uint swapAmount = IERC20(_interestTokens[i]).balanceOf(address(this));
            aToken(_interestTokens[i]).redeem(swapAmount);
        }
        // Faciliate curve swap
        address[index] memory _reserveTokens = reserveTokens;
        IERC20 token = IERC20(_reserveTokens[j]);
        if (address(token) == _reserveTokens[0]) {
            uint amount = token.balanceOf(address(this));
            curve.exchange_underlying(int128(0), int128(3), amount, 0); 
            uint susd = IERC20(_reserveTokens[1]).balanceOf(address(this));
            require(susd >= minAmount, ERR_SLIPPAGE);
            IERC20(_reserveTokens[1]).safeTransfer(msg.sender, susd);
        }
        else if (address(token) == _reserveTokens[1]) {
            uint amount = token.balanceOf(address(this));
            curve.exchange_underlying(int128(3), int128(0), amount, 0); 
            uint dai = IERC20(_reserveTokens[0]).balanceOf(address(this));
            require(dai >= minAmount, ERR_SLIPPAGE);
            IERC20(_reserveTokens[0]).safeTransfer(msg.sender, dai);
        }
        // Burn DUSD
        core.redeem(dusdAmount, msg.sender);
    }

    // CALC FUNCTIONS 
    function calcMint(uint[index] memory inAmounts) public view returns (uint dusdAmount) {
        uint[] memory prices = stableIndexPeak.getPrices();
        for (uint i = 0; i < prices.length; i++) {
            dusdAmount.add(inAmounts[i].mul(stableIndexPeak.weiToUSD(prices[i].div(1e18))));
        }
        return dusdAmount;
    }

    function calcMintSingleCoin(uint inAmount, uint i) public view returns (uint dusdAmount) {
        address[index] memory _reserveTokens = reserveTokens;
        uint price = stableIndexPeak.getPrice(_reserveTokens[i]);
        return inAmount.mul(stableIndexPeak.weiToUSD(price.div(1e18)));
    }

    // Redeem only aToken deposit (interest is deployed elsewhere)
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
