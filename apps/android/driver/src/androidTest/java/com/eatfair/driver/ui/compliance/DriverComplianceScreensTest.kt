package com.eatfair.driver.ui.compliance

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.eatfair.driver.ui.theme.DollorDriverTheme
import org.junit.Rule
import org.junit.Test

/**
 * UI Tests for Driver Compliance Screens
 * P2P Matchmaking Platform Compliance
 */
class DriverComplianceScreensTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    // =========================================================================
    // INSURANCE DISCLOSURE SCREEN TESTS
    // =========================================================================

    @Test
    fun insuranceScreen_displaysP2PInfo() {
        composeTestRule.setContent {
            DollorDriverTheme {
                InsuranceDisclosureScreen(onContinue = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Insurance Disclosure").assertIsDisplayed()
        composeTestRule.onNodeWithText("Your personal insurance responsibility").assertIsDisplayed()
        composeTestRule.onNodeWithText("How Dollor Works").assertIsDisplayed()
        composeTestRule.onNodeWithText("Your Insurance Responsibility").assertIsDisplayed()
    }

    @Test
    fun insuranceScreen_continueButtonDisabledByDefault() {
        composeTestRule.setContent {
            DollorDriverTheme {
                InsuranceDisclosureScreen(onContinue = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Continue").assertIsNotEnabled()
    }

    @Test
    fun insuranceScreen_continueButtonEnabledAfterAcknowledgment() {
        var continueClicked = false

        composeTestRule.setContent {
            DollorDriverTheme {
                InsuranceDisclosureScreen(onContinue = { continueClicked = true }, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("I understand the insurance requirements", substring = true).performClick()
        composeTestRule.onNodeWithText("Continue").assertIsEnabled()
        composeTestRule.onNodeWithText("Continue").performClick()
        assert(continueClicked)
    }

    @Test
    fun insuranceScreen_displaysImportantNotice() {
        composeTestRule.setContent {
            DollorDriverTheme {
                InsuranceDisclosureScreen(onContinue = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Important Notice").assertIsDisplayed()
        composeTestRule.onNodeWithText("peer-to-peer rideshare marketplace", substring = true).assertIsDisplayed()
    }

    // =========================================================================
    // BACKGROUND CHECK CONSENT SCREEN TESTS
    // =========================================================================

    @Test
    fun backgroundCheckScreen_displaysAllVerificationItems() {
        composeTestRule.setContent {
            DollorDriverTheme {
                BackgroundCheckConsentScreen(onContinue = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Background Check Authorization").assertIsDisplayed()
        composeTestRule.onNodeWithText("What We Verify").assertIsDisplayed()
        composeTestRule.onNodeWithText("Identity Verification").assertIsDisplayed()
        composeTestRule.onNodeWithText("Driving Record (MVR)").assertIsDisplayed()
        composeTestRule.onNodeWithText("Criminal Background").assertIsDisplayed()
        composeTestRule.onNodeWithText("Sex Offender Registry").assertIsDisplayed()
    }

    @Test
    fun backgroundCheckScreen_displaysDisqualifyingFactors() {
        composeTestRule.setContent {
            DollorDriverTheme {
                BackgroundCheckConsentScreen(onContinue = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Disqualifying Factors").assertIsDisplayed()
        composeTestRule.onNodeWithText("DUI/DWI conviction within past 7 years", substring = true).assertIsDisplayed()
    }

    @Test
    fun backgroundCheckScreen_displaysFCRARights() {
        composeTestRule.setContent {
            DollorDriverTheme {
                BackgroundCheckConsentScreen(onContinue = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Your Rights (FCRA)").assertIsDisplayed()
        composeTestRule.onNodeWithText("Receive a copy of your background check report", substring = true).assertIsDisplayed()
    }

    @Test
    fun backgroundCheckScreen_requiresBothCheckboxes() {
        composeTestRule.setContent {
            DollorDriverTheme {
                BackgroundCheckConsentScreen(onContinue = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Authorize Background Check").assertIsNotEnabled()
        composeTestRule.onNodeWithText("I authorize Dollor and its screening partners", substring = true).performClick()
        composeTestRule.onNodeWithText("Authorize Background Check").assertIsNotEnabled()
        composeTestRule.onNodeWithText("I have read and understand my rights", substring = true).performClick()
        composeTestRule.onNodeWithText("Authorize Background Check").assertIsEnabled()
    }

    // =========================================================================
    // VEHICLE REQUIREMENTS SCREEN TESTS
    // =========================================================================

    @Test
    fun vehicleScreen_displaysBasicRequirements() {
        composeTestRule.setContent {
            DollorDriverTheme {
                VehicleRequirementsScreen(onContinue = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Vehicle Requirements").assertIsDisplayed()
        composeTestRule.onNodeWithText("Basic Requirements").assertIsDisplayed()
        composeTestRule.onNodeWithText("Vehicle Age").assertIsDisplayed()
        composeTestRule.onNodeWithText("15 years old or newer", substring = true).assertIsDisplayed()
        composeTestRule.onNodeWithText("Doors").assertIsDisplayed()
        composeTestRule.onNodeWithText("4-door vehicle required", substring = true).assertIsDisplayed()
    }

    @Test
    fun vehicleScreen_displaysConditionRequirements() {
        composeTestRule.setContent {
            DollorDriverTheme {
                VehicleRequirementsScreen(onContinue = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Vehicle Condition").assertIsDisplayed()
        composeTestRule.onNodeWithText("No significant cosmetic damage", substring = true).assertIsDisplayed()
    }

    @Test
    fun vehicleScreen_displaysDocumentsNeeded() {
        composeTestRule.setContent {
            DollorDriverTheme {
                VehicleRequirementsScreen(onContinue = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Documents You'll Need").assertIsDisplayed()
        composeTestRule.onNodeWithText("Vehicle Registration").assertIsDisplayed()
        composeTestRule.onNodeWithText("Proof of Insurance").assertIsDisplayed()
    }

    @Test
    fun vehicleScreen_continueButtonRequiresAcknowledgment() {
        var continueClicked = false

        composeTestRule.setContent {
            DollorDriverTheme {
                VehicleRequirementsScreen(onContinue = { continueClicked = true }, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Continue").assertIsNotEnabled()
        composeTestRule.onNodeWithText("My vehicle meets all requirements", substring = true).performClick()
        composeTestRule.onNodeWithText("Continue").assertIsEnabled()
        composeTestRule.onNodeWithText("Continue").performClick()
        assert(continueClicked)
    }

    // =========================================================================
    // INDEPENDENT CONTRACTOR AGREEMENT SCREEN TESTS
    // =========================================================================

    @Test
    fun contractorScreen_displaysContractorBenefits() {
        composeTestRule.setContent {
            DollorDriverTheme {
                IndependentContractorAgreementScreen(onAccept = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Independent Contractor Agreement").assertIsDisplayed()
        composeTestRule.onNodeWithText("Peer-to-peer rideshare marketplace relationship").assertIsDisplayed()
        composeTestRule.onNodeWithText("What This Means For You").assertIsDisplayed()
        composeTestRule.onNodeWithText("Set Your Own Hours").assertIsDisplayed()
        composeTestRule.onNodeWithText("Choose Your Requests").assertIsDisplayed()
        composeTestRule.onNodeWithText("Use Multiple Platforms").assertIsDisplayed()
        composeTestRule.onNodeWithText("Keep 100% of Your Fare").assertIsDisplayed()
    }

    @Test
    fun contractorScreen_displaysResponsibilities() {
        composeTestRule.setContent {
            DollorDriverTheme {
                IndependentContractorAgreementScreen(onAccept = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Your Responsibilities").assertIsDisplayed()
        composeTestRule.onNodeWithText("Maintain your own vehicle and insurance", substring = true).assertIsDisplayed()
        composeTestRule.onNodeWithText("Pay your own taxes", substring = true).assertIsDisplayed()
    }

    @Test
    fun contractorScreen_displaysNotAnEmployeeNotice() {
        composeTestRule.setContent {
            DollorDriverTheme {
                IndependentContractorAgreementScreen(onAccept = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Not An Employment Relationship").assertIsDisplayed()
    }

    @Test
    fun contractorScreen_displaysP2PCompliance() {
        composeTestRule.setContent {
            DollorDriverTheme {
                IndependentContractorAgreementScreen(onAccept = {}, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Peer-to-Peer Platform").assertIsDisplayed()
        composeTestRule.onNodeWithText("peer-to-peer rideshare marketplace", substring = true).assertIsDisplayed()
    }

    @Test
    fun contractorScreen_requiresAllThreeCheckboxes() {
        var acceptClicked = false

        composeTestRule.setContent {
            DollorDriverTheme {
                IndependentContractorAgreementScreen(onAccept = { acceptClicked = true }, onBackClick = {})
            }
        }

        composeTestRule.onNodeWithText("Accept & Continue").assertIsNotEnabled()
        composeTestRule.onNodeWithText("I agree to operate as an independent contractor", substring = true).performClick()
        composeTestRule.onNodeWithText("Accept & Continue").assertIsNotEnabled()
        composeTestRule.onNodeWithText("I understand that I control my own schedule", substring = true).performClick()
        composeTestRule.onNodeWithText("Accept & Continue").assertIsNotEnabled()
        composeTestRule.onNodeWithText("I acknowledge that I am responsible", substring = true).performClick()
        composeTestRule.onNodeWithText("Accept & Continue").assertIsEnabled()
        composeTestRule.onNodeWithText("Accept & Continue").performClick()
        assert(acceptClicked)
    }

    // =========================================================================
    // NAVIGATION TESTS
    // =========================================================================

    @Test
    fun insuranceScreen_backButtonWorks() {
        var backClicked = false

        composeTestRule.setContent {
            DollorDriverTheme {
                InsuranceDisclosureScreen(onContinue = {}, onBackClick = { backClicked = true })
            }
        }

        composeTestRule.onNodeWithContentDescription("Back").performClick()
        assert(backClicked)
    }

    @Test
    fun backgroundCheckScreen_backButtonWorks() {
        var backClicked = false

        composeTestRule.setContent {
            DollorDriverTheme {
                BackgroundCheckConsentScreen(onContinue = {}, onBackClick = { backClicked = true })
            }
        }

        composeTestRule.onNodeWithContentDescription("Back").performClick()
        assert(backClicked)
    }

    @Test
    fun vehicleScreen_backButtonWorks() {
        var backClicked = false

        composeTestRule.setContent {
            DollorDriverTheme {
                VehicleRequirementsScreen(onContinue = {}, onBackClick = { backClicked = true })
            }
        }

        composeTestRule.onNodeWithContentDescription("Back").performClick()
        assert(backClicked)
    }

    @Test
    fun contractorScreen_backButtonWorks() {
        var backClicked = false

        composeTestRule.setContent {
            DollorDriverTheme {
                IndependentContractorAgreementScreen(onAccept = {}, onBackClick = { backClicked = true })
            }
        }

        composeTestRule.onNodeWithContentDescription("Back").performClick()
        assert(backClicked)
    }
}
