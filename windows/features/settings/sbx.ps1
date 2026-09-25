# sbx: paste images from the clipboard into sandboxes
sbx settings set clipboard.imagePaste true
if ($LASTEXITCODE) { Stop-Install "sbx settings set clipboard.imagePaste failed (exit code $LASTEXITCODE)" }
