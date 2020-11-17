pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Detailed} from "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {Initializable} from "../common/Initializable.sol";
import {OwnableProxy} from "../common/OwnableProxy.sol";

contract ibDUSD is OwnableProxy, Initializable, ERC20, ERC20Detailed {
    using SafeERC20 for IERC20;

    uint constant FEE_PRECISION = 10000;

    IERC20 public dusd;
    ibController public controller;
    uint public redeemFactor;

    constructor ()
        public
        ERC20Detailed("interest-bearing DUSD", "ibDUSD", 18) {}

    modifier harvest() {
        controller.harvest();
        _;
    }

    function mint(uint _amount) external harvest {
        dusd.safeTransferFrom(msg.sender, address(this), _amount);
        uint _supply = totalSupply();
        uint shares;
        if (_supply == 0) {
            shares = _amount;
        } else {
            shares = _amount.mul(_supply).div(dusd.balanceOf(address(this)));
        }
        _mint(msg.sender, shares);
    }

    function withdraw(uint _shares) external harvest {
        _burn(msg.sender, _shares);
        uint r = dusd.balanceOf(address(this)).mul(_shares).div(totalSupply());
        dusd.safeTransfer(msg.sender, r);
    }

    function getPricePerFullShare() public view returns (uint) {
        return dusd.balanceOf(address(this)).add(controller.earned()).mul(1e18).div(totalSupply());
    }

    /* ### Admin Functions ### */

    function setParams(
        IERC20 _dusd,
        ibController _controller,
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

interface ibController {
    function harvest() external;
    function earned() external view returns(uint);
}


