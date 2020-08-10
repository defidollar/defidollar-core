const fs = require('fs')

const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const DUSD = artifacts.require("DUSD");
const Oracle = artifacts.require("Oracle");
const StakeLPTokenProxy = artifacts.require("StakeLPTokenProxy");
const StakeLPToken = artifacts.require("StakeLPToken");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const CurveSusdPeakProxy = artifacts.require("CurveSusdPeakProxy");

async function execute() {
    const config = JSON.parse(
        fs.readFileSync(`${process.cwd()}/deployments/mainnet-init.json`).toString()
    )
    let core = await Core.new()
    const coreProxy = await CoreProxy.new()
    const dusd = await DUSD.new(coreProxy.address)

    // Oracles
    const aggregators = config.contracts.chainlink
    const oracle = await Oracle.new(
        [
            aggregators.daiEthAggregator,
            aggregators.usdcEthAggregator,
            aggregators.usdtEthAggregator,
            aggregators.susdEthAggregator,
        ],
        aggregators.ethUsdAggregator
    )

    // StakeLPToken
    const stakeLPToken = await StakeLPToken.new()
    const stakeLPTokenProxy = await StakeLPTokenProxy.new()
    await stakeLPTokenProxy.updateAndCall(
        stakeLPToken.address,
        stakeLPToken.contract.methods.initialize(
            coreProxy.address,
            dusd.address
        ).encodeABI()
    )

    await coreProxy.updateAndCall(
        core.address,
        core.contract.methods.initialize(
            dusd.address,
            stakeLPTokenProxy.address,
            oracle.address,
            10000, // 0 redeem fee
        ).encodeABI()
    )

    core = await Core.at(coreProxy.address)
    const peak = config.contracts.peaks.curveSUSDPool
    const tokens = []
    for (let i = 0; i < 4; i++) {
        tokens.push(config.contracts.tokens[peak.coins[i]])
    }
    console.log(tokens.map(t => t.address))
    const initial_price = web3.utils.toWei('1')
    await core.whitelistTokens(
        tokens.map(t => t.address),
        tokens.map(t => t.decimals),
        new Array(4).fill(initial_price)
    )
    await core.syncSystem()
    config.contracts.base = coreProxy.address
    config.contracts.valley = stakeLPTokenProxy.address

    // sUSD peak
    let curveSusdPeak = await CurveSusdPeak.new()
    const curveSusdPeakProxy = await CurveSusdPeakProxy.new()
    await curveSusdPeakProxy.updateAndCall(
        curveSusdPeak.address,
        curveSusdPeak.contract.methods.initialize(
            config.contracts.curve.susd.deposit,
            config.contracts.curve.susd.swap,
            config.contracts.tokens.crvPlain3andSUSD.address,
            core.address,
            tokens.map(t => t.address)
        ).encodeABI()
    )
    curveSusdPeak = await CurveSusdPeak.at(curveSusdPeakProxy.address)
    // await curveSusdPeak.replenishApprovals()
    await core.whitelistPeak(curveSusdPeakProxy.address, [0, 1, 2, 3])

    config.contracts.peaks.curveSUSDPool.address = curveSusdPeakProxy.address,
    fs.writeFileSync(
        `${process.cwd()}/deployments/mainnet-fork.json`,
        JSON.stringify(config, null, 4) // Indent 4 spaces
    )
}

module.exports = async function (callback) {
    try {
        await execute()
    } catch (e) {
        // truffle exec <script> doesn't throw errors, so handling it in a verbose manner here
        console.log(e)
    }
    callback()
}
