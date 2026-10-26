package com.eatfair.app.ui.address

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.shared.constants.AddressType
import com.eatfair.shared.model.address.AddressDto
import com.eatfair.shared.model.address.LocationData
import com.eatfair.app.ui.common.EFTopAppBar
import com.eatfair.app.ui.theme.pinkVerticalGradient

@Composable
fun AddAddressDetailsScreen(
    location: LocationData?,
    addressId: Int,
    locationViewModel: LocationViewModel,
    onBackClick: () -> Unit = {},
    onSaveAddress: (AddressDto) -> Unit = {}
) {
    // UNIFIED: Use new field names matching iOS/DoorDash/Uber architecture
    var unit by remember { mutableStateOf("") }  // was: houseNumber
    var street by remember { mutableStateOf("") }  // was: apartmentRoad
    var instructions by remember { mutableStateOf("") }  // was: directions
    var selectedType by remember { mutableStateOf(AddressType.HOME) }
    var phoneNumber by remember { mutableStateOf("") }

    LaunchedEffect(key1 = addressId) {
        if (addressId != 0) {
            val existingAddress = locationViewModel.getAddressById(addressId.toString())
            existingAddress?.let {
                // Support both new and legacy field names
                unit = it.unit.ifEmpty { it.houseNumber }
                street = it.street.ifEmpty { it.apartmentRoad }
                instructions = it.instructions ?: it.directions ?: ""
                phoneNumber = it.phoneNumber ?: ""
                selectedType = it.type
            }
        }
    }

    // UNIFIED: Use fullAddress (new) with fallback to completeAddress (legacy)
    val fullAddress =
        location?.address ?: locationViewModel.getAddressById(addressId.toString())?.getDisplayAddress()
        ?: "Unknown Address"
    val locationName =
        location?.locationName ?: locationViewModel.getAddressById(addressId.toString())?.locationName
        ?: "Unknown Location"
    val lat = location?.latitude ?: locationViewModel.getAddressById(addressId.toString())?.latitude ?: 0.0
    val lng = location?.longitude ?: locationViewModel.getAddressById(addressId.toString())?.longitude ?: 0.0

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(pinkVerticalGradient())
            .windowInsetsPadding(WindowInsets.statusBars)
    ) {
        // Top Section with Map
//        Box(modifier = Modifier.height(120.dp)) {
//            // Mini Map Preview
//            Box(
//                modifier = Modifier
//                    .fillMaxSize()
//                    .background(Lx.Surface2),
//                contentAlignment = Alignment.Center
//            ) {
//                Icon(
//                    imageVector = Icons.Default.Map,
//                    contentDescription = "Map Preview",
//                    modifier = Modifier.size(60.dp),
//                    tint = Lx.TextSecondary.copy(alpha = 0.3f)
//                )
//            }
//
//            // Back Button
//            IconButton(
//                onClick = onBackClick,
//                modifier = Modifier
//                    .padding(start = 12.dp)
//                    .background(
//                        color = Color.White,
//                        shape = RoundedCornerShape(Lx.Radius.chip)
//                    ).size(38.dp)
//            ) {
//                Icon(
//                    imageVector = Icons.AutoMirrored.Filled.ArrowBackIos,
//                    contentDescription = "Back",
//                    tint = Lx.Text,
//                    modifier = Modifier.size(20.dp).padding(start = 4.dp)
//                )
//            }
//        }

        EFTopAppBar(title = "Address Details", onBackClick = onBackClick)

        // Scrollable Content
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 12.dp)
        ) {
            // Location Name
            Row(
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.LocationOn,
                    contentDescription = "Location",
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(24.dp)
                )

                Column {
                    Text(
                        text = locationName,
                        fontSize = Lx.FontSize.title,
                        fontWeight = FontWeight.Bold,
                        color = Lx.Text
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = fullAddress,
                        fontSize = Lx.FontSize.footnote,
                        color = Lx.TextSecondary
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Help Message
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.chip),
                color = Lx.OrangeTint
            ) {
                Text(
                    text = "A detailed address will help your driver reach your pickup location easily",
                    fontSize = Lx.FontSize.footnote,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(8.dp)
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Unit/Apt/Suite Number (UNIFIED: was houseNumber)
            AddressTextField(
                value = unit,
                onValueChange = { unit = it },
                label = "APT / SUITE / UNIT NO.",
                placeholder = "",
            )

            Spacer(modifier = Modifier.height(20.dp))
            // Street Address (UNIFIED: was apartmentRoad)
            AddressTextField(
                value = street,
                onValueChange = { street = it },
                label = "STREET / ROAD / AREA (RECOMMENDED)",
                placeholder = ""
            )

            Spacer(modifier = Modifier.height(20.dp))
            AddressTextField(
                value = phoneNumber,
                onValueChange = { phoneNumber = it },
                label = "PHONE NUMBER",
                placeholder = "",
                keyboardType = KeyboardType.Phone,

            )

            Spacer(modifier = Modifier.height(20.dp))

            // Delivery Instructions (UNIFIED: was Directions)
            Text(
                text = "DELIVERY INSTRUCTIONS (OPTIONAL)",
                fontSize = Lx.FontSize.caption,
                fontWeight = FontWeight.Medium,
                color = Lx.TextSecondary,
                modifier = Modifier.padding(bottom = 8.dp)
            )

            Spacer(modifier = Modifier.height(4.dp))

            // Text Instructions
            OutlinedTextField(
                value = instructions,
                onValueChange = {
                    if (it.length <= 100) instructions = it
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(120.dp),
                placeholder = {
                    Text(
                        text = "e.g. Ring the bell on the red gate",
                        color = Lx.TextSecondary,
                        fontSize = Lx.FontSize.footnote
                    )
                },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedContainerColor = Lx.Surface,
                    unfocusedContainerColor = Lx.Surface,
                    focusedBorderColor = Lx.Hairline,
                    unfocusedBorderColor = Lx.Hairline
                ),
                shape = RoundedCornerShape(Lx.Radius.chip),
                textStyle = TextStyle(fontSize = Lx.FontSize.footnote)
            )

            Text(
                text = "${instructions.length}/200",
                fontSize = Lx.FontSize.caption,
                color = Lx.TextSecondary,
                modifier = Modifier.padding(top = 4.dp)
            )

            Spacer(modifier = Modifier.height(18.dp))

            // Save As Label
            Text(
                text = "SAVE AS",
                fontSize = Lx.FontSize.caption,
                color = Lx.TextSecondary,
                modifier = Modifier.padding(bottom = 12.dp)
            )

            val addressTypes = AddressType.entries.toList()

            FlowRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                addressTypes.forEach { type ->
                    AddressTypeChip(
                        icon = type.icon,
                        label = type.name.lowercase().replaceFirstChar { it.uppercase() },
                        isSelected = selectedType == type,
                        onClick = { selectedType = type }
                    )
                }
            }

            Spacer(modifier = Modifier.height(32.dp))

            // Save Button
            Button(
                onClick = {
                    // UNIFIED: Use new field names matching iOS/DoorDash/Uber architecture
                    val newAddressDto = AddressDto(
                        id = if (addressId != 0) addressId.toString() else java.util.UUID.randomUUID().toString(),
                        apiId = if (addressId != 0) addressId else null,
                        locationName = locationName,
                        fullAddress = fullAddress,  // UNIFIED: was completeAddress
                        unit = unit,                // UNIFIED: was houseNumber
                        street = street,            // UNIFIED: was apartmentRoad
                        instructions = instructions.ifEmpty { null },  // UNIFIED: was directions
                        addressType = selectedType.name.lowercase(),  // UNIFIED: string type
                        type = selectedType,        // Keep for backward compatibility
                        latitude = lat,
                        longitude = lng,
                        phoneNumber = phoneNumber
                    )

                    locationViewModel.saveAddress(newAddressDto)
                    onSaveAddress(newAddressDto)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = Color.White
                ),
                shape = RoundedCornerShape(Lx.Radius.button),
                enabled = unit.isNotEmpty() || street.isNotEmpty()
            ) {
                Text(
                    text = if (unit.isNotEmpty() || street.isNotEmpty()) "SAVE ADDRESS" else "ENTER APT / SUITE / UNIT NO.",
                    fontSize = Lx.FontSize.footnote,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

@Composable
fun AddressTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    placeholder: String,
    keyboardType: KeyboardType = KeyboardType.Text,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            text = label,
            fontSize = Lx.FontSize.caption,
            fontWeight = FontWeight.Medium,
            color = Lx.TextSecondary,
            modifier = Modifier.padding(bottom = 4.dp)
        )

        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            placeholder = {
                Text(
                    text = placeholder,
                    color = Lx.TextSecondary,
                    fontSize = Lx.FontSize.footnote
                )
            },

            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = Lx.Surface,
                unfocusedContainerColor = Lx.Surface,
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                unfocusedBorderColor = Lx.Hairline
            ),
            shape = RoundedCornerShape(Lx.Radius.chip),
            textStyle = TextStyle(fontSize = Lx.FontSize.footnote)
        )
    }
}

@Composable
fun AddressTypeChip(
    icon: ImageVector,
    label: String,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .wrapContentWidth()
            .height(32.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(Lx.Radius.sheet),
        color = if (isSelected) MaterialTheme.colorScheme.primaryContainer else Lx.Surface2,
        border = if (isSelected) BorderStroke(1.dp, MaterialTheme.colorScheme.primary) else null
    ) {
        Row(
            modifier = Modifier
                .padding(horizontal = 16.dp)
                .wrapContentHeight()
                .wrapContentWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                tint = if (isSelected) MaterialTheme.colorScheme.primary else Lx.TextSecondary,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = label,
                fontSize = Lx.FontSize.footnote,
                fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                color = if (isSelected) MaterialTheme.colorScheme.primary else Lx.TextSecondary
            )
        }
    }
}
