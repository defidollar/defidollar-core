pragma solidity 0.5.17;

contract IPeak {
    function updateFeed(uint[] calldata feed, bool calcPortfolio) external returns(uint portfolio);
    function portfolioValue() public view returns(uint);
    function portfolioValueWithFeed(uint[] memory feed) public view returns(uint);
}
