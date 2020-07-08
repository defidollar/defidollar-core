pragma solidity ^0.5.12;

import { ERC20Mintable } from "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import { ERC20Detailed } from "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";

contract Reserve is ERC20Detailed, ERC20Mintable {
  constructor (uint8 decimals)
    public
    ERC20Detailed("Reserve", "UN", decimals)
  {
  }

  function mint(address account, uint256 amount)
    public
    returns (bool)
  {
    _mint(account, amount);
    return true;
  }
}
