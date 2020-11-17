pragma solidity 0.5.17;

import {UpgradableProxy} from "../common/proxy/UpgradableProxy.sol";

contract ibDUSDProxy is UpgradableProxy {
    constructor() public UpgradableProxy() {}
}
