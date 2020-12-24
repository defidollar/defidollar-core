const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const CurveSusdPeakProxy = artifacts.require("CurveSusdPeakProxy");
const YVaultPeak = artifacts.require("YVaultPeak");

const DUSD = artifacts.require("DUSD");
const IERC20 = artifacts.require("IERC20");

const fromWei = web3.utils.fromWei
let from = '0x08F7506E0381f387e901c9D0552cf4052A0740a4'
let account = '0xf53EFd29431099b5FbDA81d582B0b12020704737'

async function execute() {
    const config = JSON.parse(
        fs.readFileSync(`${process.cwd()}/deployments/mainnet-init.json`).toString()
    )
    let curveSusdPeak = await updateCurveSusdPeak()
    await migrate(curveSusdPeak)

    let yVaultPeak = await YVaultPeak.at(config.)

}

async function updateCurveSusdPeak() {
    let curveSusdPeak = await CurveSusdPeak.new()
    const curveSusdPeakProxy = await CurveSusdPeakProxy.at('0x80db6e1a3f6dc0D048026f3BeDb39807843366e4')
    await curveSusdPeakProxy.updateImplementation(curveSusdPeak.address, { from })
    return CurveSusdPeak.at(curveSusdPeakProxy.address)
}

async function migrate(curveSusdPeak) {
    await curveSusdPeak.migrate(from, { from, gas: 6000000 })
    const yCrv = await IERC20.at('0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8')
    console.log((await yCrv.balanceOf(from)).toString())
}

async function harvest(curveSusdPeak) {
    const dusd = await DUSD.at('0x5BC25f649fc4e26069dDF4cF4010F9f706c23831')
    console.log(fromWei(await dusd.balanceOf(from)))
    await curveSusdPeak.harvest(true, 0, { from })
    console.log(fromWei(await dusd.balanceOf(from)))
}

async function claimRewards(curveSusdPeak) {
    const crv = await IERC20.at('0xD533a949740bb3306d119CC777fa900bA034cd52')
    const snx = await IERC20.at('0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F')
    console.log({ crv: fromWei(await crv.balanceOf(from)), snx: fromWei(await snx.balanceOf(from)) })
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
