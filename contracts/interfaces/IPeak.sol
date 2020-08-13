pragma solidity 0.5.17;

contract IPeak {
    function updateFeed(uint[] calldata _prices) external;
    function portfolioValue() public view returns(uint);
}
