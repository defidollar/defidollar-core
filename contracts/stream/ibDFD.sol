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

    // Mainnet
    // IERC20 public constant dfd = IERC20(0x20c36f062a31865bED8a5B1e512D9a1A20AA333A);

    // Kovan
    // IERC20 public constant dfd = IERC20(0x81e5EB7FEa117Ea692990dc49C3A8de46054f9ff);

    IDFDComptroller public comptroller;
    uint public redeemFactor;

    /**
    * @dev Since this is a proxy, the values set in the ERC20Detailed constructor are not actually set in the main contract.
    */
    constructor ()
        public
        ERC20Detailed("ibDFD Implementation", "ibDFD_i", 18) {}

    function deposit(uint _amount) external {
        comptroller.getReward();
        uint _pool = balance();

        // If no funds are staked, send the accrued reward to governance multisig
        uint totalSupply = totalSupply();
        if (totalSupply == 0) {
            dfd.safeTransfer(owner(), _pool);
            _pool = 0;
        }

        uint shares = 0;
        if (_pool == 0) {
            shares = _amount;
        } else {
            shares = _amount.mul(totalSupply).div(_pool);
        }
        dfd.safeTransferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, shares);
    }

    function withdraw(uint _shares) external {
        comptroller.getReward();
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

    /**
    * @dev This is also used for initializing the proxy
    */
    function setParams(
        IDFDComptroller _comptroller,
        uint _redeemFactor
    )
        external
        onlyOwner
    {
        require(
            address(_comptroller) != address(0),
            "_comptroller == 0"
        );
        require(
            _redeemFactor <= FEE_PRECISION,
            "Incorrect upper bound for fee"
        );
        comptroller = _comptroller;
        redeemFactor = _redeemFactor;
    }
}

contract ibDFDTest is ibDFD {
    function setDFD(address _dfd) external {
        dfd = IERC20(_dfd);
    }
}

