pragma solidity 0.5.17;

import {Proxy} from "./Proxy.sol";
import {Ownable} from "../Ownable.sol";

contract UpgradableProxy is Ownable, Proxy {
    bytes32 constant IMPLEMENTATION_SLOT = keccak256("proxy.implementation");

    event ProxyUpdated(address indexed previousImpl, address indexed newImpl);

    function() external payable {
        delegatedFwd(implementation(), msg.data);
    }

    function implementation() public view returns(address _impl) {
        bytes32 position = IMPLEMENTATION_SLOT;
        assembly {
            _impl := sload(position)
        }
    }

    function updateAndCall(address _newProxyTo, bytes memory data) public payable {
        // ACLed by the call to execute
        updateImplementation(_newProxyTo);
        execute(address(this), data);
    }

    function execute(address _target, bytes memory data) public payable onlyOwner {
        (bool success, bytes memory returnData) = _target.call.value(msg.value)(data);
        require(success, string(returnData));
    }

    function updateImplementation(address _newProxyTo) public onlyOwner {
        require(_newProxyTo != address(0x0), "INVALID_PROXY_ADDRESS");
        require(isContract(_newProxyTo), "DESTINATION_ADDRESS_IS_NOT_A_CONTRACT");
        emit ProxyUpdated(implementation(), _newProxyTo);
        setImplementation(_newProxyTo);
    }

    function setImplementation(address _newProxyTo) private {
        bytes32 position = IMPLEMENTATION_SLOT;
        assembly {
            sstore(position, _newProxyTo)
        }
    }

    function isContract(address _target) internal view returns (bool) {
        if (_target == address(0)) {
            return false;
        }
        uint256 size;
        assembly {
            size := extcodesize(_target)
        }
        return size > 0;
    }
}
