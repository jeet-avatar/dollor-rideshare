package com.eatfair.app.ui.refer

import com.eatfair.shared.config.AppConfig
import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.filled.ContentCopy
import com.eatfair.app.ui.common.EFTopAppBar
import com.eatfair.app.ui.theme.pinkVerticalGradient

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReferAndEarnScreen(
    referralCode: String = "EATFAIR2024",
    onBackClick: () -> Unit = {},
    onShareClick: () -> Unit = {},
    onCopyCodeClick: () -> Unit = {}
) {
    var isCodeCopied by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(pinkVerticalGradient())
    ) {

        EFTopAppBar("Invite Friends", true, onBackClick)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(40.dp))

            // Illustration
            Text(
                text = "🎁",
                fontSize = 100.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            Text(
                text = "Invite Friends & Earn Rewards",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold,
                color = Lx.Text,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(12.dp))

            Text(
                text = "Share your referral code with friends." + (AppConfig.Rideshare.referralRewardText?.let { " Reward: $it." } ?: ""),
                fontSize = Lx.FontSize.footnote,
                color = Lx.TextSecondary,
                textAlign = TextAlign.Center,
                lineHeight = 20.sp
            )

            Spacer(modifier = Modifier.height(40.dp))

            // Referral Code Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = Lx.Surface
                ),
                shape = RoundedCornerShape(Lx.Radius.card)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = "Your Referral Code",
                        fontSize = Lx.FontSize.footnote,
                        color = Lx.TextSecondary
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    Text(
                        text = referralCode,
                        fontSize = Lx.FontSize.largeTitle,
                        fontWeight = FontWeight.Bold,
                        color = Lx.Orange,
                        letterSpacing = 2.sp
                    )

                    Spacer(modifier = Modifier.height(16.dp))

                    Button(
                        onClick = {
                            isCodeCopied = true
                            onCopyCodeClick()
                        },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Lx.OrangeTint,
                            contentColor = Lx.Orange
                        ),
                        shape = RoundedCornerShape(Lx.Radius.button)
                    ) {
                        Icon(
                            imageVector = if (isCodeCopied) Icons.Filled.Check else Icons.Filled.ContentCopy,
                            contentDescription = if (isCodeCopied) "Copied" else "Copy",
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = if (isCodeCopied) "Copied!" else "Copy Code",
                            fontSize = Lx.FontSize.subheadline,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Share Button
            Button(
                onClick = onShareClick,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Lx.Orange
                ),
                shape = RoundedCornerShape(Lx.Radius.button)
            ) {
                Icon(
                    imageVector = Icons.Filled.Share,
                    contentDescription = "Share",
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Share with Friends",
                    fontSize = Lx.FontSize.callout,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White
                )
            }

            Spacer(modifier = Modifier.height(40.dp))

            // How it works
            Text(
                text = "How it works",
                fontSize = Lx.FontSize.callout,
                fontWeight = FontWeight.Bold,
                color = Lx.Text,
                modifier = Modifier.align(Alignment.Start)
            )

            Spacer(modifier = Modifier.height(16.dp))

            InviteStep(
                number = "1",
                title = "Share your code",
                description = "Send your referral code to friends"
            )

            Spacer(modifier = Modifier.height(12.dp))

            InviteStep(
                number = "2",
                title = "Friend signs up",
                description = "They create an account using your code"
            )

            Spacer(modifier = Modifier.height(12.dp))

            InviteStep(
                number = "3",
                title = "Earn your reward",
                description = AppConfig.Rideshare.referralRewardText ?: "Rewards are shown here once available"
            )

            Spacer(modifier = Modifier.height(100.dp))
        }
    }
}

@Composable
fun InviteStep(
    number: String,
    title: String,
    description: String
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .background(Lx.Orange, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = number,
                fontSize = Lx.FontSize.callout,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
        }

        Spacer(modifier = Modifier.width(12.dp))

        Column(
            modifier = Modifier.weight(1f)
        ) {
            Text(
                text = title,
                fontSize = Lx.FontSize.subheadline,
                fontWeight = FontWeight.SemiBold,
                color = Lx.Text
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = description,
                fontSize = Lx.FontSize.footnote,
                color = Lx.TextSecondary
            )
        }
    }
}
