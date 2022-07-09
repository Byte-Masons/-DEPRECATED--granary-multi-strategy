async function main() {
  const vaultAddress = '0xa6313302B3CeFF2727f19AAA30d7240d5B3CD9CD';
  const Vault = await ethers.getContractFactory('ReaperVaultV2');
  const vault = Vault.attach(vaultAddress);

  const strategyAddress = '0x303DF25f303376ebb84D0F2F0139E7b0C7F3Bf43';
  const strategyAllocation = 1000;
  await vault.addStrategy(strategyAddress, strategyAllocation);
  console.log('Strategy added!');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
