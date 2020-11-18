const fs = require('fs')

const ibDUSDProxy = artifacts.require("ibDUSDProxy");
const ibDUSD = artifacts.require("ibDUSD");
const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const DUSD = artifacts.require("DUSD");

const toWei = web3.utils.toWei

const owner = '0x5b5cF8620292249669e1DCC73B753d01543D6Ac7'

async function execute() {
    const config = JSON.parse(
        fs.readFileSync(`${process.cwd()}/deployments/mainnet.json`).toString()
        // fs.readFileSync(`${process.cwd()}/deployments/kovan.json`).toString()
    )

    let ibDusd = await ibDUSD.new()
    const ibDusdProxy = await ibDUSDProxy.new()
    console.log({ ibDusdProxy: ibDusdProxy.address, ibDusd: ibDusd.address })
    await ibDusdProxy.updateImplementation(ibDusd.address)
    ibDusd = await ibDUSD.at(ibDusdProxy.address)
    await ibDusd.setParams(
        config.contracts.tokens.DUSD.address,
        config.contracts.base,
        9950 // 0.5% redeem fee
    )

    let core = await Core.new()
    const coreProxy = await CoreProxy.at(config.contracts.base)
    await coreProxy.updateImplementation(core.address, { from: owner })
    core = await Core.at(coreProxy.address)
    await core.authorizeController(ibDusdProxy.address, { from: owner })

    // console.log((await core.earned()).toString())
    // const harvest = await core.harvest({ from: owner })
    // console.log(JSON.stringify(harvest.receipt.rawLogs, null, 2))
    // const dusd = await DUSD.at(config.contracts.tokens.DUSD.address)
    // await dusd.approve(ibDusdProxy.address, toWei('100'), { from: '0x5b5cF8620292249669e1DCC73B753d01543D6Ac7' })
    // const deposit = await ibDusd.deposit(toWei('100'), { from: '0x5b5cF8620292249669e1DCC73B753d01543D6Ac7' })
    // console.log(JSON.stringify(deposit.receipt.rawLogs, null, 2))
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
