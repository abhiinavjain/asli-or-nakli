@echo off
REM Asli-or-Nakli: copies the asli_match extension files into PostgreSQL.
REM Right-click -> "Run as administrator". Change PGVER if your version differs.
set PGVER=18
set PGEXT=C:\Program Files\PostgreSQL\%PGVER%\share\extension
if not exist "%PGEXT%" (
  echo Folder not found: %PGEXT%
  echo Edit PGVER in this file to your PostgreSQL version.
  pause
  exit /b 1
)
copy /Y "%~dp0asli_match.control" "%PGEXT%\"
copy /Y "%~dp0asli_match--1.0.sql" "%PGEXT%\"
echo Done. Now run the *_06_candidate_indexes.sql script for this database in DBeaver.
pause
