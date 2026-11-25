@echo off
rem Build a single-ABI x86_64 debug APK (fast to install into MuMu).
call "%~dp0b.cmd" --target-platform android-x64
