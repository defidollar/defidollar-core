pragma solidity 0.5.17;

import {UpgradableProxy} from "../common/proxy/UpgradableProxy.sol";

contract CoreProxy is UpgradableProxy {
    constructor() public UpgradableProxy() {}
}
