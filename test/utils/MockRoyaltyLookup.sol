// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
import {IRoyaltyLookup} from "src/helpers/IRoyaltyLookup.sol";

/// @dev Royalty lookup that returns whatever schedule a test sets, including malformed ones
/// @dev In bps mode each amount is `value * amounts[i] / 10_000`, otherwise amounts are returned as is
contract MockRoyaltyLookup is IRoyaltyLookup {
    address payable[] internal _recipients;
    uint256[] internal _amounts;
    bool public bpsMode;
    bool public shouldRevert;

    function setSchedule(address payable[] memory recipients, uint256[] memory amounts, bool bpsMode_) external {
        _recipients = recipients;
        _amounts = amounts;
        bpsMode = bpsMode_;
    }

    function setShouldRevert(bool status) external {
        shouldRevert = status;
    }

    function getRoyalty(address, uint256, uint256 value)
        external
        view
        returns (address payable[] memory, uint256[] memory)
    {
        return _schedule(value);
    }

    function getRoyaltyView(address, uint256, uint256 value)
        external
        view
        returns (address payable[] memory, uint256[] memory)
    {
        return _schedule(value);
    }

    function _schedule(uint256 value)
        internal
        view
        returns (address payable[] memory recipients, uint256[] memory amounts)
    {
        require(!shouldRevert, "royalty lookup reverted");
        recipients = _recipients;
        amounts = _amounts;
        if (bpsMode) {
            for (uint256 i = 0; i < amounts.length; ++i) {
                amounts[i] = Math.mulDiv(value, amounts[i], 10_000);
            }
        }
    }
}
