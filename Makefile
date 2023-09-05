# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# Clean the repo
clean:
	forge clean

# Remove modules
remove:
	rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib

# Install the Modules
install:
	forge install foundry-rs/forge-std --no-commit --no-git
	forge install OpenZeppelin/openzeppelin-contracts@v4.8.3 --no-commit --no-git
	forge install Transient-Labs/tl-sol-tools@2.3.0 --no-commit --no-git
	forge install Transient-Labs/tl-creator-contracts@2.6.2 --no-commit --no-git
	forge install dmfxyz/murky --no-commit --no-git
	git add .
	git commit -m "installed modules"
	
# Update the modules
update: remove install

# Builds
build:
	forge fmt && forge clean && forge build --optimize --optimizer-runs 2000

# Tests
tests:
	forge test --gas-report -vvv