pragma solidity 0.5.17;

interface aToken {
    function redeem(uint256 _amount) external;
    function transfer(address recipient, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external;
    function redirectInterestStream(address _to) external;
    function redirectInterestStreamOf(address _from, address _to) external;
    function allowInterestRedirectionTo(address _to) external;
}

interface LendingPool {
    function deposit(address _reserve, uint256 _amouny, uint16 _referralCode) external;
    function getReserveData(address _reserve) external;
}

interface LendingPoolAddressProvider {
    function getLendingPool() external;
    function getLendingPoolCore() external;
}

interface PriceOracleGetter {
    function getAssetPrice(address _asset) external view returns (uint256);
    function getAssetPrices(address[] calldata _assets) external view returns (uint256[] memory);
    function getFallbackOracle() external view returns (address);
}
