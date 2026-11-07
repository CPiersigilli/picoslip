@echo off
rem Builds and runs the golden-corpus generators into build\corpus (see docs\golden-corpus.md).
setlocal
cd /d "%~dp0\.."
if /i not "%VSCMD_ARG_TGT_ARCH%"=="x64" call :compiler
if errorlevel 1 exit /b 1
if not exist build mkdir build
set "CORPUS_CFLAGS=/nologo /TC /std:c17 /W4 /WX /O2 /MT /utf-8 /Fd"build\corpus.pdb""
set "CORPUS_LIBS=build\corpus-archive.obj build\corpus-tags.obj build\corpus-search.obj build\corpus-location.obj user32.lib gdi32.lib shell32.lib dwmapi.lib comctl32.lib uxtheme.lib normaliz.lib ole32.lib uuid.lib"
rc /nologo /fo build\corpus.res src\picoslip.rc
if errorlevel 1 exit /b 1
for %%M in (archive tags search location) do (
    cl %CORPUS_CFLAGS% /c src\%%M.c /Fo"build\corpus-%%M.obj"
    if errorlevel 1 exit /b 1
)
cl %CORPUS_CFLAGS% tools\corpus.c /Fo"build\corpus.obj" /Fe"build\corpus.exe" /link build\corpus.res /SUBSYSTEM:CONSOLE /MANIFEST:EMBED /MANIFESTINPUT:src\app.manifest %CORPUS_LIBS%
if errorlevel 1 exit /b 1
cl %CORPUS_CFLAGS% tools\unicode_golden.c /Fo"build\unicode_golden.obj" /Fe"build\unicode_golden.exe" /link /SUBSYSTEM:CONSOLE build\corpus-tags.obj user32.lib normaliz.lib
if errorlevel 1 exit /b 1
if exist build\corpus rmdir /s /q build\corpus
mkdir build\corpus
build\corpus.exe "%CD%\build\corpus\corpus"
if errorlevel 1 exit /b 1
build\unicode_golden.exe "%CD%\build\corpus\unicode"
exit /b %errorlevel%

:compiler
set "CORPUS_VS="
if not exist "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" (
    echo Install Microsoft Build Tools with C/C++ tools and the Windows SDK.
    exit /b 1
)
for /f "usebackq delims=" %%I in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "CORPUS_VS=%%I"
if not defined CORPUS_VS exit /b 1
call "%CORPUS_VS%\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul
exit /b %errorlevel%
