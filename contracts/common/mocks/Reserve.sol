pragma solidity 0.5.17;

import { ERC20Mintable } from "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import { ERC20Detailed } from "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";

contract Reserve is ERC20Detailed, ERC20Mintable {
    constructor (uint8 _decimals)
        public
        ERC20Detailed("Reserve", "UN", _decimals)
    {
    }

    function mint(address account, uint amount)
        public
        returns (bool)
    {
        _mint(account, amount);
        return true;
    }

    function burn(address account, uint amount)
        public
        returns (bool)
    {
        _burn(account, amount);
        return true;
    }
}
