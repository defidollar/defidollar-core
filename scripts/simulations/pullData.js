const fs = require('fs')
const Web3 = require('web3')
const web3 = new Web3(process.env.WEB3)

const Aggregator = require('../../build/contracts/AggregatorInterface.json')
const IERC20 = require('../../build/contracts/IERC20.json')
const susdCurveABI = require('../abis/susdCurve.json')

async function execute() {
    const startBlock = 10694990
    const endBlock = 10695000
    let curveToken = new web3.eth.Contract(IERC20.abi, '0xC25a3A3b969415c80451098fa907EC722572917F')
    let curve = new web3.eth.Contract(susdCurveABI, '0xA5407eAE9Ba41422680e2e00537571bcC53efBfD')
    const eth_usd_agg = new web3.eth.Contract(Aggregator.abi, '0xf79d6afbb6da890132f9d7c355e3015f15f3406f')
    const dai_eth_agg = new web3.eth.Contract(Aggregator.abi, '0x037E8F2125bF532F3e228991e051c8A7253B642c')
    const usdc_eth_agg = new web3.eth.Contract(Aggregator.abi, '0xde54467873c3bcaa76421061036053e371721708')
    const usdt_eth_agg = new web3.eth.Contract(Aggregator.abi, '0xa874fe207DF445ff19E7482C746C4D3fD0CB9AcE')
    const susd_eth_agg = new web3.eth.Contract(Aggregator.abi, '0x6d626Ff97f0E89F6f983dE425dc5B24A18DE26Ea')
    for (let i = startBlock; i < endBlock; i++) {
        await sleep(1000)
        const data = JSON.parse(
            fs.readFileSync(`${process.cwd()}/scripts/simulations/archive-data-aug.json`).toString()
        )
        const ans = await Promise.all([
            eth_usd_agg.methods.latestAnswer().call({}, i),
            dai_eth_agg.methods.latestAnswer().call({}, i),
            usdc_eth_agg.methods.latestAnswer().call({}, i),
            usdt_eth_agg.methods.latestAnswer().call({}, i),
            susd_eth_agg.methods.latestAnswer().call({}, i),
            curveToken.methods.totalSupply().call({}, i),
            curve.methods.balances(0).call({}, i),
            curve.methods.balances(1).call({}, i),
            curve.methods.balances(2).call({}, i),
            curve.methods.balances(3).call({}, i)
        ])
        // console.log(ans)
        data[i] = ans
        fs.writeFileSync(
            `${process.cwd()}/scripts/simulations/archive-data-aug.json`,
            JSON.stringify(data, null, 2) // Indent 4 spaces
        )
    }
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

execute().then().catch(console.log)
