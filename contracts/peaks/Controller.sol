pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IVault} from "../interfaces/IVault.sol";
import {OwnableProxy} from "../common/OwnableProxy.sol";

contract Controller is OwnableProxy {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Math for uint;

    // whether a peak is whitelisted
    mapping(address => bool) public peaks;

    // token => vault that accepts the said token
    mapping (address => IVault) public vaults;

    // Reserved storage space to allow for layout changes in the future.
    uint256[20] private _gap;

    event PeakAdded(address indexed peak);
    event VaultAdded(address indexed token, address indexed vault);

    modifier onlyPeak() {
        require(peaks[msg.sender], "!peak");
        _;
    }

    /**
    * @dev Send monies to vault to start earning on it
    */
    function earn(IERC20 token) public {
        IVault vault = vaults[address(token)];
        uint b = token.balanceOf(address(this));
        if (b > 0) {
            token.approve(address(vault), b);
            vault.deposit(b);
        }
    }

    /**
    * @dev Withdraw from vault
    * @param _shares Shares to withdraw
    */
    function vaultWithdraw(IERC20 token, uint _shares) public onlyPeak {
        IVault vault = vaults[address(token)];
        // withdraw as much as humanly possible
        _shares = _shares.min(vault.balanceOf(address(this)));
        uint here = token.balanceOf(address(this));
        vault.withdraw(_shares);
        token.safeTransfer(msg.sender, token.balanceOf(address(this)).sub(here));
    }

    /**
    * @dev Peak may request withdrawl of any token.
    * This may also be used to withdraw all liquidity when deprecating the controller
    */
    function withdraw(IERC20 token, uint amount) public onlyPeak {
        amount = amount.min(token.balanceOf(address(this)));
        token.safeTransfer(msg.sender, amount);
    }

    function getPricePerFullShare(address token) public view returns(uint) {
        IVault vault = vaults[token];
        if (vault.totalSupply() == 0) {
            return 1e18;
        }
        // reverts on totalSupply == 0
        return vault.getPricePerFullShare();
    }

    // Privileged methods

    function addPeak(address peak) external onlyOwner {
        require(!peaks[peak], "Peak is already added");
        require(Address.isContract(peak), "peak is !contract");
        peaks[peak] = true;
        emit PeakAdded(peak);
    }

    function addVault(address token, address vault) external onlyOwner {
        require(address(vaults[token]) == address(0x0), "vault is already added for token");
        require(Address.isContract(token), "token is !contract");
        require(Address.isContract(vault), "vault is !contract");
        vaults[token] = IVault(vault);
        emit VaultAdded(token, vault);
    }
}
