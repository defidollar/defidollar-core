pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {ICurve} from "../../interfaces/ICurve.sol";
import {ICore} from "../../interfaces/ICore.sol";
import {IPeak} from "../../interfaces/IPeak.sol";
import {IController} from "../../interfaces/IController.sol";

import {Initializable} from "../../common/Initializable.sol";
import {OwnableProxy} from "../../common/OwnableProxy.sol";

contract YVaultPeak is OwnableProxy, Initializable, IPeak {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Math for uint;

    string constant ERR_SLIPPAGE = "ERR_SLIPPAGE";
    string constant ERR_INSUFFICIENT_FUNDS = "INSUFFICIENT_FUNDS";

    ICore core;
    IController controller;
    ICurve yPool;
    IERC20 yUsd;
    IERC20 yyCrv;

    uint public min = 9500;
    uint public constant max = 10000;
    
    function initialize(
        ICore _core,
        IController _controller,
        ICurve _yPool,
        IERC20 _yUsd,
        IERC20 _yyCrv
    )
        public
        notInitialized
    {
        core = _core;
        controller = _controller;
        yPool = _yPool;
        yUsd = _yUsd;
        yyCrv = _yyCrv;
    }

    function mintWithYusd(uint inAmount) external returns(uint dusdAmount) {
        yUsd.safeTransferFrom(msg.sender, address(this), inAmount);
        dusdAmount = calcMintWithYusd(inAmount);
        core.mint(dusdAmount, msg.sender);  

        // best effort at keeping min.div(max) funds here
        (uint here, uint there) = yUsdDistribution();
        uint shouldBeHere = here.add(there).mul(min).div(max);
        if (here > shouldBeHere) {
            yUsd.safeTransfer(address(controller), here.sub(shouldBeHere));
            controller.earn(address(yUsd)); // this is just acting like a callback
        }
    }

    function calcMintWithYusd(uint inAmount) public view returns (uint dusdAmount) {
        return inAmount.mul(yPool.get_virtual_price()).div(1e18);
    }

    function yUsdDistribution() public view returns (uint here, uint there) {
        here = yUsd.balanceOf(address(this));
        there = yyCrv.balanceOf(address(controller))
            .mul(controller.getPricePerFullShare(address(yUsd)));
    }

    function redeemInYusd(uint dusdAmount, uint minOut) external returns(uint r) {
        r = dusdAmount.mul(1e18).div(yPool.get_virtual_price());
        uint b = yUsd.balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r.sub(b).mul(1e18).div(controller.getPricePerFullShare(address(yUsd)));
            controller.vaultWithdraw(yUsd, _withdraw);
            r = yUsd.balanceOf(address(this));
        }
        require(r >= minOut, ERR_INSUFFICIENT_FUNDS);
        core.redeem(dusdAmount, msg.sender);
        yUsd.safeTransfer(msg.sender, r);
    }

    function calcRedeemWithYusd(uint dusdAmount) public view returns (uint) {
        uint r = dusdAmount.mul(1e18).div(yPool.get_virtual_price());
        (uint here, uint there) = yUsdDistribution();
        return r.min(here.add(there));
    }

    // yyCRV

    function mintWithYycrv(uint inAmount) external {
        yyCrv.safeTransferFrom(msg.sender, address(controller), inAmount);
        core.mint(calcMintWithYycrv(inAmount), msg.sender);
    }

    function calcMintWithYycrv(uint inAmount) public view returns (uint dusdAmount) {
        return inAmount.mul(yyCrvToUsd()).div(1e18);
    }

    function redeemInYycrv(uint dusdAmount, uint minOut) external {
        core.redeem(dusdAmount, msg.sender);
        uint r = dusdAmount.mul(1e18).div(yyCrvToUsd());
        // there should be no reason that this contracts has yyCrv, however being safe doesn't hurt
        uint b = yyCrv.balanceOf(address(this));
        if (b < r) {
            controller.withdraw(yyCrv, r.sub(b));
            r = yyCrv.balanceOf(address(this));
        }
        require(r >= minOut, ERR_INSUFFICIENT_FUNDS);
        yyCrv.safeTransfer(msg.sender, r);
    }

    function calcRedeemWithYycrv(uint dusdAmount) public view returns (uint) {
        uint r = dusdAmount.mul(1e18).div(yyCrvToUsd());
        return r.min(
            yyCrv.balanceOf(address(this))
            .add(yyCrv.balanceOf(address(controller))));
    }

    function yyCrvToUsd() public view returns (uint) {
        return controller.getPricePerFullShare(address(yUsd)) // # yUsd
            .mul(yUsdToUsd()) // USD price
            .div(1e18);
    }

    function yUsdToUsd() public view returns (uint) {
        return yPool.get_virtual_price();
    }
    
    function portfolioValue() external view returns(uint) {
        (uint here, uint there) = yUsdDistribution();
        return here.add(there).mul(yUsdToUsd());
    }

    // function vars() public view returns(
    //     address _curveDeposit,
    //     address _curve,
    //     address _curveToken,
    //     address _util,
    //     address _gauge,
    //     address _mintr,
    //     address _core,
    //     address[N_COINS] memory _underlyingCoins,
    //     uint[N_COINS] memory _feed
    // ) {
    //     return(
    //         address(curveDeposit),
    //         address(curve),
    //         address(curveToken),
    //         address(util),
    //         address(gauge),
    //         address(mintr),
    //         address(core),
    //         underlyingCoins,
    //         feed
    //     );
    // }
}
