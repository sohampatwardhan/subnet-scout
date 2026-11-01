import Testing
@testable import ScannerCore

@Test func bonjourNameIsPreferred() async {
    // Requirements 5.1 and 5.2
    let resolver = CompositeHostNameResolver(
        reverseDNS: ScriptedReverseDNS(name: "router.example"),
        bonjour: ScriptedBonjour(name: "Living Room")
    )
    let names = await resolver.resolve(host: address("192.168.1.1"), timeout: .milliseconds(20))
    #expect(names.reverseDNS == "router.example")
    #expect(names.bonjour == "Living Room")
    #expect(names.displayName == "Living Room")
}

@Test func displayNameFallsBackAndCanBeEmpty() async {
    // Requirements 5.3 and 5.4
    let dnsOnly = CompositeHostNameResolver(
        reverseDNS: ScriptedReverseDNS(name: "host.example"),
        bonjour: UnavailableBonjourResolver()
    )
    let named = await dnsOnly.resolve(host: address("10.0.0.2"), timeout: .milliseconds(20))
    #expect(named.displayName == "host.example")

    let empty = CompositeHostNameResolver(
        reverseDNS: ScriptedReverseDNS(name: nil),
        bonjour: UnavailableBonjourResolver()
    )
    let missing = await empty.resolve(host: address("10.0.0.3"), timeout: .milliseconds(20))
    #expect(missing.displayName == nil)
}
