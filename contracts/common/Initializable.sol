pragma solidity 0.5.17;

contract Initializable {
    bool initialized = false;

    modifier notInitialized() {
        require(!initialized, "already initialized");
        initialized = true;
        _;
    }

    // Reserved storage space to allow for layout changes in the future.
    uint256[20] private _gap;

    function getStore(uint a) internal view returns(uint) {
        require(a < 20, "Not allowed");
        return _gap[a];
    }

    function setStore(uint a, uint val) internal {
        require(a < 20, "Not allowed");
        _gap[a] = val;
    }
}
