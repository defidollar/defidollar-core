const fs = require('fs')
const assert = require('assert')

const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");

const Comptroller = artifacts.require("Comptroller");
const DFDComptroller = artifacts.require("DFDComptroller");
const ibDFD = artifacts.require("ibDFD");
const ibDFDProxy = artifacts.require("ibDFDProxy");
const IERC20 = artifacts.require("IERC20");

const from = '0x08F7506E0381f387e901c9D0552cf4052A0740a4' // DefiDollar Deployer
let contracts, config

const toWei = web3.utils.toWei

async function execute() {
    await deploy()
    // await deposit()
    // await harvest()
}

async function deploy() {
    config = JSON.parse(
        fs.readFileSync(`${process.cwd()}/deployments/kovan.json`).toString()
    ).contracts

    // 1. Comptroller (Set DUSD and Core address in the contract)
    let comptroller = await Comptroller.new()
    console.log({ comptroller: comptroller.address })

    // 2. ibDFD
    let ibDfd = await ibDFD.new()
    console.log({ ibDfd: ibDfd.address })
    let ibDfdProxy = await ibDFDProxy.new()
    console.log({ ibDfdProxy: ibDfdProxy.address })
    await ibDfdProxy.updateImplementation(ibDfd.address)
    ibDfd = await ibDFD.at(ibDfdProxy.address)

    // 3. DFDComptroller (Set addresses before deployment)
    let dfdComptroller = await DFDComptroller.at('0xd4B089787f6F49d83F904394A386C6B38aCae442')
    // let dfdComptroller = await DFDComptroller.new()
    console.log({ dfdComptroller: dfdComptroller.address })
    await dfdComptroller.setHarvester('0x238238C3398e0116FAD7bBFdc323f78187135815', true)
    await dfdComptroller.setBeneficiary(ibDfd.address)
    // await ibDfd.setParams(config.tokens.DFD.address, dfdComptroller.address, 9950) // 0.5% redeem fee
    // await comptroller.modifyBeneficiaries(
    //     [config.tokens.ibDUSD.address, dfdComptroller.address], [5000, 5000] // 50:50 revenue split
    // )
    // const core = await Core.at(config.base)
    // await core.authorizeController(comptroller.address)
    // await core.authorizeController(comptroller.address, { from: '0x5b5cF8620292249669e1DCC73B753d01543D6Ac7' })

    // await dfdComptroller.setParams(
    //     '0xD8E9690eFf99E21a2de25E0b148ffaf47F47C972', // balancer pool
    //     config.tokens.DFD.address,
    //     config.tokens.DUSD.address,
    //     comptroller.address
    // )
    // contracts = { ibDfd, dfdComptroller }
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

async function harvest() {
    contracts.dusd = await IERC20.at(config.tokens.DUSD.address)
    // await contracts.dusd.transfer(contracts.dfdComptroller.address, toWei('100'), { from: '0x5b5cF8620292249669e1DCC73B753d01543D6Ac7'})
    const { receipt } = await contracts.dfdComptroller.harvest(0, { gas: 5000000 })
    console.log(receipt, receipt.rawLogs)

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
