# DefiDollar

DefiDollar (DUSD) is a stablecoin backed by [Curve Finance](https://www.curve.fi/) LP tokens. It uses chainlink oracles for its stability mechanism.

DefiDollar was originally built for the ETHGlobal [HackMoney](https://hackathon.money/) and the details about the first design are [here](https://medium.com/@atvanguard/introducing-defidollar-742e30be9780). While the ideas are the same, underlying protocols have sinced been changed - In a nutshell, we leverage Curve to handle the logic around integrating with lending protocols and token swaps; which are essential ingredients for the stability of the DefiDollar.

### Technical Details

1. Admin needs to whitelist a stablecoin using `whitelistToken(address)` and a supported curve pool using `addSupportedPool(...)`. Any curve pools can be supported as long they follow the interface:
```
interface ICurveDeposit {
  function add_liquidity(uint[] calldata uamounts, uint min_mint_amount) external;
  function remove_liquidity_imbalance(uint[] calldata uamounts, uint max_burn_amount) external;
}

interface ICurve {
  function balances(uint arg) external view returns(uint);
}

```

2. User can mint DUSD with supported stablecoins.
```
/**
  * @dev Mint DUSD
  * @param pool_id Curve pool ID defined by the defidollar system
  * @param in_amounts Exact in_amounts in the same order as required by the curve pool
  * @param min_dusd_amount Minimum DUSD to mint, used for capping slippage
  */
  function mint(
    uint pool_id,
    uint[] calldata in_amounts,
    uint min_dusd_amount
  ) external returns(uint dusd_amount);
```
Core contract deposits these in the chosen curve pools, receives curve LP tokens for it and determines the DUSD to mint based on the lp share in the curve pool and prices for the underlying coins obtained from the [chainlink price feeds](https://feeds.chain.link/).

3. User can burn DUSD and obtain underlying coins in any ratio they desire.
```
/**
  * @dev Burn DUSD
  * @param pool_id Curve pool ID defined by the defidollar system
  * @param out_amounts Exact out_amounts in the same order as required by the curve pool
  * @param max_dusd_amount Max DUSD to burn, used for capping slippage
  */
  function burn(
    uint pool_id,
    uint[] calldata out_amounts,
    uint max_dusd_amount
  ) external returns(uint dusd_amount);
```

4. It is also possible to mint/burn shares across several underlying curve pools in a single transaction. One such scenario when this is definitely required is when the number of shares of any particular curve pool are not enough to burn a large amount of DUSD.
```
/**
  * @dev Mint DUSD while depositing in more than 1 curve pools
  * @param in_amounts Exact in_amounts that user wants to supply. Ordered as system_coins.
  * @param pool_ids Curve pool IDs defined by the defidollar system
  * @param distribution distribution[i] is the list of coins that will be supplied to pool at pool_ids[i]
  * @param min_dusd_amount Minimum DUSD to mint, used for capping slippage
  */
  function mintBatch(
    uint[] calldata in_amounts,
    uint[] calldata pool_ids,
    uint[][] calldata distribution,
    uint min_dusd_amount
  ) external returns (uint dusd_amount);

/**
  * @dev Burn DUSD while withdrawing from more than 1 curve pools
  * @param out_amounts Exact out_amounts that the user wants to withdraw. Ordered as system_coins.
  * @param pool_ids Curve pool IDs defined by the defidollar system
  * @param distribution distribution[i] is the list of coins that will be withdrawn from the pool at pool_ids[i]
  * @param max_dusd_amount Miximum DUSD to burn, used for capping slippage
  */
  function burnBatch(
    uint[] calldata out_amounts,
    uint[] calldata pool_ids,
    uint[][] calldata distribution,
    uint max_dusd_amount
  ) external returns (uint dusd_amount)
```

### Development
1. Compile
```
npm run compile
```
