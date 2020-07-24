const Core = artifacts.require("Core");
const StakeLPToken = artifacts.require("StakeLPToken");
const DUSD = artifacts.require("DUSD");
const Aggregator = artifacts.require("MockAggregator");
const Oracle = artifacts.require("Oracle");
const Reserve = artifacts.require("Reserve");

const StakeLPTokenProxy = artifacts.require("StakeLPTokenProxy");
const CoreProxy = artifacts.require("CoreProxy");

const toBN = web3.utils.toBN
const toWei = web3.utils.toWei

module.exports = async function(deployer, network, accounts) {
    await deployer.deploy(Core);
    const coreProxy = await deployer.deploy(CoreProxy)
    const core = await Core.at(CoreProxy.address)

    await deployer.deploy(DUSD, CoreProxy.address)

    // initialize system with 4 coins
    const reserves = [
        await Reserve.new(18), // dai
        await Reserve.new(6), // usdc
        await Reserve.new(6), // usdt
        await Reserve.new(18) // susd
    ]
    const tokens = reserves.map(a => a.address)

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
    await deployer.deploy(Oracle, aggregators.map(a => a.address), ethUsdAgg.address)

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
    const initial_price = toWei('1')
    await core.whitelistTokens(tokens, [18, 6, 6, 18], new Array(4).fill(initial_price))
    await core.sync_system()
};
