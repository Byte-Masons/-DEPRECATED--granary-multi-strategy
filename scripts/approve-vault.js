async function main() {
  const vaultAddress = '0xa6313302B3CeFF2727f19AAA30d7240d5B3CD9CD';
  const ERC20 = await ethers.getContractFactory('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');
  const wantAddress = '0x21be370d5312f44cb42ce377bc9b8a0cef1a4c83';
  const want = await ERC20.attach(wantAddress);
  await want.approve(vaultAddress, ethers.utils.parseEther('1000'));
  console.log('want approved');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
