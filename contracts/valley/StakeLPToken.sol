pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {Core} from "../base/Core.sol";
import {Initializable} from "../common/Initializable.sol";

contract LPTokenWrapper {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20 public stok;

    uint public totalSupply;
    mapping(address => uint) private _balances;

    function balanceOf(address account) public view returns (uint) {
        return _balances[account];
    }

    function stake(uint amount) public {
        totalSupply = totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        stok.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint amount) public {
        totalSupply = totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stok.safeTransfer(msg.sender, amount);
    }
}

contract StakeLPToken is Initializable, LPTokenWrapper {
    Core public core;

    uint public rewardPerTokenStored;
    uint public deficit;

    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public rewards;

    event Staked(address indexed user, uint indexed amount);
    event Withdrawn(address indexed user, uint indexed amount);
    event RewardPaid(address indexed user, uint indexed reward);
    event RewardPerTokenUpdated(uint indexed rewardPerToken, uint indexed when);

    modifier onlyCore() {
        require(
            msg.sender == address(core),
            "Not authorized"
        );
        _;
    }

    function initialize(Core _core, IERC20 _stok) public notInitialized {
        core = _core;
        stok = _stok;
    }

    modifier updateReward(address account) {
        updateProtocolIncome();
        if (account != address(0)) {
            rewards[account] = _earned(rewardPerTokenStored, account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function updateProtocolIncome() public returns(uint) {
        uint income = core.rewardDistributionCheckpoint();
        rewardPerTokenStored = rewardPerToken(income);
        emit RewardPerTokenUpdated(rewardPerTokenStored, block.timestamp);
        return rewardPerTokenStored;
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint amount) public updateReward(msg.sender) {
        require(
            amount <= withdrawAble(msg.sender),
            "Withdrawing more than staked or illiquid due to system deficit"
        );
        _withdraw(amount);
    }

    function exit() external {
        getReward();
        _withdraw(withdrawAble(msg.sender));
    }

    function getReward() public updateReward(msg.sender) {
        uint reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            core.mintReward(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function notify(uint _deficit) external onlyCore {
        deficit = _deficit;
    }

    // View Functions
    function earned(address account) public view returns (uint) {
        uint income = core.lastPeriodIncome();
        return _earned(rewardPerToken(income), account);
    }

    function rewardPerToken(uint income) public view returns(uint) {
        if (totalSupply == 0 || income == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored.add(
            income
            .mul(1e18)
            .div(totalSupply)
        );
    }

    function withdrawAble(address account) public view returns(uint) {
        uint _withdrawAble = balanceOf(account);
        if (totalSupply == 0 || deficit == 0) {
            return _withdrawAble;
        }
        uint deficitShare = _withdrawAble.mul(deficit).div(totalSupply);
        if (deficitShare >= _withdrawAble) {
            return 0;
        }
        return _withdrawAble.sub(deficitShare);
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
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }
}
