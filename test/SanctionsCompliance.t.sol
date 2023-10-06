// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {SanctionsCompliance, ChainalysisSanctionsOracle} from "tl-stacks/utils/SanctionsCompliance.sol";

contract SanctionsComplianceTest is Test, SanctionsCompliance {

    constructor() SanctionsCompliance(address(0)) {}

    function test_init(address sender) public view {
        assert(address(oracle) == address(0));
        _isNotSanctioned(sender);
    }

    function test_updateOracle(address newOracle) public {
        vm.expectEmit(true, true, false, false);
        emit SanctionsOracleUpdated(address(0), newOracle);
        _updateSanctionsOracle(newOracle);

        assert(address(oracle) == newOracle);
    }

    function isNotSanctioned(address sender) external view {
        _isNotSanctioned(sender);
    }

    function test_isNotSanctioned(address sender, address newOracle, bool isSanctioned) public {
        vm.assume(sender != newOracle);
        vm.assume(sender != address(this));
        vm.assume(newOracle != address(this) || newOracle != address(0));
        _updateSanctionsOracle(newOracle);

        vm.mockCall(newOracle, abi.encodeWithSelector(ChainalysisSanctionsOracle.isSanctioned.selector, sender), abi.encode(isSanctioned));

        if (isSanctioned) {
            vm.expectRevert(SanctionedAddress.selector);
        }
        this.isNotSanctioned(sender);

        vm.clearMockedCalls();
    }
}