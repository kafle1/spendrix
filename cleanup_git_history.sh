#!/bin/bash

# Git History Cleanup Script
# This script removes the exposed API keys from git history
# WARNING: This rewrites git history. Make sure all team members are notified!

set -e  # Exit on error

echo "🔒 Git History Cleanup for Security Fix"
echo "========================================"
echo ""
echo "⚠️  WARNING: This will rewrite git history!"
echo "⚠️  Make sure you've:"
echo "    1. Revoked the old API keys in Google Cloud Console"
echo "    2. Generated new API keys"
echo "    3. Updated your .env file with new keys"
echo "    4. Notified all team members"
echo ""
read -p "Have you completed all steps above? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Aborting. Complete the steps above first."
    exit 1
fi

echo ""
echo "Select cleanup method:"
echo "1) git-filter-repo (Recommended - Fast and Safe)"
echo "2) BFG Repo-Cleaner (Alternative)"
echo "3) Cancel"
echo ""
read -p "Enter choice (1-3): " choice

case $choice in
    1)
        echo ""
        echo "📦 Checking for git-filter-repo..."
        
        if ! command -v git-filter-repo &> /dev/null; then
            echo "❌ git-filter-repo not found!"
            echo ""
            echo "Install it with:"
            echo "  macOS:  brew install git-filter-repo"
            echo "  Linux:  pip3 install git-filter-repo"
            echo ""
            exit 1
        fi
        
        echo "✅ git-filter-repo found"
        echo ""
        echo "🧹 Cleaning git history..."
        echo ""
        
        # Backup the current state
        echo "📦 Creating backup branch..."
        git branch backup-before-cleanup 2>/dev/null || echo "Backup branch already exists"
        
        # Remove sensitive files from history
        echo "🗑️  Removing firebase_options.dart from history..."
        git filter-repo --path lib/firebase_options.dart --invert-paths --force
        
        echo "🗑️  Removing google-services.json from history..."
        git filter-repo --path android/app/google-services.json --invert-paths --force
        
        echo ""
        echo "✅ History cleaned successfully!"
        ;;
        
    2)
        echo ""
        echo "📦 Checking for BFG Repo-Cleaner..."
        
        if ! command -v bfg &> /dev/null; then
            echo "❌ BFG not found!"
            echo ""
            echo "Install it with:"
            echo "  macOS:  brew install bfg"
            echo ""
            exit 1
        fi
        
        echo "✅ BFG found"
        echo ""
        
        # Create file with secrets to remove
        echo "📝 Creating secrets list..."
        cat > /tmp/secrets.txt << EOF
AIzaSyAFSx0ERt6rT36-5Qd8aMw_qEnHRrRoX6U
AIzaSyCTqf4v0RtNvx2rLeQ2VK1mH-S8sqywDcA
EOF
        
        echo "🧹 Cleaning git history with BFG..."
        bfg --replace-text /tmp/secrets.txt
        
        echo "🗑️  Running git gc..."
        git reflog expire --expire=now --all
        git gc --prune=now --aggressive
        
        # Clean up
        rm /tmp/secrets.txt
        
        echo ""
        echo "✅ History cleaned successfully!"
        ;;
        
    3)
        echo "❌ Cancelled"
        exit 0
        ;;
        
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "📋 Next Steps:"
echo "=============="
echo ""
echo "1. Re-add your remote repository:"
echo "   git remote add origin https://github.com/kafle1/spendrix.git"
echo ""
echo "2. Verify the files are still there:"
echo "   ls -la lib/firebase_options.dart"
echo "   ls -la android/app/google-services.json"
echo ""
echo "3. Add your security fixes back:"
echo "   git add ."
echo "   git commit -m \"security: Remove hardcoded API keys and implement environment variable system\""
echo ""
echo "4. Force push to GitHub:"
echo "   git push origin main --force"
echo "   git push origin --force --all"
echo "   git push origin --force --tags"
echo ""
echo "5. Close the GitHub security alert:"
echo "   https://github.com/kafle1/spendrix/security/secret-scanning/1"
echo ""
echo "⚠️  Remember to notify all team members to re-clone the repository!"
echo ""
