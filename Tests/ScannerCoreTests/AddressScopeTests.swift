import Testing
@testable import ScannerCore

@Test func privateAndLocalPrefixesAreLocal() {
    // Requirement 3.1
    let local = ["10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.4.4", "127.0.0.1", "169.254.8.8"]
    for dotted in local {
        #expect(AddressScope.classify(address(dotted)) == .privateLocal)
    }
}

@Test func otherAddressesArePublic() {
    // Requirement 3.1
    let publicAddresses = ["8.8.8.8", "172.32.0.1", "100.64.0.1", "192.0.2.1", "11.0.0.1"]
    for dotted in publicAddresses {
        #expect(AddressScope.classify(address(dotted)) == .publicRange)
    }
}

@Test func privatePlanDoesNotRequireAcknowledgement() throws {
    // Requirement 3.1
    let plan = try ScanPlanner.plan(request("192.168.1.0/30", ports: "80"))
    #expect(plan.hosts.count == 4)
}
