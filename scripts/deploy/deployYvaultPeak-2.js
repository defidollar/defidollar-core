const fs = require('fs')

const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const CurveSusdPeakProxy = artifacts.require("CurveSusdPeakProxy");
const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const YVaultPeak = artifacts.require("YVaultPeak");
const YVaultPeakProxy = artifacts.require("YVaultPeakProxy");
const YVaultZap = artifacts.require("YVaultZap");
const Controller = artifacts.require("Controller");
const ControllerProxy = artifacts.require("ControllerProxy");

async function execute() {
    const config = JSON.parse(
        fs.readFileSync(`${process.cwd()}/deployments/mainnet.json`).toString()
    )
    const from = '0x08F7506E0381f387e901c9D0552cf4052A0740a4'

    const yVaultPeakProxy = await YVaultPeakProxy.at('0xa89bd606d5dadda60242e8dedeebc95c41ad8986')
    console.log({ YVaultPeakProxy: yVaultPeakProxy.address })

    const yVaultPeak = await YVaultPeak.at('0x621944ba45358656a19E95f9DA05D7f54F2FeCD2')
    console.log({ YVaultPeak: yVaultPeak.address })

    const controller = await Controller.at('0x88fF54ED47402A97F6e603737f26Bb9e4E6cb03d')
    console.log({ Controller: controller.address })

    const core = await Core.at('0xE449Ca7d10b041255E7e989D158Bee355d8f88d3')
    await core.whitelistTokens([config.contracts.tokens.TUSD.address])
    await core.whitelistPeak(yVaultPeakProxy.address, [0, 1, 2, 4], web3.utils.toWei('20000000'), false)

    const zap = await YVaultZap.new(yVaultPeakProxy.address)

    Object.assign(config.contracts.peaks.yVaultPeak, {
        address: yVaultPeakProxy.address,
        zap: zap.address,
        controller: controller.address
    })

    fs.writeFileSync(
        `${process.cwd()}/deployments/mainnetY.json`,
        JSON.stringify(config, null, 4) // Indent 4 spaces
    )

    // Update sPeak
    const curveSusdPeakProxy = await CurveSusdPeakProxy.at(config.contracts.peaks.curveSUSDPool.address)
    await curveSusdPeakProxy.transferOwnership(from, { from: '0x511ed30E9404CBeC4bB06280395B74Da5f876D47' })
    const sPeak = await CurveSusdPeak.new()
    console.log(curveSusdPeakProxy.contract.methods.updateImplementation(sPeak.address, { from }))
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
