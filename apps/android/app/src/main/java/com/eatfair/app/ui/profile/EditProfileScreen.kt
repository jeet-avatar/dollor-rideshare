package com.eatfair.app.ui.profile

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.eatfair.app.ui.theme.BrandGreen

/** Edit Profile (iOS parity): name is editable, email is read-only. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditProfileScreen(
    userName: String,
    userEmail: String,
    onBackClick: () -> Unit,
    onSave: (name: String, onResult: (Result<Unit>) -> Unit) -> Unit
) {
    var name by remember(userName) { mutableStateOf(userName) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Edit Profile", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBackClick) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Lx.Surface2)
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it; error = null },
                label = { Text("Full name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedTextField(
                value = userEmail,
                onValueChange = {},
                label = { Text("Email") },
                enabled = false,
                singleLine = true,
                supportingText = { Text("Your email can't be changed here.") },
                modifier = Modifier.fillMaxWidth()
            )
            error?.let { Text(it, color = Lx.Error) }
            Button(
                onClick = {
                    saving = true
                    onSave(name) { result ->
                        saving = false
                        result.onSuccess { onBackClick() }
                            .onFailure { error = it.message ?: "Couldn't save your profile" }
                    }
                },
                enabled = name.isNotBlank() && name.trim() != userName && !saving,
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = ButtonDefaults.buttonColors(containerColor = BrandGreen)
            ) {
                if (saving) CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                else Text("Save changes", fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
