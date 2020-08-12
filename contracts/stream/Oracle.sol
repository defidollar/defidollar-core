pragma solidity 0.5.17;

import "@chainlink/contracts/src/v0.5/interfaces/AggregatorInterface.sol";
import {Ownable} from "@openzeppelin/contracts/ownership/Ownable.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

contract Oracle is Ownable {
    using SafeMath for uint;
    AggregatorInterface[] public refs;
    AggregatorInterface public ethUsdAggregator;

    /**
    * @dev Initialize oracle with chainlink aggregators
    * @param _aggregators <coin>-ETH Aggregator
    * @param _ethUsdAggregator ETH-USD Aggregator
    */
    constructor(
        AggregatorInterface[] memory _aggregators,
        AggregatorInterface _ethUsdAggregator
    ) public {
        refs.length = _aggregators.length;
        for(uint8 i = 0; i < _aggregators.length; i++) {
            refs[i] = _aggregators[i];
        }
        ethUsdAggregator = _ethUsdAggregator;
    }

    /**
    * @dev The latestAnswer value for all USD reference data contracts is multiplied by 100000000
    * before being written on-chain and by 1000000000000000000 for all ETH pairs.
    */
    function getPriceFeed() public view returns(uint[] memory feed) {
        int256 ethUsdRate = ethUsdAggregator.latestAnswer();
        feed = new uint[](refs.length);
        for(uint8 i = 0; i < refs.length; i++) {
            feed[i] = uint(refs[i].latestAnswer() * ethUsdRate).div(1e8);
        }
    }

    function addAggregator(AggregatorInterface _aggregator) external onlyOwner {
        refs.push(_aggregator);
    }
}
