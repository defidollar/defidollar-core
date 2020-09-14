pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {IVault} from "../interfaces/IVault.sol";

contract Controller {
    using SafeERC20 for IERC20;
    using Math for uint;
    
    mapping(address => bool) public peaks;
    mapping (address => IVault) public vaults;
    
    modifier onlyPeak() {
        require(peaks[msg.sender], "!peak");
        _;
    }
    
    function earn(IERC20 token) public {
        vaults[address(token)].deposit(token.balanceOf(address(this)));
    }

    function vaultWithdraw(IERC20 token, uint _shares) public onlyPeak {
        IVault vault = vaults[address(token)];
        vault.withdraw(_shares);
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }

    function withdraw(IERC20 token, uint amount) public onlyPeak {
        amount = amount.min(token.balanceOf(address(this)));
        token.safeTransfer(msg.sender, amount);
    }

    function getPricePerFullShare(address token) public view returns(uint) {
        IVault vault = vaults[token];
        return vault.getPricePerFullShare();
    }
}