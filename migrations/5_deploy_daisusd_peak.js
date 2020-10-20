// Artifacts
const Core = artifacts.require("Core")
const CoreProxy = artifacts.require("CoreProxy")
const StableIndexPeak = artifacts.require("StableIndexPeak")
const StableIndexPeakProxy = artifacts.require("StableIndexPeakProxy")
const StableIndexZap = artifacts.require("StableIndexZap")
const DUSD = artifacts.require("DUSD")

const Reserve = artifacts.require("Reserve")

// Mint with single reserve asset
const susdCurveABI = require('../scripts/abis/susdCurve.json')
const susdCurveDepositABI = require('../scripts/abis/susdCurveDeposit.json')
const utils = require('./utils')

const toBN = web3.utils.toBN
const toWei = web3.utils.toWei

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

    // Mock aTokens
    const aDai = await MockaToken.new() 
    const aSusd = await MockaToken.new()

    config.contracts.tokens['aDai'] = {
        address: aDai.address,
        decimals: 18,
        name: "Aave Dai",
        peak: "stableIndexPeak"
    }
    config.contracts.tokens['aSusd'] = {
        address: aSusd.address,
        decimals: 18,
        name: "Aave aSusd",
        peak: "stableIndexPeak"
    }

    // Curve susd pool deployment ... (single token swap)

    // Contract deployments ...
    await deployer.deploy(StableIndexPeak)
    const stableIndexPeakProxy = await deployer.deploy(StableIndexPeakProxy)
    const stableIndexPeak = await StableIndexPeak.at(stableIndexPeakProxy.address)

    const stableIndexZap = await deployer.deploy(StableIndexZap, stableIndexPeak.address)

    // CRP deployment

    // Setup peak parameters
    await Promise.all([
        core.whitelistPeak(stableIndexPeak.address)
    ])
    
}
