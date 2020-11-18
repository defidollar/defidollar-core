const fs = require('fs')

const ibDUSDProxy = artifacts.require("ibDUSDProxy");
const ibDUSD = artifacts.require("ibDUSD");
const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");

async function execute() {
    const config = JSON.parse(
        fs.readFileSync(`${process.cwd()}/deployments/kovan.json`).toString()
    )

    const ibDusdProxy = await ibDUSDProxy.new()
    let ibDusd = await ibDUSD.new()
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
    await coreProxy.updateImplementation(core.address, { from: '0x238238C3398e0116FAD7bBFdc323f78187135815' }) // contract owner on kovan
    core = await Core.at(coreProxy.address)
    await core.authorizeController(ibDusdProxy.address)
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
