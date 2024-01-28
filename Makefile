# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

################################################################ Modules ################################################################
remove:
	rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules

install:
	forge install foundry-rs/forge-std --no-commit
	forge install Transient-Labs/tl-creator-contracts@3.0.2 --no-commit
	forge install dmfxyz/murky --no-commit
	git add .
	git commit

update: remove install
	
################################################################ Build ################################################################
clean:
	forge fmt && forge clean

build:
	forge build --evm-version paris

clean_build: clean build

################################################################ Tests ################################################################
default_test:
	forge test

gas_test:
	forge test --gas-report

fuzz_test:
	forge test --fuzz-runs 10000

################################################################ TLAuctionHouse Deployments ################################################################
deploy_TLAuctionHouse_sepolia: build
	forge script script/Deploy.s.sol:DeployERC721TL --evm-version paris --rpc-url sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/erc-721/ERC721TL.sol:ERC721TL --chain sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLAuctionHouse_arbitrum_sepolia: build
	forge script script/Deploy.s.sol:DeployERC721TL --evm-version paris --rpc-url arbitrum_sepolia --ledger --sender ${SENDER} --broadcast --skip-simulation
	forge verify-contract $$(cat out.txt) src/erc-721/ERC721TL.sol:ERC721TL --verifier-url https://api-sepolia.arbiscan.io/api --etherscan-api-key ${ARBISCAN_KEY} --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLAuctionHouse_base_sepolia: build
	forge script script/Deploy.s.sol:DeployERC721TL --evm-version paris --rpc-url base_sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/erc-721/ERC721TL.sol:ERC721TL --verifier-url https://api-sepolia.basescan.org/api --etherscan-api-key ${BASESCAN_KEY}  --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLAuctionHouse_mainnet: build
	forge script script/Deploy.s.sol:DeployERC721TL --evm-version paris --rpc-url mainnet --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/erc-721/ERC721TL.sol:ERC721TL --chain mainnet --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLAuctionHouse_arbitrum_one: build
	forge script script/Deploy.s.sol:DeployERC721TL --evm-version paris --rpc-url arbitrum --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/erc-721/ERC721TL.sol:ERC721TL --chain arbitrum --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLAuctionHouse_base: build
	forge script script/Deploy.s.sol:DeployERC721TL --evm-version paris --rpc-url base --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/erc-721/ERC721TL.sol:ERC721TL --chain base --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh