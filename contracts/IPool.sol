pragma solidity 0.5.17;

contract IPool {
  function portfolio() public view returns(uint[] memory _portfolio);
}
