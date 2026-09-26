// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC721} from "@openzeppelin-contracts-5.6.1/token/ERC721/ERC721.sol";

/// @dev ERC-721 that behaves normally until switched into a misbehaving mode
contract BadERC721 is ERC721 {
    enum Mode {
        NORMAL,
        REVERT_TRANSFER,
        NOOP_TRANSFER,
        LIE_OWNER_OF,
        EXPENSIVE_TRANSFER,
        BURN_GAS_TRANSFER
    }

    enum ContractOwnerMode {
        NORMAL,
        MALFORMED,
        BURN_GAS
    }

    Mode public mode;
    ContractOwnerMode public contractOwnerMode;
    address public fakeOwner;
    address public contractOwner;
    mapping(uint256 => uint256) private _junk;

    constructor(address contractOwner_) ERC721("Bad", "BAD") {
        contractOwner = contractOwner_;
    }

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    function setFakeOwner(address fakeOwner_) external {
        fakeOwner = fakeOwner_;
    }

    function setContractOwnerMode(ContractOwnerMode mode_) external {
        contractOwnerMode = mode_;
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        if (mode == Mode.REVERT_TRANSFER) revert("no transfers");
        if (mode == Mode.NOOP_TRANSFER) return;
        if (mode == Mode.BURN_GAS_TRANSFER) _burnGas();
        if (mode == Mode.EXPENSIVE_TRANSFER) {
            // simulate heavy transfer hooks (~1.5M gas of fresh storage writes)
            uint256 start = uint256(keccak256(abi.encode(from, to, tokenId)));
            for (uint256 i = 0; i < 70; ++i) {
                _junk[start + i] = i + 1;
            }
        }
        super.transferFrom(from, to, tokenId);
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        if (mode == Mode.LIE_OWNER_OF) return fakeOwner;
        return super.ownerOf(tokenId);
    }

    /// @dev ERC-2981 royalty info (zero royalty), which burns all gas in `BURN_GAS` mode
    function royaltyInfo(uint256, uint256) external view returns (address, uint256) {
        if (contractOwnerMode == ContractOwnerMode.BURN_GAS) _burnGas();
        return (contractOwner, 0);
    }

    /// @dev Ownable-style `owner` used by the creator lookup
    function owner() external view returns (address) {
        if (contractOwnerMode == ContractOwnerMode.MALFORMED) {
            assembly {
                return(0, 1)
            }
        }
        if (contractOwnerMode == ContractOwnerMode.BURN_GAS) _burnGas();
        return contractOwner;
    }

    function _burnGas() private pure {
        uint256 i;
        while (true) {
            i++;
        }
    }
}
