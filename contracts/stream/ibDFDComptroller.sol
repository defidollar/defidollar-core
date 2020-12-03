pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/ownership/Ownable.sol";

import {IComptroller} from "../interfaces/IComptroller.sol";

contract IRewardDistributionRecipient is Ownable {
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

contract ibDFDComptroller is IRewardDistributionRecipient {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    uint public constant DURATION = 7 days;

    /*
        Todo (before deployment)
        1. Provide comptroller address
        2. Make the following constant
    */
    IERC20 public dfd = IERC20(0x20c36f062a31865bED8a5B1e512D9a1A20AA333A);
    IERC20 public dusd = IERC20(0x5BC25f649fc4e26069dDF4cF4010F9f706c23831);
    IComptroller public comptroller = IComptroller(0x0);
    address public uni = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address public beneficiary; // ibDFD

    uint public periodFinish;
    uint public rewardRate;
    uint public lastUpdateTime;
    uint public rewardStored;
    uint public rewardPaid;

    event RewardAdded(uint reward);
    event RewardPaid(address indexed user, uint256 reward);
    event Harvested(uint indexed dusd, uint indexed dfd);

    constructor(address _beneficiary) public {
        beneficiary = _beneficiary;
    }

    modifier updateReward() {
        uint _lastTimeRewardApplicable = lastTimeRewardApplicable();
        rewardStored = rewardStored.add(
            _lastTimeRewardApplicable
                .sub(lastUpdateTime)
                .mul(rewardRate)
        );
        lastUpdateTime = _lastTimeRewardApplicable;
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function getReward()
        external
        updateReward
    {
        require(msg.sender == beneficiary, "GET_REWARD_NO_AUTH");
        uint reward = rewardStored.sub(rewardPaid);
        rewardPaid = rewardStored;
        dfd.safeTransfer(beneficiary, reward);
        emit RewardPaid(beneficiary, reward);
    }

    function notifyRewardAmount(uint256 reward)
        external
        onlyRewardDistribution
        updateReward
    {
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

    function harvest() external {
        // This contract will receive dusd because it should be a registered beneficiary
        comptroller.harvest();

        uint256 _dusd = dusd.balanceOf(address(this));
        if (_dusd > 0) {
            dusd.safeApprove(uni, 0);
            dusd.safeApprove(uni, _dusd);

            address[] memory path = new address[](3);
            path[0] = address(dusd);
            path[1] = address(dfd);

            uint[] memory amounts = Uni(uni).swapExactTokensForTokens(_dusd, uint256(0), path, address(this), now.add(1800));
            if (amounts[1] > 0) {
                dfd.safeTransfer(beneficiary, amounts[1]);
            }
            emit Harvested(_dusd, amounts[1]);
        }
    }
}

interface Uni {
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external returns (uint[] memory);
}
