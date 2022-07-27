const txOptions = { maxFeePerGas: 40e9, maxPriorityFeePerGas: 1e9 }

async function main() {
    // const YVaultPeak = await ethers.getContractFactory('YVaultPeak')
    // const peak = await YVaultPeak.deploy(txOptions)
    // console.log(peak.address)
    const Core = await ethers.getContractFactory('Core')
    const core = await Core.deploy(txOptions)
    console.log(core.address)
}

main()
.then(() => process.exit(0))
.catch(error => {
    console.error(error);
    process.exit(1);
});
