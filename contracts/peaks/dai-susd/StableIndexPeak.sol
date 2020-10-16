pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {IPeak} from "../../interfaces/IPeak.sol";
import {aToken} from "../../interfaces/IAave.sol";
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

    // Tracking user BPT
    mapping(address => uint256) private bptBalances;

    function initialize(
        IConfigurableRightsPool _crp
    ) public {
        // CRP
        crp = _crp;
    }

    // mint dusd based on aTokens
    function mint(uint[index] calldata inAmounts, uint minDusdAmount) 
        external 
        returns (uint dusdAmount) {
            address[index] memory _interestTokens = interestTokens;
            // aTokens Zap => Peak
            for(uint i = 0; i < index; i++) {
                aToken(_interestTokens).safeTransferFrom(msg.sender, address(this), inAmounts[i]);
            }
            dusdAmount = _mint(inAmounts, minDusdAmount);
    }

    function _mint(uint[index] memory inAmounts, uint minDusdAmout) 
        internal 
        returns (uint dusdAmount) {
        // NOTE: Implement portfolioValue() 
        uint _old = portfolioValue();
        joinBPool(inAmounts, 0); //  Double check
        uint _new = portfolioValue();
        dusdAmount = core.mint(_new.sub(_old), msg.sender);
        require(dusdAmount >= minDusdAmount, ERR_SLIPPAGE);
    }

    function redeem() external {

    }

    function joinBPool(uint[] calldata maxAmountsIn, uint poolAmountOut) internal {
        /** 
        1 - Take in aDAI and aSUSD input amounts
        2 - Migrate liquidity to CRP
            => crp.joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn)
        3 - Update and handle BPT Balances
            => Update mapping with safeMath
            => *Migrate BPT to address(controller)*
        */

        // Zap triggers this function
        // After Aave token conversion so input = aDAI/aSUSD
        crp.joinPool(maxAmountsIn, poolAmountOut); // 
    }

    function exitBPool(uint[] calldata minAmountsOut, uint poolAmountIn) internal {
        /**
        1 - Verify user BPT balance > poolAmountIn
        2 - Migrate liquidity from CRP
            => *withdraw BPT amount from controller* safeTransfer(address(controller), address(this), bpt)
            => crp.exitPool(uint poolAmountIn, uint[] calldata minAmountsOut)
        3 - Update BPT Balances
            => Update mapping with safeMath (before crp.exitPool())
        4 - Transfer aDAI/aSUSD + interest for DAI/sUSD conversion
        */
    }

    function migrateBPT() external {
        /** 
        Migrates BPT after joinPool() to the controller address
        */
    }

}
