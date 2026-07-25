import Testing
@testable import ThreeWood

struct PhoneNumberTests {
    @Test func tenDigitUSNumbersGetCountryCode() {
        #expect(PhoneNumber.normalize("4085551234") == "+14085551234")
        #expect(PhoneNumber.normalize("(408) 555-1234") == "+14085551234")
        #expect(PhoneNumber.normalize("408.555.1234") == "+14085551234")
        #expect(PhoneNumber.normalize("408-555-1234") == "+14085551234")
    }

    @Test func elevenDigitWithLeadingOne() {
        #expect(PhoneNumber.normalize("1-408-555-1234") == "+14085551234")
        #expect(PhoneNumber.normalize("14085551234") == "+14085551234")
    }

    @Test func plusPrefixedInternationalPassesThrough() {
        #expect(PhoneNumber.normalize("+14085551234") == "+14085551234")
        #expect(PhoneNumber.normalize("+1 (408) 555-1234") == "+14085551234")
        #expect(PhoneNumber.normalize("+44 20 7946 0958") == "+442079460958")
    }

    @Test func junkIsRejected() {
        #expect(PhoneNumber.normalize("") == nil)
        #expect(PhoneNumber.normalize("555-1234") == nil)          // 7 digits, no area code
        #expect(PhoneNumber.normalize("not a number") == nil)
        #expect(PhoneNumber.normalize("+123") == nil)              // too short
        #expect(PhoneNumber.normalize("22345678901") == nil)       // 11 digits, not US
        #expect(PhoneNumber.normalize("+1234567890123456") == nil) // 16 digits, too long
    }

    @Test func displayFormatsUSNumbers() {
        #expect(PhoneNumber.display("+14085551234") == "(408) 555-1234")
        #expect(PhoneNumber.display("+442079460958") == "+442079460958")
    }
}
