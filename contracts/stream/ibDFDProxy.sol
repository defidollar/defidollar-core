pragma solidity 0.5.17;

import {UpgradableProxy} from "../common/proxy/UpgradableProxy.sol";

contract ibDFDProxy is UpgradableProxy {

    function name() public pure returns (string memory) {
        return "interest-bearing DFD";
    }

    function symbol() public pure returns (string memory) {
        return "ibDFD";
    }

    /* NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public pure returns (uint8) {
        return 18;
    }
}
