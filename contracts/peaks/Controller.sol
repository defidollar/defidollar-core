pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IVault} from "../interfaces/IVault.sol";
import {OwnableProxy} from "../common/OwnableProxy.sol";

contract Controller is OwnableProxy {
    using SafeERC20 for IERC20;
    using Math for uint;

    mapping(address => bool) public peaks;
    mapping (address => IVault) public vaults;

    // Reserved storage space to allow for layout changes in the future.
    uint256[20] private _gap;

    modifier onlyPeak() {
        require(peaks[msg.sender], "!peak");
        _;
    }

    function earn(IERC20 token) public {
        IVault vault = vaults[address(token)];
        uint b = token.balanceOf(address(this));
        if (b > 0) {
            token.safeApprove(address(vault), 0);
            token.safeApprove(address(vault), b);
            vault.deposit(b);
        }
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
        if (vault.totalSupply() == 0) {
            return 1e18;
        }
        return vault.getPricePerFullShare();
    }

    function addPeak(address peak) external onlyOwner {
        require(Address.isContract(peak), "peak is !contract");
        peaks[peak] = true;
    }

    function addVault(address token, address vault) external onlyOwner {
        require(Address.isContract(token), "token is !contract");
        require(Address.isContract(vault), "vault is !contract");
        vaults[token] = IVault(vault);
    }
}
