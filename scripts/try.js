const assert = require('assert')
// const utils = require('./utils.js');

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);
const n_coins = 4
let _artifacts

const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const daiABI = require('../test/abi/dai.json');

// userAddress must be unlocked using --unlock ADDRESS
const userAddress = '0x07bb41df8c1d275c4259cdd0dbf0189d6a9a5f32'

const dai = new web3.eth.Contract(daiABI, '0x6B175474E89094C44Da98b954EedeAC495271d0F');
const susdPeak = new web3.eth.Contract(CurveSusdPeak.abi, '');

async function execute() {
    const accounts = await web3.eth.getAccounts()
    const alice = accounts[0]
    const amount = toWei('100')

    // get Dai
    let daiBalance = await dai.methods.balanceOf(alice).call();
    console.log({ daiBalance })
    await dai.methods
        .transfer(alice, amount)
        .send({ from: userAddress, gasLimit: 800000 });
    daiBalance = await dai.methods.balanceOf(alice).call();
    console.log({ daiBalance })

    // Mint DUSD
    await dai.methods.approve(susdPeak.options.address, amount)
    const dusdAmount = await susdPeak.methods.mint([amount, 0, 0, 0]).call()
    console.log({ dusdAmount: dusdAmount.toString() })
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
