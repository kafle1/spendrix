# SECURITY FIX: Remove Exposed API Keys from Git History

## ⚠️ CRITICAL: Follow These Steps Immediately

### Step 1: Revoke the Leaked API Keys

**IMPORTANT**: The exposed API keys have been publicly leaked and MUST be revoked immediately.

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project: **spendrix-68b84**
3. Navigate to **APIs & Services** → **Credentials**
4. Find and **DELETE** these compromised API keys:
   - Android API Key: `AIzaSyAFSx0ERt6rT36-5Qd8aMw_qEnHRrRoX6U`
   - iOS API Key: `AIzaSyCTqf4v0RtNvx2rLeQ2VK1mH-S8sqywDcA`

### Step 2: Generate New API Keys

1. In Google Cloud Console → **APIs & Services** → **Credentials**
2. Click **Create Credentials** → **API Key**
3. Repeat for both Android and iOS
4. Restrict each key appropriately:
   - Android: Restrict to Android apps with your package name
   - iOS: Restrict to iOS apps with your bundle ID

### Step 3: Update Your .env File

Replace the placeholder values in `.env` with your NEW API keys:

```bash
# Open the .env file
nano .env  # or use your preferred editor
```

Update with your NEW keys:
```env
ANDROID_API_KEY=YOUR_NEW_ANDROID_API_KEY
IOS_API_KEY=YOUR_NEW_IOS_API_KEY
```

### Step 4: Remove Secrets from Git History

⚠️ **WARNING**: This will rewrite git history. Coordinate with your team first!

```bash
# Option 1: Using git-filter-repo (RECOMMENDED - faster and safer)
# Install git-filter-repo first:
# macOS: brew install git-filter-repo
# Then run:
git filter-repo --path lib/firebase_options.dart --invert-paths --force
git filter-repo --path android/app/google-services.json --invert-paths --force

# Option 2: Using BFG Repo-Cleaner (Alternative)
# Download BFG from https://rtyley.github.io/bfg-repo-cleaner/
# Then run:
java -jar bfg.jar --replace-text passwords.txt
# Where passwords.txt contains the API keys to remove

# Option 3: Manual approach with filter-branch (SLOWEST)
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch lib/firebase_options.dart" \
  --prune-empty --tag-name-filter cat -- --all
```

### Step 5: Force Push to GitHub

⚠️ **CRITICAL**: This will overwrite the remote repository!

```bash
# Force push to all branches
git push origin --force --all

# Force push tags
git push origin --force --tags
```

### Step 6: Notify GitHub to Close the Security Alert

1. Go to your [GitHub Security Alerts](https://github.com/kafle1/spendrix/security/secret-scanning/1)
2. Click on the alert for the Google API Key
3. Select **Close as** → **Revoked**
4. Confirm that you've:
   - ✅ Revoked the API key
   - ✅ Removed it from git history
   - ✅ Generated new credentials

### Step 7: Update Google-Services Configuration Files

Since `google-services.json` is already in `.gitignore`, you need to:

1. Download NEW `google-services.json` from Firebase Console:
   - Go to [Firebase Console](https://console.firebase.google.com/)
   - Select your project
   - Project Settings → Your Apps → Android App
   - Download `google-services.json`

2. Replace the existing file:
   ```bash
   # Backup current file (optional)
   cp android/app/google-services.json android/app/google-services.json.backup
   
   # Replace with new file (downloaded from Firebase Console)
   ```

3. Do the same for iOS `GoogleService-Info.plist`

### Step 8: Verify Everything Works

```bash
# Clean build
flutter clean
flutter pub get

# Test the app
flutter run
```

## What Was Changed

✅ **Removed hardcoded API keys** from `lib/firebase_options.dart`
✅ **Added flutter_dotenv** package for environment variable management
✅ **Created .env file** for secure API key storage
✅ **Updated .gitignore** to exclude .env files
✅ **Modified main.dart** to load environment variables on startup

## File Changes Summary

1. **lib/firebase_options.dart**: Now loads API keys from environment variables
2. **lib/main.dart**: Added `dotenv.load()` call at startup
3. **pubspec.yaml**: Added `flutter_dotenv` dependency
4. **.gitignore**: Added `.env*` files to ignore list
5. **.env**: Created with placeholder values (YOU MUST UPDATE THIS)
6. **.env.example**: Template for team members

## Important Notes

- ⚠️ **NEVER commit the .env file** to git
- ✅ `.env.example` can be committed (contains no secrets)
- 🔄 Share new API keys with team members through secure channels (1Password, LastPass, etc.)
- 📝 Update your CI/CD pipeline to inject environment variables
- 🔒 Consider using Firebase App Check for additional security

## For Team Members

When pulling the latest code:

1. Copy `.env.example` to `.env`
2. Request the actual API keys from the team lead
3. Update `.env` with the real values
4. Run `flutter pub get`
5. Never commit the `.env` file!

## CI/CD Configuration

For GitHub Actions, add these secrets:
- `ANDROID_API_KEY`
- `IOS_API_KEY`
- And all other env variables

Then create the `.env` file in your workflow:

```yaml
- name: Create .env file
  run: |
    echo "ANDROID_API_KEY=${{ secrets.ANDROID_API_KEY }}" >> .env
    echo "IOS_API_KEY=${{ secrets.IOS_API_KEY }}" >> .env
    # Add all other variables...
```

## Reference Links

- [GitHub Secret Scanning](https://docs.github.com/en/code-security/secret-scanning)
- [Google Cloud API Key Best Practices](https://cloud.google.com/docs/authentication/api-keys)
- [Firebase Security Best Practices](https://firebase.google.com/docs/projects/api-keys)
- [git-filter-repo Documentation](https://github.com/newren/git-filter-repo)
