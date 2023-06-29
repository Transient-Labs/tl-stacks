# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# Clean the repo
clean:
	forge clean

# Remove modules
remove:
	rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

# Install the Modules
install:
	forge install foundry-rs/forge-std
	forge install Transient-Labs/tl-creator-contracts@2.4.0
	forge install dmfxyz/murky
	
# Update the modules
update: remove install

# Builds
build:
	forge fmt && forge clean && forge build --optimize --optimizer-runs 2000

# Tests
tests:
	forge test --gas-report -vvv