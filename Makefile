# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

#####################################
### FORMAT & LINT
#####################################
fmt:
	forge fmt

slither:
	poetry run slither .

install-pre-commit:
	poetry run pre-commit install

#####################################
### MODULES
#####################################
remove:
	rm -rf dependencies

install:
	forge soldeer install
	
#####################################
### BUILD
#####################################
clean:
	forge fmt && forge clean

build:
	forge build --evm-version paris

clean_build: clean build

docs: clean_build
	forge doc --build

#####################################
### TESTS
#####################################
tests: build
	forge test

gas-tests: build
	forge test --gas-report

cov-tests: build
	forge coverage --no-match-coverage "(script|test|Foo|Bar)"

fuzz-tests: build
	forge test --fuzz-runs 10000

#####################################
### CreatorLookup
#####################################
deploy_CreatorLookup_testnets: build
	forge script --evm-version paris --ledger --sender ${SENDER} --broadcast --sig "run(string,bool)" script/Deploy.s.sol:Deploy "CreatorLookup.sol:CreatorLookup" true
	forge verify-contract $$(cat out.txt) src/helpers/CreatorLookup.sol:CreatorLookup --chain sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	forge verify-contract $$(cat out.txt) src/helpers/CreatorLookup.sol:CreatorLookup --chain arbitrum-sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	forge verify-contract $$(cat out.txt) src/helpers/CreatorLookup.sol:CreatorLookup --chain base-sepolia  --watch --constructor-args ${CONSTRUCTOR_ARGS}
	forge verify-contract $$(cat out.txt) src/helpers/CreatorLookup.sol:CreatorLookup --verifier blockscout --verifier-url https://explorer-sepolia.shape.network/api --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

#####################################
### RoyaltyLookup
#####################################
deploy_RoyaltyLookup_testnets: build
	forge script --evm-version paris --ledger --sender ${SENDER} --broadcast --sig "run(string,bool)" script/Deploy.s.sol:Deploy "RoyaltyLookup.sol:RoyaltyLookup" true
	forge verify-contract $$(cat out.txt) src/helpers/RoyaltyLookup.sol:RoyaltyLookup --chain sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	forge verify-contract $$(cat out.txt) src/helpers/RoyaltyLookup.sol:RoyaltyLookup --chain arbitrum-sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	forge verify-contract $$(cat out.txt) src/helpers/RoyaltyLookup.sol:RoyaltyLookup --chain base-sepolia  --watch --constructor-args ${CONSTRUCTOR_ARGS}
	forge verify-contract $$(cat out.txt) src/helpers/RoyaltyLookup.sol:RoyaltyLookup --verifier blockscout --verifier-url https://explorer-sepolia.shape.network/api --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

#####################################
### TLAuctionHouse
#####################################
deploy_TLAuctionHouse_testnets: build
	forge script --evm-version paris --ledger --sender ${SENDER} --broadcast --sig "run(string,bool)" script/Deploy.s.sol:Deploy "TLAuctionHouse.sol:TLAuctionHouse" true
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --chain sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --chain arbitrum-sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --chain base-sepolia  --watch --constructor-args ${CONSTRUCTOR_ARGS}
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --verifier blockscout --verifier-url https://explorer-sepolia.shape.network/api --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

deploy_TLAuctionHouse_mainnets: build
	forge script --evm-version paris --ledger --sender ${SENDER} --broadcast --sig "run(string,bool)" script/Deploy.s.sol:Deploy "TLAuctionHouse.sol:TLAuctionHouse" false
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --chain mainnet --watch --constructor-args ${CONSTRUCTOR_ARGS}
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --chain arbitrum --watch --constructor-args ${CONSTRUCTOR_ARGS}
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --chain base  --watch --constructor-args ${CONSTRUCTOR_ARGS}
	forge verify-contract $$(cat out.txt) src/TLAuctionHouse.sol:TLAuctionHouse --verifier blockscout --verifier-url https://shapescan.xyz/api --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

#####################################
### TLStacks721
#####################################
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

deploy_TLStacks721_shape_sepolia: build
	forge script script/Deploy.s.sol:DeployTLStacks721 --evm-version paris --rpc-url shape_sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks721.sol:TLStacks721  --verifier blockscout --verifier-url https://explorer-sepolia.shape.network/api --watch --constructor-args ${CONSTRUCTOR_ARGS}
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

deploy_TLStacks721_shape: build
	forge script script/Deploy.s.sol:DeployTLStacks721 --evm-version paris --rpc-url shape --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks721.sol:TLStacks721  --verifier blockscout --verifier-url https://shapescan.xyz/api --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh

#####################################
### TLStacks1155
#####################################
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

deploy_TLStacks1155_shape_sepolia: build
	forge script script/Deploy.s.sol:DeployTLStacks1155 --evm-version paris --rpc-url shape_sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks1155.sol:TLStacks1155 --verifier blockscout --verifier-url https://explorer-sepolia.shape.network/api  --watch --constructor-args ${CONSTRUCTOR_ARGS}
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

deploy_TLStacks1155_shape: build
	forge script script/Deploy.s.sol:DeployTLStacks1155 --evm-version paris --rpc-url shape --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/TLStacks1155.sol:TLStacks1155 --verifier blockscout --verifier-url https://shapescan.xyz/api  --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh