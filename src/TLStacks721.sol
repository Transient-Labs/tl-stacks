// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ITLStacks721, Drop, ITLStacks721Events} from "tl-stacks/ITLStacks721.sol";
import {OwnableAccessControlUpgradeable} from "tl-sol-tools/upgradeable/access/OwnableAccessControlUpgradeable.sol";
import {ERC721TL} from "tl-creator/core/ERC721TL.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {AddressUpgradeable} from "openzeppelin-upgradeable/utils/AddressUpgradeable.sol";
import {StringsUpgradeable} from "openzeppelin-upgradeable/utils/StringsUpgradeable.sol";
import {MerkleProofUpgradeable} from "openzeppelin-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";

contract TLStacks721 is ITLStacks721, OwnableAccessControlUpgradeable, ReentrancyGuardUpgradeable {
	using SafeERC20Upgradeable for IERC20Upgradeable;
	using StringsUpgradeable for uint256;

	/*//////////////////////////////////////////////////////////////////////////
	                              Constants
	//////////////////////////////////////////////////////////////////////////*/

	bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

	/*//////////////////////////////////////////////////////////////////////////
	                   		Contract State Variables
	//////////////////////////////////////////////////////////////////////////*/

	// nft_caddr => Drop
	mapping(address => Drop) private drops;

	// nft_caddr => round_id => user => num_minted
	mapping(address => mapping(uint256 => mapping(address => uint256))) private numMinted;

	// nft_addr => round_num
	mapping(address => uint256) private dropRound;

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
        string calldata _baseUri,
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
		require(getDropPhase(_nftAddr) == DropPhase.NOT_CONFIGURED, "there is an existing drop");
		require(_decayRate == 0 || _presaleDuration == 0, "cant have allowlist with burn/extending");

		Drop memory drop = Drop(
			_baseUri,
			_supply,
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

		drops[_nftAddr] = drop;

		emit DropConfigured(msg.sender, _nftAddr);
	}

	function closeDrop(address _nftAddr) external {
		require(!paused, "contract is paused");
		require(isDropAdmin(_nftAddr, msg.sender), "unauthorized");
		delete drops[_nftAddr];
		dropRound[_nftAddr] += 1;
		emit DropClosed(msg.sender, _nftAddr);
	}

	function updateDropParam(
		address _nftAddr,
		DropPhase _phase,
		DropParam _param,
		bytes32 _paramValue
	) external {
		require(isDropAdmin(_nftAddr, msg.sender), "unauthorized");

		if (_phase == DropPhase.PRESALE) {
			if (_param == DropParam.MERKLE_ROOT) {
				drops[_nftAddr].presaleMerkleRoot = _paramValue;
			} else if (_param == DropParam.COST) {
				drops[_nftAddr].presaleCost = uint256(_paramValue);
			} else if (_param == DropParam.DURATION) {
				drops[_nftAddr].presaleDuration = uint256(_paramValue);
			} else {
				revert("unknown param update");
			}
		} else if (_phase == DropPhase.PUBLIC_SALE) {
			if (_param == DropParam.ALLOWANCE) {
				drops[_nftAddr].allowance = uint256(_paramValue);
			} else if (_param == DropParam.COST) {
				drops[_nftAddr].publicCost = uint256(_paramValue);
			} else if (_param == DropParam.DURATION) {
				drops[_nftAddr].publicDuration = uint256(_paramValue);
			} else {
				revert("unknown param update");
			}
		} else if (_phase == DropPhase.NOT_CONFIGURED) {
			if (_param == DropParam.PAYOUT_ADDRESS) {
				drops[_nftAddr].payoutReceiver = address(uint160(uint256(_paramValue)));
			} else if (_param == DropParam.CURRENCY_ADDRESS) {
				drops[_nftAddr].currencyAddr = address(uint160(uint256(_paramValue)));
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
		uint256 _numMint,
		address _receiver,
		bytes32[] calldata _proof,
		uint256 _allowlistAllocation
	) external payable nonReentrant {
		require(!paused, "contract is paused");

		Drop memory drop = drops[_nftAddr];

		require(drop.supply != 0, "no supply left");

		DropPhase dropPhase = getDropPhase(_nftAddr);

		if (dropPhase == DropPhase.PRESALE) {
			bytes32 leaf = keccak256(abi.encodePacked(_receiver, _allowlistAllocation));
			bytes32 root = drop.presaleMerkleRoot;

			require(MerkleProofUpgradeable.verifyCalldata(_proof, root, leaf), "unable to verify proof");

			uint256 mintNum = _determineMintNum(_nftAddr, _receiver, _numMint, _allowlistAllocation, drop.currencyAddr, drop.presaleCost);
			
			_settleUp(_nftAddr, _receiver, drop.currencyAddr, mintNum, drop.presaleCost);

			emit Purchase(msg.sender, _receiver, _nftAddr, mintNum, drop.presaleCost, true);
		} else if (dropPhase == DropPhase.PUBLIC_SALE) {
			uint256 mintNum = _determineMintNum(_nftAddr, _receiver, _numMint, drop.allowance, drop.currencyAddr, drop.publicCost);

			uint256 adjust = mintNum * uint256(drop.decayRate < 0 ? drop.decayRate * -1 : drop.decayRate);

			if (drop.decayRate < 0) {
				if (adjust > drop.publicDuration) {
					drops[_nftAddr].publicDuration = 0;
				} else {
					drops[_nftAddr].publicDuration -= adjust;
				}
			} else if (drop.decayRate > 0) {
				drops[_nftAddr].publicDuration += adjust;
			}

			_settleUp(_nftAddr, _receiver, drop.currencyAddr, mintNum, drop.publicCost);

			emit Purchase(msg.sender, _receiver, _nftAddr, mintNum, drop.publicCost, false);
		} else {
			revert("you shall not mint");
		}
	}

	/*//////////////////////////////////////////////////////////////////////////
	                   			External Read Functions
	//////////////////////////////////////////////////////////////////////////*/

	function getDrop(address _nftAddr) external view returns (Drop memory) {
		return drops[_nftAddr];
	}

	function getNumMinted(address _nftAddr, address _user) external view returns (uint256) {
		return numMinted[_nftAddr][dropRound[_nftAddr]][_user];
	}

	function getDropPhase(address _nftAddr) public view returns (DropPhase) {
		Drop memory drop = drops[_nftAddr];

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
		address _receiver,
		uint256 _numMint,
		uint256 _allowance,
		address _currencyAddr,
		uint256 _cost
	) internal returns (uint256) {
		Drop memory drop = drops[_nftAddr];
		uint256 currDropRound = dropRound[_nftAddr];
		uint256 currMinted = numMinted[_nftAddr][currDropRound][_receiver];

		uint256 mintNum = _numMint;

		require(currMinted != _allowance, "already hit mint allowance");

		if (currMinted + _numMint > _allowance) {
			mintNum = _allowance - currMinted;
		}

		if (mintNum > drop.supply) {
			mintNum = drop.supply;
		}

		_checkAmountAndTransfer(_currencyAddr, mintNum * _cost);

		drops[_nftAddr].supply -= mintNum;
		numMinted[_nftAddr][currDropRound][_receiver] += mintNum;

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
    	address _receiver,
    	address _currencyAddr,
    	uint256 _mintNum,
    	uint256 _cost
  	) internal {
  		IERC20Upgradeable erc20 = IERC20Upgradeable(_currencyAddr);
  		ERC721TL erc721 = ERC721TL(_nftAddr);
  		Drop memory drop = drops[_nftAddr];

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

  		uint256 tokenId = drop.initialSupply - drop.supply - _mintNum;

  		for (uint256 i = tokenId; i < tokenId + _mintNum; i++) {
  			erc721.externalMint(_receiver, string(abi.encode(drop.baseUri, i.toString())));
  		}
  	}
}
