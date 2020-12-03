const Core = artifacts.require("Core");
const DUSD = artifacts.require("DUSD");
const Reserve = artifacts.require("Reserve");
const CoreProxy = artifacts.require("CoreProxy");


const Comptroller = artifacts.require("Comptroller");
const ibDUSD = artifacts.require("ibDUSD");
const ibDUSDProxy = artifacts.require("ibDUSDProxy");

const utils = require('./utils')

const toBN = web3.utils.toBN

module.exports = async function(deployer, network, accounts) {
    await deployer.deploy(Core);
    const coreProxy = await deployer.deploy(CoreProxy)
    const core = await Core.at(CoreProxy.address)

    await deployer.deploy(DUSD, CoreProxy.address, "tDUSD", "tDUSD", 18)
    const config = {
        contracts: {
            base: CoreProxy.address,
            tokens: {
                DUSD: { address: DUSD.address, decimals: 18 }
            }
        }
    }

    // initialize system with 4 coins
    const tickerSymbols = ['DAI', 'USDC', 'USDT', 'sUSD', 'TUSD']
    const decimals = [18, 6, 6, 18, 18]
    const reserves = []
    const tokens = []
    for(let i = 0; i < tickerSymbols.length; i++) {
        const reserve = await Reserve.new(tickerSymbols[i], tickerSymbols[i], decimals[i])
        reserves.push(reserve)
        tokens.push(reserve.address)
        if (process.env.INITIALIZE === 'true') {
            await reserves[i].mint(accounts[0], toBN(10000).mul(toBN(10 ** decimals[i])))
        }
        config.contracts.tokens[tickerSymbols[i]] = {
            address: reserve.address,
            decimals: decimals[i]
        }
    }

    await coreProxy.updateAndCall(
        Core.address,
        core.contract.methods.initialize(
            DUSD.address,
            '0x0000000000000000000000000000000000000000', // StakeLPToken
            '0x0000000000000000000000000000000000000000', // Oracle
            9999, // .01% redeem fee, 0.05% fee would be 9995
            0, // 0 colBuffer
        ).encodeABI()
    )
    await core.whitelistTokens(tokens)
    utils.writeContractAddresses(config)
};
