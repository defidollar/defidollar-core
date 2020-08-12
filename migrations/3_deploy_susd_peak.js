const fs = require('fs')

const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const CurveSusdPeakProxy = artifacts.require("CurveSusdPeakProxy");

const MockSusdToken = artifacts.require("MockSusdToken");

const utils = require('./utils')
const susdCurveABI = require('../scripts/abis/susdCurve.json')
const susdCurveDepositABI = require('../scripts/abis/susdCurveDeposit.json')

module.exports = async function(deployer, network, accounts) {
    const config = utils.getContractAddresses()
    const peak = {
        coins: ["DAI", "USDC", "USDT", "sUSD"],
        native: "crvPlain3andSUSD"
    }

    const coreProxy = await CoreProxy.deployed()
    const core = await Core.at(coreProxy.address)
    const tokens = []
    for (let i = 0; i < 4; i++) {
        tokens.push(config.contracts.tokens[peak.coins[i]].address)
    }

    // Deploy Mock sUSD pool
    const curveToken = await deployer.deploy(MockSusdToken)
    config.contracts.tokens['crvPlain3andSUSD'] = {
        address: curveToken.address,
        decimals: 18,
        name: "Curve.fi DAI/USDC/USDT/sUSD",
        peak: "curveSUSDPool"
    }

    let curve = new web3.eth.Contract(susdCurveABI)
    curve = await curve.deploy({
        data: fs.readFileSync(`${process.cwd()}/vyper/curveSusd`).toString().slice(0, -1),
        arguments: [
            tokens,
            tokens,
            curveToken.address,
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
            curveToken.address
        ]
    }).send({ from: accounts[0], gas: 10000000 })

    let iUtil = new web3.eth.Contract([{"name": "get_D", "outputs": [{"type": "uint256", "name": ""}], "inputs": [{"type": "uint256[4]", "name": "xp"}], "constant": true, "payable": false, "type": "function", "gas": 1412494}])
    iUtil = await iUtil.deploy({
        data: '0x61038956600436101561000d5761037f565b600035601c52740100000000000000000000000000000000000000006020526f7fffffffffffffffffffffffffffffff6040527fffffffffffffffffffffffffffffffff8000000000000000000000000000000060605274012a05f1fffffffffffffffffffffffffdabf41c006080527ffffffffffffffffffffffffed5fa0e000000000000000000000000000000000060a0526305eb8fa6600051141561037e5734156100ba57600080fd5b60006101405261018060006004818352015b6020610180510260040135610160526101408051610160518181830110156100f357600080fd5b808201905090508152505b81516001018083528114156100cc575b505061014051151561012657600060005260206000f3505b60006101a052610140516101c0526101906101e052610200600060ff818352015b6101c0516102205261026060006004818352015b602061026051026004013561024052610220516101c051808202821582848304141761018657600080fd5b8090509050905061024051600480820282158284830414176101a757600080fd5b8090509050905060018181830110156101bf57600080fd5b8082019050905080806101d157600080fd5b820490509050610220525b815160010180835281141561015b575b50506101c0516101a0526101e05161014051808202821582848304141761021257600080fd5b80905090509050610220516004808202821582848304141761023357600080fd5b8090509050905081818301101561024957600080fd5b808201905090506101c051808202821582848304141761026857600080fd5b809050905090506101e05160018082101561028257600080fd5b808203905090506101c05180820282158284830414176102a157600080fd5b8090509050905060056102205180820282158284830414176102c257600080fd5b809050905090508181830110156102d857600080fd5b8082019050905080806102ea57600080fd5b8204905090506101c0526101a0516101c05111156103315760016101c0516101a0518082101561031957600080fd5b8082039050905011151561032c5761036d565b61035c565b60016101a0516101c0518082101561034857600080fd5b8082039050905011151561035b5761036d565b5b5b8151600101808352811415610147575b50506101c05160005260206000f350005b5b60006000fd5b61000461038903610004600039610004610389036000f3'
    }).send({ from: accounts[0], gas: 10000000 })

    await deployer.deploy(CurveSusdPeak)
    const curveSusdPeakProxy = await deployer.deploy(CurveSusdPeakProxy)
    const curveSusdPeak = await CurveSusdPeak.at(CurveSusdPeakProxy.address)
    await curveSusdPeakProxy.updateAndCall(
        CurveSusdPeak.address,
        curveSusdPeak.contract.methods.initialize(
            curveDeposit.options.address,
            curve.options.address,
            curveToken.address,
            core.address,
            iUtil.options.address,
            tokens
        ).encodeABI()
    )
    await core.whitelistPeak(curveSusdPeakProxy.address, [0, 1, 2, 3], true)

    peak.address = CurveSusdPeakProxy.address,
    config.contracts.peaks = config.contracts.peaks || {}
    config.contracts.peaks['curveSUSDPool'] = peak
    utils.writeContractAddresses(config)
}
