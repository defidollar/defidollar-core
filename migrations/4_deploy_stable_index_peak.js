const fs = require("fs")

// Artifacts
const Core = artifacts.require("Core")
const CoreProxy = artifacts.require("CoreProxy")
const StableIndexPeak = artifacts.require("StableIndexPeak")
const StableIndexPeakProxy = artifacts.require("StableIndexPeakProxy")
const StableIndexZap = artifacts.require("StableIndexZap")
const MockAToken = artifacts.require("MockAToken")

const utils = require('./utils')

const toWei = web3.utils.toWei

module.exports = async function(deployer, network, accounts) {
    const admin = accounts[0]

    const coreProxy = await CoreProxy.deployed()
    const core = await Core.at(coreProxy.address)

    const aDAI = await MockAToken.new('Aave Dai', 'aDai')
    const aSUSD = await MockAToken.new('Aave sUSD', 'aSUSD')

    // CRP deployment
    const crpFactoryArtifact = JSON.parse(fs.readFileSync('./configurable-rights-pool/build/contracts/CRPFactory.json').toString())
    let crpFactory = new web3.eth.Contract(crpFactoryArtifact.abi, crpFactoryArtifact.networks['420'].address)
    const params = {
        poolTokenSymbol: 'DSI',
        poolTokenName: 'Decentralized Stable Index',
        constituentTokens: [aDAI.address, aSUSD.address],
        tokenBalances: [toWei('60'), toWei('40')],
        tokenWeights: [toWei('15'), toWei('10')],
        swapFee: toWei('0.0004') // 0.04%
    }
    const permissions = {
        canPauseSwapping: true,
        canChangeSwapFee: true,
        canChangeWeights: true,
        canAddRemoveTokens: true,
        canWhitelistLPs: false,
        canChangeCap: true
    }
    const newCrp = await crpFactory.methods.newCrp(
        JSON.parse(fs.readFileSync('./configurable-rights-pool/build/contracts/BFactory.json').toString()).networks['420'].address,
        params,
        permissions
    ).send({ from: accounts[0], gas: 6000000 })

    const crpArtifact = JSON.parse(fs.readFileSync('./configurable-rights-pool/build/contracts/ConfigurableRightsPool.json').toString())
    const crp = new web3.eth.Contract(crpArtifact.abi, newCrp.events.LogNewCrp.returnValues.pool)
    await Promise.all([
        aDAI.mint(admin, params.tokenBalances[0]),
        aDAI.approve(crp.options.address, params.tokenBalances[0]),
        aSUSD.mint(admin, params.tokenBalances[1]),
        aSUSD.approve(crp.options.address, params.tokenBalances[1])
    ])
    // bPool deployment
    await crp.methods.createPool(toWei('100') /* initial supply */).send({ from: accounts[0], gas: 6000000 })

    const stableIndexPeakProxy = await deployer.deploy(StableIndexPeakProxy)
    await deployer.deploy(StableIndexPeak)
    const stableIndexPeak = await StableIndexPeak.at(stableIndexPeakProxy.address)

    // To-do @Brad
    await stableIndexPeakProxy.updateAndCall(
        StableIndexPeak.address,
        stableIndexPeak.contract.methods.initialize(
            crp.options.address,
            // crp bPool address
        ).encodeABI()
    )
    console.log(crp)
    const bPool = await crp.methods.bPool.call()
    console.log(bPool.options.address)
    

    //await stableIndexPeakProxy.updateAndCall(
        //StableIndexPeak.address,
        //stableIndexPeak.contract.methods.initialize(
            //crp.options.address,
            //bPool.options.address
        //).encodeABI()
    //)

    await core.whitelistPeak(stableIndexPeakProxy.address, [0, 3] /* Dai, sUSD */, toWei('1000'), false)

    // For later
    // const stableIndexPeak = await StableIndexPeak.at(stableIndexPeakProxy.address)

    // Write config to file - For later
    // const config = utils.getContractAddresses()
    // const peak = 'StableIndexPeak'
    // config.contracts.peaks[peak] = {
    //     coins: ["DAI", "sUSD"],
    //     native: ["aDAI", "aSUSD"],
    //     address: stableIndexPeakProxy.address
    // }
    // config.contracts.tokens['aDai'] = {
    //     address: aDAI.address,
    //     decimals: 18,
    //     name: "Aave Dai",
    //     peak
    // }
    // config.contracts.tokens['aSUSD'] = {
    //     address: aSUSD.address,
    //     decimals: 18,
    //     name: "Aave aSUSD",
    //     peak
    // }
    // utils.writeContractAddresses(config)
}

