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
    let [ yVaultPeak, yVaultPeakProxy, controller, controllerProxy, core, coreProxy ] = await Promise.all([
        YVaultPeak.new(),
        YVaultPeakProxy.new(),
        Controller.new(),
        ControllerProxy.new(),
        Core.new(),
        CoreProxy.at('0xE449Ca7d10b041255E7e989D158Bee355d8f88d3')
    ])
    console.log({
        YVaultPeak: yVaultPeak.address,
        YVaultPeakProxy: yVaultPeakProxy.address,
        Controller: controller.address,
        ControllerProxy: controllerProxy.address,
        Core: core.address
    })

    await controllerProxy.updateImplementation(controller.address);
    controller = await Controller.at(controllerProxy.address)
    const [ zap ] = await Promise.all([
        YVaultZap.new(yVaultPeakProxy.address),
        yVaultPeakProxy.updateAndCall(
            yVaultPeak.address,
            yVaultPeak.contract.methods.initialize(
                controllerProxy.address,
            ).encodeABI()
        ),
        coreProxy.updateImplementation(core.address, { from }),
        controller.addPeak(yVaultPeakProxy.address),
        controller.addVault(config.contracts.tokens.yCRV.address, config.contracts.tokens.yUSD.address)
    ])

    core = await Core.at(coreProxy.address)
    await core.whitelistTokens([config.contracts.tokens.TUSD.address], { from })
    await core.whitelistPeak(yVaultPeakProxy.address, [0, 1, 2, 4], web3.utils.toWei('20000000'), false, { from })
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
    await curveSusdPeakProxy.updateImplementation(sPeak.address, { from })
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
