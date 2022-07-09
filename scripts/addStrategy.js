async function main() {
  const vaultAddress = '0x58C60B6dF933Ff5615890dDdDCdD280bad53f1C1';
  const Vault = await ethers.getContractFactory('ReaperVaultV2');
  const vault = Vault.attach(vaultAddress);

  const strategyAddress = '0x3c399524c9BC775E1BdF7f3aA3F9851ea8140527';
  const strategyAllocation = 200;
  await vault.addStrategy(strategyAddress, strategyAllocation);
  console.log('Strategy added!');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
