# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# Clean the repo
clean:
	forge clean

# Remove the modules
remove:
	rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

# Install the modules
install:
	forge install foundry-rs/forge-std
	forge install OpenZeppelin/openzeppelin-contracts@v4.8.3
	forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v4.8.3

# Updatee the modules
update: remove install

# Builds
build:
	forge fmt && forge clean && forge build --optimize --optimizer-runs 2000

# Tests
tests:
	forge test --gas-report -vvv
