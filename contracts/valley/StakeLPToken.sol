pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {ICore} from "../interfaces/ICore.sol";
import {IDUSD} from "../interfaces/IDUSD.sol";
import {Initializable} from "../common/Initializable.sol";
import {OwnableProxy} from "../common/OwnableProxy.sol";


contract LPTokenWrapper {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20 public dusd;

    uint public totalSupply;
    mapping(address => uint) private _balances;

    function balanceOf(address account) public view returns (uint) {
        return _balances[account];
    }

    function stake(uint amount) public {
        totalSupply = totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        dusd.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint amount) public {
        totalSupply = totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
    }
}

contract StakeLPToken is OwnableProxy, Initializable, LPTokenWrapper {
    ICore public core;

    uint public rewardPerTokenStored;
    uint public deficit;
    bool public isPaused;

    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public rewards;

    event Staked(address indexed user, uint indexed amount);
    event Withdrawn(address indexed user, uint indexed amount);
    event RewardPaid(address indexed user, uint indexed reward);
    event RewardPerTokenUpdated(uint indexed rewardPerToken, uint indexed when);
    event DeficitUpdated(uint indexed deficit);

    modifier onlyCore() {
        require(
            msg.sender == address(core),
            "Not authorized"
        );
        _;
    }

    function initialize(ICore _core, IERC20 _dusd)
        public
        notInitialized
    {
        core = _core;
        dusd = _dusd;
    }

    modifier updateReward(address account) {
        if (account != address(0)) {
            rewards[account] = _earned(rewardPerTokenStored, account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint amount) public updateReward(msg.sender) {
        require(!isPaused, "Staking is paused");
        require(amount > 0, "Cannot stake 0");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint amount) public updateReward(msg.sender) {
        _withdraw(amount);
    }

    function exit() external {
        getReward();
        _withdraw(balanceOf(msg.sender));
    }

    function getReward() public updateReward(msg.sender) {
        uint reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            // this contract had received the reward tokens during the call to core.rewardDistributionCheckpoint()
            dusd.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // View Functions
    function earned(address account) public view returns (uint) {
        return _earned(rewardPerTokenStored, account);
    }

    function withdrawAble(address account) public view returns(uint) {
        return balanceOf(account);
    }

    function toggleIsPaused(bool _isPaused) external onlyOwner {
        isPaused = _isPaused;
    }

    // Internal functions
    function _earned(uint _rewardPerTokenStored, address account) internal view returns(uint) {
        return
            balanceOf(account)
                .mul(_rewardPerTokenStored.sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    function _withdraw(uint amount) internal {
        if (amount == 0) {
            // there might be case where user has 0 staked funds, but called getReward()
            return;
        }
        super.withdraw(amount);
        dusd.safeTransfer(msg.sender, amount);
    }
}
