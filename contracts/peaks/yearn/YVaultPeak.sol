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

    string constant ERR_INSUFFICIENT_FUNDS = "INSUFFICIENT_FUNDS";
    uint constant MAX = 10000;

    uint min;
    uint redeemMultiplier;
    uint[4] feed; // unused for now but might need later

    ICore core;
    ICurve ySwap;
    IERC20 yCrv;
    IERC20 yUSD;

    IController controller;

    function initialize(IController _controller)
        public
        notInitialized
    {
        controller = _controller;
        // these need to be initialzed here, because the contract is used via a proxy
        core = ICore(0xE449Ca7d10b041255E7e989D158Bee355d8f88d3);
        ySwap = ICurve(0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51);
        yCrv = IERC20(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8);
        yUSD = IERC20(0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c);
        _setParams(
            200, // 200.div(10000) implies to keep 2% of yCRV in the contract
            9998 // 9998.div(10000) implies a redeem fee of .02%
        );
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
    function toFarm() internal view returns (uint) {
        (uint here, uint total) = yCrvDistribution();
        uint shouldBeHere = total.mul(min).div(MAX);
        if (here > shouldBeHere) {
            return here.sub(shouldBeHere);
        }
        return 0;
    }

    function yCrvDistribution() public view returns (uint here, uint total) {
        here = yCrv.balanceOf(address(this));
        total = yUSD.balanceOf(address(controller))
            .mul(controller.getPricePerFullShare(address(yCrv)))
            .div(1e18)
            .add(here);
    }

    function calcMintWithYcrv(uint inAmount) public view returns (uint dusdAmount) {
        return inAmount.mul(yCrvToUsd()).div(1e18);
    }

    function redeemInYcrv(uint dusdAmount, uint minOut) external returns(uint _yCrv) {
        core.redeem(dusdAmount, msg.sender);
        _yCrv = dusdAmount.mul(1e18).div(yCrvToUsd()).mul(redeemMultiplier).div(MAX);
        uint here = yCrv.balanceOf(address(this));
        if (here < _yCrv) {
            // withdraw only as much as needed from the vault
            uint _withdraw = _yCrv.sub(here).mul(1e18).div(controller.getPricePerFullShare(address(yCrv)));
            controller.vaultWithdraw(yCrv, _withdraw);
            _yCrv = yCrv.balanceOf(address(this));
        }
        require(_yCrv >= minOut, ERR_INSUFFICIENT_FUNDS);
        yCrv.safeTransfer(msg.sender, _yCrv);
    }

    function calcRedeemInYcrv(uint dusdAmount) public view returns (uint _yCrv) {
        _yCrv = dusdAmount.mul(1e18).div(yCrvToUsd()).mul(redeemMultiplier).div(MAX);
        (,uint total) = yCrvDistribution();
        return _yCrv.min(total);
    }

    function yCrvToUsd() public view returns (uint) {
        return ySwap.get_virtual_price();
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
        uint r = dusdAmount.mul(1e18).div(yUSDToUsd()).mul(redeemMultiplier).div(MAX);
        // there should be no reason that this contract has yUSD, however being safe doesn't hurt
        uint here = yUSD.balanceOf(address(this));
        if (here < r) {
            if (here.add(yUSD.balanceOf(address(controller))) < r) {
                // if it is still not enough, we make a best effort to deposit yCRV to yUSD
                yCrv.safeTransfer(address(controller), yCrv.balanceOf(address(this)));
                controller.earn(address(yCrv));
            }
            controller.withdraw(yUSD, r.sub(here));
            r = yUSD.balanceOf(address(this));
        }
        require(r >= minOut, ERR_INSUFFICIENT_FUNDS);
        yUSD.safeTransfer(msg.sender, r);
    }

    function calcRedeemInYusd(uint dusdAmount) public view returns (uint) {
        uint r = dusdAmount.mul(1e18).div(yUSDToUsd()).mul(redeemMultiplier).div(MAX);
        return r.min(
            yUSD.balanceOf(address(this))
            .add(yUSD.balanceOf(address(controller))));
    }

    function yUSDToUsd() public view returns (uint) {
        return controller.getPricePerFullShare(address(yCrv)) // # yCrv
            .mul(yCrvToUsd()) // USD price
            .div(1e18);
    }

    function portfolioValue() external view returns(uint) {
        (,uint total) = yCrvDistribution();
        return total.mul(yCrvToUsd()).div(1e18);
    }

    function vars() external view returns(
        address _core,
        address _ySwap,
        address _yCrv,
        address _yUSD,
        address _controller,
        uint _redeemMultiplier,
        uint _min
    ) {
        return(
            address(core),
            address(ySwap),
            address(yCrv),
            address(yUSD),
            address(controller),
            redeemMultiplier,
            min
        );
    }

    // Privileged methods

    function setParams(uint _min, uint _redeemMultiplier) external onlyOwner {
        _setParams(_min, _redeemMultiplier);
    }

    function _setParams(uint _min, uint _redeemMultiplier) internal {
        require(min <= MAX && redeemMultiplier <= MAX, "Invalid");
        min = _min;
        redeemMultiplier = _redeemMultiplier;
    }
}
