---
trigger: always_on
description: Mandatory workflow to build and push to git after debugging the app
---

# Mandatory Post-Debug Workflow

Whenever debugging, fixing bugs, or implementing changes in `Z-Truyenviet.koplugin`:

1. **Syntax Check**:
   ```sh
   find truyenviet.koplugin -name "*.lua" -exec luajit -b {} /dev/null \;
   ```
2. **Build App**:
   ```sh
   ./scripts/build.sh
   ```
   Ensures `dist/truyenviet.koplugin.zip` is re-generated.
3. **Update Documentation**:
   Record status and lessons learned in `Project_memory.md`.
4. **Git Commit & Push**:
   Commit the build archive and modified code with a descriptive commit summary of the version/fix and push to remote:
   ```sh
   git add -A
   git commit -m "fix/feat: <summary of changes and version/build>"
   git push origin main
   ```
