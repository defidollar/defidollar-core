const fs = require('fs')

const Core = artifacts.require("Core");
const DUSD = artifacts.require("DUSD");
const CoreProxy = artifacts.require("CoreProxy");
const YVaultPeak = artifacts.require("YVaultPeakTest");
const YVaultPeakProxy = artifacts.require("YVaultPeakProxy");
const YVaultZap = artifacts.require("YVaultZapTest");
const MockYvault = artifacts.require("MockYvault");
const Controller = artifacts.require("Controller");
const ControllerProxy = artifacts.require("ControllerProxy");

const MockSusdToken = artifacts.require("MockSusdToken");
const Reserve = artifacts.require("Reserve");

const utils = require('./utils')
const susdCurveABI = require('../scripts/abis/susdCurve.json')
const susdCurveDepositABI = require('../scripts/abis/susdCurveDeposit.json')

const toBN = web3.utils.toBN
const toWei = web3.utils.toWei

module.exports = async function(deployer, network, accounts) {
    const config = utils.getContractAddresses()
    const peak = {
        coins: ["DAI", "USDC", "USDT", "TUSD"],
        native: ["yCRV", "yUSD"]
    }
    const coreProxy = await CoreProxy.deployed()
    const core = await Core.at(coreProxy.address)
    const reserves = []
    for (let i = 0; i < 4; i++) {
        reserves.push(await Reserve.at(config.contracts.tokens[peak.coins[i]].address))
    }
    const tokens = reserves.map(r => r.address)

    // Deploy yPool
    const yCrv = await MockSusdToken.new()
    config.contracts.tokens['yCRV'] = {
        address: yCrv.address,
        decimals: 18,
        name: "Curve.fi yDAI/yCrvC/yCrvT/yTUSD",
        peak: "yVaultPeak"
    }

    let curve = new web3.eth.Contract(susdCurveABI)
    curve = await curve.deploy({
        data: fs.readFileSync(`${process.cwd()}/vyper/curveSusd`).toString().slice(0, -1),
        arguments: [
            tokens,
            tokens,
            yCrv.address,
            100,
            4000000
        ]
    }).send({ from: accounts[0], gas: 10000000 })

    let curveDeposit = new web3.eth.Contract(susdCurveDepositABI)
    curveDeposit = await curveDeposit.deploy({
        data: fs.readFileSync(`${process.cwd()}/vyper/curveSusdDeposit`).toString().slice(0, -1),
        arguments: [
            tokens,
            tokens,
            curve.options.address,
            yCrv.address
        ]
    }).send({ from: accounts[0], gas: 10000000 })

    await deployer.deploy(Controller)
    const controllerProxy = await deployer.deploy(ControllerProxy)
    await controllerProxy.updateImplementation(Controller.address);
    const controller = await Controller.at(controllerProxy.address)

    const yVault = await deployer.deploy(MockYvault, yCrv.address, '0x0000000000000000000000000000000000000000')
    config.contracts.tokens['yUSD'] = {
        address: yVault.address,
        decimals: 18,
        name: "Yvault-LP-YCurve",
        peak: "yVaultPeak"
    }
    await deployer.deploy(YVaultPeak)
    const yVaultPeakProxy = await deployer.deploy(YVaultPeakProxy)
    const yVaultPeak = await YVaultPeak.at(YVaultPeakProxy.address)
    await yVaultPeakProxy.updateAndCall(
        YVaultPeak.address,
        yVaultPeak.contract.methods.initialize(controller.address).encodeABI()
    )
    const yVaultZap = await deployer.deploy(YVaultZap, yVaultPeak.address)
    peak.zap = yVaultZap.address
    await Promise.all([
        controller.addPeak(yVaultPeak.address),
        controller.addVault(yCrv.address, yVault.address),
        core.whitelistPeak(yVaultPeakProxy.address, [0, 1, 2, 4], toWei('1234567')),
        yVaultZap.setDeps(
            curveDeposit.options.address,
            curve.options.address,
            yCrv.address,
            DUSD.address,
            tokens,
            tokens
        ),
        yVaultPeak.setDeps(
            core.address,
            curve.options.address,
            yCrv.address,
            yVault.address
        ),
        yVaultPeak.setParams(500, 10000)
    ])
    peak.address = yVaultPeakProxy.address,
    config.contracts.peaks = config.contracts.peaks || {}
    config.contracts.peaks['yVaultPeak'] = peak
    utils.writeContractAddresses(config)

    // todo fix
    if (process.env.INITIALIZE === 'true') {
        // seed initial liquidity
        const charlie = accounts[0]
        const amounts = [100, 100, 100, 100]
        const decimals = [18,6,6,18]
        const tasks = []
        for (let i = 0; i < 4; i++) {
            amounts[i] = toBN(amounts[i]).mul(toBN(10 ** decimals[i])).toString()
            tasks.push(reserves[i].mint(charlie, amounts[i]))
            tasks.push(reserves[i].approve(curveDeposit.options.address, amounts[i], { from: charlie }))
        }
        await Promise.all(tasks)
        await curveDeposit.methods.add_liquidity(amounts, '400').send({ from: charlie, gas: 10000000 })
    }
}
