async function main() {
  const vaultAddress = '0x77dc33dC0278d21398cb9b16CbFf99c1B712a87A';
  const Vault = await ethers.getContractFactory('ReaperVaultV2');
  const vault = Vault.attach(vaultAddress);

  const strategyAddress = '0x78c436272fA7d3CFEf1cEE0B3c14d9f5C4856647';
  const strategyAllocation = 50;
  await vault.addStrategy(strategyAddress, strategyAllocation);
  console.log('Strategy added!');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
