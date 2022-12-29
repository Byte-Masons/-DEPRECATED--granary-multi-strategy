async function main() {
  const vaultAddress = '0xE4a54b6a175Cf3F6D7A5e8Ab7544C3e6e364dBF9';
  const Vault = await ethers.getContractFactory('ReaperVaultV2');
  const vault = Vault.attach(vaultAddress);

  const strategyAddress = '0xc99911Af7594964C399f605840d1107E98602aD4';
  const strategyAllocation = 9000;
  await vault.addStrategy(strategyAddress, 450, strategyAllocation);
  console.log('Strategy added!');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
