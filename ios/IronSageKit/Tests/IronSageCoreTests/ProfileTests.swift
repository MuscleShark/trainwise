import Foundation
import Testing

@testable import IronSageCore

@Test func birthdaysRoundTripAsCalendarDates() {
    var profile = Profile(birthday: "2001-04-30")
    let date = profile.birthdayDate
    #expect(date == Date(timeIntervalSince1970: 988_588_800))

    profile.birthdayDate = Date(timeIntervalSince1970: 946_684_800 + 3600)
    #expect(profile.birthday == "2000-01-01")
    profile.birthdayDate = nil
    #expect(profile.birthday == nil)
}

@Test func heightCanBeEnteredInInches() {
    var profile = Profile(heightCm: 180)
    #expect(profile.heightInches == 70.9)
    profile.heightInches = 70
    #expect(profile.heightCm == 177.8)
}
