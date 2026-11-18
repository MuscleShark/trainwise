import Foundation
import Testing

@testable import IronSageCore

@Test func aSharedLinkIsTheWebAddressWithTheCode() {
    #expect(SharedPlanLink.url(code: "k3T9xQ2mLa").absoluteString == "https://ironsage.app/p/k3T9xQ2mLa")
}

@Test(arguments: [
    "https://ironsage.app/p/k3T9xQ2mLa",
    "  https://ironsage.app/p/k3T9xQ2mLa\n",
    "ironsage.app/p/k3T9xQ2mLa",
    "https://www.ironsage.app/p/k3T9xQ2mLa",
    "Try my plan https://ironsage.app/p/k3T9xQ2mLa it's good",
    "看看我的计划：https://ironsage.app/p/k3T9xQ2mLa",
    "ironsage://shared/k3T9xQ2mLa",
    "k3T9xQ2mLa",
])
func theCodeIsFoundInWhatWasPasted(_ text: String) {
    #expect(SharedPlanLink.code(in: text) == "k3T9xQ2mLa")
}

@Test(arguments: ["", "hello", "https://example.com/p/k3T9xQ2mLa", "k3T9-xQ2mLa", "https://ironsage.app/privacy"])
func textWithoutALinkHasNoCode(_ text: String) {
    #expect(SharedPlanLink.code(in: text) == nil)
}

@Test func theAppOpensItsLinksAndNoOthers() {
    #expect(SharedPlanLink.code(of: URL(string: "https://ironsage.app/p/k3T9xQ2mLa")!) == "k3T9xQ2mLa")
    #expect(SharedPlanLink.code(of: URL(string: "ironsage://shared/k3T9xQ2mLa")!) == "k3T9xQ2mLa")
    #expect(SharedPlanLink.code(of: URL(string: "https://ironsage.app/privacy")!) == nil)
    #expect(SharedPlanLink.code(of: URL(string: "https://example.com/p/k3T9xQ2mLa")!) == nil)
    #expect(SharedPlanLink.code(of: URL(string: "ironsage://today")!) == nil)
    #expect(SharedPlanLink.code(of: URL(string: "ironsage://start-up-next")!) == nil)
}
