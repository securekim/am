@echo off
:: ==================================================
:: Author: securekim (https://securekim.com)
:: License: MIT License
:: ������ �����Ӱ� ���� �� ������ �� ������, ���� ǥ�⸸ ������ �ֽø� �˴ϴ�.
:: ==================================================
setlocal enabledelayedexpansion

set "VERSION=1.0.1"

:: ���� ���?����
set "CONFIG_BASE_DIR=%~dp0claude_configs"
if not exist "!CONFIG_BASE_DIR!" mkdir "!CONFIG_BASE_DIR!"
set "GLOBAL_PATH_FILE=!CONFIG_BASE_DIR!\last_path.txt"
set "LAST_ALIAS_FILE=!CONFIG_BASE_DIR!\last_alias.txt"
set "PS_SCRIPT=!CONFIG_BASE_DIR!\get_session.ps1"
set "MERGE_SCRIPT=!CONFIG_BASE_DIR!\merge_settings.ps1"
set "ARG1=%~1"
set "ARG2=%~2"
set "ARG3=%~3"
set "NEW_PATH="
set "TARGET_ALIAS="

:: PowerShell ��ũ��Ʈ ����
(
echo param^($ConfigDir, $CurrentPath, $MaxSessions^)
echo if ^([string]::IsNullOrEmpty^($MaxSessions^)^) { $MaxSessions = 1 }
echo $accName = ""
echo $accEmail = ""
echo $globalSessionId = ""
echo $claudeFile = Join-Path $ConfigDir ".claude.json"
echo $credFile = Join-Path $ConfigDir ".credentials.json"
echo $cData = $null
echo if ^(Test-Path $claudeFile^) {
echo     $cData = Get-Content $claudeFile -Encoding UTF8 -Raw -ErrorAction SilentlyContinue ^| ConvertFrom-Json -ErrorAction SilentlyContinue
echo     if ^($null -ne $cData^) {
echo         if ^($null -ne $cData.oauthAccount^) {
echo             if ^($null -ne $cData.oauthAccount.displayName^) { $accName = $cData.oauthAccount.displayName }
echo             if ^($null -ne $cData.oauthAccount.emailAddress^) { $accEmail = $cData.oauthAccount.emailAddress }
echo         }
echo     }
echo }
echo if ^(Test-Path $credFile^) {
echo     $credData = Get-Content $credFile -Encoding UTF8 -Raw -ErrorAction SilentlyContinue ^| ConvertFrom-Json -ErrorAction SilentlyContinue
echo     if ^($null -ne $credData^) {
echo         if ^($null -ne $credData.sessionId^) { $globalSessionId = $credData.sessionId }
echo     }
echo }
echo Write-Output "ACC_NAME=$accName"
echo Write-Output "ACC_EMAIL=$accEmail"
echo $allFiles = Get-ChildItem -Path "$ConfigDir" -Filter "*.jsonl" -Recurse -ErrorAction SilentlyContinue ^| Sort-Object LastWriteTime -Descending ^| Select-Object -First 30
echo $matchedFiles = @^(^)
echo foreach ^($file in $allFiles^) {
echo     if ^($matchedFiles.Count -ge $MaxSessions^) { break }
echo     $fileCwd = ""
echo     foreach ^($line in Get-Content $file.FullName -Encoding UTF8 -TotalCount 20 -ErrorAction SilentlyContinue^) {
echo         try { $obj = $line ^| ConvertFrom-Json -ErrorAction SilentlyContinue; if ^($null -ne $obj -and $null -ne $obj.cwd^) { $fileCwd = $obj.cwd; break } } catch {}
echo     }
echo     if ^([string]::IsNullOrEmpty^($CurrentPath^)^) {
echo         $matchedFiles += $file
echo     } else {
echo         $normFileCwd = $fileCwd -replace '\\', '/' -replace '/$', ''
echo         $normCurrPath = $CurrentPath -replace '\\', '/' -replace '/$', ''
echo         if ^($normFileCwd.TrimEnd^('/'^) -eq $normCurrPath.TrimEnd^('/'^)^) { $matchedFiles += $file }
echo     }
echo }
echo $projectSessionId = ""
echo if ^(-not [string]::IsNullOrEmpty^($CurrentPath^) -and $null -ne $cData -and $null -ne $cData.projects^) {
echo     $normCurrPath = $CurrentPath -replace '\\', '/' -replace '/$', ''
echo     foreach ^($prop in $cData.projects.psobject.properties^) {
echo         $keyNorm = $prop.Name -replace '\\', '/' -replace '/$', ''
echo         if ^($keyNorm -eq $normCurrPath^) { $projectSessionId = $prop.Value.lastSessionId; break }
echo     }
echo }
echo $primarySessionId = ""
echo if ^(-not [string]::IsNullOrEmpty^($projectSessionId^)^) {
echo     $lastIdValid = $false
echo     foreach ^($mf in $matchedFiles^) { if ^($mf.BaseName -eq $projectSessionId^) { $lastIdValid = $true; break } }
echo     if ^(-not $lastIdValid^) {
echo         $fc = Get-ChildItem -Path $ConfigDir -Recurse -Filter "$projectSessionId.jsonl" -ErrorAction SilentlyContinue ^| Select-Object -First 1
echo         if ^($null -ne $fc^) { $lastIdValid = $true }
echo     }
echo     if ^($lastIdValid^) { $primarySessionId = $projectSessionId }
echo     elseif ^($matchedFiles.Count -gt 0^) { $primarySessionId = $matchedFiles[0].BaseName }
echo } elseif ^($matchedFiles.Count -gt 0^) { $primarySessionId = $matchedFiles[0].BaseName }
echo elseif ^([string]::IsNullOrEmpty^($CurrentPath^)^) { $primarySessionId = $globalSessionId }
echo if ^([string]::IsNullOrEmpty^($primarySessionId^)^) { Write-Output "S_COUNT=0"; exit }
echo $cwd = "���� ���� ����"
echo $branch = "���� ���� ����"
echo $time = "���� ���� ����"
echo $userMsg = "���� ���� ����"
echo $assistantMsg = "���� ���� ����"
echo if ^($matchedFiles.Count -gt 0^) {
echo     foreach ^($line in Get-Content $matchedFiles[0].FullName -Encoding UTF8^) {
echo         try {
echo             $obj = $line ^| ConvertFrom-Json -ErrorAction SilentlyContinue
echo             if ^($null -ne $obj^) {
echo                 if ^($null -ne $obj.cwd^) { $cwd = $obj.cwd }
echo                 if ^($null -ne $obj.gitBranch^) { $branch = $obj.gitBranch }
echo                 if ^($null -ne $obj.timestamp^) { $time = $obj.timestamp }
echo                 if ^($obj.type -eq 'last-prompt' -and $null -ne $obj.lastPrompt^) { $userMsg = $obj.lastPrompt }
echo                 if ^($obj.type -eq 'assistant' -and $null -ne $obj.message.content^) { $assistantMsg = $obj.message.content }
echo             }
echo         } catch {}
echo     }
echo }
echo $userMsg = $userMsg.Substring^(0, [Math]::Min^($userMsg.Length, 47^)^) + '...'
echo $assistantMsg = $assistantMsg.Substring^(0, [Math]::Min^($assistantMsg.Length, 47^)^) + '...'
echo $userMsg = $userMsg -replace "\r", " " -replace "\n", " "
echo $assistantMsg = $assistantMsg -replace "\r", " " -replace "\n", " "
echo Write-Output "S_ID=$primarySessionId"
echo Write-Output "S_PATH=$cwd"
echo Write-Output "S_BRANCH=$branch"
echo Write-Output "S_TIME=$time"
echo Write-Output "S_USER=$userMsg"
echo Write-Output "S_ASSISTANT=$assistantMsg"
echo $count = 0
echo foreach ^($file in $matchedFiles^) {
echo     $count++
echo     $cwd = "���� ���� ����"
echo     $branch = "���� ���� ����"
echo     $time = "���� ���� ����"
echo     $userMsg = "���� ���� ����"
echo     $assistantMsg = "���� ���� ����"
echo     foreach ^($line in Get-Content $file.FullName -Encoding UTF8^) {
echo         try {
echo             $obj = $line ^| ConvertFrom-Json -ErrorAction SilentlyContinue
echo             if ^($null -ne $obj^) {
echo                 if ^($null -ne $obj.cwd^) { $cwd = $obj.cwd }
echo                 if ^($null -ne $obj.gitBranch^) { $branch = $obj.gitBranch }
echo                 if ^($null -ne $obj.timestamp^) { $time = $obj.timestamp }
echo                 if ^($obj.type -eq 'last-prompt' -and $null -ne $obj.lastPrompt^) { $userMsg = $obj.lastPrompt }
echo                 if ^($obj.type -eq 'assistant' -and $null -ne $obj.message.content^) { $assistantMsg = $obj.message.content }
echo             }
echo         } catch {}
echo     }
echo     $userMsg = $userMsg.Substring^(0, [Math]::Min^($userMsg.Length, 47^)^) + '...'
echo     $assistantMsg = $assistantMsg.Substring^(0, [Math]::Min^($assistantMsg.Length, 47^)^) + '...'
echo     $userMsg = $userMsg -replace "\r", " " -replace "\n", " "
echo     $assistantMsg = $assistantMsg -replace "\r", " " -replace "\n", " "
echo     Write-Output "S_ID_$count=$($file.BaseName)"
echo     Write-Output "S_PATH_$count=$cwd"
echo     Write-Output "S_BRANCH_$count=$branch"
echo     Write-Output "S_TIME_$count=$time"
echo     Write-Output "S_USER_$count=$userMsg"
echo     Write-Output "S_ASSISTANT_$count=$assistantMsg"
echo }
echo Write-Output "S_COUNT=$count"
) > "!PS_SCRIPT!"

:: settings.json �÷�����/�� Ű ���� ��ũ��Ʈ (�۷ι� -^> alias)
(
echo param^($AliasDir, $GlobalDir^)
echo $g = Join-Path $GlobalDir "settings.json"
echo $a = Join-Path $AliasDir "settings.json"
echo if ^(-not ^(Test-Path $g^)^) { exit }
echo try { $gd = Get-Content $g -Raw -Encoding UTF8 ^| ConvertFrom-Json } catch { exit }
echo $ad = $null
echo if ^(Test-Path $a^) { try { $ad = Get-Content $a -Raw -Encoding UTF8 ^| ConvertFrom-Json } catch {} }
echo if ^($null -eq $ad^) { $ad = New-Object PSObject }
echo foreach ^($k in 'hooks','statusLine','extraKnownMarketplaces','enabledPlugins'^) {
echo     if ^($gd.PSObject.Properties.Name -contains $k^) {
echo         Add-Member -InputObject $ad -NotePropertyName $k -NotePropertyValue $gd.$k -Force
echo     }
echo }
echo $json = $ad ^| ConvertTo-Json -Depth 32
echo [IO.File]::WriteAllText^($a, $json, [Text.UTF8Encoding]::new^($false^)^)
) > "!MERGE_SCRIPT!"

:: 1. Ư�� ���ɾ� ó��
if /i "!ARG1!"=="" goto :START_PARSE
if /i "!ARG1!"=="-h" goto :SHOW_HELP
if /i "!ARG1!"=="--help" goto :SHOW_HELP
if /i "!ARG1!"=="login" goto :DO_LOGIN
if /i "!ARG1!"=="copy" goto :DO_COPY
if /i "!ARG1!"=="reset" goto :DO_RESET
if /i "!ARG1!"=="logout" goto :DO_LOGOUT
if /i "!ARG1!"=="remote" goto :DO_REMOTE
if /i "!ARG1!"=="info" goto :DO_INFO
if /i "!ARG1!"=="version" goto :DO_VERSION

:START_PARSE
:: 2. �μ� �м�: ���?���ڿ����� ���� Alias���� ����
if not "!ARG1!"=="" (
    if exist "!ARG1!\" (
        set "NEW_PATH=!ARG1!"
    ) else (
        set "TARGET_ALIAS=!ARG1!"
        if not "!ARG2!"=="" (
            if exist "!ARG2!\" (
                set "NEW_PATH=!ARG2!"
            )
        )
    )
)

:: 3. ���� �������� ����
if "!TARGET_ALIAS!"=="" (
    if exist "!LAST_ALIAS_FILE!" set /p TARGET_ALIAS=<"!LAST_ALIAS_FILE!"
)

if not "!TARGET_ALIAS!"=="" (
    if exist "!CONFIG_BASE_DIR!\!TARGET_ALIAS!" (
        set "CLAUDE_CONFIG_DIR=!CONFIG_BASE_DIR!\!TARGET_ALIAS!"
        echo !TARGET_ALIAS!>"!LAST_ALIAS_FILE!"
        echo [���� ����] ���� Alias '!TARGET_ALIAS!' �������Ϸ� �����մϴ�.
    ) else (
        echo [����] '!TARGET_ALIAS!' ���� Alias�� �ش��ϴ� ���������� �����ϴ�. %~n0 login�� ���� �����ϼ���.
        goto :EOF
    )
) else (
    echo [����] ������ ���������� �����ϴ�. %~n0 login�� ���� �����ϼ���.
    goto :EOF
)

:: ���� ȯ�� ���?�÷����� �� �� ���͸� ������ ���� ����
set "GLOBAL_CLAUDE_DIR=%USERPROFILE%\.claude"
if not exist "!GLOBAL_CLAUDE_DIR!\plugins" mkdir "!GLOBAL_CLAUDE_DIR!\plugins"
if not exist "!GLOBAL_CLAUDE_DIR!\hooks" mkdir "!GLOBAL_CLAUDE_DIR!\hooks"

for %%D in (plugins hooks) do (
    fsutil reparsepoint query "!CLAUDE_CONFIG_DIR!\%%D" >nul 2>&1
    if errorlevel 1 (
        if exist "!CLAUDE_CONFIG_DIR!\%%D" (
            xcopy /E /Y /I "!CLAUDE_CONFIG_DIR!\%%D\*" "!GLOBAL_CLAUDE_DIR!\%%D\" >nul 2>&1
            rmdir /S /Q "!CLAUDE_CONFIG_DIR!\%%D"
        )
        mklink /J "!CLAUDE_CONFIG_DIR!\%%D" "!GLOBAL_CLAUDE_DIR!\%%D" >nul 2>&1
    )
)

:: MCP ���� ���� ����ȭ
if exist "!GLOBAL_CLAUDE_DIR!\mcp.json" (
    copy /Y "!GLOBAL_CLAUDE_DIR!\mcp.json" "!CLAUDE_CONFIG_DIR!\mcp.json" >nul 2>&1
)

:: settings.json �÷�����/�� Ű �ڵ� ���� (�۷ι� -^> alias, caveman ��)
powershell -NoProfile -ExecutionPolicy Bypass -File "!MERGE_SCRIPT!" "!CLAUDE_CONFIG_DIR!" "!GLOBAL_CLAUDE_DIR!" >nul 2>&1

:: 4. ���?ó��
set "PROFILE_PATH_FILE=!CLAUDE_CONFIG_DIR!\last_path.txt"

if not "!NEW_PATH!"=="" (
    echo !NEW_PATH!>"!PROFILE_PATH_FILE!"
    echo !NEW_PATH!>"!GLOBAL_PATH_FILE!"
)

set "LAST_PATH="
if exist "!PROFILE_PATH_FILE!" set /p LAST_PATH=<"!PROFILE_PATH_FILE!"
if "!LAST_PATH!"=="" (
    if exist "!GLOBAL_PATH_FILE!" set /p LAST_PATH=<"!GLOBAL_PATH_FILE!"
)

if "!LAST_PATH!"=="" (
    echo.
    set /p LAST_PATH="�̵��� ��θ�?�Է��ϼ���: "
    echo !LAST_PATH!>"!PROFILE_PATH_FILE!"
    echo !LAST_PATH!>"!GLOBAL_PATH_FILE!"
)

:: 5. �ڵ� ���� ���� Ȯ�� �� �簳 ���� ����
set "RESUME_ARG="
powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!" "!CLAUDE_CONFIG_DIR!" "!LAST_PATH!" > "!CONFIG_BASE_DIR!\temp_session.txt"
set "S_ID="
for /f "tokens=1,* delims==" %%A in ('type "!CONFIG_BASE_DIR!\temp_session.txt"') do (
    if "%%A"=="S_ID" (
        set "TMP_ID=%%B"
        set "S_ID=!TMP_ID:~0,36!"
    )
    if "%%A"=="S_PATH" set "S_PATH=%%B"
    if "%%A"=="S_BRANCH" set "S_BRANCH=%%B"
    if "%%A"=="S_TIME" set "S_TIME=%%B"
    if "%%A"=="S_USER" set "S_USER=%%B"
)

if not "!S_ID!"=="" (
    echo --------------------------------------------------
    echo [�ֱ� ���� ����]
    echo  - �۾� ��ġ: !S_PATH!
    echo  - ���� �ð�: !S_TIME!
    echo  - �ֱ� �Է�: !S_USER!
    echo --------------------------------------------------

    :ASK_SESSION
    set "USE_SESSION="
    set /p USE_SESSION="�ֱ� ������ �̾ �����ұ��? (y/n) �Ǵ� ���� ���� �˻� ���� �Է�(����): "

    if /i "!USE_SESSION!"=="y" (
        set "RESUME_ARG=--resume !S_ID!"
        goto :RUN_CLAUDE
    )
    if /i "!USE_SESSION!"=="n" (
        goto :RUN_CLAUDE
    )

    if "!USE_SESSION!"=="" goto :ASK_SESSION

    set /a NUM_CHECK=!USE_SESSION! 2>nul
    if "!NUM_CHECK!"=="!USE_SESSION!" (
        if !USE_SESSION! GTR 0 (
            goto :FETCH_MULTIPLE_SESSIONS
        )
    )
    goto :ASK_SESSION

    :FETCH_MULTIPLE_SESSIONS
    echo �ֱ� !USE_SESSION!���� ������ �˻��մϴ�...
    set "FOUND_COUNT=0"
    for /f "tokens=1,* delims==" %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!" "!CLAUDE_CONFIG_DIR!" "!LAST_PATH!" "!USE_SESSION!"') do (
        if "%%A"=="S_COUNT" set "FOUND_COUNT=%%B"
        for /l %%I in (1,1,!USE_SESSION!) do (
            if "%%A"=="S_ID_%%I" (
                set "TMP_ID=%%B"
                set "M_ID_%%I=!TMP_ID:~0,36!"
            )
            if "%%A"=="S_PATH_%%I" set "M_PATH_%%I=%%B"
            if "%%A"=="S_BRANCH_%%I" set "M_BRANCH_%%I=%%B"
            if "%%A"=="S_TIME_%%I" set "M_TIME_%%I=%%B"
            if "%%A"=="S_USER_%%I" set "M_USER_%%I=%%B"
            if "%%A"=="S_ASSISTANT_%%I" set "M_ASSISTANT_%%I=%%B"
        )
    )

    if "!FOUND_COUNT!"=="0" (
        echo ���� ������ �����ϴ�.
        goto :ASK_SESSION
    )

    echo --------------------------------------------------
    for /l %%I in (1,1,!FOUND_COUNT!) do (
        echo [%%I] �ð�: !M_TIME_%%I! ^| �Է�: !M_USER_%%I! ^| ����: !M_ASSISTANT_%%I!
    )
    echo --------------------------------------------------

    :SELECT_SESSION
    set "SEL_INDEX="
    set /p SEL_INDEX="������ ���� ��ȣ�� �Է��ϼ��� (���? c): "
    if /i "!SEL_INDEX!"=="c" goto :ASK_SESSION

    set "SELECTED_ID="
    for /l %%I in (1,1,!FOUND_COUNT!) do (
        if "!SEL_INDEX!"=="%%I" set "SELECTED_ID=!M_ID_%%I!"
    )

    if not "!SELECTED_ID!"=="" (
        set "RESUME_ARG=--resume !SELECTED_ID!"
        goto :RUN_CLAUDE
    ) else (
        echo �߸��� ��ȣ�Դϴ�.
        goto :SELECT_SESSION
    )
) else (
    echo [�ȳ�] �߰ߵ� ���� ���� ����.
)

:RUN_CLAUDE
:: 6. Claude ����
del "!CONFIG_BASE_DIR!\temp_session.txt" 2>nul
echo.
echo "!LAST_PATH!" ��ġ���� Claude�� �����մϴ�...
echo.

cd /d "!LAST_PATH!"
claude !RESUME_ARG!

:: ���� ���� �� ���ÿ��� �����?MCP ������ �������� ����ȭ
if exist "!CLAUDE_CONFIG_DIR!\mcp.json" (
    copy /Y "!CLAUDE_CONFIG_DIR!\mcp.json" "!GLOBAL_CLAUDE_DIR!\mcp.json" >nul 2>&1
)

pause
goto :EOF

:: ==================================================
:: ���ɾ� ó�� �Լ� ����
:: ==================================================

:DO_VERSION
echo Claude Code �����?����: !VERSION!
goto :EOF

:DO_LOGIN
set /p NEW_ALIAS="�α����� ���� Alias�� �Է��ϼ���: "
if not exist "!CONFIG_BASE_DIR!\!NEW_ALIAS!" mkdir "!CONFIG_BASE_DIR!\!NEW_ALIAS!"
set "CLAUDE_CONFIG_DIR=!CONFIG_BASE_DIR!\!NEW_ALIAS!"
echo !NEW_ALIAS!>"!LAST_ALIAS_FILE!"
echo [�ȳ�] '!NEW_ALIAS!' ���� Alias �������� ȯ�濡�� �α����� �����մϴ�.
claude login
goto :EOF

:DO_COPY
set "SRC_ALIAS=!ARG2!"
set "NEW_ALIAS=!ARG3!"
if "!SRC_ALIAS!"=="" (
    set /p SRC_ALIAS="���� ���� Alias�� �Է��ϼ���: "
)
if "!NEW_ALIAS!"=="" (
    set /p NEW_ALIAS="������ ���� ���� Alias�� �Է��ϼ���: "
)

if not exist "!CONFIG_BASE_DIR!\!SRC_ALIAS!" (
    echo [����] ���� ���� '!SRC_ALIAS!'�� �������� �ʽ��ϴ�.
    goto :EOF
)
if exist "!CONFIG_BASE_DIR!\!NEW_ALIAS!" (
    echo [����] ���?���� '!NEW_ALIAS!'�� �̹� �����մϴ�.
    goto :EOF
)

mkdir "!CONFIG_BASE_DIR!\!NEW_ALIAS!"
for %%F in ("!CONFIG_BASE_DIR!\!SRC_ALIAS!\*") do (
    if /i not "%%~nxF"=="last_path.txt" (
        copy /Y "%%F" "!CONFIG_BASE_DIR!\!NEW_ALIAS!\" >nul
    )
)

set "CLAUDE_CONFIG_DIR=!CONFIG_BASE_DIR!\!NEW_ALIAS!"
echo !NEW_ALIAS!>"!LAST_ALIAS_FILE!"

echo [�ȳ�] '!SRC_ALIAS!' ������ ���� ������ �����Ͽ� �������� �� ���� '!NEW_ALIAS!'�� �����߽��ϴ�.
goto :EOF

:DO_RESET
echo claude_configs ������ ���?�����͸� �ʱ�ȭ�մϴ�.
if exist "!CONFIG_BASE_DIR!" rmdir /s /q "!CONFIG_BASE_DIR!"
mkdir "!CONFIG_BASE_DIR!"
echo �ʱ�ȭ�� �Ϸ�Ǿ����ϴ�?
goto :EOF

:DO_LOGOUT
set "LOGOUT_ALIAS=!ARG2!"
if "!LOGOUT_ALIAS!"=="" (
    echo [����] �α׾ƿ��� ���� Alias�� �Է��ϼ���. ��: %~n0 logout a
    goto :EOF
)
if exist "!CONFIG_BASE_DIR!\!LOGOUT_ALIAS!" (
    rmdir /s /q "!CONFIG_BASE_DIR!\!LOGOUT_ALIAS!"
    echo [�ȳ�] '!LOGOUT_ALIAS!' ���� ������ �����Ǿ����ϴ�.
    if exist "!LAST_ALIAS_FILE!" (
        set /p CUR_LAST_ALIAS=<"!LAST_ALIAS_FILE!"
        if "!CUR_LAST_ALIAS!"=="!LOGOUT_ALIAS!" del "!LAST_ALIAS_FILE!"
    )
) else (
    echo [����] '!LOGOUT_ALIAS!' ���� Alias�� ã�� �� �����ϴ�.
)
goto :EOF

:DO_INFO
echo ==================================================
echo                �����?���� ���� ���?
echo ==================================================
if not exist "!CONFIG_BASE_DIR!" (
    echo �����?���� ������ �����ϴ�.
    goto :EOF
)

set "GLOBAL_LAST_PATH="
if exist "!GLOBAL_PATH_FILE!" set /p GLOBAL_LAST_PATH=<"!GLOBAL_PATH_FILE!"

if not "!GLOBAL_LAST_PATH!"=="" (
    echo [���� ������ ���?: !GLOBAL_LAST_PATH!
    echo --------------------------------------------------
)

for /d %%D in ("!CONFIG_BASE_DIR!\*") do (
    if /i not "%%~nxD"=="shared" (
        powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!" "%%D" "" > "!CONFIG_BASE_DIR!\temp_info.txt"
        set "A_NAME=Unknown"
        set "A_EMAIL=Unknown"

        for /f "tokens=1,* delims==" %%A in ('type "!CONFIG_BASE_DIR!\temp_info.txt"') do (
            if "%%A"=="ACC_NAME" if not "%%B"=="" set "A_NAME=%%B"
            if "%%A"=="ACC_EMAIL" if not "%%B"=="" set "A_EMAIL=%%B"
        )

        set "A_PATH=�����ξ���"
        if exist "%%D\last_path.txt" set /p A_PATH=<"%%D\last_path.txt"

        echo [���� Alias: %%~nxD] !A_NAME! - !A_EMAIL!
        echo  - ���? !A_PATH!

        set "SI="
        for /f "tokens=1,* delims==" %%A in ('type "!CONFIG_BASE_DIR!\temp_info.txt"') do (
            if "%%A"=="S_ID" (
                set "TMP_ID=%%B"
                set "SI=!TMP_ID:~0,36!"
            )
        )
        if "!SI!"=="" (
            echo  - ����: ���� ���� ����
        ) else (
            echo  - ����: !SI!
        )
        echo.
    )
)
del "!CONFIG_BASE_DIR!\temp_info.txt" 2>nul
echo ==================================================
goto :EOF

:DO_REMOTE
set "REMOTE_ALIAS=!ARG2!"
set "REMOTE_PATH=!ARG3!"
if "!REMOTE_ALIAS!"=="" (
    echo [error] alias required. example: %~n0 remote a [path]
    goto :EOF
)
if not exist "!CONFIG_BASE_DIR!\!REMOTE_ALIAS!" (
    echo [error] alias '!REMOTE_ALIAS!' profile not found. run %~n0 login first.
    goto :EOF
)
set "CLAUDE_CONFIG_DIR=!CONFIG_BASE_DIR!\!REMOTE_ALIAS!"
echo !REMOTE_ALIAS!>"!LAST_ALIAS_FILE!"

set "GLOBAL_CLAUDE_DIR=%USERPROFILE%\.claude"
if not exist "!GLOBAL_CLAUDE_DIR!\plugins" mkdir "!GLOBAL_CLAUDE_DIR!\plugins"
if not exist "!GLOBAL_CLAUDE_DIR!\hooks" mkdir "!GLOBAL_CLAUDE_DIR!\hooks"
for %%D in (plugins hooks) do (
    fsutil reparsepoint query "!CLAUDE_CONFIG_DIR!\%%D" >nul 2>&1
    if errorlevel 1 (
        if exist "!CLAUDE_CONFIG_DIR!\%%D" (
            xcopy /E /Y /I "!CLAUDE_CONFIG_DIR!\%%D\*" "!GLOBAL_CLAUDE_DIR!\%%D\" >nul 2>&1
            rmdir /S /Q "!CLAUDE_CONFIG_DIR!\%%D"
        )
        mklink /J "!CLAUDE_CONFIG_DIR!\%%D" "!GLOBAL_CLAUDE_DIR!\%%D" >nul 2>&1
    )
)
if exist "!GLOBAL_CLAUDE_DIR!\mcp.json" copy /Y "!GLOBAL_CLAUDE_DIR!\mcp.json" "!CLAUDE_CONFIG_DIR!\mcp.json" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "!MERGE_SCRIPT!" "!CLAUDE_CONFIG_DIR!" "!GLOBAL_CLAUDE_DIR!" >nul 2>&1

set "PROFILE_PATH_FILE=!CLAUDE_CONFIG_DIR!\last_path.txt"
set "TARGET_PATH="
if not "!REMOTE_PATH!"=="" (
    if exist "!REMOTE_PATH!\" set "TARGET_PATH=!REMOTE_PATH!"
)
if "!TARGET_PATH!"=="" (
    if exist "!PROFILE_PATH_FILE!" set /p TARGET_PATH=<"!PROFILE_PATH_FILE!"
)
if "!TARGET_PATH!"=="" (
    if exist "!GLOBAL_PATH_FILE!" set /p TARGET_PATH=<"!GLOBAL_PATH_FILE!"
)
if "!TARGET_PATH!"=="" (
    echo [error] no valid path. provide path arg or set via normal run first.
    goto :EOF
)
if not exist "!TARGET_PATH!\" (
    echo [error] path '!TARGET_PATH!' does not exist.
    goto :EOF
)
echo !TARGET_PATH!>"!PROFILE_PATH_FILE!"
echo !TARGET_PATH!>"!GLOBAL_PATH_FILE!"

for %%F in ("!TARGET_PATH!") do set "FOLDER=%%~nxF"
set "WIN_TITLE=claude-remote-!REMOTE_ALIAS!-!FOLDER!"

echo [remote] alias='!REMOTE_ALIAS!' path='!TARGET_PATH!' folder='!FOLDER!'
echo [remote] title='!WIN_TITLE!'
echo [remote] CLAUDE_CONFIG_DIR='!CLAUDE_CONFIG_DIR!'

pushd "!TARGET_PATH!"
start "!WIN_TITLE!" /MIN cmd /k claude --remote-control "!FOLDER!"
popd
echo [done] https://claude.ai/code remote control available.
echo [info] window title: !WIN_TITLE!
goto :EOF

:SHOW_HELP
echo ==================================================
echo                Claude Code �����?v!VERSION!
echo ==================================================
echo [����]
echo  %~n0                        : ���������� �����?������ ������ ��ο���?����
echo  %~n0 login                  : ���ο� ���� �������� ���� �� �α���
echo  %~n0 copy [����Alias] [�ű�Alias] : ���� ������ ���� ������ �����Ͽ� �������� �� ���� ����
echo  %~n0 logout [Alias]         : Ư�� ���� Alias ���� �� ���� ����
echo  %~n0 reset                  : �����?���?����, ���? ���� ���� �ʱ�ȭ
echo  %~n0 remote [Alias] [path]   : alias profile + 'claude --remote-control' background cmd window (claude.ai/code)
echo  %~n0 info                   : �����?���� ���?�� ���� ���� ���?
echo  %~n0 version                : ���� ��ũ��Ʈ ���� ���?
echo  %~n0 [���� Alias]           : ������ ������ ������ ���?�Ǵ� ��ü ������ ��ο���?����
echo  %~n0 [���?                 : ������ �������� ������ ��ο���?����
echo  %~n0 [���� Alias] [���?    : ������ �������� ������ ��ο���?����
echo  %~n0 -h, --help             : ���� ���� ǥ��
echo.
echo [���?����]
echo  - ���� �������� ���? ���� ���丮�� Ȱ���Ͽ� �������� ������ ȯ�� ����
echo  - ���� ���� ���? copy ���ɾ ���� ���� ������ �����ϸ鼭 �۾� ������ �и��� ���ο� ȯ�� ����
echo  - �۾� ���?����: �������� ������ �۾� ��θ�?���?
echo  - �÷����� �� �� ����: �����?���� ���� ���� �������?���͸� ������(Junction)�� �����Ͽ� �ڿ� ����
echo  - �ڵ� ���� ����: ���� �� ���� �Է� ���� Claude�� ������ jsonl ���Ͽ��� �ڵ����� ������ �۾� ���� ����
echo.
echo [����]
echo  %~n0 login                  -^> ���� Alias a�� �α���
echo  %~n0 copy a a1              -^> a ���� ������ �����Ͽ� �۾� ������ �������� a1 ���� ����
echo  %~n0 a D:\workspace         -^> a �������� D:\workspace ���� �۾� �� ���� �� �ڵ� ���� ����
echo  %~n0 a1 E:\project          -^> a1 �������� E:\project ���� �۾�
echo  %~n0 logout a1              -^> a1 ���� ���� ����
echo  %~n0 reset                  -^> ��ü ���� �ʱ�ȭ
echo ==================================================
goto :EOF
