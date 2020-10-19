pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {IPeak} from "../../interfaces/IPeak.sol";
import {aToken, PriceOracleGetter} from "../../interfaces/IAave.sol";
import {IConfigurableRightsPool} from "../../interfaces/IConfigurableRightsPool.sol";

import {Initializable} from "../../common/Initializable.sol";
import {OwnableProxy} from "../../common/OwnableProxy.sol";

contract StableIndexPeak is OwnableProxy, Initializable, IPeak {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Math for uint;

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

    // Configurable Rights Pool
    IConfigurableRightsPool crp;

    // Aave Oracle
    PriceOracleGetter priceOracle;

    // Tracking user BPT
    mapping(address => uint256) private bptBalances;

    function initialize(
        IConfigurableRightsPool _crp,
        PriceOracleGetter _priceOracle
    ) public {
        // CRP
        crp = _crp;
        // Aave Price Oracle
        priceOracle = _priceOracle;
    }

    // mint dusd based on aTokens
    function mint(uint[index] calldata inAmounts, uint minDusdAmount) 
        external 
        returns (uint dusdAmount) {
            // aTokens Zap => Peak
            address[index] memory _interestTokens = interestTokens;
            for(uint i = 0; i < index; i++) {
                aToken(_interestTokens).safeTransferFrom(msg.sender, address(this), inAmounts[i]);
            }
            // Mint DUSD
            uint256[index] memory prices = getPrices(); // Prices in wei?
            uint value = 0;
            uint daiValue = inAmounts[0].div(1e18).mul(prices[0].div(1e18));
            uint susdValue = inAmounts[1].div(1e18).mil(prices[1].div(1e18));
            value.add(daiVaule).add(susdValue);
            // Mint DUSD + transfer to user
            dusdAmount = core.mint(value, msg.sender);
            dusd.safeTransfer(dusdAmount, msg.sender);
            // Migrate liquidity
            joinBPool(inAmounts);
    }

    // Return prices of reserve tokens (1:1)
    function getPrices() internal returns (uint256[] memory prices) {
        address[index] memory _reserveTokens = reserveTokens;
        prices = priceOracle.getAssetPrices(_reserveTokens); // prices in wei
        return prices;
    }

    function redeem(uint dusdAmount) external {
        // Remove liquidity
        exitBPool();
        // Get deposit amount + interest
        // ASSUME: No interest (for now)
        uint aDai = aToken(interestTokens[0]).balanceOf(address(this));
        uint aSusd = aToken(interestTokens[1]).balanceOf(address(this));
        aToken(reserveTokens[0]).safeTransfer(msg.sender, aDai);
        aToken(reserveTokens[1]).safeTransfer(msg.sender, aSusd);
    }

    function joinBPool(uint[index] calldata inAmounts) internal {
        uint before = crp.balanceOf(address(this));
        // Approvals for aToken => crp
        crp.joinPool(0, inAmounts); // joinPool(poolAmountOut (BPT), maxAmountsIn)
        uint after = crp.balanceOf(address(this));
        bptBalance[msg.sender] = after.sub(before);
    }

    function exitBPool() internal {
        uint bpt = bptBalances[msg.sender];
        if (bpt > 0) {
            uint before = crp.balanceOf(address(this));
            crp.exitPoll(); // exitPool()
            uint after = crp.balanceOf(address(this));
            bptBalance[msg.sender] = before.sub(after);
        }
    }

    function redirectInterest() internal {
        address[index] memory _interestTokens = interestTokens;
        for (uint i = 0; i < index; i++) {
            aToken(_interestTokens[i]).allowInterestRedirectionTo(address(this));
            aToken(_interestTokens[i]).redirectInterestStreamOf(address(crp), address(this));
        }
    }

    function migrateBPT() external {
        /** 
        Migrates BPT after joinPool() to the controller address
        */
    }

}
