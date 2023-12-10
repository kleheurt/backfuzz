This is a backtest of some findings of the C4 Mute.io contest.
It was aimed at exploring Foundry's fuzzing capabilities as well as Z3, although admittedly the latter turned out not so relevant in this case.
No conclusion shall be drawn from this repo.

### Instructions
Add files to the C4 2023 Mute repo

#### Env prep
git submodule update --init
yarn
npm i --save-dev @nomicfoundation/hardhat-foundry
yarn add --dev @nomicfoundation/hardhat-foundry
// add [import "@nomicfoundation/hardhat-foundry";] to hardhat.config.ts
npx hardhat init-foundry
// in a separate terminal :
npx hardhat node --fork https://eth-mainnet.g.alchemy.com/v2/O4_LHLyl_HAAXs8o7Hu80pgmJF9Wnu12

#### Deploy
mkdir scripts
// add deploy.ts to scripts
npx hardhat run --network localhost scripts/deploy.ts
// add Test.sol to contracts
forge test -vv --fork-url localhost:8545 
// (end of procedure)

#### TODO
--> set block number for consistency