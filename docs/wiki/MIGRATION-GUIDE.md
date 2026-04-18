# GitHub Wiki Migration Guide

This guide explains how to migrate the `docs/wiki/` documentation to GitHub's Wiki feature.

## Prerequisites

The GitHub Wiki must be initialized before it can be cloned as a Git repository.

## Step 1: Initialize GitHub Wiki

**Via Web Interface:**

1. Go to https://github.com/rpmcdougall/turnipsim
2. Click the **Wiki** tab (top navigation)
3. Click **Create the first page**
4. **Title:** "Home"
5. **Body:** (can be anything, we'll replace it)
   ```
   Wiki is being migrated from docs/wiki/
   ```
6. Click **Save Page**

This creates the wiki repository at `https://github.com/rpmcdougall/turnipsim.wiki.git`

## Step 2: Clone Wiki Repository

```bash
cd /tmp
git clone https://github.com/rpmcdougall/turnipsim.wiki.git
cd turnipsim.wiki
```

## Step 3: Copy Documentation Files

```bash
# Copy all wiki markdown files
cp /Users/rmcdougall/dev/turnipsim/docs/wiki/*.md .

# Verify files copied
ls -la *.md
```

You should see:
- Architecture-Overview.md
- Code-Style-Guide.md
- Codebase-Tour.md
- Commit-Conventions.md
- Debugging-Guide.md
- Development-Process.md
- Home.md
- MIGRATION-GUIDE.md (this file)
- Phase-4-UI-Tasks.md
- Project-Setup.md
- README.md
- Session-Discipline.md
- Testing-Guidelines.md

## Step 4: Commit and Push

```bash
# Add all files
git add *.md

# Commit
git commit -m "docs: migrate wiki from docs/wiki/ directory

Migrated comprehensive developer documentation from repository:
- 12 wiki pages
- ~4,500 lines of documentation
- Covers setup, development process, code style, testing, and Phase 4 tasks

All files previously committed to main repository in docs/wiki/."

# Push to GitHub Wiki
git push origin master
```

## Step 5: Verify

1. Go to https://github.com/rpmcdougall/turnipsim/wiki
2. Verify all pages are listed in the sidebar
3. Click through each page to ensure content rendered correctly
4. Check that links work (some may need adjustment)

## Step 6: Update Links (Optional)

If you want to link to wiki pages from the main repository:

**In README.md:**
```markdown
## Documentation

See the [Developer Wiki](https://github.com/rpmcdougall/turnipsim/wiki) for:
- [Project Setup](https://github.com/rpmcdougall/turnipsim/wiki/Project-Setup)
- [Development Process](https://github.com/rpmcdougall/turnipsim/wiki/Development-Process)
- [Architecture Overview](https://github.com/rpmcdougall/turnipsim/wiki/Architecture-Overview)
```

## Keeping Wiki in Sync

The wiki is now in two places:
1. **Main repo:** `docs/wiki/` (version controlled with code)
2. **GitHub Wiki:** Separate git repository

### Option A: GitHub Wiki as Source of Truth

**Remove from main repo:**
```bash
cd /Users/rmcdougall/dev/turnipsim
git rm -r docs/wiki/
git commit -m "docs: remove wiki docs (migrated to GitHub Wiki)"
```

**Update from wiki:**
- Edit pages on GitHub Wiki web interface
- Or clone wiki repo, edit, push

### Option B: Main Repo as Source of Truth (Recommended)

**Keep in main repo, sync to wiki:**

```bash
# After updating docs/wiki/ in main repo
cd /tmp/turnipsim.wiki
git pull origin master

# Copy updated files
cp /Users/rmcdougall/dev/turnipsim/docs/wiki/*.md .

# Commit and push
git add *.md
git commit -m "docs: sync from main repo"
git push origin master
```

**Automate with script:**

Create `sync-wiki.sh`:
```bash
#!/bin/bash
set -e

REPO_DIR="/Users/rmcdougall/dev/turnipsim"
WIKI_DIR="/tmp/turnipsim.wiki"

# Clone wiki if not exists
if [ ! -d "$WIKI_DIR" ]; then
  git clone https://github.com/rpmcdougall/turnipsim.wiki.git "$WIKI_DIR"
fi

cd "$WIKI_DIR"
git pull origin master

# Copy all markdown files
cp "$REPO_DIR/docs/wiki/"*.md .

# Commit if changes
if ! git diff --quiet; then
  git add *.md
  git commit -m "docs: sync from main repo ($(date +%Y-%m-%d))"
  git push origin master
  echo "✅ Wiki synced successfully"
else
  echo "ℹ️  No changes to sync"
fi
```

Run after updating docs:
```bash
chmod +x sync-wiki.sh
./sync-wiki.sh
```

## Troubleshooting

### "Repository not found"
- Ensure you created the first page via web UI (Step 1)
- Wait a few seconds after creating, then try cloning again

### "Permission denied"
- Ensure you're authenticated: `gh auth status`
- Check you have write access to the repository

### Links broken in wiki
- GitHub Wiki uses different link format
- Change `[Text](File.md)` to `[Text](File)` (no .md extension)
- Or use full URLs: `[Text](https://github.com/user/repo/wiki/Page-Name)`

### Sidebar not showing all pages
- GitHub Wiki automatically generates sidebar from page titles
- To customize, create a `_Sidebar.md` file

## Custom Sidebar

Create `/tmp/turnipsim.wiki/_Sidebar.md`:

```markdown
### Getting Started
- [Home](Home)
- [Project Setup](Project-Setup)
- [Architecture Overview](Architecture-Overview)
- [Codebase Tour](Codebase-Tour)

### Development
- [Development Process](Development-Process)
- [Code Style Guide](Code-Style-Guide)
- [Testing Guidelines](Testing-Guidelines)
- [Commit Conventions](Commit-Conventions)

### Tasks
- [Phase 4 UI Tasks](Phase-4-UI-Tasks)

### Reference
- [Session Discipline](Session-Discipline)
- [Debugging Guide](Debugging-Guide)
```

Commit and push:
```bash
cd /tmp/turnipsim.wiki
git add _Sidebar.md
git commit -m "docs: add custom wiki sidebar"
git push origin master
```

## See Also

- [GitHub Wiki Documentation](https://docs.github.com/en/communities/documenting-your-project-with-wikis)
- [Markdown Guide](https://guides.github.com/features/mastering-markdown/)
