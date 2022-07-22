async function main() {
  const vaultAddress = '0x17D099fc623bd06CFE4861d874704Af184773c75';
  const Vault = await ethers.getContractFactory('ReaperVaultV2');
  const vault = Vault.attach(vaultAddress);

  const strategyAddress = '0xDA4E5116DF14bD08dEe3E65eAD2B6809b62d4042';
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
