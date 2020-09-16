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

    uint constant N_COINS = 4;
    string constant ERR_SLIPPAGE = "ERR_SLIPPAGE";
    string constant ERR_INSUFFICIENT_FUNDS = "INSUFFICIENT_FUNDS";
    uint constant MAX = 10000;

    // these are unused for now
    address[N_COINS] underlyingCoins;
    uint[N_COINS] feed;

    ICore core;
    ICurve ySwap;
    IERC20 yCrv;
    IERC20 yUSD;

    IController controller;
    uint min;

    function initialize(IController _controller)
        public
        notInitialized
    {
        controller = _controller;
        core = ICore(0xE449Ca7d10b041255E7e989D158Bee355d8f88d3);
        ySwap = ICurve(0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51);
        yCrv = IERC20(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8);
        yUSD = IERC20(0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c);
        min = 500;
    }

    function mintWithYcrv(uint inAmount) external returns(uint dusdAmount) {
        yCrv.safeTransferFrom(msg.sender, address(this), inAmount);
        dusdAmount = calcMintWithYcrv(inAmount);
        core.mint(dusdAmount, msg.sender);

        // best effort at keeping min.div(MAX) funds here
        uint farm = toFarm();
        if (farm > 0) {
            yCrv.safeTransfer(address(controller), farm);
            controller.earn(address(yCrv)); // this is acting like a callback
        }
    }

    // Sets minimum required on-hand to keep small withdrawals cheap
    function toFarm() public view returns (uint) {
        (uint here, uint there) = yCrvDistribution();
        uint shouldBeHere = here.add(there).mul(min).div(MAX);
        if (here > shouldBeHere) {
            return here.sub(shouldBeHere);
        }
        return 0;
    }

    function yCrvDistribution() public view returns (uint here, uint there) {
        here = yCrv.balanceOf(address(this));
        there = yUSD.balanceOf(address(controller))
            .mul(controller.getPricePerFullShare(address(yCrv)))
            .div(1e18);
    }

    function calcMintWithYcrv(uint inAmount) public view returns (uint dusdAmount) {
        return inAmount.mul(yCrvToUsd()).div(1e18);
    }

    function redeemInYcrv(uint dusdAmount, uint minOut) external returns(uint r) {
        r = dusdAmount.mul(1e18).div(yCrvToUsd());
        uint b = yCrv.balanceOf(address(this));
        if (b < r) {
            // withdraw only as much as needed from vault
            uint _withdraw = r.sub(b).mul(1e18).div(controller.getPricePerFullShare(address(yCrv)));
            controller.vaultWithdraw(yCrv, _withdraw);
            r = yCrv.balanceOf(address(this));
        }
        require(r >= minOut, ERR_INSUFFICIENT_FUNDS);
        core.redeem(dusdAmount, msg.sender);
        yCrv.safeTransfer(msg.sender, r);
    }

    function calcRedeemInYcrv(uint dusdAmount) public view returns (uint) {
        uint r = dusdAmount.mul(1e18).div(yCrvToUsd());
        (uint here, uint there) = yCrvDistribution();
        return r.min(here.add(there));
    }

    // yUSD

    function mintWithYusd(uint inAmount) external {
        yUSD.safeTransferFrom(msg.sender, address(controller), inAmount);
        core.mint(calcMintWithYusd(inAmount), msg.sender);
    }

    function calcMintWithYusd(uint inAmount) public view returns (uint dusdAmount) {
        return inAmount.mul(yUSDToUsd()).div(1e18);
    }

    function redeemInYusd(uint dusdAmount, uint minOut) external {
        core.redeem(dusdAmount, msg.sender);
        uint r = dusdAmount.mul(1e18).div(yUSDToUsd());
        // there should be no reason that this contracts has yUSD, however being safe doesn't hurt
        uint b = yUSD.balanceOf(address(this));
        if (b < r) {
            controller.withdraw(yUSD, r.sub(b));
            r = yUSD.balanceOf(address(this));
        }
        require(r >= minOut, ERR_INSUFFICIENT_FUNDS);
        yUSD.safeTransfer(msg.sender, r);
    }

    function calcRedeemInYusd(uint dusdAmount) public view returns (uint) {
        uint r = dusdAmount.mul(1e18).div(yUSDToUsd());
        return r.min(
            yUSD.balanceOf(address(this))
            .add(yUSD.balanceOf(address(controller))));
    }

    function yUSDToUsd() public view returns (uint) {
        return controller.getPricePerFullShare(address(yCrv)) // # yCrv
            .mul(yCrvToUsd()) // USD price
            .div(1e18);
    }

    function yCrvToUsd() public view returns (uint) {
        return ySwap.get_virtual_price();
    }

    function portfolioValue() external view returns(uint) {
        (uint here, uint there) = yCrvDistribution();
        return here.add(there).mul(yCrvToUsd());
    }

    function vars() public view returns(
        address _core,
        address _ySwap,
        address _yCrv,
        address _yUSD,
        address _controller,
        uint _min
    ) {
        return(
            address(core),
            address(ySwap),
            address(yCrv),
            address(yUSD),
            address(controller),
            min
        );
    }

    function setMin(uint _min) external onlyOwner {
        min = _min;
    }
}
