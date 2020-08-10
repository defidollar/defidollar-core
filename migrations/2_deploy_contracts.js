const Core = artifacts.require("Core");
const StakeLPToken = artifacts.require("StakeLPToken");
const DUSD = artifacts.require("DUSD");
const Aggregator = artifacts.require("MockAggregator");
const Oracle = artifacts.require("Oracle");
const Reserve = artifacts.require("Reserve");
const StakeLPTokenProxy = artifacts.require("StakeLPTokenProxy");
const CoreProxy = artifacts.require("CoreProxy");

const utils = require('./utils')

const toBN = web3.utils.toBN
const toWei = web3.utils.toWei

module.exports = async function(deployer, network, accounts) {
    await deployer.deploy(Core);
    const coreProxy = await deployer.deploy(CoreProxy)
    const core = await Core.at(CoreProxy.address)

    await deployer.deploy(DUSD, CoreProxy.address)
    const config = { contracts: { tokens: { DUSD: { address: DUSD.address, decimals: 18 } } } }

    // initialize system with 4 coins
    const tickerSymbols = ['DAI', 'USDC', 'USDT', 'sUSD']
    const decimals = [18, 6, 6, 18]
    const reserves = []
    const tokens = []
    for(let i = 0; i < tickerSymbols.length; i++) {
        const reserve = await Reserve.new(decimals[i])
        reserves.push(reserve)
        tokens.push(reserve.address)
        config.contracts.tokens[tickerSymbols[i]] = {
            address: reserve.address,
            decimals: decimals[i]
        }
    }

    // Oracles
    const ethPrice = toBN(200)
    const ethUsdAgg = await Aggregator.new()
    // The latestAnswer value for all USD reference data contracts is multiplied by 100000000 before being written on-chain and
    await ethUsdAgg.setLatestAnswer(ethPrice.mul(toBN('100000000')))
    const aggregators = []
    for(let i = 0; i < 4; i++) {
        aggregators.push(await Aggregator.new())
        // set price = $1 but relative to eth
        await aggregators[i].setLatestAnswer(toBN(web3.utils.toWei('1')).div(ethPrice))
    }
    await deployer.deploy(
        Oracle,
        aggregators.map(a => a.address),
        ethUsdAgg.address
    )

    // B. StakeLPToken
    await deployer.deploy(StakeLPToken);
    const stakeLPTokenProxy = await deployer.deploy(StakeLPTokenProxy)
    const stakeLPToken = await StakeLPToken.at(StakeLPTokenProxy.address)
    await stakeLPTokenProxy.updateAndCall(
        StakeLPToken.address,
        stakeLPToken.contract.methods.initialize(
            CoreProxy.address,
            DUSD.address
        ).encodeABI()
    )
    await coreProxy.updateAndCall(
        Core.address,
        core.contract.methods.initialize(
            DUSD.address,
            StakeLPTokenProxy.address,
            Oracle.address,
            10000, // 0 redeem fee, 0.05% would be 10005
        ).encodeABI()
    )
    await core.whitelistTokens(tokens)
    await core.syncSystem()

    config.contracts.base = CoreProxy.address
    config.contracts.valley = StakeLPTokenProxy.address
    utils.writeContractAddresses(config)
};
