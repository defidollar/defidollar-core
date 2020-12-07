pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Detailed} from "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {Initializable} from "../common/Initializable.sol";
import {OwnableProxy} from "../common/OwnableProxy.sol";
import {IDFDComptroller} from "../interfaces/IComptroller.sol";

contract ibDFD is OwnableProxy, Initializable, ERC20, ERC20Detailed {
    using SafeERC20 for IERC20;

    uint constant FEE_PRECISION = 10000;

    IERC20 public dfd;
    IDFDComptroller public comptroller;
    uint public redeemFactor;

    /**
    * @dev Since this is a proxy, the values set in the ERC20Detailed constructor are not actually set in the main contract.
    */
    constructor ()
        public
        ERC20Detailed("ibDFD Implementation", "ibDFD_i", 18) {}

    modifier getReward() {
        comptroller.getReward();
        _;
    }

    function deposit(uint _amount) external getReward {
        uint _pool = balance();
        dfd.safeTransferFrom(msg.sender, address(this), _amount);
        uint shares = 0;
        if (_pool == 0) {
            shares = _amount;
        } else {
            shares = _amount.mul(totalSupply()).div(_pool);
        }
        _mint(msg.sender, shares);
    }

    function withdraw(uint _shares) external getReward {
        uint r = balance()
            .mul(_shares)
            .mul(redeemFactor)
            .div(totalSupply().mul(FEE_PRECISION));
        _burn(msg.sender, _shares);
        dfd.safeTransfer(msg.sender, r);
    }

    /* ##### View ##### */

    function balance() public view returns (uint) {
        return dfd.balanceOf(address(this));
    }

    function getPricePerFullShare() public view returns (uint) {
        if (totalSupply() == 0) {
            return 1e18;
        }
        return balance().add(comptroller.availableReward()).mul(1e18).div(totalSupply());
    }

    /* ##### Admin ##### */

    function setParams(
        IERC20 _dfd,
        IDFDComptroller _comptroller,
        uint _redeemFactor
    )
        external
        onlyOwner
    {
        require(
            address(_dfd) != address(0) && address(_comptroller) != address(0),
            "0 address during initialization"
        );
        require(
            _redeemFactor <= FEE_PRECISION,
            "Incorrect upper bound for fee"
        );
        dfd = _dfd;
        comptroller = _comptroller;
        redeemFactor = _redeemFactor;
    }
}

