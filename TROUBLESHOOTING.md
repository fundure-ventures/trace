# Troubleshooting

## Finder cannot open `.traceboard` files

After removing a worktree, macOS may still associate `.traceboard` files with
the deleted app. Run **Launch Trace** or `./tools/trace` from the current
worktree, then reopen the file.

**Build Trace** alone does not update file associations.
