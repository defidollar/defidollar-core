const fs = require('fs')
const assert = require('assert')

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);
const n_coins = 4

const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const YVaultPeak = artifacts.require("YVaultPeak");
const YVaultZap = artifacts.require("YVaultZap");
const Controller = artifacts.require("Controller");
const Core = artifacts.require("Core");
const DUSD = artifacts.require("DUSD");
const IERC20 = artifacts.require("IERC20");

const daiABI = require('../test/abi/dai.json');
const { contracts } = JSON.parse(fs.readFileSync(`../deployments/mainnetY.json`).toString())

// userAddress must be unlocked using --unlock ADDRESS
const userAddress = '0x3dfd23a6c5e8bbcfc9581d2e864a68feb6a076d3'

const _artifacts = {
    dai: new web3.eth.Contract(daiABI, '0x6B175474E89094C44Da98b954EedeAC495271d0F'),
    usdc: new web3.eth.Contract(daiABI, '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'),
    usdt: new web3.eth.Contract(daiABI, '0xdAC17F958D2ee523a2206206994597C13D831ec7'),
    tusd: new web3.eth.Contract(daiABI, '0x0000000000085d4780B73119b644AE5ecd22b376'),
    susdPeak: new web3.eth.Contract(CurveSusdPeak.abi, contracts.peaks.curveSUSDPool.address),
    yPeak: new web3.eth.Contract(YVaultPeak.abi, contracts.peaks.yVaultPeak.address),
    yZap: new web3.eth.Contract(YVaultZap.abi, contracts.peaks.yVaultPeak.zap),
    controller: new web3.eth.Contract(Controller.abi, contracts.peaks.yVaultPeak.controller),
    core: new web3.eth.Contract(Core.abi, contracts.base),
    dusd: new web3.eth.Contract(DUSD.abi, contracts.tokens.DUSD.address),
    yCRV: new web3.eth.Contract(DUSD.abi, contracts.tokens.yCRV.address),
    yUSD: new web3.eth.Contract(DUSD.abi, contracts.tokens.yUSD.address),
    curveToken: new web3.eth.Contract(DUSD.abi, contracts.tokens.crvPlain3andSUSD.address),
    curveSusd: new web3.eth.Contract(
        require('./abis/susdCurve.json'),
        contracts.curve.susd.swap
    ),
}

let from
const owner = '0x08F7506E0381f387e901c9D0552cf4052A0740a4'

async function execute() {
    const accounts = await web3.eth.getAccounts()
    from = accounts[0]
    const {
        dai, dusd, susdPeak, yPeak, yZap, core, yUSD
    } = _artifacts

    await printTokenBalances(_artifacts)

    // Migrate Liquidity
    console.log('Migrating liquidity...')
    await susdPeak.methods.migrate(yPeak.options.address).send({ from: owner, gas: 3000000 })
    await printTokenBalances(_artifacts)

    // Collect Protocol Income
    const before = toBN(await dusd.methods.balanceOf(owner).call())
    console.log('collectProtocolIncome...')
    await core.methods.collectProtocolIncome(owner).send({ from: owner, gas: 3000000 })
    const after = toBN(await dusd.methods.balanceOf(owner).call())
    console.log({ income: fromWei(after.sub(before)) })

    let amount = toWei('10001')
    let res, tx
    // get Dai
    tx = await dai.methods
        .transfer(from, amount)
        .send({ from: userAddress, gasLimit: 800000 });
    await printTokenBalances(_artifacts)

    // Mint DUSD
    console.log(`approving ${fromWei(amount)} dai...`)
    await dai.methods.approve(yZap.options.address, amount).send({ from })

    console.log(`yVaultZap.mint with ${fromWei(amount)} dai...`)
    tx = await yZap.methods.mint([amount, 0, 0, 0],0).send({ from, gas: 3000000 })
    console.log({ gasUsed: tx.gasUsed })
    res = await printTokenBalances(_artifacts)

    let _dusd = toWei((parseInt(res.dusd) / 2).toString())
    console.log(`redeem ${fromWei(_dusd)} in yUSD...`)
    tx = await yPeak.methods.redeemInYusd(_dusd,0).send({ from, gas: 3000000 })
    console.log({ gasUsed: tx.gasUsed })
    res = await printTokenBalances(_artifacts)

    let _yUSD = toWei((parseInt(res.yUSD) / 2).toString())
    console.log(`mint dusd with ${fromWei(_yUSD)}... yUSD`)
    await yUSD.methods.approve(yPeak.options.address, _yUSD).send({ from })
    tx = await yPeak.methods.mintWithYusd(_yUSD).send({ from, gas: 3000000 })
    console.log({ gasUsed: tx.gasUsed })
    res = await printTokenBalances(_artifacts)

    await dusd.methods.approve(yZap.options.address, toWei(res.dusd)).send({ from })
    _dusd = toWei((parseInt(res.dusd) / 2).toString())
    console.log(`redeem ${fromWei(_dusd)} dusd in all coins...`)
    tx = await yZap.methods.redeem(_dusd,[0,0,0,0]).send({ from, gas: 3000000 })
    console.log({ gasUsed: tx.gasUsed })
    res = await printTokenBalances(_artifacts)

    _dusd = res.dusd
    console.log(`redeem ${_dusd} dusd in TUSD...`)
    tx = await yZap.methods.redeemInSingleCoin(toWei(_dusd),3,0).send({ from, gas: 3000000 })
    console.log({ gasUsed: tx.gasUsed })
    res = await printTokenBalances(_artifacts)
}

async function printTokenBalances(_artifacts) {
    const {
        dai, usdc, usdt, tusd, dusd, susdPeak, core, yCRV, yUSD, yPeak, controller
    } = _artifacts
    const [ _dai, _usdc, _usdt, _tusd, _ycrv, _yusd, _dusd ] = await Promise.all([
        dai.methods.balanceOf(from).call(),
        usdc.methods.balanceOf(from).call(),
        usdt.methods.balanceOf(from).call(),
        tusd.methods.balanceOf(from).call(),
        yCRV.methods.balanceOf(from).call(),
        yUSD.methods.balanceOf(from).call(),
        dusd.methods.balanceOf(from).call()
    ])
    const res = {
        dai: fromWei(_dai),
        usdc: fromWei(toBN(_usdc).mul(toBN(1e12))),
        usdt: fromWei(toBN(_usdt).mul(toBN(1e12))),
        tusd: fromWei(_tusd),
        yCRV: fromWei(_ycrv),
        yUSD: fromWei(_yusd),
        dusd: fromWei(_dusd)
    }

    const [ _scrv, __ycrv, __yusd, totalSupply, totalSystemAssets ] = await Promise.all([
        susdPeak.methods.sCrvBalance().call(),
        yCRV.methods.balanceOf(yPeak.options.address).call(),
        yUSD.methods.balanceOf(controller.options.address).call(),
        dusd.methods.totalSupply().call(),
        core.methods.totalSystemAssets().call()
    ])
    res.system = {
        sCRV: fromWei(_scrv),
        yCRV: fromWei(__ycrv),
        yUSD: fromWei(__yusd),
        totalSupply: fromWei(totalSupply),
        totalSystemAssets: fromWei(totalSystemAssets)
    }
    console.log(res)
    return res
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
