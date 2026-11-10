@echo off
REM Wrapper to run Linux path compatibility audit without execution policy issues
REM Usage: run-audit.cmd [arguments]

cd /d "%~dp0"
echo %* | findstr /i /c:"-Roots" >nul
if errorlevel 1 (
	echo.
	echo Usage: run-audit.cmd -Roots ^<path1[,path2,...]^> [-OutputDir docs] [-ReportFileName linux-path-compat-report.html] [-NoOpenReport]
	echo Example: run-audit.cmd -Roots src/base,src/med10 -OutputDir docs -ReportFileName linux-path-compat-report.html
	echo.
	exit /b 1
)

powershell -NoProfile -File ".\generate-linux-path-compat-report.ps1" %*
