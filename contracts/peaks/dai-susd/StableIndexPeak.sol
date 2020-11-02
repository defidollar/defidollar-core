pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {IPeak} from "../../interfaces/IPeak.sol";
import {ICore} from "../../interfaces/ICore.sol";
import {IOracle} from "../../interfaces/IOracle.sol";
import {aToken, PriceOracleGetter} from "../../interfaces/IAave.sol";
import {IConfigurableRightsPool, IBPool} from "../../interfaces/IConfigurableRightsPool.sol";
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
    IBPool bPool;

    // Aave Oracle
    PriceOracleGetter priceOracle;
    IOracle public oracle;

    // Core contract
    ICore core; 
    IERC20 dusd; 

    function initialize(
        IConfigurableRightsPool _crp,
        IBPool _bPool,
        PriceOracleGetter _priceOracle,
        IOracle _oracle
    ) public notInitialized {
        // CRP & BPool
        crp = _crp;
        bPool = _bPool;
        // Aave Price Oracle
        priceOracle = _priceOracle;
        oracle = _oracle;
        // Tokens
        core = ICore(0xE449Ca7d10b041255E7e989D158Bee355d8f88d3);
        dusd = IERC20(0x5BC25f649fc4e26069dDF4cF4010F9f706c23831);
    }

    // Returns average ETHUSD value from chainlink feeds
    function ethusd() internal returns (uint value) {
        uint[] memory feed = oracle.getPriceFeed();
        for (uint i = 0; i < feed.length; i++) {
            value.add(feed[i]);
        }
        return value.div(feed.length);
    }

    // Convert aToken wei value to usd
    function weiToUSD(uint price) public returns (uint value) {
        return price.mul(ethusd());
    }

    // Return prices of reserve tokens (wei)
    function getPrices() public view returns (uint256[] memory prices) {
        address[index] memory _reserveTokens = reserveTokens;
        for (uint i = 0; i < index; i++) {
            prices[i] = priceOracle.getAssetPrice(_reserveTokens[i]);
        }
        return prices;
    }

    // Return price of a reserve asset (wei)
    function getPrice(address token) public view returns (uint price) {
        return priceOracle.getAssetPrice(token);
    }

    function mint(uint[] calldata inAmounts) external {
        // aTokens (zap -> peak)
        address[index] memory _interestTokens = interestTokens;
        for(uint i = 0; i < index; i++) {
            aToken(_interestTokens[i]).transferFrom(msg.sender, address(this), inAmounts[i]);
            IERC20(_interestTokens[i]).safeApprove(address(crp), inAmounts[i]);
        }
        // Migrate liquidity to BPool via CRP
        crp.joinPool(0, inAmounts); // Check BPT
    }

    function redeem(uint dusdAmount) external {
        address[index] memory _interestTokens = interestTokens;
        uint[] memory balances;
        // DUSD value (How many BPT tokens to redeem)
        // uint usd = core.dusdToUsd(dusdAmount, true);
        // aToken balances before
        for (uint i = 0; i < index; i++) {
            balances[i] = IERC20(_interestTokens[i]).balanceOf(address(this));
        }
        // Remove liquidity
        // crp.exitPool();
        // aTokens balances after (peak -> zap)
        for (uint i = 0; i < index; i++) {
            balances[i] = IERC20(_interestTokens[i]).balanceOf(address(this)).sub(balances[i]);
            aToken(_interestTokens[i]).transfer(msg.sender, balances[i]);
        }
    }

    // Assuming crp have provided peak with allowance (NOT NEEDED)
    function redirectInterest(address _from, address _to) internal onlyOwner {
        address[index] memory _interestTokens = interestTokens;
        for (uint i = 0; i < index; i++) {
            aToken(_interestTokens[i]).redirectInterestStreamOf(_from, _to);
        }
    }

    // USD valuation of stable index peak (aTokens interest + bPool deposits)
    function portfolioValue() external view returns (uint) {
        return peakValue.add(bPoolValue);
    }

    // Internal Functions
    function peakValue() internal returns (uint interest) {
        address[index] memory _interestTokens = interestTokens;
        for (uint i = 0; i < index; i++) {
            interest.add(weiToUSD(IERC20(_interestTokens[i]).balanceOf(address(this)).div(1e18)));
        }
        return interest;
    }

    function bPoolValue() internal returns (uint value) {
        address[index] memory _interestTokens;
        for (uint i = 0; i < index; i++) {
            value.add(weiToUSD(IERC20(_interestTokens[i]).balanceOf(address(bPool)).div(1e18)));
        }
        return value;
    }

}
