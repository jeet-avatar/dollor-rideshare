package com.eatfair.driver.ui.compliance

import com.eatfair.shared.ui.Lx
import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import coil.compose.rememberAsyncImagePainter
import com.eatfair.driver.ui.theme.DollorDriverColors
import java.io.File

/**
 * Camera-or-library capture for a single driver verification document (license / insurance).
 * Mirrors iOS's DriverOnboardingView license/insurance steps + DocumentCaptureView: tap the
 * dashed tile -> choose Take Photo or Choose from Library -> preview + checkmark once uploaded,
 * with a Retake affordance. Upload itself (resize + POST) is handled by [DriverDocumentViewModel].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DriverDocumentCaptureScreen(
    title: String,
    subtitle: String,
    requirementBullets: List<String>,
    documentType: String,
    isUploaded: Boolean,
    isUploading: Boolean,
    error: String?,
    onPicked: (Uri) -> Unit,
    onContinue: () -> Unit,
    onBackClick: (() -> Unit)? = null
) {
    val context = LocalContext.current
    var previewUri by remember { mutableStateOf<Uri?>(null) }
    var pendingCameraUri by remember { mutableStateOf<Uri?>(null) }
    var showSourceDialog by remember { mutableStateOf(false) }

    fun newCameraUri(): Uri {
        val dir = File(context.filesDir, "images").apply { mkdirs() }
        val file = File(dir, "${documentType}_${System.currentTimeMillis()}.jpg")
        return FileProvider.getUriForFile(context, "${context.packageName}.provider", file)
    }

    val cameraLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.TakePicture()
    ) { success ->
        if (success) {
            pendingCameraUri?.let {
                previewUri = it
                onPicked(it)
            }
        }
    }

    val galleryLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri ->
        if (uri != null) {
            previewUri = uri
            onPicked(uri)
        }
    }

    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            val uri = newCameraUri()
            pendingCameraUri = uri
            cameraLauncher.launch(uri)
        }
    }

    fun launchCamera() {
        val hasPermission = ContextCompat.checkSelfPermission(
            context, Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
        if (hasPermission) {
            val uri = newCameraUri()
            pendingCameraUri = uri
            cameraLauncher.launch(uri)
        } else {
            cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, fontWeight = FontWeight.SemiBold) },
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
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(DollorDriverColors.Blue.copy(alpha = 0.1f))
                    .align(Alignment.CenterHorizontally),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.CameraAlt,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp),
                    tint = DollorDriverColors.Blue
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = title,
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold,
                color = DollorDriverColors.Gray900,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                text = subtitle,
                fontSize = Lx.FontSize.footnote,
                color = DollorDriverColors.Gray500,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(modifier = Modifier.height(24.dp))

            if (requirementBullets.isNotEmpty()) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(Lx.Radius.button),
                    colors = CardDefaults.cardColors(containerColor = Lx.Surface)
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        requirementBullets.forEach { item ->
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
            }

            // Upload tile
            val effectiveUri = previewUri
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(200.dp)
                    .clip(RoundedCornerShape(Lx.Radius.button))
                    .then(
                        if (effectiveUri == null && !isUploaded) {
                            Modifier.border(1.5.dp, DollorDriverColors.Gray300, RoundedCornerShape(Lx.Radius.button))
                        } else Modifier
                    )
                    .background(
                        if (isUploaded && effectiveUri == null) DollorDriverColors.Green.copy(alpha = 0.12f)
                        else DollorDriverColors.White
                    ),
                contentAlignment = Alignment.Center
            ) {
                when {
                    effectiveUri != null -> {
                        Image(
                            painter = rememberAsyncImagePainter(effectiveUri),
                            contentDescription = "$title preview",
                            modifier = Modifier.fillMaxSize(),
                            contentScale = ContentScale.Crop
                        )
                        if (isUploading) {
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .background(Color.Black.copy(alpha = 0.35f)),
                                contentAlignment = Alignment.Center
                            ) {
                                CircularProgressIndicator(color = DollorDriverColors.White)
                            }
                        } else {
                            Icon(
                                imageVector = Icons.Default.CheckCircle,
                                contentDescription = null,
                                tint = DollorDriverColors.Green,
                                modifier = Modifier
                                    .align(Alignment.TopEnd)
                                    .padding(10.dp)
                                    .size(28.dp)
                            )
                        }
                    }

                    isUploaded -> {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                imageVector = Icons.Default.CheckCircle,
                                contentDescription = null,
                                tint = DollorDriverColors.Green,
                                modifier = Modifier.size(40.dp)
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text("Uploaded", fontWeight = FontWeight.SemiBold, color = DollorDriverColors.Gray900)
                            Text("Tap to replace", fontSize = Lx.FontSize.caption, color = DollorDriverColors.Gray500)
                        }
                    }

                    else -> {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                imageVector = Icons.Default.CameraAlt,
                                contentDescription = null,
                                tint = DollorDriverColors.Blue,
                                modifier = Modifier.size(36.dp)
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text("Take a photo or choose from library", fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray500)
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedButton(
                    onClick = { showSourceDialog = true },
                    enabled = !isUploading,
                    modifier = Modifier.weight(1f)
                ) {
                    Icon(Icons.Default.CameraAlt, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(if (isUploaded || effectiveUri != null) "Retake / Replace" else "Add Photo")
                }
            }

            if (error != null) {
                Spacer(modifier = Modifier.height(12.dp))
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(Lx.Radius.button),
                    colors = CardDefaults.cardColors(containerColor = DollorDriverColors.Error.copy(alpha = 0.1f))
                ) {
                    Text(
                        text = error,
                        modifier = Modifier.padding(12.dp),
                        color = DollorDriverColors.Error,
                        fontSize = Lx.FontSize.footnote
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            Button(
                onClick = onContinue,
                enabled = isUploaded && !isUploading,
                modifier = Modifier.fillMaxWidth().height(56.dp),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = ButtonDefaults.buttonColors(
                    containerColor = DollorDriverColors.Blue,
                    disabledContainerColor = DollorDriverColors.Gray300,
                    disabledContentColor = Lx.TextMuted
                )
            ) {
                Text(text = "Continue", fontSize = Lx.FontSize.callout, fontWeight = FontWeight.SemiBold)
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }

    if (showSourceDialog) {
        AlertDialog(
            onDismissRequest = { showSourceDialog = false },
            title = { Text("Add Photo") },
            text = { Text("Take a new photo or choose one from your library.") },
            confirmButton = {
                TextButton(onClick = {
                    showSourceDialog = false
                    launchCamera()
                }) {
                    Icon(Icons.Default.CameraAlt, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Take Photo")
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    showSourceDialog = false
                    galleryLauncher.launch("image/*")
                }) {
                    Icon(Icons.Default.PhotoLibrary, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Choose from Library")
                }
            }
        )
    }
}
