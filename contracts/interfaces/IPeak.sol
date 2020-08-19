pragma solidity 0.5.17;

contract IPeak {
    function updateFeed(uint[] calldata feed) external returns(uint portfolio);
    function portfolioValueWithFeed(uint[] memory feed) public view returns(uint);
}
