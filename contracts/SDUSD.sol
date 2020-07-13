pragma solidity 0.5.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SDUSD is ERC20 {
  address public core;

  constructor(address _core) public {
    core = _core;
  }

  modifier onlyCore() {
    require(msg.sender == core, "Not authorized");
    _;
  }

  function mint(address account, uint amount) public onlyCore {
    _mint(account, amount);
  }

  function burn(address account, uint amount) public onlyCore {
    _burn(account, amount);
  }
}
