const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const CurveSusdPeakProxy = artifacts.require("CurveSusdPeakProxy");
const DUSD = artifacts.require("DUSD");
const IERC20 = artifacts.require("IERC20");

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
    // await claimRewards(curveSusdPeakProxy.address)
}

async function harvest(curveSusdPeakProxyAddress) {
    const dusd = await DUSD.at('0x5BC25f649fc4e26069dDF4cF4010F9f706c23831')
    console.log(fromWei(await dusd.balanceOf(from)))
    const curveSusdPeak = await CurveSusdPeak.at(curveSusdPeakProxyAddress)
    await curveSusdPeak.harvest(0, { from })
    console.log(fromWei(await dusd.balanceOf(from)))
}

async function claimRewards(curveSusdPeakProxyAddress) {
    const crv = await IERC20.at('0xD533a949740bb3306d119CC777fa900bA034cd52')
    const snx = await IERC20.at('0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F')
    console.log({ crv: fromWei(await crv.balanceOf(from)), snx: fromWei(await snx.balanceOf(from)) })
    const curveSusdPeak = await CurveSusdPeak.at(curveSusdPeakProxyAddress)
    await curveSusdPeak.getRewards([crv.address,snx.address], from, { from })
    console.log({ crv: fromWei(await crv.balanceOf(from)), snx: fromWei(await snx.balanceOf(from)) })
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
