#!/usr/bin/env python3
"""
fixup_fdinfo.py — Fix fdinfo.c after SUSFS patching

The SUSFS VFS patch for gki-android13-5.15 modifies fs/notify/fdinfo.c, but on
some kernels the patch introduces three issues that clang with -Werror rejects:

  1. inotify_mark_user_mask() called before declaration
  2. Label immediately followed by a declaration (C23 extension)
  3. fanotify_fdinfo has wrong signature (missing the 3rd param added by SUSFS)

This script applies minimal, safe fixups based on content patterns (not line
numbers) so it is robust across different kernel/patch versions.
"""
import re
import sys
from pathlib import Path


def fixup_fdinfo(kernel_dir: str) -> None:
    fdinfo = Path(kernel_dir) / "fs" / "notify" / "fdinfo.c"

    if not fdinfo.exists():
        print(f"  [ERROR] {fdinfo} not found")
        sys.exit(1)

    content = fdinfo.read_text(encoding="utf-8", errors="replace")
    original = content

    # ----------------------------------------------------------------
    # Fix 1: Add forward declaration for inotify_mark_user_mask
    #
    # The SUSFS patch may call this function before its definition.
    # We add a forward declaration after the last #include line.
    # ----------------------------------------------------------------
    if "inotify_mark_user_mask" in content:
        # Check if it's already declared (not just defined)
        if not re.search(
            r"^(static\s+)?u32\s+inotify_mark_user_mask\s*\(.*?\)\s*;",
            content,
            re.MULTILINE,
        ):
            # Find last #include to insert after
            last_include = None
            for m in re.finditer(r"^#include\s+.*$", content, re.MULTILINE):
                last_include = m.end()
            if last_include:
                fwd = "\n\n/* SUSFS: forward declaration */\nstatic u32 inotify_mark_user_mask(struct fsnotify_mark *mark);\n"
                content = content[:last_include] + fwd + content[last_include:]
                print("  [FIX] Added inotify_mark_user_mask forward declaration")

    # ----------------------------------------------------------------
    # Fix 2: Label followed by declaration
    #
    # Insert a null statement (";") after a label when the next
    # non-empty line starts with a type declaration.
    # Example:
    #   some_label:
    #       int x;        <-- error: declaration after label
    # Becomes:
    #   some_label: ;
    #       int x;
    # ----------------------------------------------------------------
    lines = content.splitlines(keepends=True)
    new_lines = []
    i = 0
    while i < len(lines):
        new_lines.append(lines[i])
        # Match a label: whitespace + identifier + colon + possibly whitespace
        m = re.match(r"^(\s*)([a-zA-Z_]\w*)\s*:\s*$", lines[i])
        if m:
            # Look at next non-blank line
            j = i + 1
            while j < len(lines) and lines[j].strip() == "":
                j += 1
            if j < len(lines):
                # Check if next line is a declaration (starts with a type keyword)
                next_line = lines[j].strip()
                if re.match(
                    r"^(int|long|short|char|void|u\d+|s\d+|unsigned|struct|const|bool|size_t|ssize_t|__\w+)\s+",
                    next_line,
                ) or re.match(r"^struct\s+\w+\s*\*?\s*\w+\s*;", next_line):
                    new_lines.append(" ;\n")
                    print(f"  [FIX] Inserted null statement after label '{m.group(2)}'")
        i += 1
    content = "".join(new_lines)

    # ----------------------------------------------------------------
    # Fix 3: fanotify_fdinfo function signature
    #
    # The SUSFS patch changes show_fdinfo callback to take 3 params:
    #   void (*show)(struct seq_file *, struct fsnotify_mark *, struct file *)
    # But fanotify_fdinfo may still have the old 2-param signature:
    #   void fanotify_fdinfo(struct seq_file *m, struct fsnotify_mark *mark)
    # Fix: add the 3rd param "struct file *f"
    # ----------------------------------------------------------------
    # Pattern: fanotify_fdinfo with old 2-param signature
    # We need a careful regex that doesn't match call sites
    old_sig = (
        r"(\bfanotify_fdinfo\s*\(\s*)"
        r"(struct\s+seq_file\s*\*\s*\w+\s*,\s*struct\s+fsnotify_mark\s*\*\s*\w+\s*)"
        r"(\s*\)\s*\{)"
    )
    new_sig = r"\1\2, struct file *f\3"

    content_before = content
    content = re.sub(old_sig, new_sig, content)
    if content != content_before:
        print("  [FIX] Updated fanotify_fdinfo signature (added struct file *f)")

    # ----------------------------------------------------------------
    # Write back
    # ----------------------------------------------------------------
    if content != original:
        fdinfo.write_text(content, encoding="utf-8")
        print("  [OK]  fdinfo.c fixed successfully")
    else:
        print("  [INFO] No fdinfo.c changes needed")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: fixup_fdinfo.py <kernel_src_dir>", file=sys.stderr)
        sys.exit(1)
    fixup_fdinfo(sys.argv[1])
