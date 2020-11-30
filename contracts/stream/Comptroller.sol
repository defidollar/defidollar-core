pragma solidity 0.5.17;

import {Ownable} from "@openzeppelin/contracts/ownership/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {ICore} from "../interfaces/ICore.sol";

contract Comptroller is Ownable {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint constant MAX = 10000;

    struct Beneficiary {
        uint share;
        uint pendingWithdrawl;
    }
    mapping(address => Beneficiary) public account;
    address[] public beneficiaries;

    IERC20 public dusd;
    ICore public core;

    constructor(IERC20 _dusd, ICore _core) public {
        dusd = _dusd;
        core = _core;
    }

    function harvest() external {
        core.harvest();
        uint revenue = dusd.balanceOf(address(this));
        if (revenue == 0) {
            return;
        }
        for (uint i = 0; i < beneficiaries.length; i++) {
            Beneficiary storage beneficiary = account[beneficiaries[i]];
            beneficiary.pendingWithdrawl =
                beneficiary.pendingWithdrawl
                .add(
                    revenue.mul(beneficiary.share).div(MAX)
                );
        }
    }

    /**
    * @notice Beneficiaries can claim their respective accrued withdrawls after the last harvest.
    * @dev Doesn't require an ACL because beneficiary.pendingWithdrawl will always be == 0,
           for accounts that are not whitelisted beneficiaries.
    */
    function claim() external {
        _claim(msg.sender);
    }

    /* ##### Internal ##### */

    function _claim(address _beneficiary) internal {
        Beneficiary storage beneficiary = account[_beneficiary];
        uint withdraw = beneficiary.pendingWithdrawl;
        if (withdraw > 0) {
            beneficiary.pendingWithdrawl = 0;
            dusd.safeTransfer(_beneficiary, withdraw);
        }
    }

    /* ##### Admin ##### */

    function addBeneficiary(
        address beneficiary,
        uint[] calldata _allocations
    )
        external
        onlyOwner
    {
        require(beneficiary != address(0x0), "ZERO_ADDRESS");
        account[beneficiary] = Beneficiary(0, 0);
        beneficiaries.push(beneficiary);
        modifyAllocation(_allocations);
    }

    function modifyAllocation(
        uint[] memory _allocations
    )
        public
        onlyOwner
    {
        require(beneficiaries.length == _allocations.length, "MALFORMED_INPUT");
        uint total = 0;
        for (uint i = 0; i < _allocations.length; i++) {
            account[beneficiaries[i]].share = _allocations[i];
            total = total.add(_allocations[i]);
        }
        require(total == MAX, "INVALID_ALLOCATIONS");
    }
}
