package com.eatfair.app.ui.address

import com.eatfair.shared.ui.Lx
// Complete imports
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.shared.model.address.AddressDto
import com.eatfair.app.ui.common.EFTopAppBar
import com.eatfair.app.ui.theme.pinkVerticalGradient
import com.eatfair.app.ui.theme.primaryVerticalGradient

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SavedAddressesScreen(
    locationViewModel: LocationViewModel,
    onBackClick: () -> Unit = {},
    onAddAddressClick: () -> Unit = {},
    onAddressClick: (AddressDto) -> Unit = {},
    onEditAddress: (AddressDto) -> Unit = {},
    onShareAddress: (AddressDto) -> Unit = {}
) {
    val addresses by locationViewModel.allAddresses.collectAsState()

    var showDeleteDialog by remember { mutableStateOf<AddressDto?>(null) }
    var showOptionsMenu by remember { mutableStateOf<AddressDto?>(null) }

    Scaffold(
        topBar = {
            EFTopAppBar("My Addresses", onBackClick= onBackClick)
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { paddingValues ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .background(brush = primaryVerticalGradient()),
            contentPadding = PaddingValues(vertical = 16.dp)
        ) {
            // Add Address Button
            item {
                AddressActionCard(
                    icon = Icons.Default.Add,
                    text = "Add Address",
                    iconTint = Lx.Orange,
                    onClick = onAddAddressClick
                )
            }

            // Saved Addresses Section
            item {
                Spacer(modifier = Modifier.height(24.dp))
                Text(
                    text = "SAVED ADDRESSES",
                    fontSize = Lx.FontSize.caption,
                    fontWeight = FontWeight.Bold,
                    color = Lx.TextSecondary,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }

            // Address List
            items(addresses) { address ->
                SavedAddressCard(
                    address = address,
                    onClick = { onAddressClick(address) },
                    onMenuClick = { showOptionsMenu = address }
                )
                Spacer(modifier = Modifier.height(12.dp))
            }
        }
    }

    // Options Bottom Sheet
    showOptionsMenu?.let { address ->
        AddressOptionsBottomSheet(
            address = address,
            onDismiss = { showOptionsMenu = null },
            onEdit = {
                showOptionsMenu = null
                onEditAddress(address)
            },
            onDelete = {
                showOptionsMenu = null
                showDeleteDialog = address
            },
            onShare = {
                showOptionsMenu = null
                onShareAddress(address)
            }
        )
    }

    // Delete Confirmation Dialog
    showDeleteDialog?.let { address ->
        DeleteAddressDialog(
            address = address,
            onConfirm = {
                locationViewModel.deleteAddress(address)
                showDeleteDialog = null
            },
            onDismiss = { showDeleteDialog = null }
        )
    }
}

@Composable
fun AddressActionCard(
    icon: ImageVector,
    text: String,
    iconTint: Color,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(Lx.Radius.button),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = text,
                    tint = iconTint,
                    modifier = Modifier.size(24.dp)
                )
                Text(
                    text = text,
                    fontSize = Lx.FontSize.callout,
                    fontWeight = FontWeight.SemiBold,
                    color = iconTint
                )
            }

            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = "Go",
                tint = Lx.TextSecondary
            )
        }
    }
}

@Composable
fun SavedAddressCard(
    address: AddressDto,
    onClick: () -> Unit,
    onMenuClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(Lx.Radius.button),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            // Icon and Distance
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.width(60.dp)
            ) {
                Icon(
                    imageVector = address.type.icon,
                    contentDescription = address.type.displayName,
                    tint = Lx.TextSecondary,
                    modifier = Modifier.size(32.dp)
                )
                Spacer(modifier = Modifier.height(8.dp))
//                Text(
//                    text = address.distance,
//                    fontSize = Lx.FontSize.caption,
//                    color = Lx.TextSecondary,
//                    fontWeight = FontWeight.Medium
//                )
            }

            Spacer(modifier = Modifier.width(12.dp))

            // Address Details
            Column(modifier = Modifier.weight(1f)) {

                Text(
                    text = address.type.displayName,
                    fontSize = Lx.FontSize.callout,
                    fontWeight = FontWeight.Bold,
                    color = Lx.Text
                )

                Spacer(modifier = Modifier.height(4.dp))

                Text(
                    text = address.addressLine1(),
                    fontSize = Lx.FontSize.footnote,
                    color = Lx.TextSecondary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )

                // UNIFIED: Use getDisplayAddress() which handles both fullAddress and legacy completeAddress
                val displayAddress = address.getDisplayAddress()
                if (displayAddress.isNotEmpty()) {
                    Text(
                        text = displayAddress,
                        fontSize = Lx.FontSize.footnote,
                        color = Lx.TextSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                Text(
                    text = "Phone number: ${address.phoneNumber}",
                    fontSize = Lx.FontSize.caption,
                    color = Lx.TextSecondary
                )

                Spacer(modifier = Modifier.height(12.dp))

                // Action Buttons
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    // More Options Button
                    IconButton(
                        onClick = onMenuClick,
                        modifier = Modifier.size(40.dp)
                    ) {
                        Surface(
                            modifier = Modifier.fillMaxSize(),
                            shape = CircleShape,
                            border = BorderStroke(1.dp, Lx.Hairline),
                            color = Color.White
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    imageVector = Icons.Default.MoreHoriz,
                                    contentDescription = "More Options",
                                    tint = Lx.TextSecondary,
                                    modifier = Modifier.size(20.dp)
                                )
                            }
                        }
                    }

                    // Share Button
                    IconButton(
                        onClick = { /* Share action */ },
                        modifier = Modifier.size(40.dp)
                    ) {
                        Surface(
                            modifier = Modifier.fillMaxSize(),
                            shape = CircleShape,
                            border = BorderStroke(1.dp, Lx.Hairline),
                            color = Color.White
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    imageVector = Icons.Default.Share,
                                    contentDescription = "Share",
                                    tint = Lx.Orange,
                                    modifier = Modifier.size(20.dp)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddressOptionsBottomSheet(
    address: AddressDto,
    onDismiss: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onShare: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Lx.Surface,
        shape = RoundedCornerShape(topStart = Lx.Radius.card, topEnd = Lx.Radius.card)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 32.dp)
        ) {
            // Header
            Text(
                text = address.type.displayName,
                fontSize = Lx.FontSize.body,
                fontWeight = FontWeight.Bold,
                color = Lx.Text,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp)
            )

            HorizontalDivider(Modifier, DividerDefaults.Thickness, DividerDefaults.color)

            // Edit Option
            BottomSheetOption(
                icon = Icons.Default.Edit,
                text = "Edit Address",
                onClick = onEdit
            )

            // Share Option
            BottomSheetOption(
                icon = Icons.Default.Share,
                text = "Share Address",
                onClick = onShare
            )

            // Delete Option
            BottomSheetOption(
                icon = Icons.Default.Delete,
                text = "Delete Address",
                iconTint = Lx.Error,
                textColor = Lx.Error,
                onClick = onDelete
            )
        }
    }
}

@Composable
fun BottomSheetOption(
    icon: ImageVector,
    text: String,
    iconTint: Color = Lx.TextSecondary,
    textColor: Color = Lx.Text,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = text,
            tint = iconTint,
            modifier = Modifier.size(24.dp)
        )
        Text(
            text = text,
            fontSize = Lx.FontSize.callout,
            color = textColor
        )
    }
}

@Composable
fun DeleteAddressDialog(
    address: AddressDto,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = "Warning",
                tint = Lx.Warning,
                modifier = Modifier.size(32.dp)
            )
        },
        title = {
            Text(
                text = "Delete Address?",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold
            )
        },
        text = {
            Text(
                text = "Are you sure you want to delete '${address.type}'? This action cannot be undone.",
                fontSize = Lx.FontSize.footnote,
                color = Lx.TextSecondary
            )
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Lx.Error
                )
            ) {
                Text("Delete", color = Color.White)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel", color = Lx.TextSecondary)
            }
        },
        containerColor = Lx.Surface,
        shape = RoundedCornerShape(Lx.Radius.card)
    )
}

//@Composable
//fun EditAddressScreen(
//    address: AddressDto,
//    onBackClick: () -> Unit = {},
//    onSaveAddress: (AddressDto) -> Unit = {}
//) {
//    var title by remember { mutableStateOf(address.type) }
//    var addressLine1 by remember { mutableStateOf(address.addressLine1()) }
//    var phoneNumber by remember { mutableStateOf(address.phoneNumber) }
//    var selectedType by remember { mutableStateOf(address.type) }
//
//    Column(
//        modifier = Modifier
//            .fillMaxSize()
//            .background(Lx.Surface)
//    ) {
//        // Top Bar
//        Row(
//            modifier = Modifier
//                .fillMaxWidth()
//                .padding(16.dp),
//            verticalAlignment = Alignment.CenterVertically
//        ) {
//            IconButton(onClick = onBackClick) {
//                Icon(
//                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
//                    contentDescription = "Back",
//                    tint = Lx.Text
//                )
//            }
//            Text(
//                text = "Edit Address",
//                fontSize = Lx.FontSize.title,
//                fontWeight = FontWeight.Bold,
//                color = Lx.Text,
//                modifier = Modifier.padding(start = 8.dp)
//            )
//        }
//
//        Column(
//            modifier = Modifier
//                .fillMaxSize()
//                .padding(20.dp)
//        ) {
//            // Title Field
//            OutlinedTextField(
//                value = title,
//                onValueChange = { title = it },
//                label = { Text("Title") },
//                modifier = Modifier.fillMaxWidth(),
//                shape = RoundedCornerShape(Lx.Radius.chip)
//            )
//
//            Spacer(modifier = Modifier.height(16.dp))
//
//            // Address Field
//            OutlinedTextField(
//                value = addressLine1,
//                onValueChange = { addressLine1 = it },
//                label = { Text("Address") },
//                modifier = Modifier.fillMaxWidth(),
//                minLines = 3,
//                shape = RoundedCornerShape(Lx.Radius.chip)
//            )
//
//            Spacer(modifier = Modifier.height(16.dp))
//
//            // Phone Number Field
//            OutlinedTextField(
//                value = phoneNumber,
//                onValueChange = { phoneNumber = it },
//                label = { Text("Phone Number") },
//                modifier = Modifier.fillMaxWidth(),
//                shape = RoundedCornerShape(Lx.Radius.chip)
//            )
//
//            Spacer(modifier = Modifier.height(24.dp))
//
//            // Type Selection
//            Text(
//                text = "Address Type",
//                fontSize = Lx.FontSize.footnote,
//                fontWeight = FontWeight.Medium,
//                color = Lx.TextSecondary
//            )
//
//            Spacer(modifier = Modifier.height(12.dp))
//
//            Row(
//                modifier = Modifier.fillMaxWidth(),
//                horizontalArrangement = Arrangement.spacedBy(12.dp)
//            ) {
//                AddressCategory.values().take(2).forEach { type ->
//                    FilterChip(
//                        selected = selectedType == type,
//                        onClick = { selectedType = type },
//                        label = { Text(type.displayName) },
//                        leadingIcon = {
//                            Icon(type.icon, null, Modifier.size(18.dp))
//                        },
//                        modifier = Modifier.weight(1f)
//                    )
//                }
//            }
//
//            Spacer(modifier = Modifier.weight(1f))
//
//            // Save Button
//            Button(
//                onClick = {
//                    val updatedAddress = address.copy(
//                        title = title,
//                        addressLine1 = addressLine1,
//                        phoneNumber = phoneNumber,
//                        type = selectedType
//                    )
//                    onSaveAddress(updatedAddress)
//                },
//                modifier = Modifier
//                    .fillMaxWidth()
//                    .height(56.dp),
//                colors = ButtonDefaults.buttonColors(
//                    containerColor = Lx.Orange
//                ),
//                shape = RoundedCornerShape(Lx.Radius.button)
//            ) {
//                Text(
//                    text = "Save Changes",
//                    fontSize = Lx.FontSize.callout,
//                    fontWeight = FontWeight.Bold,
//                    color = Color.White
//                )
//            }
//        }
//    }
//}