pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Detailed} from "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {Initializable} from "../common/Initializable.sol";
import {OwnableProxy} from "../common/OwnableProxy.sol";
import {IComptroller} from "../interfaces/IComptroller.sol";

contract ibDUSD is OwnableProxy, Initializable, ERC20, ERC20Detailed {
    using SafeERC20 for IERC20;

    uint constant FEE_PRECISION = 10000;

    IERC20 public dusd;
    IComptroller public controller;
    uint public redeemFactor;

    /**
    * @dev Since this is a proxy, the values set in the ERC20Detailed constructor are not actually set in the main contract.
    */
    constructor ()
        public
        ERC20Detailed("interest-bearing DUSD", "ibDUSD", 18) {}

    function deposit(uint _amount) external {
        controller.harvest();
        uint _pool = balance();
        dusd.safeTransferFrom(msg.sender, address(this), _amount);
        uint shares = 0;
        if (_pool == 0) {
            shares = _amount;
        } else {
            shares = _amount.mul(totalSupply()).div(_pool);
        }
        _mint(msg.sender, shares);
    }

    function withdraw(uint _shares) external {
        controller.harvest();
        uint r = balance()
            .mul(_shares)
            .mul(redeemFactor)
            .div(totalSupply().mul(FEE_PRECISION));
        _burn(msg.sender, _shares);
        dusd.safeTransfer(msg.sender, r);
    }

    /* ##### View ##### */

    function balance() public view returns (uint) {
        return dusd.balanceOf(address(this));
    }

    function getPricePerFullShare() public view returns (uint) {
        if (totalSupply() == 0) {
            return 1e18;
        }
        return balance()
            .add(controller.earned(address(this)))
            .mul(1e18)
            .div(totalSupply());
    }

    /* ##### Admin ##### */

    function setParams(
        IERC20 _dusd,
        IComptroller _controller,
        uint _redeemFactor
    )   external
        onlyOwner
    {
        require(
            address(_dusd) != address(0) && address(_controller) != address(0),
            "0 address during initialization"
        );
        require(
            _redeemFactor <= FEE_PRECISION,
            "Incorrect upper bound for fee"
        );
        dusd = _dusd;
        controller = _controller;
        redeemFactor = _redeemFactor;
    }
}
