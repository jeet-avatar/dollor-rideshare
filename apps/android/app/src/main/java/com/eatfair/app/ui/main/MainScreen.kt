package com.eatfair.app.ui.main

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material.icons.outlined.DirectionsCar
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Receipt
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.eatfair.app.ui.profile.ProfileScreen
import com.eatfair.app.ui.profile.ProfileViewModel
import com.eatfair.app.ui.theme.BrandGreen
import com.eatfair.app.ui.rideshare.RideRequestScreen

/**
 * Bottom navigation tab items. Rideshare-only: Ride (index 0) and
 * Profile (index 4). The gaps at indices 1-3 are intentional: they match
 * the ride/profile `selectedTabIndex` values used elsewhere in the app.
 */
data class BottomNavItem(
    val title: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector,
    val route: String
)

private val rideNavItem = BottomNavItem(
    title = "Ride",
    selectedIcon = Icons.Filled.DirectionsCar,
    unselectedIcon = Icons.Outlined.DirectionsCar,
    route = "home"
)

private val profileNavItem = BottomNavItem(
    title = "Profile",
    selectedIcon = Icons.Filled.Person,
    unselectedIcon = Icons.Outlined.Person,
    route = "profile"
)

private val tripsNavItem = BottomNavItem(
    title = "Trips",
    selectedIcon = Icons.Filled.Receipt,
    unselectedIcon = Icons.Outlined.Receipt,
    route = "trips"
)

private val visibleTabs: List<Pair<Int, BottomNavItem>> = listOf(
    0 to rideNavItem,
    1 to tripsNavItem,
    4 to profileNavItem
)

@Composable
fun MainScreen(
    profileViewModel: ProfileViewModel,
    onRideChatClick: (Int, String, Int?) -> Unit = { _, _, _ -> },
    onEditProfileClick: () -> Unit,
    onNotificationsClick: () -> Unit,
    onReferAndEarnClick: () -> Unit,
    onSavedAddressClick: () -> Unit,
    onSettingsClick: () -> Unit,
    onHelpSupportClick: () -> Unit,
    onPaymentMethodClick: () -> Unit,
    onWhatDriversSeeClick: () -> Unit,
    onYourPrivacyClick: () -> Unit,
    onSafetyFeaturesClick: () -> Unit,
    onDeleteAccountClick: (onError: (String) -> Unit) -> Unit,
    onLogoutClick: () -> Unit
) {
    var selectedTabIndex by rememberSaveable { mutableIntStateOf(0) }

    Scaffold(
        bottomBar = {
            NavigationBar(
                containerColor = Lx.Surface,
                contentColor = BrandGreen
            ) {
                visibleTabs.forEach { (index, item) ->
                    NavigationBarItem(
                        selected = selectedTabIndex == index,
                        onClick = { selectedTabIndex = index },
                        icon = {
                            Icon(
                                imageVector = if (selectedTabIndex == index) item.selectedIcon else item.unselectedIcon,
                                contentDescription = item.title
                            )
                        },
                        label = {
                            Text(
                                text = item.title,
                                fontSize = Lx.FontSize.caption,
                                fontWeight = if (selectedTabIndex == index) FontWeight.SemiBold else FontWeight.Normal
                            )
                        },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = BrandGreen,
                            selectedTextColor = BrandGreen,
                            unselectedIconColor = Lx.TextSecondary,
                            unselectedTextColor = Lx.TextSecondary,
                            indicatorColor = BrandGreen.copy(alpha = 0.1f)
                        )
                    )
                }
            }
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            when (selectedTabIndex) {
                0 -> {
                    // Rideshare-only landing: the ride request flow is the
                    // default tab. This is the root, so there is nowhere to
                    // navigate "back" to (no food home).
                    RideRequestScreen(
                        onBackClick = { },
                        onNavigateToChat = onRideChatClick
                    )
                }
                1 -> com.eatfair.app.ui.trips.TripsScreen()
                4 -> {
                    // Profile Tab
                    ProfileScreen(
                        profileViewModel = profileViewModel,
                        onBackClick = { selectedTabIndex = 0 }, // Go back to Ride
                        onEditProfileClick = onEditProfileClick,
                        onNotificationsClick = onNotificationsClick,
                        onReferAndEarnClick = onReferAndEarnClick,
                        onSavedAddressClick = onSavedAddressClick,
                        onSettingsClick = onSettingsClick,
                        onPaymentMethodClick = onPaymentMethodClick,
                        onHelpSupportClick = onHelpSupportClick,
                        onWhatDriversSeeClick = onWhatDriversSeeClick,
                        onYourPrivacyClick = onYourPrivacyClick,
                        onSafetyFeaturesClick = onSafetyFeaturesClick,
                        onDeleteAccountClick = onDeleteAccountClick,
                        onLogoutClick = onLogoutClick
                    )
                }
            }
        }
    }
}
