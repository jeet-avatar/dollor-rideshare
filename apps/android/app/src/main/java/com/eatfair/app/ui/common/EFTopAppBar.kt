package com.eatfair.app.ui.common

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarColors
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * A common, reusable TopAppBar for the Dollor.ai app.
 *
 * @param title The text to be displayed in the center of the app bar.
 * @param showBackButton Determines if the back navigation button is shown.
 * @param onBackClick The lambda to be executed when the back button is clicked.
 * @param actions A slot for adding action icons to the end of the app bar.
 * @param colors The colors to be used for the app bar. Defaults to a transparent background.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EFTopAppBar(
    title: String,
    showBackButton: Boolean = true,
    onBackClick: () -> Unit = {},
    actions: @Composable RowScope.() -> Unit = {},
    colors: TopAppBarColors = TopAppBarDefaults.topAppBarColors(
        containerColor = Color.Transparent,
        titleContentColor = MaterialTheme.colorScheme.onSurface,
        navigationIconContentColor = MaterialTheme.colorScheme.onSurface,
        scrolledContainerColor = Color.Transparent
    )
) {
    CenterAlignedTopAppBar(
        title = {
            Text(
                text = title,
                fontSize = Lx.FontSize.body,
                fontWeight = FontWeight.SemiBold,
            )
        },
        // Navigation Icon (e.g., Back Button)
        navigationIcon = {
            if (showBackButton) {
                IconButton(
                    onClick = onBackClick,
                    modifier = Modifier
                        .padding(start = 12.dp)
                        .background(
                            color = Lx.Surface,
                            shape = RoundedCornerShape(Lx.Radius.chip)
                        ).size(38.dp)
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowBackIos,
                        contentDescription = "Back",
                        tint = Lx.Text,
                        modifier = Modifier.size(20.dp).padding(start = 4.dp)
                    )
                }
            }
        },
        // Action Icons (e.g., Notifications, Settings)
        actions = actions,
        colors = colors
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Preview(showBackground = true, backgroundColor = 0xFFF0F000)
@Composable
fun TopAppBarPreview() {
    EFTopAppBar(title = "Dollor.ai")
}
