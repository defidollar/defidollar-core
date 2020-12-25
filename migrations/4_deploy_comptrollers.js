const Core = artifacts.require("Core");
const DUSD = artifacts.require("DUSD");
const Reserve = artifacts.require("Reserve");
const CoreProxy = artifacts.require("CoreProxy");

const Comptroller = artifacts.require("ComptrollerTest");
const DFDComptroller = artifacts.require("DFDComptrollerTest");
const ibDUSD = artifacts.require("ibDUSD");
const ibDUSDProxy = artifacts.require("ibDUSDProxy");
const ibDFD = artifacts.require("ibDFDTest");
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

    const comptroller = await deployer.deploy(Comptroller)
    await comptroller.setParams(dusd.address, core.address)
    await core.authorizeController(comptroller.address)

    // ibDUSD
    const ibDusdProxy = await deployer.deploy(ibDUSDProxy)
    await deployer.deploy(ibDUSD)
    await ibDusdProxy.updateImplementation(ibDUSD.address)
    const ibDusd = await ibDUSD.at(ibDusdProxy.address)
    await ibDusd.setParams(DUSD.address, comptroller.address, 9950) // 0.5% redeem fee
    config.contracts.tokens.ibDUSD = { address: ibDUSDProxy.address, decimals: 18 }

    // ibDFD
    const [ dfd, ibDfdProxy, dfdComptroller ] = await Promise.all([
        Reserve.new('DefiDollar DAO', 'DFD', 18),
        deployer.deploy(ibDFDProxy),
        deployer.deploy(DFDComptroller),
        deployer.deploy(MockUniswap),
        deployer.deploy(ibDFD),
    ])
    await ibDfdProxy.updateImplementation(ibDFD.address)
    const ibDfd = await ibDFD.at(ibDfdProxy.address)
    // Essentials
    await Promise.all([
        ibDfd.setParams(dfdComptroller.address, 9950), // 0.5% redeem fee
        dfdComptroller.setBeneficiary(ibDfdProxy.address),
        dfdComptroller.setHarvester(accounts[0], true),
        comptroller.modifyBeneficiaries(
            [ibDusdProxy.address, dfdComptroller.address], [7500, 2500] // 75:25 revenue sharing
        )
    ])
    // Need to be called only while running tests locally. Will be hardcoded for network deployments.
    await Promise.all([
        ibDfd.setDFD(dfd.address),
        dfdComptroller.setParams(
            MockUniswap.address,
            dfd.address,
            dusd.address,
            comptroller.address
        )
    ])

    config.contracts.tokens.ibDFD = { address: ibDFDProxy.address, decimals: 18 }
    config.contracts.tokens.DFD = { address: dfd.address, decimals: 18 }
    utils.writeContractAddresses(config)
}
