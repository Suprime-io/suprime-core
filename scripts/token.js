const hre = require("hardhat");
const { MAIN} = require('./addresses_lookup')

async function main() {
  const token = await hre.ethers.deployContract("SuprimeToken", [MAIN[hre.network.name]]);
  await token.waitForDeployment();
  console.log(
    `SuprimeToken with OWNER address  ${MAIN[hre.network.name]} deployed to ${token.target}`
  );

  //verify
  if (hre.network.name !== 'localhost') {
    console.log('Waiting before verification....')
    const delay = ms => new Promise(res => setTimeout(res, ms));
    await delay(10000);

    await hre.run("verify:verify", {
      address: token.target,
      constructorArguments: [
        MAIN[hre.network.name]
      ],
    });
  }

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
