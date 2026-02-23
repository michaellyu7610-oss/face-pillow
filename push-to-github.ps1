# Push to GitHub and trigger APK build
# Create empty repo at https://github.com/new first

$username = Read-Host "GitHub username"
$repo = Read-Host "Repo name (e.g. face-pillow)"
if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($repo)) {
    Write-Host "Username and repo required"
    exit 1
}

$remoteUrl = "https://github.com/$username/$repo.git"
Set-Location -LiteralPath $PSScriptRoot

git remote remove origin 2>$null
git remote add origin $remoteUrl
git branch -M main
Write-Host "Pushing to $remoteUrl ..."
git push -u origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Done! Check https://github.com/$username/$repo/actions for APK build"
}
