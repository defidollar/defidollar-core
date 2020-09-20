pragma solidity 0.5.17;

interface ICurveDeposit {
    function add_liquidity(uint[4] calldata uamounts, uint min_mint_amount) external;
    function remove_liquidity(uint amount, uint[4] calldata min_uamounts) external;
    function remove_liquidity_imbalance(uint[4] calldata uamounts, uint max_burn_amount) external;
    function remove_liquidity_one_coin(uint _token_amount, int128 i, uint min_uamount) external;
    function calc_withdraw_one_coin(uint _token_amount, int128 i) external view returns(uint);
}

interface ICurve {
    function add_liquidity(uint[4] calldata uamounts, uint min_mint_amount) external;
    function remove_liquidity_imbalance(uint[4] calldata uamounts, uint max_burn_amount) external;
    function remove_liquidity(uint amount, uint[4] calldata min_amounts) external;
    function calc_token_amount(uint[4] calldata inAmounts, bool deposit) external view returns(uint);
    function balances(int128 i) external view returns(uint);
    function get_virtual_price() external view returns(uint);
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
    // for tests
    function mock_add_to_balance(uint[4] calldata amounts) external;
}

interface IUtil {
    function get_D(uint[4] calldata uamounts) external pure returns(uint);
}
