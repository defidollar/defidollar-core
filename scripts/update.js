const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const CurveSusdPeakProxy = artifacts.require("CurveSusdPeakProxy");

// async function execute() {
//     let core = await Core.new()
//     console.log({ Core: core.address })

//     const coreProxy = await CoreProxy.at('0xD6647C5eF783eACc4f02686E3DC62198394702A5')
//     console.log({ CoreProxy: coreProxy.address })

//     await coreProxy.updateImplementation(core.address)

//     let curveSusdPeak = await CurveSusdPeak.new()
//     console.log({ CurveSusdPeak: curveSusdPeak.address })

//     const curveSusdPeakProxy = await CurveSusdPeakProxy.at('0x872F66de4408F95837014552300deBAdB45021e8')
//     console.log({ CurveSusdPeakProxy: curveSusdPeakProxy.address })

//     await curveSusdPeakProxy.updateImplementation(curveSusdPeak.address)
// }

async function execute() {
    Core.new()
    await sleep(5)
    CurveSusdPeak.new()
    await sleep(5)
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
