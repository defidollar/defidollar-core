const txOptions = { maxFeePerGas: 140e9, maxPriorityFeePerGas: 15e8 }

async function main() {
    const YVaultPeak = await ethers.getContractFactory('YVaultPeak')
    const peak = await YVaultPeak.deploy(txOptions)
    console.log(peak.address)
}

main()
.then(() => process.exit(0))
.catch(error => {
    console.error(error);
    process.exit(1);
});
