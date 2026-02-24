@echo off
chcp 65001 >nul
cd /d "%~dp0"

set GITHUB_USER=michaellyu7610-oss
set REPO_NAME=face-pillow

if "%GITHUB_USER%"=="YOUR_USERNAME" (
    echo Please edit PUSH.bat: set GITHUB_USER=your_github_username
    echo                and: set REPO_NAME=your_repo_name
    pause
    exit /b 1
)

git remote remove origin 2>nul
git remote add origin https://github.com/%GITHUB_USER%/%REPO_NAME%.git
git branch -M main
git push -u origin main

if %errorlevel%==0 (
    echo.
    echo Push OK! Open https://github.com/%GITHUB_USER%/%REPO_NAME%/actions
)
pause
