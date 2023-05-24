// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ITLStacks1155, Drop, ITLStacks1155Events} from "tl-stacks/ITLStacks1155.sol";
import {OwnableAccessControlUpgradeable} from "tl-sol-tools/upgradeable/access/OwnableAccessControlUpgradeable.sol";
import {ERC1155TL} from "tl-creator/core/ERC1155TL.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {AddressUpgradeable} from "openzeppelin-upgradeable/utils/AddressUpgradeable.sol";
import {StringsUpgradeable} from "openzeppelin-upgradeable/utils/StringsUpgradeable.sol";
import {MerkleProofUpgradeable} from "openzeppelin-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";

contract TLStacks1155 is ITLStacks1155, OwnableAccessControlUpgradeable, ReentrancyGuardUpgradeable {
	using SafeERC20Upgradeable for IERC20Upgradeable;
	using StringsUpgradeable for uint256;

	/*//////////////////////////////////////////////////////////////////////////
	                              Constants
	//////////////////////////////////////////////////////////////////////////*/

	bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

	/*//////////////////////////////////////////////////////////////////////////
	                   		Contract State Variables
	//////////////////////////////////////////////////////////////////////////*/

	// nft_caddr => token_id => Drop
	mapping(address => mapping(uint256 => Drop)) private drops;

	// nft_caddr => token_id => round_id => user => num_minted
	mapping(address => mapping(uint256 => mapping(uint256 => mapping(address => uint256)))) private numMinted;

	// nft_addr => token_id => round_num
	mapping(address => mapping(uint256 => uint256)) private dropRound;

	bool private paused;

	/*//////////////////////////////////////////////////////////////////////////
	                   				Constructor
	//////////////////////////////////////////////////////////////////////////*/

	constructor(bool _disableInitializer) {
		if (_disableInitializer) _disableInitializers();
	}

	/*//////////////////////////////////////////////////////////////////////////
	                   				Initializer
	//////////////////////////////////////////////////////////////////////////*/

	function initialize(address _owner) public initializer {
		__OwnableAccessControl_init(_owner);
		__ReentrancyGuard_init();
	}

	/*//////////////////////////////////////////////////////////////////////////
	                   			Owner Write Functions
	//////////////////////////////////////////////////////////////////////////*/

	function setPaused(bool _paused) external onlyRoleOrOwner(ADMIN_ROLE) {
		paused = _paused;
		emit Paused(_paused);
	}

	/*//////////////////////////////////////////////////////////////////////////
	                   			Admin Write Functions
	//////////////////////////////////////////////////////////////////////////*/

	function configureDrop(
		address _nftAddr,
        uint256 _tokenId,
        uint256 _supply,
        int256 _decayRate,
        uint256 _allowance,
        address _payoutReceiver,
        uint256 _startTime,
        uint256 _presaleDuration,
        address _currencyAddr,
        uint256 _presaleCost,
        bytes32 _presaleMerkleRoot,
        uint256 _publicDuration,
        uint256 _publicCost
	) external {
		require(!paused, "contract is paused");
		require(_startTime != 0, "start time cannot be 0");
		require(isDropAdmin(_nftAddr, msg.sender), "unauthorized");
		require(getDropPhase(_nftAddr, _tokenId) == DropPhase.NOT_CONFIGURED, "there is an existing drop");
		require(_decayRate == 0 || _presaleDuration == 0, "cant have allowlist with burn/extending");

		Drop memory drop = Drop(
			_supply,
			_decayRate,
			_allowance,
			_payoutReceiver,
			_startTime,
			_presaleDuration,
			_currencyAddr,
			_presaleCost,
			_presaleMerkleRoot,
			_publicDuration,
			_publicCost
		);

		drops[_nftAddr][_tokenId] = drop;

		emit DropConfigured(msg.sender, _nftAddr, _tokenId);
	}

	function closeDrop(address _nftAddr, uint256 _tokenId) external {
		require(!paused, "contract is paused");
		require(isDropAdmin(_nftAddr, msg.sender), "unauthorized");
		delete drops[_nftAddr][_tokenId];
		dropRound[_nftAddr][_tokenId] += 1;
		emit DropClosed(msg.sender, _nftAddr, _tokenId);
	}

	function updateDropParam(
		address _nftAddr,
		uint256 _tokenId,
		DropPhase _phase,
		DropParam _param,
		bytes32 _paramValue
	) external {
		require(isDropAdmin(_nftAddr, msg.sender), "unauthorized");

		if (_phase == DropPhase.PRESALE) {
			if (_param == DropParam.MERKLE_ROOT) {
				drops[_nftAddr][_tokenId].presaleMerkleRoot = _paramValue;
			} else if (_param == DropParam.COST) {
				drops[_nftAddr][_tokenId].presaleCost = uint256(_paramValue);
			} else if (_param == DropParam.DURATION) {
				drops[_nftAddr][_tokenId].presaleDuration = uint256(_paramValue);
			} else {
				revert("unknown param update");
			}
		} else if (_phase == DropPhase.PUBLIC_SALE) {
			if (_param == DropParam.ALLOWANCE) {
				drops[_nftAddr][_tokenId].allowance = uint256(_paramValue);
			} else if (_param == DropParam.COST) {
				drops[_nftAddr][_tokenId].publicCost = uint256(_paramValue);
			} else if (_param == DropParam.DURATION) {
				drops[_nftAddr][_tokenId].publicDuration = uint256(_paramValue);
			} else {
				revert("unknown param update");
			}
		} else if (_phase == DropPhase.NOT_CONFIGURED) {
			if (_param == DropParam.PAYOUT_ADDRESS) {
				drops[_nftAddr][_tokenId].payoutReceiver = address(uint160(uint256(_paramValue)));
			} else if (_param == DropParam.CURRENCY_ADDRESS) {
				drops[_nftAddr][_tokenId].currencyAddr = address(uint160(uint256(_paramValue)));
			} else {
				revert("unknown param update");
			}
		} else {
			revert("unknown param update");
		}

		emit DropUpdated(uint256(_phase), uint256(_param), _paramValue);
	}

	/*//////////////////////////////////////////////////////////////////////////
	                   			Public Write Functions
	//////////////////////////////////////////////////////////////////////////*/

	function mint(
		address _nftAddr,
		uint256 _tokenId,
		uint256 _numMint,
		address _receiver,
		bytes32[] calldata _proof,
		uint256 _allowlistAllocation
	) external payable nonReentrant {
		require(!paused, "contract is paused");

		Drop memory drop = drops[_nftAddr][_tokenId];

		require(drop.supply != 0, "no supply left");

		DropPhase dropPhase = getDropPhase(_nftAddr, _tokenId);

		if (dropPhase == DropPhase.PRESALE) {
			bytes32 leaf = keccak256(abi.encodePacked(_receiver, _allowlistAllocation));
			bytes32 root = drop.presaleMerkleRoot;

			require(MerkleProofUpgradeable.verifyCalldata(_proof, root, leaf), "unable to verify proof");

			uint256 mintNum = _determineMintNum(_nftAddr, _tokenId, _receiver, _numMint, _allowlistAllocation, drop.currencyAddr, drop.presaleCost);
			
			_settleUp(_nftAddr, _tokenId, _receiver, drop.currencyAddr, mintNum, drop.presaleCost);

			emit Purchase(msg.sender, _receiver, _nftAddr, _tokenId, mintNum, drop.presaleCost, true);
		} else if (dropPhase == DropPhase.PUBLIC_SALE) {
			uint256 mintNum = _determineMintNum(_nftAddr, _tokenId, _receiver, _numMint, drop.allowance, drop.currencyAddr, drop.publicCost);

			uint256 adjust = mintNum * uint256(drop.decayRate < 0 ? drop.decayRate * -1 : drop.decayRate);

			if (drop.decayRate < 0) {
				if (adjust > drop.publicDuration) {
					drops[_nftAddr][_tokenId].publicDuration = 0;
				} else {
					drops[_nftAddr][_tokenId].publicDuration -= adjust;
				}
			} else if (drop.decayRate > 0) {
				drops[_nftAddr][_tokenId].publicDuration += adjust;
			}

			_settleUp(_nftAddr, _tokenId, _receiver, drop.currencyAddr, mintNum, drop.publicCost);

			emit Purchase(msg.sender, _receiver, _nftAddr, _tokenId, mintNum, drop.publicCost, false);
		} else {
			revert("you shall not mint");
		}
	}

	/*//////////////////////////////////////////////////////////////////////////
	                   			External Read Functions
	//////////////////////////////////////////////////////////////////////////*/

	function getDrop(address _nftAddr, uint256 _tokenId) external view returns (Drop memory) {
		return drops[_nftAddr][_tokenId];
	}

	function getNumMinted(address _nftAddr, uint256 _tokenId, address _user) external view returns (uint256) {
		return numMinted[_nftAddr][_tokenId][dropRound[_nftAddr][_tokenId]][_user];
	}

	function getDropPhase(address _nftAddr, uint256 _tokenId) public view returns (DropPhase) {
		Drop memory drop = drops[_nftAddr][_tokenId];

		if (drop.startTime == 0) return DropPhase.NOT_CONFIGURED;
		if (drop.supply == 0) return DropPhase.ENDED;
		if (block.timestamp < drop.startTime) return DropPhase.BEFORE_SALE;
		if (drop.startTime <= block.timestamp && block.timestamp < drop.startTime + drop.presaleDuration) return DropPhase.PRESALE;
		if (drop.startTime <= block.timestamp && block.timestamp < drop.startTime + drop.presaleDuration + drop.publicDuration) return DropPhase.PUBLIC_SALE;

		return DropPhase.ENDED;
	}

	function isPaused() external view returns (bool) {
		return paused;
	}

	/*//////////////////////////////////////////////////////////////////////////
	                   			Internal Read Functions
	//////////////////////////////////////////////////////////////////////////*/

	function isDropAdmin(address _nftAddr, address _operator) internal view returns (bool) {
		return OwnableAccessControlUpgradeable(_nftAddr).owner() == _operator || 
			OwnableAccessControlUpgradeable(_nftAddr).hasRole(ADMIN_ROLE, _operator);
	}

	function _determineMintNum(
		address _nftAddr,
		uint256 _tokenId,
		address _receiver,
		uint256 _numMint,
		uint256 _allowance,
		address _currencyAddr,
		uint256 _cost
	) internal returns (uint256) {
		Drop memory drop = drops[_nftAddr][_tokenId];
		uint256 currDropRound = dropRound[_nftAddr][_tokenId];
		uint256 currMinted = numMinted[_nftAddr][currDropRound][_tokenId][_receiver];

		uint256 mintNum = _numMint;

		require(currMinted != _allowance, "already hit mint allowance");

		if (currMinted + _numMint > _allowance) {
			mintNum = _allowance - currMinted;
		}

		if (mintNum > drop.supply) {
			mintNum = drop.supply;
		}

		_checkAmountAndTransfer(_currencyAddr, mintNum * _cost);

		drops[_nftAddr][_tokenId].supply -= mintNum;
		numMinted[_nftAddr][currDropRound][_tokenId][_receiver] += mintNum;

		return mintNum;
	}

	/*//////////////////////////////////////////////////////////////////////////
	                   			Internal Write Functions
	//////////////////////////////////////////////////////////////////////////*/

	function _checkAmountAndTransfer(address _currencyAddress, uint256 _amount) internal {
	    if (_currencyAddress == address(0)) {
	    	require(msg.value >= _amount, "not enough funds sent");
	    	return;
	    }

		require(msg.value == 0, "msg.value should be 0 when not using eth");

		IERC20Upgradeable erc20 = IERC20Upgradeable(_currencyAddress);
		uint256 balanceBefore = erc20.balanceOf(address(this));

		erc20.safeTransferFrom(msg.sender, address(this), _amount);

		uint256 balanceAfter = erc20.balanceOf(address(this));

		require(balanceAfter - balanceBefore == _amount, "not enough funds sent");
  	}

  	function _settleUp(
    	address _nftAddr,
    	uint256 _tokenId,
    	address _receiver,
    	address _currencyAddr,
    	uint256 _mintNum,
    	uint256 _cost
  	) internal {
  		IERC20Upgradeable erc20 = IERC20Upgradeable(_currencyAddr);
  		ERC1155TL erc1155 = ERC1155TL(_nftAddr);
  		Drop memory drop = drops[_nftAddr][_tokenId];

  		if (_currencyAddr == address(0)) {
  			if (msg.value > _mintNum * _cost) {
  				AddressUpgradeable.sendValue(payable(msg.sender), msg.value - (_mintNum * _cost));
  			}

  			AddressUpgradeable.sendValue(payable(drop.payoutReceiver), _mintNum * _cost);
  		} else {
  			if (erc20.balanceOf(address(this)) > _mintNum * _cost) {
  				erc20.safeTransferFrom(address(this), msg.sender, msg.value - (_mintNum * _cost));
  			}

  			erc20.safeTransferFrom(address(this), _receiver, _mintNum * _cost);
  		}

  		address[] memory addrs = new address[](1);
  		addrs[0] = _receiver;

  		uint256[] memory amts = new uint256[](1);
  		amts[0] = _mintNum;

  		erc1155.externalMint(_tokenId, addrs, amts);
  	}
}
