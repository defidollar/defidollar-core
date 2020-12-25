pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/ownership/Ownable.sol";

import {IComptroller, IDFDComptroller} from "../interfaces/IComptroller.sol";
import {Uni} from "../interfaces/Uni.sol";

contract RewardDistributionRecipient is Ownable {
    address public rewardDistribution;

    function notifyRewardAmount(uint256 reward) external;

    modifier onlyRewardDistribution() {
        require(_msgSender() == rewardDistribution, "Caller is not reward distribution");
        _;
    }

    function setRewardDistribution(address _rewardDistribution)
        external
        onlyOwner
    {
        rewardDistribution = _rewardDistribution;
    }
}

contract DFDComptroller is RewardDistributionRecipient, IDFDComptroller {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    uint public constant DURATION = 7 days;

    address public bal;
    IERC20 public dusd;
    IERC20 public dfd;
    IComptroller public comptroller;

    // Mainnet
    // address public constant bal = address(0xD8E9690eFf99E21a2de25E0b148ffaf47F47C972);
    // IERC20 public constant dusd = IERC20(0x5BC25f649fc4e26069dDF4cF4010F9f706c23831);
    // IERC20 public constant dfd = IERC20(0x20c36f062a31865bED8a5B1e512D9a1A20AA333A);
    // IComptroller public constant comptroller = IComptroller(<>);

    // Kovan
    // address public constant bal = address(0xe6976680e732eCbd78571C49B28dbB6F0BB057Aa);
    // IERC20 public constant dfd = IERC20(0x81e5EB7FEa117Ea692990dc49C3A8de46054f9ff);
    // IERC20 public constant dusd = IERC20(0xbA125322A44Aa62b6B621257C6120d39bEA4d6de);
    // IComptroller public constant comptroller = IComptroller(0xF7621a2faC09Fc131978678b5034B6eD2768E67a);

    address public beneficiary;
    uint public periodFinish;
    uint public rewardRate;
    uint public lastUpdateTime;
    uint public rewardStored;
    uint public rewardPaid;
    mapping(address => bool) public isHarvester;

    event RewardAdded(uint reward);
    event RewardPaid(address indexed user, uint256 reward);
    event Harvested(uint indexed dusd, uint indexed dfd);

    modifier onlyHarvester() {
        require(isHarvester[_msgSender()], "Caller is not authorized harvester");
        _;
    }

    function getReward()
        external
    {
        _updateReward();
        require(msg.sender == beneficiary, "GET_REWARD_NO_AUTH");
        uint reward = rewardStored.sub(rewardPaid);
        if (reward > 0) {
            rewardPaid = rewardStored;
            dfd.safeTransfer(beneficiary, reward);
            emit RewardPaid(beneficiary, reward);
        }
    }

    function notifyRewardAmount(uint256 reward)
        external
        onlyRewardDistribution
    {
        _updateReward();
        dfd.safeTransferFrom(msg.sender, address(this), reward);
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(DURATION);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(DURATION);
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(DURATION);
        emit RewardAdded(reward);
    }

    function harvest(uint minAmountOut)
        onlyHarvester
        external
    {
        // This contract will receive dusd because it should be a registered beneficiary
        comptroller.harvest();

        uint256 _dusd = dusd.balanceOf(address(this));
        if (_dusd > 0) {
            dusd.approve(bal, _dusd);
            (uint tokenAmountOut,) = Uni(bal).swapExactAmountIn(address(dusd), _dusd, address(dfd), minAmountOut, uint(-1) /* max */);
            if (tokenAmountOut > 0) {
                dfd.safeTransfer(beneficiary, tokenAmountOut);
            }
            emit Harvested(_dusd, tokenAmountOut);
        }
    }

    function setHarvester(address _harvester, bool _status)
        external
        onlyOwner
    {
        isHarvester[_harvester] = _status;
    }

    function setBeneficiary(address _beneficiary)
        external
        onlyOwner
    {
        beneficiary = _beneficiary;
    }

    /* ##### View ##### */

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(_timestamp(), periodFinish);
    }

    function availableReward() public view returns(uint) {
        return lastTimeRewardApplicable()
            .sub(lastUpdateTime)
            .mul(rewardRate)
            .add(rewardStored)
            .sub(rewardPaid);
    }

    /* ##### Internal ##### */

    function _updateReward() internal {
        uint _lastTimeRewardApplicable = lastTimeRewardApplicable();
        rewardStored = rewardStored.add(
            _lastTimeRewardApplicable
                .sub(lastUpdateTime)
                .mul(rewardRate)
        );
        lastUpdateTime = _lastTimeRewardApplicable;
    }

    function _timestamp() internal view returns (uint) {
        return block.timestamp;
    }
}

contract DFDComptrollerTest is DFDComptroller {
    uint public travelled;

    function increaseBlockTime(uint duration) public {
        travelled = travelled.add(duration);
    }

    function _timestamp() internal view returns (uint) {
        return block.timestamp.add(travelled);
    }

    function timestamp() public view returns (uint) {
        return _timestamp();
    }

    function setParams(
        address _bal,
        IERC20 _dfd,
        IERC20 _dusd,
        IComptroller _comptroller
    )
        external
    {
        bal = _bal;
        dfd = _dfd;
        dusd = _dusd;
        comptroller = _comptroller;
    }
}
