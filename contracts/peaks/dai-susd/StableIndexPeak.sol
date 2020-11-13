pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {IPeak} from "../../interfaces/IPeak.sol";
import {ICore} from "../../interfaces/ICore.sol";
import {IOracle} from "../../interfaces/IOracle.sol";
import {ICurve} from "../../interfaces/ICurve.sol";
import {aToken, LendingPoolAddressesProvider, LendingPool, PriceOracleGetter} from "../../interfaces/IAave.sol";
import {IConfigurableRightsPool, IBPool} from "../../interfaces/IConfigurableRightsPool.sol";

import {Initializable} from "../../common/Initializable.sol";
import {OwnableProxy} from "../../common/OwnableProxy.sol";

contract StableIndexPeak is OwnableProxy, Initializable, IPeak {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Math for uint;

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

    // Configurable Rights Pool
    IConfigurableRightsPool crp;
    IBPool bPool;

    // Curve susd pool
    ICurve curve;

    // Aave Oracle & Lending Pool
    LendingPoolAddressesProvider provider;
    PriceOracleGetter priceOracle;
    LendingPool lendingPool;
    uint16 refferal = 0;
    
    // Chainlink Oracle
    IOracle oracle;

    // Core contract
    ICore core;
    IERC20 dusd;

    function initialize(
        IConfigurableRightsPool _crp,
        IBPool _bPool
    ) public notInitialized {
        // CRP & BPool
        crp = _crp;
        bPool = _bPool;
        // Lending Pool
        provider = LendingPoolAddressesProvider(address(0x24a42fD28C976A61Df5D00D0599C34c4f90748c8)); // mainnet address, for other addresses: https://docs.aave.com/developers/developing-on-aave/deployed-contract-instances
        lendingPool = LendingPool(provider.getLendingPool());
        // Aave Price Oracle
        priceOracle = PriceOracleGetter(provider.getPriceOracle());
        oracle = IOracle(0x4EaC4c4e9050464067D673102F8E24b2FccEB350);
        // Core contracts
        core = ICore(0xE449Ca7d10b041255E7e989D158Bee355d8f88d3);
        dusd = IERC20(0x5BC25f649fc4e26069dDF4cF4010F9f706c23831);
        // Curve susd pool swap
        curve = ICurve(0xA5407eAE9Ba41422680e2e00537571bcC53efBfD);
    }

    function mint(uint[] calldata inAmounts) external returns (uint dusdAmount){
        // reserve (zap -> peak) => aTokens
        address[index] memory _reserveTokens = reserveTokens;
        for(uint i = 0; i < index; i++) {
            IERC20(_reserveTokens[i]).safeTransferFrom(msg.sender, address(this), inAmounts[i]);
            IERC20(_reserveTokens[i]).safeApprove(provider.getLendingPoolCore(), inAmounts[i]); 
            lendingPool.deposit(_reserveTokens[i], inAmounts[i], refferal);
        }
        // Mint DUSD
        uint256[] memory prices = getPrices();
        uint value;
        for(uint i = 0; i < index; i++) {
            value.add(inAmounts[i].div(1e18).mul(weiToUSD(prices[i].div(1e18))));
        }
        dusdAmount = core.mint(value, msg.sender);
        // Migrate liquidity to BPool via CRP
        migrateInBPool(inAmounts);
    }

    function redeem(uint dusdAmount) external {
        address[index] memory _interestTokens = interestTokens;
        uint[] memory balances;
        // DUSD value (How many BPT tokens to redeem)
        uint usd = core.dusdToUsd(dusdAmount, true);
        uint bpt = bptValue().div(usd);
        // aToken balances before
        for (uint i = 0; i < index; i++) {
            balances[i] = IERC20(_interestTokens[i]).balanceOf(address(this));
        }
        // Remove liquidity
        uint[] memory minAmountsOut;
        for (uint i = 0; i < index; i++) {
            minAmountsOut[i] = 0;
        }
        require(minAmountsOut.length <= 8, "Error: Balancer pool 8 tokens maximum.");
        crp.exitPool(bpt, minAmountsOut);
        // aTokens balances after (peak -> zap)
        for (uint i = 0; i < index; i++) {
            balances[i] = IERC20(_interestTokens[i]).balanceOf(address(this)).sub(balances[i]);
            aToken(_interestTokens[i]).transfer(msg.sender, balances[i]);
        }
    }

    function mintSingleSwap(IERC20 token, uint inAmount) external returns (uint dusdAmount) {
        // Transfer reserve (zap -> peak)
        token.safeTransferFrom(msg.sender, address(this), inAmount);
        // CRP Denorm Weights
        address[index] memory _interestTokens = interestTokens;
        uint daiDenorm = crp.getDenormalizedWeight(_interestTokens[0]); // 23.2
        uint susdDenorm = crp.getDenormalizedWeight(_interestTokens[1]); // 16.8
        uint totalDenorm = daiDenorm.add(susdDenorm);
        // Faciliate curve swap (Assume just Dai/sUSD in peak)
        address[index] memory _reserveTokens = reserveTokens;
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
            IERC20(_reserveTokens[i]).safeApprove(provider.getLendingPoolCore(), swapAmount);
            lendingPool.deposit(_reserveTokens[i], swapAmount, refferal);
        }
        // Mint DUSD
        uint256[] memory inAmounts = new uint256[](2);
        inAmounts[0] = IERC20(_interestTokens[0]).balanceOf(address(this));
        inAmounts[1] = IERC20(_interestTokens[1]).balanceOf(address(this));
        uint256[] memory prices = getPrices();
        uint value;
        for(uint i = 0; i < index; i++) {
            value.add(inAmounts[i].div(1e18).mul(weiToUSD(prices[i].div(1e18))));
        }
        dusdAmount = core.mint(value, msg.sender);
        // Migrate liquidity
        migrateInBPool(inAmounts);
    }

    function redeemSingleSwap(IERC20 token, uint dusdAmount, uint minAmount) external returns (uint) {
        // Migrate liquidity (bPool -> Peak)
        migrateOutBPool(dusdAmount);
        // Redeem aTokens
        address[index] memory _interestTokens = interestTokens;
        for (uint i = 0; i < index; i++) {
            uint redeemAmount = IERC20(_interestTokens[i]).balanceOf(address(this));
            aToken(_interestTokens[i]).redeem(redeemAmount);
        }
        // Curve swap
        address[index] memory _reserveTokens = reserveTokens;
        if (address(token) == _reserveTokens[0]) {
            uint amount = token.balanceOf(address(this));
            curve.exchange_underlying(int128(0), int128(3), amount, 0); 
            uint susd = IERC20(_reserveTokens[1]).balanceOf(address(this));
            require(susd >= minAmount, ERR_SLIPPAGE);
            IERC20(_reserveTokens[1]).safeTransfer(msg.sender, susd);
            return susd;
        }
        else if (address(token) == _reserveTokens[1]) {
            uint amount = token.balanceOf(address(this));
            curve.exchange_underlying(int128(3), int128(0), amount, 0); 
            uint dai = IERC20(_reserveTokens[0]).balanceOf(address(this));
            require(dai >= minAmount, ERR_SLIPPAGE);
            IERC20(_reserveTokens[0]).safeTransfer(msg.sender, dai);
            return dai;
        }
    }

    // Migrate Liquidity Functions
    function migrateInBPool(uint[] memory inAmounts) internal {
        address[index] memory _interestTokens = interestTokens;
        for (uint i = 0; i < index; i++) {
            IERC20(_interestTokens[i]).safeApprove(address(crp), inAmounts[i]);
        }
        // Calculate BPT's
        uint bpt = bptAmount(inAmounts);
        crp.joinPool(bpt, inAmounts);
    }

    function migrateOutBPool(uint dusdAmount) internal {
        uint usd = core.dusdToUsd(dusdAmount, true);
        // Calculate amount of BPT's
        uint bpt = usd.div(bptValue());
        // Remove liquidity (gas inefficient?)
        uint[] memory minAmountsOut;
        for (uint i = 0; i < index; i++) {
            minAmountsOut[i] = 0;
        }
        crp.exitPool(bpt, minAmountsOut);
    }

    // Balancer pool token Functions
    function bptAmount(uint[] memory inAmounts) internal view returns (uint bpt) {
        // Total BPool Liquidity
        address[index] memory _interestTokens = interestTokens;
        uint aDAI = IERC20(_interestTokens[0]).balanceOf(address(bPool));
        uint aSUSD = IERC20(_interestTokens[1]).balanceOf(address(bPool));
        uint totalLiquidity = aDAI.add(aSUSD); // wei
        // Input Liquidity
        uint inputLiquidity;
        for (uint i = 0; i < inAmounts.length; i++) {
            inputLiquidity.add(inAmounts[i]);
        }
        // Calculate BPT's
        uint totalBPT = IERC20(address(crp)).balanceOf(address(this));
        bpt = totalBPT.mul(inputLiquidity.div(totalLiquidity));
        return bpt;
    }

    function bptValue() internal view returns (uint bpt) {
        uint bptTotal = IERC20(address(crp)).balanceOf(address(this));
        uint poolValue = bPoolValue();
        return bptTotal.div(poolValue);
    }

    function redirectInterest(address _from, address _to) public onlyOwner {
        address[index] memory _interestTokens = interestTokens;
        for (uint i = 0; i < index; i++) {
            aToken(_interestTokens[i]).redirectInterestStreamOf(_from, _to);
        }
    }

    // Chainlink Functions

    // Returns average ETHUSD value from chainlink feeds
    function ethusd() public view returns (uint value) {
        uint[] memory feed = oracle.getPriceFeed();
        for (uint i = 0; i < feed.length; i++) {
            value.add(feed[i]);
        }
        return value.div(feed.length);
    }

    // Convert aToken wei value to usd
    function weiToUSD(uint price) public view returns (uint) {
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

    // Peak value functions
    function portfolioValue() external view returns (uint) {
        return peakValue().add(bPoolValue());
    }

    function peakValue() public view returns (uint interest) {
        address[index] memory _interestTokens = interestTokens;
        for (uint i = 0; i < index; i++) {
            interest.add(weiToUSD(IERC20(_interestTokens[i]).balanceOf(address(this)).div(1e18)));
        }
        return interest;
    }

    function bPoolValue() public view returns (uint value) {
        address[index] memory _interestTokens;
        for (uint i = 0; i < index; i++) {
            value.add(weiToUSD(IERC20(_interestTokens[i]).balanceOf(address(bPool)).div(1e18)));
        }
        return value;
    }

    function vars() public view returns (
        address _crp,
        address _bPool,
        address _priceOracle,
        address _oracle,
        address _core,
        address _dusd,
        address[index] memory _reserveTokens,
        address[index] memory _interestTokens
    ) {
        return(
            address(crp),
            address(bPool),
            address(priceOracle),
            address(oracle),
            address(core),
            address(dusd),
            reserveTokens,
            interestTokens
        );
    }

}
