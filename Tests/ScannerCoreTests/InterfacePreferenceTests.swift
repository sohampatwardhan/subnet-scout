import Testing
@testable import ScannerCore

@Test func preferredInterfaceIsPrivateNonLoopback() {
    // Requirement 1.4
    let interfaces = [
        NetworkInterface(name: "lo", address: address("127.0.0.1"), prefixLength: 8, isLoopback: true),
        NetworkInterface(name: "en0", address: address("192.168.1.20"), prefixLength: 24, isLoopback: false),
        NetworkInterface(name: "utun", address: address("1.2.3.4"), prefixLength: 32, isLoopback: false),
    ]
    let selection = CurrentSubnet.select(from: interfaces)
    #expect(selection.targetText == "192.168.1.0/24")
    #expect(selection.message == nil)
}

@Test func missingInterfaceLeavesNoTarget() {
    // Requirement 1.5
    let selection = CurrentSubnet.select(from: [
        NetworkInterface(name: "lo", address: address("127.0.0.1"), prefixLength: 8, isLoopback: true),
    ])
    #expect(selection.targetText == nil)
    #expect(selection.message == "No local IPv4 subnet detected.")
}

@Test func systemListingDoesNotCrash() {
    let listing = SystemInterfaceListing().interfaces()
    #expect(listing.allSatisfy { $0.address.description.contains(".") })
}
