const fs = require('fs')
const assert = require('assert')

const Core = artifacts.require("Core");

const Comptroller = artifacts.require("Comptroller");
const DFDComptroller = artifacts.require("DFDComptroller");
const ibDFD = artifacts.require("ibDFD");
const ibDUSD = artifacts.require("ibDUSD");
const ibDFDProxy = artifacts.require("ibDFDProxy");
const ibDUSDProxy = artifacts.require("ibDUSDProxy");
const IERC20 = artifacts.require("IERC20");

const from = '0x08F7506E0381f387e901c9D0552cf4052A0740a4' // DefiDollar Deployer
let contracts, config

const toWei = web3.utils.toWei

async function execute() {
    config = JSON.parse(
        fs.readFileSync(`${process.cwd()}/deployments/mainnet.json`).toString()
    ).contracts
    await finalMigration()
}

async function deploy() {
    config = JSON.parse(
        fs.readFileSync(`${process.cwd()}/deployments/kovan.json`).toString()
    ).contracts

    // 1. Set DUSD and Core address in the Comptroller
    // 2. Deploy Comptroller
    let comptroller = await Comptroller.new()
    console.log({ comptroller: comptroller.address })

    // 3. Set DFD address in ibDFD
    // 4. Deploy ibDFD
    let ibDfd = await ibDFD.new()
    console.log({ ibDfd: ibDfd.address })
    let ibDfdProxy = await ibDFDProxy.new()
    console.log({ ibDfdProxy: ibDfdProxy.address })
    await ibDfdProxy.updateImplementation(ibDfd.address)
    ibDfd = await ibDFD.at(ibDfdProxy.address)

    // 5. Set addresses (pick Comptroller address from above)
    // 6. Deploy DFDComptroller
    let dfdComptroller = await DFDComptroller.new()
    console.log({ dfdComptroller: dfdComptroller.address })

    // Set harvester address
    await dfdComptroller.setHarvester(from, true)
    await dfdComptroller.setBeneficiary(ibDfd.address)
    await ibDfd.setParams(dfdComptroller.address, 9950) // 0.5% redeem fee
    await comptroller.modifyBeneficiaries(
        [config.tokens.ibDUSD.address, dfdComptroller.address], [5000, 5000] // 50:50 revenue split
    )
    const core = await Core.at(config.base)
    await core.authorizeController(comptroller.address, { from: '0x5b5cF8620292249669e1DCC73B753d01543D6Ac7' })
    contracts = { ibDfd, dfdComptroller }
}

async function deposit() {
    contracts.dfd = await IERC20.at(config.tokens.DFD.address)
    const { ibDfd, dfd } = contracts
    const amount = toWei('100')
    await dfd.approve(ibDfd.address, amount, { from })
    await ibDfd.deposit(amount, { from })
    assert.strictEqual((await ibDfd.balanceOf(from)).toString(), amount)
    assert.strictEqual((await dfd.balanceOf(ibDfd.address)).toString(), amount)
}

async function harvest(min) {
    const dfdComptroller = await DFDComptroller.at(config.DFDComptroller)
    const { receipt } = await dfdComptroller.harvest(min, { gas: 5000000, from })
    console.log(receipt.rawLogs)
}

async function finalMigration() {
    const comptroller = await Comptroller.at(config.Comptroller)
    const ibDusdProxy = await ibDUSDProxy.at(config.tokens.ibDUSD.address)
    await comptroller.modifyBeneficiaries(
        [ibDusdProxy.address, config.DFDComptroller],
        [5000, 5000],
        { from }
    )
    let ibDusd = await ibDUSD.new()
    console.log({ ibDusd: ibDusd.address })
    await ibDusdProxy.updateImplementation(ibDusd.address, { from })
    ibDusd = await ibDUSD.at(ibDusdProxy.address)
    // await ibDusd.setRedeemFactor(9950, { from })
    await harvest(0)
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
