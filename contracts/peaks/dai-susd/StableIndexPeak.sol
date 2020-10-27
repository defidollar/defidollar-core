pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {IPeak} from "../../interfaces/IPeak.sol";
import {ICore} from "../../interfaces/ICore.sol";
import {IOracle} from "../../interfaces/IOracle.sol";
import {aToken, PriceOracleGetter} from "../../interfaces/IAave.sol";
import {IConfigurableRightsPool} from "../../interfaces/IConfigurableRightsPool.sol";
// PC Token for BPT Balances

import {Initializable} from "../../common/Initializable.sol";
import {OwnableProxy} from "../../common/OwnableProxy.sol";

contract StableIndexPeak is OwnableProxy, Initializable, IPeak {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Math for uint;

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

    // Configurable Rights Pool
    IConfigurableRightsPool crp;

    // Aave Oracle
    PriceOracleGetter priceOracle;
    IOracle public oracle;

    // Core contract
    ICore core; 
    IERC20 dusd; 

    // Tracking user BPT
    mapping(address => uint256) private bptBalances;

    // Track user deposits
    mapping(address => uint256) private deposits; // Solve interest problem

    function initialize(
        IConfigurableRightsPool _crp,
        PriceOracleGetter _priceOracle,
        IOracle _oracle
    ) public {
        // CRP
        crp = _crp;
        // Aave Price Oracle
        priceOracle = _priceOracle;
        oracle = _oracle;
        // Tokens
        core = ICore(0xE449Ca7d10b041255E7e989D158Bee355d8f88d3);
        dusd = IERC20(0x5BC25f649fc4e26069dDF4cF4010F9f706c23831);
    }

    // Returns ETHUSD value from chainlink feeds
    function ethusd() public returns (uint value) {
        uint[] memory feed = oracle.getPriceFeed();
        for (uint i = 0; i < feed.length; i++) {
            value.add(feed[i]);
        }
        return value.div(feed.length);
    }

    // Convert aToken wei value to usd
    function weiToUSD(uint price) public returns (uint value) {
        value = price.mul(ethusd());
        return value;
    }

    function mint(uint[index] calldata inAmounts, uint minDusdAmount) external returns (uint dusdAmount) {
        address[index] memory _interestTokens = interestTokens;
        for(uint i = 0; i < index; i++) {
            aToken(_interestTokens[i]).transferFrom(msg.sender, address(this), inAmounts[i]);
        }
        uint256[] memory prices = getPrices();
        uint daiValue = inAmounts[0].div(1e18).mul(weiToUSD(prices[0].div(1e18))); // convert USD
        uint susdValue = inAmounts[1].div(1e18).mul(weiToUSD(prices[1].div(1e18))); // convert USD
        uint value = daiValue.add(susdValue);
        joinBPool(inAmounts); // Migrate liquidity
        dusdAmount = core.mint(value, msg.sender);
        require(dusdAmount >= minDusdAmount, "Error: Insufficient DUSD");
        dusd.safeTransfer(msg.sender, dusdAmount);
        return dusdAmount;
    }

    // Return prices of reserve tokens 
    function getPrices() internal returns (uint256[] memory prices) {
        address[index] memory _reserveTokens = reserveTokens;
        for (uint i = 0; i < index; i++) {
            prices[i] = priceOracle.getAssetPrice(_reserveTokens[i]);
        }
        return prices;
    }

    // Return price of a single asset
    function getPrice(address token) external returns (uint price) {
        price = priceOracle.getAssetPrice(token); // wei value
        return price;
    }

    function redeem(uint dusdAmount) external {
        // Remove liquidity
        // exitBPool();
        // Get deposit amount + interest
        // ASSUME: No interest (for now)
        uint aDai = IERC20(interestTokens[0]).balanceOf(address(this));
        uint aSusd = IERC20(interestTokens[1]).balanceOf(address(this)); 
        aToken(reserveTokens[0]).transfer(msg.sender, aDai);
        aToken(reserveTokens[1]).transfer(msg.sender, aSusd);
    }

    function joinBPool(uint[index] memory inAmounts) internal {
        uint start = crp.balanceOf(address(this)); // bpt balance (not correct)
        address[index] memory _interestTokens = interestTokens;
        for (uint i = 0; i < index; i++) {
            aToken(_interestTokens[i]).approve(address(crp), inAmounts[i]);
        }
        crp.joinPool(0, inAmounts);
        uint end = crp.balanceOf(address(this));
        bptBalances[msg.sender] = end.sub(start);
        redirectInterest(address(crp), address(this));
    }

    function exitBPool(uint bptAmount) internal {
        uint bpt = bptBalances[msg.sender];
        if (bpt > 0 && bptAmount <= bpt) {
            uint start = crp.balanceOf(address(this));
            crp.exitPoll(bptAmount, [0,0]); 
            uint end = crp.balanceOf(address(this));
            bptBalances[msg.sender] = start.sub(end);
        }
    }

    // Assuming crp have provided peak with allowance
    function redirectInterest(address _from, address _to) internal onlyOwner {
        address[index] memory _interestTokens = interestTokens;
        for (uint i = 0; i < index; i++) {
            aToken(_interestTokens[i]).redirectInterestStreamOf(_from, _to);
        }
    }

    function portfolioValue() external returns (uint value) {
        // Total portfolio value of the peak

        // Case 1  - Redirected Interest
        uint aDaiInterest = IERC20(interestTokens[0]).balanceOf(address(this));
        uint aSusdInterest = IERC20(interestTokens[1]).balanceOf(address(this));
        uint aDaiDeposit = IERC20(interestTokens[0]).balanceOf(address(crp.bPool));
        uint aSusdDeposit = IERC20(interestTokens[1]).balanceOf(address(crp.bPool));
        uint sum = aDaiInterest.add(aSusdInterest)
            .add(aDaiDeposit)
            .add(aSusdDeposit);
        value = weiToUSD(sum);
        return value;
    }

}
