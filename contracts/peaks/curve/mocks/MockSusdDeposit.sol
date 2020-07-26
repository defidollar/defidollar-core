pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../ICurve.sol";
import "./MockSusdToken.sol";

contract MockSusdDeposit is ICurveDeposit {
    uint constant N_COINS = 4;

    ICurve curve;
    MockSusdToken token;
    address[] underlyingCoins;

    constructor(
        ICurve _curve,
        MockSusdToken _token,
        address[] memory _underlyingCoins
    ) public {
        curve = _curve;
        token = _token;
        underlyingCoins = _underlyingCoins;
    }

    function add_liquidity(uint[] calldata uamounts, uint min_mint_amount) external {
        for (uint i = 0; i < N_COINS; i++) {
            IERC20 _token = IERC20(underlyingCoins[i]);
            _token.transferFrom(msg.sender, address(this), uamounts[i]);
            _token.approve(address(curve), uamounts[i]);
        }
        curve.add_liquidity(uamounts, min_mint_amount);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function remove_liquidity_imbalance(uint[] calldata uamounts, uint max_burn_amount) external {
        uint _tokens = token.balanceOf(msg.sender);
        if (_tokens > max_burn_amount) {
            _tokens = max_burn_amount;
        }
        token.transferFrom(msg.sender, address(this), _tokens);
        token.approve(address(curve), _tokens);
        curve.remove_liquidity_imbalance(uamounts, _tokens);
        for (uint i = 0; i < N_COINS; i++) {
            IERC20 _token = IERC20(underlyingCoins[i]);
            _token.transfer(msg.sender, _token.balanceOf(address(this)));
        }
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }
}
