pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {Core} from "../base/Core.sol";

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public stok;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        stok.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stok.safeTransfer(msg.sender, amount);
    }
}

contract StakeLPToken is LPTokenWrapper {
    Core public core;

    uint public income_diff;
    uint public lastUpdated;
    uint public lastIncomeUpdate;
    uint public rewardPerTokenStored;
    uint public unitRewardForCurrentFeeWindow;
    uint public windowTotal;
    uint public lastWindowSize;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(Core _core, IERC20 _stok) public {
        core = _core;
        stok = _stok;
        lastUpdated = now;
        lastIncomeUpdate = now;
    }

    modifier onlyCore() {
        require(msg.sender == address(core), "Only Core");
        _;
    }

    modifier updateReward(address account) {
        updateRewardForCurrentFeeWindow();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function updateRewardForCurrentFeeWindow() internal {
        uint total_supply = totalSupply();
        if (total_supply > 0) {
            uint window = now.sub(lastUpdated);
            windowTotal += window;
            unitRewardForCurrentFeeWindow = unitRewardForCurrentFeeWindow
                // .add(uint(1e36).div(window).div(total_supply));
                .add(window.mul(1e36).div(total_supply));
        } else {
            unitRewardForCurrentFeeWindow = 0;
        }
        lastUpdated = now;
    }

    function stake(uint amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() public {
        withdraw(balanceOf(msg.sender));
        _getReward();
    }

    function getReward() public updateReward(msg.sender) {
        _getReward();
    }

    function _getReward() internal {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            core.mintReward(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    event Debug(uint indexed a);
    /**
    * @dev Difference of protocol income at 2 points
    */
    function update_income_diff(uint protocol_income) public onlyCore {
        updateRewardForCurrentFeeWindow();
        emit Debug(windowTotal);
        if (protocol_income > income_diff) {
            income_diff = protocol_income.sub(income_diff);
            rewardPerTokenStored = rewardPerTokenStored
            .add(
                unitRewardForCurrentFeeWindow
                .mul(income_diff)
                .div(now.sub(lastIncomeUpdate))
                .div(1e18)
            );
            // lastWindowSize = now.sub(lastIncomeUpdate);
            emit Debug(now.sub(lastIncomeUpdate));
        } else {
            income_diff = 0;
        }
        unitRewardForCurrentFeeWindow = 0;
        lastIncomeUpdate = now;
        windowTotal = 0;
    }

    function setWindow() public {
        windowTotal = 0;
    }

    // View functions
    function earned(address account)
        public
        view
        returns (uint256)
    {
        return
            balanceOf(account)
            .mul(rewardPerTokenStored.sub(userRewardPerTokenPaid[account]))
            .div(1e18)
            .add(rewards[account]);
    }
}
