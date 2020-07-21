pragma solidity 0.5.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockSusdToken is ERC20 {
  function mint(address _to, uint256 _value) public {
    _mint(_to, _value);
  }

  function redeem(address _from, uint256 _value) public {
    _burn(_from, _value);
  }
}
