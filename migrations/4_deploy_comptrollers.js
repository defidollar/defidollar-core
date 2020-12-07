const Core = artifacts.require("Core");
const DUSD = artifacts.require("DUSD");
const Reserve = artifacts.require("Reserve");
const CoreProxy = artifacts.require("CoreProxy");

const Comptroller = artifacts.require("Comptroller");
const DFDComptroller = artifacts.require("DFDComptrollerTest");
const ibDUSD = artifacts.require("ibDUSD");
const ibDUSDProxy = artifacts.require("ibDUSDProxy");
const ibDFD = artifacts.require("ibDFD");
const ibDFDProxy = artifacts.require("ibDFDProxy");
const MockUniswap = artifacts.require("MockUniswap");

const utils = require('./utils')

module.exports = async function(deployer, network, accounts) {
    const config = utils.getContractAddresses()
    const [ coreProxy, dusd ] = await Promise.all([
        CoreProxy.deployed(),
        DUSD.deployed(),
    ])
    const core = await Core.at(coreProxy.address)

    const comptroller = await deployer.deploy(Comptroller, dusd.address, core.address)
    await core.authorizeController(comptroller.address)

    // ibDUSD
    const ibDusdProxy = await deployer.deploy(ibDUSDProxy)
    await deployer.deploy(ibDUSD)
    await ibDusdProxy.updateImplementation(ibDUSD.address)
    const ibDusd = await ibDUSD.at(ibDusdProxy.address)
    await ibDusd.setParams(DUSD.address, comptroller.address, 9950) // 0.5% redeem fee
    await comptroller.addBeneficiary(ibDusdProxy.address, [10000])
    config.contracts.tokens.ibDUSD = { address: ibDUSDProxy.address, decimals: 18 }

    // ibDFD
    const [ dfd, ibDfdProxy, ibDfdComptroller ] = await Promise.all([
        Reserve.new('DefiDollar DAO', 'DFD', 18),
        deployer.deploy(ibDFDProxy),
        deployer.deploy(DFDComptroller),
        deployer.deploy(MockUniswap),
        deployer.deploy(ibDFD),
    ])
    await ibDfdProxy.updateImplementation(ibDFD.address)
    const ibDfd = await ibDUSD.at(ibDfdProxy.address)
    await Promise.all([
        ibDfd.setParams(dfd.address, ibDfdComptroller.address, 9950), // 0.5% redeem fee
        ibDfdComptroller.setParams(
            MockUniswap.address,
            ibDfdProxy.address,
            dfd.address,
            dusd.address,
            comptroller.address
        ),
        comptroller.addBeneficiary(ibDfdComptroller.address, [7500, 2500]) // 75:25 revenue sharing
    ])

    config.contracts.tokens.ibDFD = { address: ibDFDProxy.address, decimals: 18 }
    config.contracts.tokens.DFD = { address: dfd.address, decimals: 18 }
    utils.writeContractAddresses(config)
}
