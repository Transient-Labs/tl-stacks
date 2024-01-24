# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# Clean the repo
clean:
	forge clean

# Remove modules
remove:
	rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules

# Install the Modules
install:
	forge install foundry-rs/forge-std --no-commit
	forge install Transient-Labs/tl-sol-tools@3.1.1 --no-commit
	forge install dmfxyz/murky --no-commit
	git add .
	git commit
	
# Update the modules
update: remove install

# Builds
build:
	forge fmt && forge clean && forge build

# Tests
default_test:
	forge test

gas_test:
	forge test --gas-report

fuzz_test:
	forge test --fuzz-runs 10000

# Goerli Deployments
deploy_stacks_721_goerli:
	forge script script/Deployments.s.sol:Deployments --rpc-url goerli --ledger --sender ${SENDER} --broadcast --verify --sig "deployTLStacks721()"

deploy_stacks_1155_goerli:
	forge script script/Deployments.s.sol:Deployments --rpc-url goerli --ledger --sender ${SENDER} --broadcast --verify --sig "deployTLStacks1155()"

deploy_auction_house_goerli:
	forge script script/Deployments.s.sol:Deployments --rpc-url goerli --ledger --sender ${SENDER} --broadcast --verify --sig "deployTLAuctionHouse()"

# Arbitrum Goerli Deployments
deploy_stacks_721_arb_goerli:
	forge script script/Deployments.s.sol:Deployments --rpc-url arb_goerli --ledger --sender ${SENDER} --broadcast --verify --sig "deployTLStacks721()"

deploy_stacks_1155_arb_goerli:
	forge script script/Deployments.s.sol:Deployments --rpc-url arb_goerli --ledger --sender ${SENDER} --broadcast --verify --sig "deployTLStacks1155()"

deploy_auction_house_arb_goerli:
	forge script script/Deployments.s.sol:Deployments --rpc-url arb_goerli --ledger --sender ${SENDER} --broadcast --verify --sig "deployTLAuctionHouse()"

# Ethereum Deployments
deploy_stacks_721_eth:
	forge script script/Deployments.s.sol:Deployments --rpc-url mainnet --ledger --sender ${SENDER} --broadcast --verify --sig "deployTLStacks721()"

deploy_stacks_1155_eth:
	forge script script/Deployments.s.sol:Deployments --rpc-url mainnet --ledger --sender ${SENDER} --broadcast --verify --sig "deployTLStacks1155()"

deploy_auction_house_eth:
	forge script script/Deployments.s.sol:Deployments --rpc-url mainnet --ledger --sender ${SENDER} --broadcast --verify --sig "deployTLAuctionHouse()"

# Arbitrum Deployments
deploy_stacks_721_arb:
	forge script script/Deployments.s.sol:Deployments --rpc-url arb --ledger --sender ${SENDER} --broadcast --verify --sig "deployTLStacks721()"

deploy_stacks_1155_arb:
	forge script script/Deployments.s.sol:Deployments --rpc-url arb --ledger --sender ${SENDER} --broadcast --verify --sig "deployTLStacks1155()"

deploy_auction_house_arb:
	forge script script/Deployments.s.sol:Deployments --rpc-url arb --ledger --sender ${SENDER} --broadcast --verify --sig "deployTLAuctionHouse()"