// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC721} from "@openzeppelin-contracts-5.6.1/token/ERC721/ERC721.sol";
import {ERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/ERC20.sol";
import {TLAuctionHouse} from "src/TLAuctionHouse.sol";
import {ListingConfig} from "src/utils/TLAuctionHouseUtils.sol";

interface IAuditHook {
    function onTransfer() external;
}

/// @dev Models privileged NFT recovery and transfer callbacks; deliberately unrestricted test fixture.
contract AuditRecoveryNFT is ERC721 {
    bool public skipTransfer;
    address public hook;
    constructor() ERC721("Recovery", "REC") {}

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }

    function recover(address to, uint256 id) external {
        _transfer(ownerOf(id), to, id);
    }

    function setSkipTransfer(bool value) external {
        skipTransfer = value;
    }

    function setHook(address value) external {
        hook = value;
    }

    function transferFrom(address from, address to, uint256 id) public override {
        if (skipTransfer) return;
        super.transferFrom(from, to, id);
        if (hook != address(0)) IAuditHook(hook).onTransfer();
    }
}

contract AuditHookCurrency is ERC20 {
    address public hook;

    constructor(address holder) ERC20("Hook", "HOOK") {
        _mint(holder, 100 ether);
    }

    function setHook(address value) external {
        hook = value;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (hook != address(0)) IAuditHook(hook).onTransfer();
    }
}

contract AuditCallbackSeller {
    TLAuctionHouse public auction;
    address public nft;
    address public payout;

    constructor(TLAuctionHouse auction_, address nft_, address payout_) {
        auction = auction_;
        nft = nft_;
        payout = payout_;
    }

    function onTransfer() public {
        auction.updatePayoutReceiver(nft, 1, payout);
    }

    receive() external payable {
        onTransfer();
    }

    function list(ListingConfig memory cfg) external {
        ERC721(nft).setApprovalForAll(address(auction), true);
        auction.list(cfg);
    }

    function bid(uint256 id) external payable {
        auction.bid{value: msg.value}(nft, 1, address(0), msg.value, id);
    }
}

/// @dev Passive receiver has no method to initiate its own funds claim.
contract AuditPassivePayee {
    bool public reject = true;
    TLAuctionHouse public auction;
    bool public tryReentry;
    bool public reentrySucceeded;

    constructor(TLAuctionHouse auction_) {
        auction = auction_;
    }

    function setReject(bool value) external {
        reject = value;
    }

    function setTryReentry() external {
        tryReentry = true;
    }

    receive() external payable {
        require(!reject, "reject");
        if (tryReentry) {
            (reentrySucceeded,) =
                address(auction).call(abi.encodeCall(auction.retryPayout, (address(this), address(0))));
        }
    }
}

/// @dev ERC-721 without ERC-2981 whose non-reverting fallback answers `royaltyInfo` with a configurable response:
///      0 = empty return data, 1 = 32 bytes, 2 = recipient with dirty upper bits, 3 = valid (0xBEEF, value / 10)
contract MalformedRoyaltyNFT is ERC721 {
    uint8 public mode;

    constructor() ERC721("Malformed", "MAL") {}

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }

    function setMode(uint8 value) external {
        mode = value;
    }

    fallback() external {
        uint8 m = mode;
        assembly {
            switch m
            case 0 { return(0, 0) }
            case 1 {
                mstore(0, 0xBEEF)
                return(0, 0x20)
            }
            case 2 {
                mstore(0, not(0))
                mstore(0x20, div(calldataload(0x24), 10))
                return(0, 0x40)
            }
            default {
                mstore(0, 0xBEEF)
                mstore(0x20, div(calldataload(0x24), 10))
                return(0, 0x40)
            }
        }
    }
}
