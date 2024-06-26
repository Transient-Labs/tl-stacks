# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

################################################################ Modules ################################################################
remove:
	rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules

install:
	forge install foundry-rs/forge-std --no-commit
	forge install Transient-Labs/tl-creator-contracts@3.0.3 --no-commit
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

docs: clean_build
	forge doc --build

################################################################ Tests ################################################################
default_test:
	forge test

gas_test:
	forge test --gas-report

coverage_test:
	forge coverage

fuzz_test:
	forge test --fuzz-runs 10000

################################################################ TLAuctionHouse Deployments ################################################################
deploy_TLAuctionHouse_sepolia: build
	forge script script/Deploy.s.sol:DeployTLAuctionHouse --evm-version paris --rpc-url sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --chain sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLAuctionHouse_arbitrum_sepolia: build
	forge script script/Deploy.s.sol:DeployTLAuctionHouse --evm-version paris --rpc-url arbitrum_sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --chain arbitrum-sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLAuctionHouse_base_sepolia: build
	forge script script/Deploy.s.sol:DeployTLAuctionHouse --evm-version paris --rpc-url base_sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --chain base-sepolia  --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLAuctionHouse_mainnet: build
	forge script script/Deploy.s.sol:DeployTLAuctionHouse --evm-version paris --rpc-url mainnet --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --chain mainnet --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLAuctionHouse_arbitrum_one: build
	forge script script/Deploy.s.sol:DeployTLAuctionHouse --evm-version paris --rpc-url arbitrum --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --chain arbitrum --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLAuctionHouse_base: build
	forge script script/Deploy.s.sol:DeployTLAuctionHouse --evm-version paris --rpc-url base --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --chain base --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

################################################################ TLStacks721 Deployments ################################################################
deploy_TLStacks721_sepolia: build
	forge script script/Deploy.s.sol:DeployTLStacks721 --evm-version paris --rpc-url sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks721.sol:TLStacks721 --chain sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLStacks721_arbitrum_sepolia: build
	forge script script/Deploy.s.sol:DeployTLStacks721 --evm-version paris --rpc-url arbitrum_sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks721.sol:TLStacks721 --chain arbitrum-sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLStacks721_base_sepolia: build
	forge script script/Deploy.s.sol:DeployTLStacks721 --evm-version paris --rpc-url base_sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks721.sol:TLStacks721 --chain base-sepolia  --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLStacks721_mainnet: build
	forge script script/Deploy.s.sol:DeployTLStacks721 --evm-version paris --rpc-url mainnet --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks721.sol:TLStacks721 --chain mainnet --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLStacks721_arbitrum_one: build
	forge script script/Deploy.s.sol:DeployTLStacks721 --evm-version paris --rpc-url arbitrum --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks721.sol:TLStacks721 --chain arbitrum --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLStacks721_base: build
	forge script script/Deploy.s.sol:DeployTLStacks721 --evm-version paris --rpc-url base --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks721.sol:TLStacks721 --chain base --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

################################################################ TLStacks1155 Deployments ################################################################
deploy_TLStacks1155_sepolia: build
	# forge script script/Deploy.s.sol:DeployTLStacks1155 --evm-version paris --rpc-url sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks1155.sol:TLStacks1155 --chain sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLStacks1155_arbitrum_sepolia: build
	forge script script/Deploy.s.sol:DeployTLStacks1155 --evm-version paris --rpc-url arbitrum_sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks1155.sol:TLStacks1155 --chain arbitrum-sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLStacks1155_base_sepolia: build
	forge script script/Deploy.s.sol:DeployTLStacks1155 --evm-version paris --rpc-url base_sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks1155.sol:TLStacks1155 --chain base-sepolia  --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLStacks1155_mainnet: build
	forge script script/Deploy.s.sol:DeployTLStacks1155 --evm-version paris --rpc-url mainnet --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks1155.sol:TLStacks1155 --chain mainnet --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLStacks1155_arbitrum_one: build
	forge script script/Deploy.s.sol:DeployTLStacks1155 --evm-version paris --rpc-url arbitrum --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks1155.sol:TLStacks1155 --chain arbitrum --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLStacks1155_base: build
	forge script script/Deploy.s.sol:DeployTLStacks1155 --evm-version paris --rpc-url base --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks1155.sol:TLStacks1155 --chain base --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh