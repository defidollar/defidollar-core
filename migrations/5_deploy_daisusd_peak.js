// Artifacts
const Core = artifacts.require("Core")
const CoreProxy = artifacts.require("CoreProxy")
const StableIndexPeak = artifacts.require("StableIndexPeak")
const StableIndexPeakProxy = artifacts.require("StableIndexPeakProxy")
const StableIndexZap = artifacts.require("StableIndexZap")
const DUSD = artifacts.require("DUSD")

const Reserve = artifacts.require("Reserve")

const utils = require('./utils')

module.exports = async function(deployer, network, accounts) {
    const config = utils.getContractAddresses()
    const peak = {
        coins: ["DAI", "sUSD"], 
        native: ["aDAI", "aSUSD"] // Possibly BPT?
    }

    const coreProxy = await CoreProxy.deployed()
    const core = await Core.at(coreProxy.address)
    const reserves = []
    for (let i = 0; i < 2; i++) {
        reserves.push(await Reserve.at(config.contracts.tokens[peak.coins[i]].address))
    }
    const tokens = reserves.map(r => r.address)

    // Contract deployments ...

}
