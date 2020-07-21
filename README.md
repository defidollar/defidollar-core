# DefiDollar

DefiDollar (DUSD) is a stablecoin backed by [Curve Finance](https://www.curve.fi/) LP tokens. It uses chainlink oracles for its stability mechanism.

DefiDollar was originally built for the ETHGlobal [HackMoney](https://hackathon.money/) and the details about the first design are [here](https://medium.com/@atvanguard/introducing-defidollar-742e30be9780). While the ideas are the same, underlying protocols have sinced been changed - In a nutshell, we leverage Curve to handle the logic around integrating with lending protocols and token swaps; which are essential ingredients for the stability of the DefiDollar.


### Development
```
npm run compile
npm run ganache
npm run migrate
npm t
```
