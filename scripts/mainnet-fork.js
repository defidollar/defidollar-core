const fs = require('fs')
const assert = require('assert')
// const utils = require('../test/utils.js');

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);
const n_coins = 4

const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const Core = artifacts.require("Core");
const DUSD = artifacts.require("DUSD");

const daiABI = require('../test/abi/dai.json');
const { contracts } = JSON.parse(fs.readFileSync(`../deployments/mainnet-fork.json`).toString())

// userAddress must be unlocked using --unlock ADDRESS
const userAddress = '0x07bb41df8c1d275c4259cdd0dbf0189d6a9a5f32'

const _artifacts = {
    dai: new web3.eth.Contract(daiABI, '0x6B175474E89094C44Da98b954EedeAC495271d0F'),
    usdc: new web3.eth.Contract(daiABI, '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'),
    usdt: new web3.eth.Contract(daiABI, '0xdAC17F958D2ee523a2206206994597C13D831ec7'),
    susd: new web3.eth.Contract(daiABI, '0x57Ab1ec28D129707052df4dF418D58a2D46d5f51'),
    susdPeak: new web3.eth.Contract(CurveSusdPeak.abi, contracts.peaks.curveSUSDPool.address),
    core: new web3.eth.Contract(Core.abi, contracts.base),
    dusd: new web3.eth.Contract(DUSD.abi, contracts.tokens.DUSD.address),
    curveToken: new web3.eth.Contract(DUSD.abi, contracts.tokens.crvPlain3andSUSD.address),
    curveSusd: new web3.eth.Contract(
        require('./abis/susdCurve.json'),
        contracts.curve.susd.swap
    ),
}

let from

async function execute() {
    const accounts = await web3.eth.getAccounts()
    from = accounts[0]

    let amount = toWei('10000')
    let res, tx
    const {
        dai, susdPeak, curveSusd
    } = _artifacts

    // get Dai
    tx = await dai.methods
        .transfer(from, amount)
        .send({ from: userAddress, gasLimit: 800000 });
    console.log({ gasUsed: tx.gasUsed })
    await printTokenBalances(_artifacts)

    // Mint DUSD
    amount = toWei('100')
    console.log(`approving ${fromWei(amount)} dai...`)
    await dai.methods.approve(susdPeak.options.address, amount).send({ from })

    console.log(`minting dusd with ${fromWei(amount)} dai...`)
    tx = await susdPeak.methods.mint([amount, 0, 0, 0],0).send({ from, gas: 1000000 })
    console.log({ gasUsed: tx.gasUsed })
    res = await printTokenBalances(_artifacts)

    amount = toBN(toWei(res.dusd)).div(toBN(2)).toString()
    console.log(`redeemInScrv with ${fromWei(amount)} dusd...`)
    tx = await susdPeak.methods.redeemInScrv(amount,0).send({ from, gas: 1000000 })
    console.log({ gasUsed: tx.gasUsed })
    res = await printTokenBalances(_artifacts)

    // tx = await curveSusd.methods.remove_liquidity(toWei(res.scrv), [0,0,0,0]).send({ from, gas: 2000000 })
    // console.log({ gasUsed: tx.gasUsed })
    // res = await printTokenBalances(_artifacts)

    amount = toBN(toWei(res.scrv)).div(toBN(2)).toString()
    console.log(`mintWithScrv with ${fromWei(amount)} scrv...`)
    await curveToken.methods.approve(susdPeak.options.address, amount).send({ from })
    tx = await susdPeak.methods.mintWithScrv(amount,0).send({ from, gas: 1000000 })
    console.log({ gasUsed: tx.gasUsed })
    res = await printTokenBalances(_artifacts)

    amount = toBN(toWei(res.dusd)).div(toBN(2)).toString()
    console.log(`redeemInSingleCoin with ${fromWei(amount)} dusd...`)
    tx = await susdPeak.methods.redeemInSingleCoin(amount,2/* usdt */,0).send({ from, gas: 1000000 })
    console.log({ gasUsed: tx.gasUsed })
    res = await printTokenBalances(_artifacts)

    amount = toWei(res.dusd)
    console.log(`redeem with ${fromWei(amount)} dusd...`)
    console.log(await susdPeak.methods.calcRedeem(amount).call({ from, gas: 2000000 }))
    // reverts on forked ganacha
    tx = await susdPeak.methods.redeem(amount,[0,0,0,0]).call({ from, gas: 9000000 })
    console.log(tx)
    // tx = await susdPeak.methods.redeem(amount,[0,0,0,0]).send({ from, gas: 9000000 })
    // console.log({ gasUsed: tx.gasUsed })
    // await printTokenBalances(_artifacts)
}

async function printTokenBalances(_artifacts) {
    const {
        dai, usdc, usdt, susd, dusd, curveToken, susdPeak, core
    } = _artifacts
    const res = {
        dai: fromWei(await dai.methods.balanceOf(from).call()),
        usdc: fromWei(toBN(await usdc.methods.balanceOf(from).call()).mul(toBN(1e12))),
        usdt: fromWei(toBN(await usdt.methods.balanceOf(from).call()).mul(toBN(1e12))),
        susd: fromWei(await susd.methods.balanceOf(from).call()),
        scrv: fromWei(await curveToken.methods.balanceOf(from).call()),
        dusd: fromWei(await dusd.methods.balanceOf(from).call()),
        system: {
            scrv: fromWei(await curveToken.methods.balanceOf(susdPeak.options.address).call()),
            totalSupply: fromWei(await dusd.methods.totalSupply().call()),
            totalAssets: fromWei(await core.methods.totalAssets().call()),
            totalSystemAssets: fromWei(await core.methods.totalSystemAssets().call())
        }
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
