const fs = require('fs')

const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const DUSD = artifacts.require("DUSD");
const Oracle = artifacts.require("Oracle");
const StakeLPTokenProxy = artifacts.require("StakeLPTokenProxy");
const StakeLPToken = artifacts.require("StakeLPToken");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const CurveSusdPeakProxy = artifacts.require("CurveSusdPeakProxy");

async function execute() {
    const config = JSON.parse(
        fs.readFileSync(`${process.cwd()}/deployments/mainnet-init.json`).toString()
    )
    let core = await Core.new()
    console.log({ Core: core.address })

    const coreProxy = await CoreProxy.new()
    console.log({ CoreProxy: coreProxy.address })

    // CHANGE DUSD name and Symbol
    let dusd = await DUSD.new(coreProxy.address, "DefiDollar", "DUSD", 18)
    console.log({ DUSD: dusd.address })
    config.contracts.tokens.DUSD = { address: dusd.address, decimals: 18 }

    // Oracles
    const aggregators = config.contracts.chainlink
    const oracle = await Oracle.new(
        [
            aggregators.daiEthAggregator,
            aggregators.usdcEthAggregator,
            aggregators.usdtEthAggregator,
            aggregators.susdEthAggregator,
        ],
        aggregators.ethUsdAggregator
    )
    console.log({ Oracle: oracle.address })
    config.contracts.oracle = oracle.address

    // StakeLPToken
    const stakeLPToken = await StakeLPToken.new()
    console.log({ StakeLPToken: stakeLPToken.address })

    const stakeLPTokenProxy = await StakeLPTokenProxy.new()
    console.log({ StakeLPTokenProxy: stakeLPTokenProxy.address })

    await stakeLPTokenProxy.updateAndCall(
        stakeLPToken.address,
        stakeLPToken.contract.methods.initialize(
            coreProxy.address,
            dusd.address
        ).encodeABI()
    )

    await coreProxy.updateAndCall(
        core.address,
        core.contract.methods.initialize(
            dusd.address,
            stakeLPTokenProxy.address,
            oracle.address,
            9997, // .03% redeem fee
            0 // adminFee
        ).encodeABI()
    )
    core = await Core.at(coreProxy.address)

    const peak = config.contracts.peaks.curveSUSDPool
    const tokens = []
    for (let i = 0; i < 4; i++) {
        tokens.push(config.contracts.tokens[peak.coins[i]])
    }
    await core.whitelistTokens(tokens.map(t => t.address))
    config.contracts.base = coreProxy.address
    config.contracts.valley = stakeLPTokenProxy.address

    // sUSD peak
    const accounts = await web3.eth.getAccounts()
    let iUtil = new web3.eth.Contract([{"name": "get_D", "outputs": [{"type": "uint256", "name": ""}], "inputs": [{"type": "uint256[4]", "name": "xp"}], "constant": true, "payable": false, "type": "function", "gas": 1412494}])
    iUtil = await iUtil.deploy({
        data: '0x61038956600436101561000d5761037f565b600035601c52740100000000000000000000000000000000000000006020526f7fffffffffffffffffffffffffffffff6040527fffffffffffffffffffffffffffffffff8000000000000000000000000000000060605274012a05f1fffffffffffffffffffffffffdabf41c006080527ffffffffffffffffffffffffed5fa0e000000000000000000000000000000000060a0526305eb8fa6600051141561037e5734156100ba57600080fd5b60006101405261018060006004818352015b6020610180510260040135610160526101408051610160518181830110156100f357600080fd5b808201905090508152505b81516001018083528114156100cc575b505061014051151561012657600060005260206000f3505b60006101a052610140516101c0526101906101e052610200600060ff818352015b6101c0516102205261026060006004818352015b602061026051026004013561024052610220516101c051808202821582848304141761018657600080fd5b8090509050905061024051600480820282158284830414176101a757600080fd5b8090509050905060018181830110156101bf57600080fd5b8082019050905080806101d157600080fd5b820490509050610220525b815160010180835281141561015b575b50506101c0516101a0526101e05161014051808202821582848304141761021257600080fd5b80905090509050610220516004808202821582848304141761023357600080fd5b8090509050905081818301101561024957600080fd5b808201905090506101c051808202821582848304141761026857600080fd5b809050905090506101e05160018082101561028257600080fd5b808203905090506101c05180820282158284830414176102a157600080fd5b8090509050905060056102205180820282158284830414176102c257600080fd5b809050905090508181830110156102d857600080fd5b8082019050905080806102ea57600080fd5b8204905090506101c0526101a0516101c05111156103315760016101c0516101a0518082101561031957600080fd5b8082039050905011151561032c5761036d565b61035c565b60016101a0516101c0518082101561034857600080fd5b8082039050905011151561035b5761036d565b5b5b8151600101808352811415610147575b50506101c05160005260206000f350005b5b60006000fd5b61000461038903610004600039610004610389036000f3'
    }).send({ from: accounts[0], gas: 2000000, gasPrice: '133000000000' /* 133 gwei */ })
    console.log({ iUtil: iUtil.options.address })

    let curveSusdPeak = await CurveSusdPeak.new()
    console.log({ CurveSusdPeak: curveSusdPeak.address })

    const curveSusdPeakProxy = await CurveSusdPeakProxy.new()
    console.log({ CurveSusdPeakProxy: curveSusdPeakProxy.address })

    await curveSusdPeakProxy.updateAndCall(
        curveSusdPeak.address,
        curveSusdPeak.contract.methods.initialize(
            config.contracts.curve.susd.deposit,
            config.contracts.curve.susd.swap,
            config.contracts.tokens.crvPlain3andSUSD.address,
            core.address,
            iUtil.options.address,
            config.contracts.curve.susd.gauge,
            config.contracts.curve.minter,
            tokens.map(t => t.address)
        ).encodeABI()
    )
    await core.whitelistPeak(curveSusdPeakProxy.address, [0, 1, 2, 3], web3.utils.toWei('10000000'), true)

    config.contracts.peaks.curveSUSDPool.address = curveSusdPeakProxy.address,
    fs.writeFileSync(
        `${process.cwd()}/deployments/mainnet.json`,
        JSON.stringify(config, null, 4) // Indent 4 spaces
    )
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
