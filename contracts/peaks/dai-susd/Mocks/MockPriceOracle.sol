pragma solidity 0.5.17;

import { PriceOracleGetter } from "../../../interfaces/IAave.sol";

contract MockPriceOracle is PriceOracleGetter {

    /** 
    Mock contract of Aave price oracle for reserve assets.

    - Simulates Chainlink aggregator used by Aave
    - Returns price of reserve asset in wei units
    - DAI & sUSD = 0.0022.mul(1e18)
    */

    mapping(address => uint256) public reservePrices;

    function getAssetPrice(address _asset) public view returns (uint256) {
        return reservePrices[_asset];
    }

    function getAssetPrices(address[] memory _assets) public view returns (uint256[] memory) {
        uint256[] memory prices;
        for (uint i = 0; i < _assets.length; i++) {
            prices[i] = getAssetPrice(_assets[i]);
        }
        return prices;
    }

    function setAssetPrice(address _asset, uint256 _price) public {
        reservePrices[_asset] = _price;
    }

}
