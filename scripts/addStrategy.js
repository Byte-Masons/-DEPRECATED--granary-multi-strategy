async function main() {
  const vaultAddress = '0xa6313302B3CeFF2727f19AAA30d7240d5B3CD9CD';
  const Vault = await ethers.getContractFactory('ReaperVaultV2');
  const vault = Vault.attach(vaultAddress);

  const strategyAddress = '0x6613B0772F9841A0a21e14B7ce422760F7f22CAB';
  const strategyAllocation = 9000;
  await vault.addStrategy(strategyAddress, strategyAllocation);
  console.log('Strategy added!');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
