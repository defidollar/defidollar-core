const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const DUSD = artifacts.require("DUSD");
const Reserve = artifacts.require("Reserve");
const StakeLPTokenProxy = artifacts.require("StakeLPTokenProxy");
const StakeLPToken = artifacts.require("StakeLPToken");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const MockSusdToken = artifacts.require("MockSusdToken");
const MockCurveSusd = artifacts.require("MockCurveSusd");

const n_coins = 4

async function getArtifacts() {
    const coreProxy = await CoreProxy.deployed()
    const core = await Core.at(coreProxy.address)
    const dusd = await DUSD.deployed()
    const reserves = []
    const decimals = []
    for (let i = 0; i < n_coins; i++) {
        reserves.push(await Reserve.at((await core.system_coins(i)).token))
        decimals.push(await reserves[i].decimals())
    }
    const stakeLPTokenProxy = await StakeLPTokenProxy.deployed()
    return {
        core,
        dusd,
        reserves,
        decimals,
        stakeLPToken: await StakeLPToken.at(stakeLPTokenProxy.address),

        curveSusdPeak: await CurveSusdPeak.deployed(),
        curveToken: await MockSusdToken.deployed(),
        mockCurveSusd: await MockCurveSusd.deployed()
    }
}

module.exports = { getArtifacts }
