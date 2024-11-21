const hre = require("hardhat");
const { SABLER, TREASURY_FEE_RECIPIENT } = require('./addresses_lookup')

async function main() {

  const deployerAddr = (await hre.ethers.getSigners())[0];

  const treasury = await hre.ethers.deployContract("Treasury", [TREASURY_FEE_RECIPIENT[hre.network.name]]);
  await treasury.waitForDeployment();
  console.log(
    `Treasury deployed to ${treasury.target}`
  );

  //verify
  if (hre.network.name !== 'localhost') {
    console.log('Waiting before verification....')
    const delay = ms => new Promise(res => setTimeout(res, ms));
    await delay(15000);

    await hre.run("verify:verify", {
      address: treasury.target,
      constructorArguments: [
        TREASURY_FEE_RECIPIENT[hre.network.name]
      ],
    });
  }

  //TODO Update recipients: Treasury
  //TODO TransferOwnership: Treasury

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
