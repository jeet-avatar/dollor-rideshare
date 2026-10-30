# Dollor.ai Deployment Workflow

## 🎯 Overview

This document describes the complete staging-to-production CI/CD pipeline for Dollor.ai, including menu item image uploads and admin approval workflow.

## 📦 Existing Features (Already Implemented)

### 1. Menu Item Image Upload API
**Endpoint**: `POST /api/vibing/upload-image/{menu_item_id}`

**Features**:
- Validates file type (JPEG, PNG, WebP only)
- Enforces 5MB file size limit
- Uploads to S3 (production) or local storage (development)
- Updates `VendorMenuItem.image_url` automatically

**Usage Example**:
```bash
curl -X POST "https://api.dollor.ai/api/vibing/upload-image/123" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@menu-item-photo.jpg"
```

### 2. Admin Menu Approval Workflow
Three endpoints for menu item review:

#### Approve Menu Item
```
POST /api/admin/menu/{item_id}/approve
```

#### Reject Menu Item
```
POST /api/admin/menu/{item_id}/reject
```

#### Flag for Review
```
POST /api/admin/menu/{item_id}/flag
```

**Fields Updated**:
- `review_status`: 'pending' | 'approved' | 'rejected' | 'flagged'
- `needs_review`: boolean
- `admin_notes`: text notes from admin
- `reviewed_at`: timestamp
- `is_available`: auto-set based on approval

### 3. Stock Images System
- Automatic fallback images from Unsplash
- AI-powered image assignment based on dish names
- Located in `stock_images.py`

### 4. S3 Storage Service
- AWS S3 integration with local fallback
- CDN URL support for fast delivery
- Environment-based configuration

## 🚀 CI/CD Pipeline

### Architecture
```
Developer → Staging Branch → Auto Deploy to Staging → Manual Testing → Promotion Workflow → Production
```

### Environments

| Environment | URL | Branch | Database | Auto Deploy |
|-------------|-----|--------|----------|-------------|
| **Staging** | staging.dollor.ai | `staging`/`develop` | dollor-staging | ✅ Yes |
| **Production** | dollor.ai | `main` | dollor | ⚠️ Manual approval required |

## 📋 Step-by-Step Workflow

### Phase 1: Development & Staging

1. **Develop New Features**
   ```bash
   git checkout develop
   git pull origin develop
   # Make your changes
   git add .
   git commit -m "feat: Add feature description"
   git push origin develop
   ```

2. **Auto-Deploy to Staging**
   - Push to `staging` or `develop` branch
   - GitHub Actions workflow `deploy-staging.yml` triggers automatically
   - Runs tests → Builds frontend → Deploys backend → Seeds database
   - Staging URL: `https://staging.dollor.ai`

3. **Test in Staging**
   - [ ] Upload menu item images via `/api/vibing/upload-image/{item_id}`
   - [ ] Test admin approval workflow
   - [ ] Verify images display on frontend
   - [ ] Test iOS app against `staging-api.dollor.ai`
   - [ ] Test Android app against `staging-api.dollor.ai`
   - [ ] Test web app at `staging.dollor.ai`

### Phase 2: Promotion to Production

4. **Initiate Promotion**
   ```bash
   # Go to GitHub Actions
   # Select "Promote Staging to Production" workflow
   # Click "Run workflow"
   # Type "PROMOTE" in the confirmation field
   # Click "Run workflow"
   ```

5. **Automated Promotion Steps**
   - ✅ Validates confirmation input
   - ✅ Runs pre-deployment tests
   - ✅ Creates Pull Request: `staging` → `main`
   - ⏸️ **WAITS FOR MANUAL APPROVAL**

6. **Review & Approve**
   - Review the auto-generated PR
   - Check all tests passed
   - Verify staging environment works perfectly
   - Get stakeholder approval
   - **Merge the PR** → This triggers production deployment

7. **Production Deployment**
   - `deploy-dollar-ai.yml` workflow triggers on `main` branch push
   - Builds frontend with production config
   - Deploys to S3 + CloudFront
   - Deploys backend to EC2/ECS/EKS
   - Seeds production database if needed
   - **Production is LIVE**: `https://dollor.ai`

### Phase 3: Post-Deployment

8. **Verification Checklist**
   - [ ] Visit https://dollor.ai - homepage loads
   - [ ] Check https://api.dollor.ai/health - API is healthy
   - [ ] Test restaurant menu display - images show correctly
   - [ ] Test customer order flow - end-to-end works
   - [ ] Monitor error logs for 1 hour
   - [ ] Check CloudWatch/logs for issues

## 🖼️ Menu Image Upload Flow

### For Restaurant Partners (Web App)

1. Restaurant logs in to vendor portal
2. Navigates to Menu Management
3. Clicks "Add Menu Item" or "Edit Menu Item"
4. Fills in item details (name, price, description, category)
5. Uploads photo via file picker
6. **Frontend calls**: `POST /api/vibing/upload-image/{item_id}`
7. Image uploaded to S3
8. `image_url` field updated in database
9. Item goes to "Pending Review" status

### For Admin Review

1. Admin logs in to admin panel
2. Navigates to "Menu Items Pending Review"
3. Sees list of items with `needs_review = true`
4. Reviews item:
   - Image quality
   - Accurate description
   - Appropriate category
   - Correct pricing
5. Takes action:
   - **Approve**: `POST /api/admin/menu/{item_id}/approve`
   - **Reject**: `POST /api/admin/menu/{item_id}/reject` (with notes)
   - **Flag**: `POST /api/admin/menu/{item_id}/flag` (for further review)

### For Customers (iOS/Android/Web)

1. Browse restaurants
2. Click on restaurant → menu loads
3. Each menu item shows:
   - Custom uploaded image (if approved)
   - OR stock image (auto-assigned by AI)
4. Images load from CDN for fast delivery

## 🔐 Database Schema

### VendorMenuItem Table
```sql
CREATE TABLE vendor_menu_items (
  id SERIAL PRIMARY KEY,
  vendor_id INTEGER NOT NULL,
  item_name VARCHAR(255) NOT NULL,
  description TEXT,
  category VARCHAR(100),
  price FLOAT NOT NULL,

  -- Image
  image_url VARCHAR(500),  -- S3 URL or stock image URL

  -- Availability
  is_available BOOLEAN DEFAULT TRUE,
  in_stock BOOLEAN DEFAULT TRUE,

  -- Admin Review
  review_status VARCHAR(50) DEFAULT 'pending',  -- pending | approved | rejected | flagged
  needs_review BOOLEAN DEFAULT TRUE,
  admin_notes TEXT,
  reviewed_at TIMESTAMP,
  reviewed_by INTEGER,

  -- Attributes
  is_vegetarian BOOLEAN DEFAULT FALSE,
  is_vegan BOOLEAN DEFAULT FALSE,
  is_gluten_free BOOLEAN DEFAULT FALSE,
  is_spicy BOOLEAN DEFAULT FALSE,
  spice_level INTEGER DEFAULT 0,

  -- Other
  prep_time INTEGER,
  calories INTEGER,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

## 🧪 Testing Workflow

### Before Promoting to Production

**Backend API Tests**:
```bash
cd apps/web/p2p-platform/backend
pip install -r requirements.txt
pytest tests/unit/ -v
pytest tests/integration/ -v
```

**Frontend Build Test**:
```bash
cd apps/web/p2p-platform/frontend
npm install
npm run build
```

**Mobile App Tests**:
```bash
# iOS
cd apps/ios
./scripts/test.sh

# Android
cd apps/android
./gradlew test
```

## 🚨 Rollback Procedure

If production deployment fails:

1. **Immediate Rollback**
   ```bash
   # Revert the merge commit
   git revert HEAD
   git push origin main
   # This triggers automatic redeployment of previous version
   ```

2. **Database Rollback** (if needed)
   - SSH into production EC2
   - Restore database from latest backup
   - Run migration rollback scripts

3. **Verify Rollback**
   - Check https://dollor.ai
   - Test critical user flows
   - Monitor error logs

## 📊 Monitoring & Alerts

### Key Metrics to Monitor

1. **API Health**
   - Endpoint: `https://api.dollor.ai/health`
   - Expected: 200 OK with health check data

2. **Image Upload Success Rate**
   - Monitor `/api/vibing/upload-image/*` endpoints
   - Alert if error rate > 5%

3. **Menu Item Approval Rate**
   - Track `review_status` field changes
   - Alert if pending queue > 100 items

4. **Database Connections**
   - Monitor RDS CloudWatch metrics
   - Alert if connection count > 80% of max

## 🔧 Troubleshooting

### Issue: Images not uploading

**Check**:
1. S3 bucket permissions
2. AWS credentials in environment variables
3. File size < 5MB
4. File type is JPEG/PNG/WebP

**Solution**:
```bash
# Check S3 service logs
tail -f /opt/dollor-backend/backend.log | grep "S3\|upload"
```

### Issue: Staging database empty

**Fix**:
```bash
# SSH into staging EC2
ssh ec2-user@staging-api.dollor.ai

# Run seed script
cd /opt/dollor-backend
source venv/bin/activate
python seed_menu_items.py
```

### Issue: Menu items not showing

**Check**:
1. `review_status = 'approved'`
2. `is_available = TRUE`
3. `image_url` field populated (or stock image assigned)

**Solution**:
```sql
-- In database
UPDATE vendor_menu_items
SET review_status = 'approved', is_available = TRUE
WHERE needs_review = FALSE;
```

## 📞 Support

For deployment issues:
- GitHub Issues: the repository issue tracker
- Slack: #dollor-ai-deployments
- On-call engineer: Check PagerDuty schedule

---

**Last Updated**: 2026-01-06
**Maintained By**: Platform Engineering Team
**Version**: 2.0
