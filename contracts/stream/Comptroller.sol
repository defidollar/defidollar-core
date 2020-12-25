pragma solidity 0.5.17;

import {Ownable} from "@openzeppelin/contracts/ownership/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {ICore} from "../interfaces/ICore.sol";

import {IComptroller} from "../interfaces/IComptroller.sol";

contract Comptroller is Ownable, IComptroller {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint constant MAX = 10000;

    address[] public beneficiaries;
    uint[] public allocations;

    IERC20 public dusd;
    ICore public core;

    // Mainnet
    // IERC20 public constant dusd = IERC20(0x5BC25f649fc4e26069dDF4cF4010F9f706c23831);
    // ICore public constant core = ICore(0xE449Ca7d10b041255E7e989D158Bee355d8f88d3);

    // Kovan
    // IERC20 public constant dusd = IERC20(0xbA125322A44Aa62b6B621257C6120d39bEA4d6de);
    // ICore public constant core = ICore(0x559DD8DE795F7091f4457C20A3cb54Af6D57528e);

    event Harvested(uint indexed revenue);

    /**
    * @notice Harvests all accrued income from core and transfers it to beneficiaries
    * @dev All beneficiaries should account for that fact that they can have dusd transferred to them at any time
    * @dev Any account call harvest
    */
    function harvest() external {
        // address(this) needs to be the authorizedController() in core
        core.harvest();

        // any extraneous dusd tokens in the contract will also be harvested
        uint revenue = dusd.balanceOf(address(this));
        emit Harvested(revenue);
        if (revenue > 0) {
            address[] memory _beneficiaries = beneficiaries;
            uint beneficiariesLength = _beneficiaries.length;
            for (uint i = 0; i < beneficiariesLength; i++) {
                dusd.safeTransfer(_beneficiaries[i], revenue.mul(allocations[i]).div(MAX));
            }
        }
    }

    /* ##### View ##### */

    function earned(address account)
        external
        view
        returns(uint)
    {
        uint revenue = dusd.balanceOf(address(this)).add(core.earned());
        if (revenue > 0) {
            address[] memory _beneficiaries = beneficiaries;
            uint beneficiariesLength = _beneficiaries.length;
            for (uint i = 0; i < beneficiariesLength; i++) {
                if (_beneficiaries[i] == account) {
                    return revenue.mul(allocations[i]).div(MAX);
                }
            }
        }
        return 0;
    }

    /* ##### Admin ##### */

    function modifyBeneficiaries(
        address[] calldata _beneficiaries,
        uint[] calldata _allocations
    )
        external
        onlyOwner
    {
        require(_beneficiaries.length == _allocations.length, "MALFORMED_INPUT");
        uint total = 0;
        for (uint i = 0; i < _allocations.length; i++) {
            require(_beneficiaries[i] != address(0x0), "ZERO_ADDRESS");
            total = total.add(_allocations[i]);
        }
        require(total == MAX, "INVALID_ALLOCATIONS");
        allocations = _allocations;
        beneficiaries = _beneficiaries;
    }
}

contract ComptrollerTest is Comptroller {
    function setParams(IERC20 _dusd, ICore _core) external {
        dusd = _dusd;
        core = _core;
    }
}
