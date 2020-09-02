const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const CurveSusdPeakProxy = artifacts.require("CurveSusdPeakProxy");
const DUSD = artifacts.require("DUSD");

const fromWei = web3.utils.fromWei
let from

async function execute() {
    from = '0x08F7506E0381f387e901c9D0552cf4052A0740a4' // owner account

    let core = await Core.new()
    const coreProxy = await CoreProxy.at('0xE449Ca7d10b041255E7e989D158Bee355d8f88d3')
    await coreProxy.updateImplementation(core.address, { from })

    let curveSusdPeak = await CurveSusdPeak.new()
    const curveSusdPeakProxy = await CurveSusdPeakProxy.at('0x80db6e1a3f6dc0D048026f3BeDb39807843366e4')
    await curveSusdPeakProxy.updateImplementation(curveSusdPeak.address, { from })

    await harvest(curveSusdPeakProxy.address)
}

async function harvest(curveSusdPeakProxyAddress) {
    const dusd = await DUSD.at('0x5BC25f649fc4e26069dDF4cF4010F9f706c23831')
    console.log(fromWei(await dusd.balanceOf(from)))
    const curveSusdPeak = await CurveSusdPeak.at(curveSusdPeakProxyAddress)
    await curveSusdPeak.harvest(0, { from })
    console.log(fromWei(await dusd.balanceOf(from)))
}

function sleep(s) {
    return new Promise(resolve => setTimeout(resolve, s * 1000));
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
