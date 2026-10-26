package com.eatfair.driver.ui.compliance

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.driver.ui.theme.DollorDriverColors

/**
 * Driver Compliance Screens
 * P2P Matchmaking Platform Requirements:
 * - Insurance disclosure (driver's own coverage)
 * - Background check consent (safety best practice)
 * - Vehicle requirements (quality standards)
 * - Independent contractor agreement (P2P relationship clarity)
 */

// ============================================================================
// SCREEN 1: Insurance Disclosure
// ============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InsuranceDisclosureScreen(
    onContinue: () -> Unit,
    onBackClick: (() -> Unit)? = null
) {
    var acknowledged by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Insurance Requirements", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    onBackClick?.let {
                        IconButton(onClick = it) {
                            Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Lx.Surface
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(DollorDriverColors.Gray50)
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            // Header
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(DollorDriverColors.Blue.copy(alpha = 0.1f))
                    .align(Alignment.CenterHorizontally),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Security,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp),
                    tint = DollorDriverColors.Blue
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "Insurance Disclosure",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold,
                color = DollorDriverColors.Gray900,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )

            Text(
                text = "Your personal insurance responsibility",
                fontSize = Lx.FontSize.footnote,
                color = DollorDriverColors.Gray500,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(modifier = Modifier.height(24.dp))

            // P2P Platform Notice
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = "How Dollor Works",
                        fontSize = Lx.FontSize.callout,
                        fontWeight = FontWeight.Bold,
                        color = DollorDriverColors.Gray900
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Dollor is a peer-to-peer matchmaking platform that connects independent drivers with customers. We facilitate the connection and charge a flat connection fee. You provide services directly to customers.",
                        fontSize = Lx.FontSize.footnote,
                        color = DollorDriverColors.Gray700,
                        lineHeight = 20.sp
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Insurance Requirement
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Default.Shield,
                            contentDescription = null,
                            tint = DollorDriverColors.Blue,
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = "Your Insurance Responsibility",
                            fontSize = Lx.FontSize.callout,
                            fontWeight = FontWeight.Bold,
                            color = DollorDriverColors.Gray900
                        )
                    }
                    Spacer(modifier = Modifier.height(12.dp))

                    listOf(
                        "Valid personal auto insurance policy",
                        "Coverage that meets your state's minimum requirements",
                        "Insurance that covers your vehicle for personal use"
                    ).forEach { item ->
                        Row(
                            modifier = Modifier.padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                imageVector = Icons.Default.CheckCircle,
                                contentDescription = null,
                                tint = DollorDriverColors.Green,
                                modifier = Modifier.size(16.dp)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(text = item, fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray700)
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Important Notice
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(
                    containerColor = DollorDriverColors.Warning.copy(alpha = 0.1f)
                )
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.Top
                ) {
                    Icon(
                        imageVector = Icons.Default.Warning,
                        contentDescription = null,
                        tint = DollorDriverColors.Warning,
                        modifier = Modifier.size(24.dp)
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Column {
                        Text(
                            text = "Important Notice",
                            fontWeight = FontWeight.Bold,
                            color = DollorDriverColors.Gray900
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = "As a peer-to-peer matchmaking platform, Dollor does not provide commercial insurance coverage. You are solely responsible for maintaining adequate insurance for your vehicle.",
                            fontSize = Lx.FontSize.footnote,
                            color = DollorDriverColors.Gray700,
                            lineHeight = 18.sp
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Acknowledgment Checkbox
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Lx.Radius.button))
                    .background(Lx.Surface)
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Checkbox(
                    checked = acknowledged,
                    onCheckedChange = { acknowledged = it },
                    colors = CheckboxDefaults.colors(checkedColor = DollorDriverColors.Blue)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "I understand the insurance requirements and will maintain appropriate coverage",
                    fontSize = Lx.FontSize.footnote,
                    color = DollorDriverColors.Gray900
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            Button(
                onClick = onContinue,
                modifier = Modifier.fillMaxWidth().height(56.dp),
                enabled = acknowledged,
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = ButtonDefaults.buttonColors(
                    containerColor = DollorDriverColors.Blue,
                    disabledContainerColor = DollorDriverColors.Gray300
                )
            ) {
                Text(text = "Continue", fontSize = Lx.FontSize.callout, fontWeight = FontWeight.SemiBold)
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

// ============================================================================
// SCREEN 2: Background Check Consent
// ============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackgroundCheckConsentScreen(
    onContinue: () -> Unit,
    onBackClick: (() -> Unit)? = null,
    isInitiating: Boolean = false,
    statusText: String? = null
) {
    var consentGiven by remember { mutableStateOf(false) }
    var understandRights by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Background Check", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    onBackClick?.let {
                        IconButton(onClick = it) {
                            Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Lx.Surface)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(DollorDriverColors.Gray50)
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            // Header
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(DollorDriverColors.Green.copy(alpha = 0.1f))
                    .align(Alignment.CenterHorizontally),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.VerifiedUser,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp),
                    tint = DollorDriverColors.Green
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "Background Check Authorization",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold,
                color = DollorDriverColors.Gray900,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )

            Text(
                text = "Required for driver approval",
                fontSize = Lx.FontSize.footnote,
                color = DollorDriverColors.Gray500,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(modifier = Modifier.height(24.dp))

            // What We Check
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = "What We Verify",
                        fontSize = Lx.FontSize.callout,
                        fontWeight = FontWeight.Bold,
                        color = DollorDriverColors.Gray900
                    )
                    Spacer(modifier = Modifier.height(12.dp))

                    BackgroundCheckItem(Icons.Default.Badge, "Identity Verification", "Confirm your identity matches your documents")
                    BackgroundCheckItem(Icons.Default.DriveEta, "Driving Record (MVR)", "Review your motor vehicle record for the past 7 years")
                    BackgroundCheckItem(Icons.Default.Gavel, "Criminal Background", "National and county criminal database search")
                    BackgroundCheckItem(Icons.Default.Block, "Sex Offender Registry", "National sex offender registry check")
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Disqualifying Factors
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = DollorDriverColors.Error.copy(alpha = 0.05f))
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Block, null, tint = DollorDriverColors.Error, modifier = Modifier.size(20.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Disqualifying Factors", fontSize = Lx.FontSize.callout, fontWeight = FontWeight.Bold, color = DollorDriverColors.Gray900)
                    }
                    Spacer(modifier = Modifier.height(12.dp))

                    listOf(
                        "DUI/DWI conviction within past 7 years",
                        "Felony conviction within past 7 years",
                        "Violent crime conviction",
                        "Sexual offense conviction",
                        "More than 3 moving violations in past 3 years"
                    ).forEach { item ->
                        Row(modifier = Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Close, null, tint = DollorDriverColors.Error, modifier = Modifier.size(14.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(item, fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray700)
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Your Rights
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Balance, null, tint = DollorDriverColors.Blue, modifier = Modifier.size(20.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Your Rights (FCRA)", fontSize = Lx.FontSize.callout, fontWeight = FontWeight.Bold, color = DollorDriverColors.Gray900)
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    Text("Under the Fair Credit Reporting Act (FCRA), you have the right to:", fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray600)
                    Spacer(modifier = Modifier.height(8.dp))

                    listOf(
                        "Receive a copy of your background check report",
                        "Dispute any inaccurate information",
                        "Know if information was used against you",
                        "Consent before a report is obtained"
                    ).forEach { right ->
                        Row(modifier = Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.CheckCircle, null, tint = DollorDriverColors.Green, modifier = Modifier.size(16.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(right, fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray700)
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Consent Checkboxes
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.Top) {
                        Checkbox(checked = consentGiven, onCheckedChange = { consentGiven = it }, colors = CheckboxDefaults.colors(checkedColor = DollorDriverColors.Blue))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("I authorize Dollor and its screening partners to obtain a consumer report (background check) about me.", fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray900, lineHeight = 20.sp)
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    Row(verticalAlignment = Alignment.Top) {
                        Checkbox(checked = understandRights, onCheckedChange = { understandRights = it }, colors = CheckboxDefaults.colors(checkedColor = DollorDriverColors.Blue))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("I have read and understand my rights under the Fair Credit Reporting Act.", fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray900, lineHeight = 20.sp)
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            Button(
                onClick = onContinue,
                modifier = Modifier.fillMaxWidth().height(56.dp),
                enabled = consentGiven && understandRights && !isInitiating,
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = ButtonDefaults.buttonColors(containerColor = DollorDriverColors.Blue, disabledContainerColor = DollorDriverColors.Gray300)
            ) {
                if (isInitiating) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        color = DollorDriverColors.White,
                        strokeWidth = 2.dp
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                }
                Text("Authorize Background Check", fontSize = Lx.FontSize.callout, fontWeight = FontWeight.SemiBold)
            }

            if (!statusText.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = statusText,
                    fontSize = Lx.FontSize.footnote,
                    color = DollorDriverColors.Gray600,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

@Composable
private fun BackgroundCheckItem(icon: ImageVector, title: String, description: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.Top
    ) {
        Box(
            modifier = Modifier.size(40.dp).clip(RoundedCornerShape(Lx.Radius.chip)).background(DollorDriverColors.Blue.copy(alpha = 0.1f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, null, tint = DollorDriverColors.Blue, modifier = Modifier.size(20.dp))
        }
        Spacer(modifier = Modifier.width(12.dp))
        Column {
            Text(title, fontSize = Lx.FontSize.footnote, fontWeight = FontWeight.Medium, color = DollorDriverColors.Gray900)
            Text(description, fontSize = Lx.FontSize.caption, color = DollorDriverColors.Gray500)
        }
    }
}

// ============================================================================
// SCREEN 3: Vehicle Requirements
// ============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VehicleRequirementsScreen(
    onContinue: () -> Unit,
    onBackClick: (() -> Unit)? = null
) {
    var meetsRequirements by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Vehicle Requirements", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    onBackClick?.let {
                        IconButton(onClick = it) {
                            Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Lx.Surface)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(DollorDriverColors.Gray50)
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            // Header
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(DollorDriverColors.Orange.copy(alpha = 0.1f))
                    .align(Alignment.CenterHorizontally),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.DirectionsCar, null, modifier = Modifier.size(40.dp), tint = DollorDriverColors.Orange)
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "Vehicle Requirements",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold,
                color = DollorDriverColors.Gray900,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )

            Text(
                text = "Your vehicle must meet these standards",
                fontSize = Lx.FontSize.footnote,
                color = DollorDriverColors.Gray500,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Basic Requirements
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Basic Requirements", fontSize = Lx.FontSize.callout, fontWeight = FontWeight.Bold, color = DollorDriverColors.Gray900)
                    Spacer(modifier = Modifier.height(12.dp))

                    VehicleRequirementItem(Icons.Default.CalendarToday, "Vehicle Age", "15 years old or newer (2010 or later)")
                    VehicleRequirementItem(Icons.Default.AirlineSeatReclineNormal, "Doors", "4-door vehicle required")
                    VehicleRequirementItem(Icons.Default.Groups, "Seating Capacity", "Minimum 4 passengers (excluding driver)")
                    VehicleRequirementItem(Icons.Default.Receipt, "Registration", "Valid, current registration in your name")
                    VehicleRequirementItem(Icons.Default.Security, "Insurance", "Valid personal auto insurance")
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Condition Requirements
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Vehicle Condition", fontSize = Lx.FontSize.callout, fontWeight = FontWeight.Bold, color = DollorDriverColors.Gray900)
                    Spacer(modifier = Modifier.height(12.dp))

                    listOf(
                        "No significant cosmetic damage",
                        "All doors, windows, and locks work properly",
                        "Clean interior and exterior",
                        "Functioning AC/heat",
                        "Working headlights, brake lights, turn signals",
                        "Good tire condition with adequate tread"
                    ).forEach { condition ->
                        Row(modifier = Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.CheckCircle, null, tint = DollorDriverColors.Green, modifier = Modifier.size(16.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(condition, fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray700)
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Documents Required
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Description, null, tint = DollorDriverColors.Blue, modifier = Modifier.size(20.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Documents You'll Need", fontSize = Lx.FontSize.callout, fontWeight = FontWeight.Bold, color = DollorDriverColors.Gray900)
                    }
                    Spacer(modifier = Modifier.height(12.dp))

                    DocumentItem("Vehicle Registration", "Current and valid")
                    DocumentItem("Proof of Insurance", "Personal auto policy")
                    DocumentItem("Vehicle Photos", "Front, back, sides, interior")
                    DocumentItem("Driver's License", "Valid with current address")
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Acknowledgment
            Row(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(Lx.Radius.button)).background(Lx.Surface).padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Checkbox(checked = meetsRequirements, onCheckedChange = { meetsRequirements = it }, colors = CheckboxDefaults.colors(checkedColor = DollorDriverColors.Blue))
                Spacer(modifier = Modifier.width(8.dp))
                Text("My vehicle meets all requirements listed above", fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray900)
            }

            Spacer(modifier = Modifier.height(24.dp))

            Button(
                onClick = onContinue,
                modifier = Modifier.fillMaxWidth().height(56.dp),
                enabled = meetsRequirements,
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = ButtonDefaults.buttonColors(containerColor = DollorDriverColors.Blue, disabledContainerColor = DollorDriverColors.Gray300)
            ) {
                Text("Continue", fontSize = Lx.FontSize.callout, fontWeight = FontWeight.SemiBold)
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

@Composable
private fun VehicleRequirementItem(icon: ImageVector, title: String, requirement: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier.size(40.dp).clip(RoundedCornerShape(Lx.Radius.chip)).background(DollorDriverColors.Orange.copy(alpha = 0.1f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, null, tint = DollorDriverColors.Orange, modifier = Modifier.size(20.dp))
        }
        Spacer(modifier = Modifier.width(12.dp))
        Column {
            Text(title, fontSize = Lx.FontSize.footnote, fontWeight = FontWeight.Medium, color = DollorDriverColors.Gray900)
            Text(requirement, fontSize = Lx.FontSize.caption, color = DollorDriverColors.Gray500)
        }
    }
}

@Composable
private fun DocumentItem(title: String, note: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Article, null, tint = DollorDriverColors.Gray400, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text(title, fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray900)
        }
        Text(note, fontSize = Lx.FontSize.caption, color = DollorDriverColors.Gray500)
    }
}

// ============================================================================
// SCREEN 4: Independent Contractor Agreement
// ============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IndependentContractorAgreementScreen(
    onAccept: () -> Unit,
    onBackClick: (() -> Unit)? = null
) {
    var agreeToTerms by remember { mutableStateOf(false) }
    var understandRelationship by remember { mutableStateOf(false) }
    var acknowledgeNoEmployment by remember { mutableStateOf(false) }

    val allAgreed = agreeToTerms && understandRelationship && acknowledgeNoEmployment

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Contractor Agreement", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    onBackClick?.let {
                        IconButton(onClick = it) {
                            Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Lx.Surface)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(DollorDriverColors.Gray50)
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            // Header
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(DollorDriverColors.Green.copy(alpha = 0.1f))
                    .align(Alignment.CenterHorizontally),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.Handshake, null, modifier = Modifier.size(40.dp), tint = DollorDriverColors.Green)
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "Independent Contractor Agreement",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold,
                color = DollorDriverColors.Gray900,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )

            Text(
                text = "P2P matchmaking platform relationship",
                fontSize = Lx.FontSize.footnote,
                color = DollorDriverColors.Gray500,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(modifier = Modifier.height(24.dp))

            // What This Means
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("What This Means For You", fontSize = Lx.FontSize.callout, fontWeight = FontWeight.Bold, color = DollorDriverColors.Gray900)
                    Spacer(modifier = Modifier.height(12.dp))

                    ContractorBenefit(Icons.Default.Schedule, "Set Your Own Hours", "Work when you want. No minimum hours required.")
                    ContractorBenefit(Icons.Default.Route, "Choose Your Requests", "Accept or decline any request.")
                    ContractorBenefit(Icons.Default.Apps, "Use Multiple Platforms", "Work with other services simultaneously.")
                    ContractorBenefit(Icons.Default.AttachMoney, "Flat Connection Fee", "Only a $1-$3 fee per ride. Keep the rest of the fare plus 100% of tips.")
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Your Responsibilities
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Your Responsibilities", fontSize = Lx.FontSize.callout, fontWeight = FontWeight.Bold, color = DollorDriverColors.Gray900)
                    Spacer(modifier = Modifier.height(12.dp))

                    listOf(
                        "Maintain your own vehicle and insurance",
                        "Pay your own taxes (including self-employment)",
                        "Cover your own business expenses",
                        "Comply with local traffic laws",
                        "Maintain valid driver's license and registration",
                        "Provide safe, professional service"
                    ).forEach { item ->
                        Row(modifier = Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.ChevronRight, null, tint = DollorDriverColors.Blue, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(item, fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray700)
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Not An Employee Notice
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = DollorDriverColors.Warning.copy(alpha = 0.1f))
            ) {
                Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
                    Icon(Icons.Default.Info, null, tint = DollorDriverColors.Warning, modifier = Modifier.size(24.dp))
                    Spacer(modifier = Modifier.width(12.dp))
                    Column {
                        Text("Not An Employment Relationship", fontWeight = FontWeight.Bold, color = DollorDriverColors.Gray900)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            "As an independent contractor using our P2P matchmaking platform, you are not an employee of Dollor. This means you are not eligible for employee benefits such as health insurance, paid time off, workers' compensation, or unemployment insurance from Dollor.",
                            fontSize = Lx.FontSize.footnote,
                            color = DollorDriverColors.Gray700,
                            lineHeight = 18.sp
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // P2P Platform Info
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = DollorDriverColors.Blue.copy(alpha = 0.1f))
            ) {
                Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
                    Icon(Icons.Default.Gavel, null, tint = DollorDriverColors.Blue, modifier = Modifier.size(24.dp))
                    Spacer(modifier = Modifier.width(12.dp))
                    Column {
                        Text("Peer-to-Peer Platform", fontWeight = FontWeight.Bold, color = DollorDriverColors.Gray900)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            "Dollor operates as a peer-to-peer matchmaking platform. You are classified as an independent contractor because: (1) Dollor does not prescribe your work hours, (2) you may use other platforms, (3) you may engage in other activities, and (4) we have agreed in writing to this relationship.",
                            fontSize = Lx.FontSize.footnote,
                            color = DollorDriverColors.Gray700,
                            lineHeight = 18.sp
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Agreement Checkboxes
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.Top) {
                        Checkbox(checked = agreeToTerms, onCheckedChange = { agreeToTerms = it }, colors = CheckboxDefaults.colors(checkedColor = DollorDriverColors.Blue))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("I agree to operate as an independent contractor and not as an employee of Dollor.", fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray900, lineHeight = 20.sp)
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    Row(verticalAlignment = Alignment.Top) {
                        Checkbox(checked = understandRelationship, onCheckedChange = { understandRelationship = it }, colors = CheckboxDefaults.colors(checkedColor = DollorDriverColors.Blue))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("I understand that I control my own schedule, can decline requests, and can work for competing platforms.", fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray900, lineHeight = 20.sp)
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    Row(verticalAlignment = Alignment.Top) {
                        Checkbox(checked = acknowledgeNoEmployment, onCheckedChange = { acknowledgeNoEmployment = it }, colors = CheckboxDefaults.colors(checkedColor = DollorDriverColors.Blue))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("I acknowledge that I am responsible for my own taxes, insurance, and business expenses.", fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray900, lineHeight = 20.sp)
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            Button(
                onClick = onAccept,
                modifier = Modifier.fillMaxWidth().height(56.dp),
                enabled = allAgreed,
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = ButtonDefaults.buttonColors(containerColor = DollorDriverColors.Green, disabledContainerColor = DollorDriverColors.Gray300)
            ) {
                Icon(Icons.Default.Check, null, modifier = Modifier.size(20.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("Accept & Continue", fontSize = Lx.FontSize.callout, fontWeight = FontWeight.SemiBold)
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

@Composable
private fun ContractorBenefit(icon: ImageVector, title: String, description: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.Top
    ) {
        Box(
            modifier = Modifier.size(40.dp).clip(RoundedCornerShape(Lx.Radius.chip)).background(DollorDriverColors.Green.copy(alpha = 0.1f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, null, tint = DollorDriverColors.Green, modifier = Modifier.size(20.dp))
        }
        Spacer(modifier = Modifier.width(12.dp))
        Column {
            Text(title, fontSize = Lx.FontSize.footnote, fontWeight = FontWeight.Medium, color = DollorDriverColors.Gray900)
            Text(description, fontSize = Lx.FontSize.caption, color = DollorDriverColors.Gray500)
        }
    }
}
