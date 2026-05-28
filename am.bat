@echo off
:: ==================================================
:: Author: securekim (https://securekim.com)
:: License: MIT License
:: 자유롭게 수정·사용 가능. 원본 표기만 남겨주세요.
:: ==================================================
setlocal enabledelayedexpansion

set "VERSION=1.1.15"

:: 기본 경로 설정
set "CONFIG_BASE_DIR=%~dp0claude_configs"
if not exist "!CONFIG_BASE_DIR!" mkdir "!CONFIG_BASE_DIR!"
set "GLOBAL_PATH_FILE=!CONFIG_BASE_DIR!\last_path.txt"
set "LAST_ALIAS_FILE=!CONFIG_BASE_DIR!\last_alias.txt"
set "PATH_ALIAS_FILE=!CONFIG_BASE_DIR!\path_aliases.txt"
set "PS_SCRIPT=!CONFIG_BASE_DIR!\get_session.ps1"
set "MERGE_SCRIPT=!CONFIG_BASE_DIR!\merge_settings.ps1"
set "ARG1=%~1"
set "ARG2=%~2"
set "ARG3=%~3"
set "NEW_PATH="
set "TARGET_ALIAS="

:: 예약어 (계정/경로 alias 로 사용 불가)
set "RESERVED_WORDS=login copy reset logout remote close account alias version path help install uninstall"

:: PowerShell 스크립트 생성
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
echo $cwd = "알 수 없음"
echo $branch = "알 수 없음"
echo $time = "알 수 없음"
echo $userMsg = "알 수 없음"
echo $assistantMsg = "알 수 없음"
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
echo     $cwd = "알 수 없음"
echo     $branch = "알 수 없음"
echo     $time = "알 수 없음"
echo     $userMsg = "알 수 없음"
echo     $assistantMsg = "알 수 없음"
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

:: settings.json 일부 키 머지 스크립트 (글로벌 -^> alias)
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

call :CHECK_INSTALL_HINT

:: 1. 특수 명령어 처리
if /i "!ARG1!"=="" goto :START_PARSE
if /i "!ARG1!"=="-h" goto :SHOW_HELP
if /i "!ARG1!"=="--help" goto :SHOW_HELP
if /i "!ARG1!"=="login" goto :DO_LOGIN
if /i "!ARG1!"=="copy" goto :DO_COPY
if /i "!ARG1!"=="reset" goto :DO_RESET
if /i "!ARG1!"=="logout" goto :DO_LOGOUT
if /i "!ARG1!"=="remote" goto :DO_REMOTE
if /i "!ARG1!"=="close" goto :DO_CLOSE
if /i "!ARG1!"=="account" goto :DO_ACCOUNT
if /i "!ARG1!"=="version" goto :DO_VERSION
if /i "!ARG1!"=="path" goto :DO_PATH
if /i "!ARG1!"=="alias" goto :DO_ALIAS
if /i "!ARG1!"=="install" goto :DO_INSTALL
if /i "!ARG1!"=="uninstall" goto :DO_UNINSTALL

:START_PARSE
:: 2. 인자 분석: 경로 / 계정 Alias / 경로 Alias
if not "!ARG1!"=="" (
    if exist "!ARG1!\" (
        set "NEW_PATH=!ARG1!"
        goto :AFTER_PARSE
    )
    if not exist "!CONFIG_BASE_DIR!\!ARG1!" (
        call :GET_PATH_ALIAS "!ARG1!"
        if not "!RESOLVED_PATH!"=="" (
            if exist "!RESOLVED_PATH!\" (
                set "NEW_PATH=!RESOLVED_PATH!"
                goto :AFTER_PARSE
            )
        )
    )
    set "TARGET_ALIAS=!ARG1!"
    if not "!ARG2!"=="" (
        if exist "!ARG2!\" (
            set "NEW_PATH=!ARG2!"
        ) else (
            call :GET_PATH_ALIAS "!ARG2!"
            if not "!RESOLVED_PATH!"=="" (
                if exist "!RESOLVED_PATH!\" set "NEW_PATH=!RESOLVED_PATH!"
            )
        )
    )
)
:AFTER_PARSE

:: 3. 프로파일 결정
if "!TARGET_ALIAS!"=="" (
    if exist "!LAST_ALIAS_FILE!" set /p TARGET_ALIAS=<"!LAST_ALIAS_FILE!"
)

if not "!TARGET_ALIAS!"=="" (
    if exist "!CONFIG_BASE_DIR!\!TARGET_ALIAS!" (
        set "CLAUDE_CONFIG_DIR=!CONFIG_BASE_DIR!\!TARGET_ALIAS!"
        echo !TARGET_ALIAS!>"!LAST_ALIAS_FILE!"
        echo [프로필 적용] 계정 Alias '!TARGET_ALIAS!' 프로파일로 실행합니다.
    ) else (
        echo [오류] '!TARGET_ALIAS!' 계정 Alias에 해당하는 프로파일이 없습니다. %~n0 login 으로 먼저 생성하세요.
        goto :EOF
    )
) else (
    echo [오류] 사용할 프로파일이 없습니다. %~n0 login 으로 먼저 생성하세요.
    goto :EOF
)

:: 전역 환경의 plugins/hooks 디렉터리 심볼릭 링크 공유
set "GLOBAL_CLAUDE_DIR=%USERPROFILE%\.claude"
if not exist "!GLOBAL_CLAUDE_DIR!\plugins" mkdir "!GLOBAL_CLAUDE_DIR!\plugins"
if not exist "!GLOBAL_CLAUDE_DIR!\hooks" mkdir "!GLOBAL_CLAUDE_DIR!\hooks"
if not exist "!GLOBAL_CLAUDE_DIR!\skills" mkdir "!GLOBAL_CLAUDE_DIR!\skills"
if not exist "!GLOBAL_CLAUDE_DIR!\agents" mkdir "!GLOBAL_CLAUDE_DIR!\agents"

for %%D in (plugins hooks skills agents) do (
    fsutil reparsepoint query "!CLAUDE_CONFIG_DIR!\%%D" >nul 2>&1
    if errorlevel 1 (
        if exist "!CLAUDE_CONFIG_DIR!\%%D" (
            xcopy /E /Y /I "!CLAUDE_CONFIG_DIR!\%%D\*" "!GLOBAL_CLAUDE_DIR!\%%D\" >nul 2>&1
            rmdir /S /Q "!CLAUDE_CONFIG_DIR!\%%D"
        )
        mklink /J "!CLAUDE_CONFIG_DIR!\%%D" "!GLOBAL_CLAUDE_DIR!\%%D" >nul 2>&1
    )
)

:: MCP 설정 파일 동기화
if exist "!GLOBAL_CLAUDE_DIR!\mcp.json" (
    copy /Y "!GLOBAL_CLAUDE_DIR!\mcp.json" "!CLAUDE_CONFIG_DIR!\mcp.json" >nul 2>&1
)

:: settings.json 일부 키 머지 (글로벌 -^> alias)
powershell -NoProfile -ExecutionPolicy Bypass -File "!MERGE_SCRIPT!" "!CLAUDE_CONFIG_DIR!" "!GLOBAL_CLAUDE_DIR!" >nul 2>&1

:: 4. 경로 처리
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
    set /p LAST_PATH="이동할 경로를 입력하세요: "
    echo !LAST_PATH!>"!PROFILE_PATH_FILE!"
    echo !LAST_PATH!>"!GLOBAL_PATH_FILE!"
)

:: 5. 자동 세션 감지 및 재개 처리
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
    echo [최근 세션 정보]
    echo  - 작업 위치: !S_PATH!
    echo  - 마지막 시각: !S_TIME!
    echo  - 최근 입력: !S_USER!
    echo --------------------------------------------------

    :ASK_SESSION
    set "USE_SESSION="
    set /p USE_SESSION="최근 세션을 이어서 진행할까요? (y/n) 또는 검색할 세션 개수 입력(숫자): "

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
    echo 최근 !USE_SESSION!개 세션을 검색합니다...
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
        echo 검색 결과가 없습니다.
        goto :ASK_SESSION
    )

    echo --------------------------------------------------
    for /l %%I in (1,1,!FOUND_COUNT!) do (
        echo [%%I] 시간: !M_TIME_%%I! ^| 입력: !M_USER_%%I! ^| 응답: !M_ASSISTANT_%%I!
        if %%I lss !FOUND_COUNT! echo.
    )
    echo --------------------------------------------------

    :SELECT_SESSION
    set "SEL_INDEX="
    set /p SEL_INDEX="이어서 진행할 번호를 입력하세요 (취소: c): "
    if /i "!SEL_INDEX!"=="c" goto :ASK_SESSION

    set "SELECTED_ID="
    for /l %%I in (1,1,!FOUND_COUNT!) do (
        if "!SEL_INDEX!"=="%%I" set "SELECTED_ID=!M_ID_%%I!"
    )

    if not "!SELECTED_ID!"=="" (
        set "RESUME_ARG=--resume !SELECTED_ID!"
        goto :RUN_CLAUDE
    ) else (
        echo 잘못된 번호입니다.
        goto :SELECT_SESSION
    )
) else (
    echo [안내] 발견된 세션 정보 없음.
)

:RUN_CLAUDE
:: 6. Claude 실행
del "!CONFIG_BASE_DIR!\temp_session.txt" 2>nul
echo.
echo "!LAST_PATH!" 위치에서 Claude를 실행합니다...
echo.

cd /d "!LAST_PATH!"
claude !RESUME_ARG!

:: 종료 후 alias의 mcp.json을 글로벌로 역동기화
if exist "!CLAUDE_CONFIG_DIR!\mcp.json" (
    copy /Y "!CLAUDE_CONFIG_DIR!\mcp.json" "!GLOBAL_CLAUDE_DIR!\mcp.json" >nul 2>&1
)

pause
goto :EOF

:: ==================================================
:: 명령어 처리 함수 모음
:: ==================================================

:CHECK_INSTALL_HINT
if /i "!ARG1!"=="install" goto :EOF
if /i "!ARG1!"=="uninstall" goto :EOF
if /i "!ARG1!"=="version" goto :EOF
if /i "!ARG1!"=="-h" goto :EOF
if /i "!ARG1!"=="--help" goto :EOF
set "REPO_DIR_CHK=%~dp0"
if "!REPO_DIR_CHK:~-1!"=="\" set "REPO_DIR_CHK=!REPO_DIR_CHK:~0,-1!"
reg query "HKCU\Environment" /v Path 2>nul | findstr /i /c:"!REPO_DIR_CHK!" >nul 2>&1
if not errorlevel 1 goto :EOF
echo [안내] '%~n0' 명령이 PATH 에 등록되지 않았습니다. '%~n0 install' 로 설치하면 어디서나 '%~n0' 명령으로 실행 가능합니다.
goto :EOF

:CHECK_RESERVED
:: arg1: 검사할 이름, 결과: RESERVED=1 이면 예약어
set "RESERVED=0"
for %%R in (%RESERVED_WORDS%) do (
    if /i "%~1"=="%%R" set "RESERVED=1"
)
if /i "%~1"=="-h" set "RESERVED=1"
if /i "%~1"=="--help" set "RESERVED=1"
goto :EOF

:GET_PATH_ALIAS
:: arg1: alias 이름, 결과: RESOLVED_PATH
set "RESOLVED_PATH="
if not exist "!PATH_ALIAS_FILE!" goto :EOF
for /f "usebackq tokens=1,* delims==" %%A in ("!PATH_ALIAS_FILE!") do (
    if /i "%%A"=="%~1" set "RESOLVED_PATH=%%B"
)
goto :EOF

:DO_VERSION
echo Claude Code 사용자 도구 버전: !VERSION!
goto :EOF

:DO_INSTALL
set "REPO_DIR=%~dp0"
if "!REPO_DIR:~-1!"=="\" set "REPO_DIR=!REPO_DIR:~0,-1!"
if not exist "!REPO_DIR!\%~n0.bat" (
    echo [오류] !REPO_DIR!\%~n0.bat 파일을 찾을 수 없습니다.
    goto :EOF
)
powershell -NoProfile -Command "$d=$env:REPO_DIR; $p=[Environment]::GetEnvironmentVariable('Path','User'); if($null -eq $p){$p=''}; $parts=$p -split ';' | Where-Object {$_ -ne ''}; if($parts -contains $d){exit 1}else{$np=if($p -eq ''){$d}else{$p+';'+$d}; [Environment]::SetEnvironmentVariable('Path',$np,'User'); exit 0}"
if errorlevel 1 (
    echo [안내] 이미 PATH 에 등록되어 있습니다: !REPO_DIR!
) else (
    echo [완료] PATH 에 추가됨: !REPO_DIR!
)
echo [안내] 새 cmd/PowerShell 창에서 %~n0 명령으로 실행 가능합니다.
goto :EOF

:DO_UNINSTALL
set "REPO_DIR=%~dp0"
if "!REPO_DIR:~-1!"=="\" set "REPO_DIR=!REPO_DIR:~0,-1!"
powershell -NoProfile -Command "$d=$env:REPO_DIR; $p=[Environment]::GetEnvironmentVariable('Path','User'); if($null -eq $p){$p=''}; $parts=$p -split ';' | Where-Object {$_ -ne '' -and $_ -ne $d}; [Environment]::SetEnvironmentVariable('Path',($parts -join ';'),'User'); exit 0"
echo [완료] PATH 에서 제거됨: !REPO_DIR!
goto :EOF

:DO_LOGIN
set "NEW_ALIAS=!ARG2!"
if "!NEW_ALIAS!"=="" set /p NEW_ALIAS="로그인할 계정 Alias를 입력하세요: "
if "!NEW_ALIAS!"=="" (
    echo [오류] Alias가 비어있습니다.
    goto :EOF
)
call :CHECK_RESERVED "!NEW_ALIAS!"
if "!RESERVED!"=="1" (
    echo [오류] '!NEW_ALIAS!'은^(는^) 예약어이므로 계정 Alias로 사용할 수 없습니다.
    goto :EOF
)
call :GET_PATH_ALIAS "!NEW_ALIAS!"
if not "!RESOLVED_PATH!"=="" (
    echo [오류] '!NEW_ALIAS!'은^(는^) 이미 경로 Alias로 등록되어 있습니다.
    goto :EOF
)
if not exist "!CONFIG_BASE_DIR!\!NEW_ALIAS!" mkdir "!CONFIG_BASE_DIR!\!NEW_ALIAS!"
set "CLAUDE_CONFIG_DIR=!CONFIG_BASE_DIR!\!NEW_ALIAS!"
echo !NEW_ALIAS!>"!LAST_ALIAS_FILE!"
echo [안내] '!NEW_ALIAS!' 계정 Alias 프로파일 환경에서 로그인을 진행합니다.
claude login
goto :EOF

:DO_COPY
set "SRC_ALIAS=!ARG2!"
set "NEW_ALIAS=!ARG3!"
if "!SRC_ALIAS!"=="" (
    set /p SRC_ALIAS="원본 계정 Alias를 입력하세요: "
)
if "!NEW_ALIAS!"=="" (
    set /p NEW_ALIAS="복제할 신규 계정 Alias를 입력하세요: "
)

call :CHECK_RESERVED "!NEW_ALIAS!"
if "!RESERVED!"=="1" (
    echo [오류] '!NEW_ALIAS!'은^(는^) 예약어이므로 계정 Alias로 사용할 수 없습니다.
    goto :EOF
)
call :GET_PATH_ALIAS "!NEW_ALIAS!"
if not "!RESOLVED_PATH!"=="" (
    echo [오류] '!NEW_ALIAS!'은^(는^) 이미 경로 Alias로 등록되어 있습니다.
    goto :EOF
)

if not exist "!CONFIG_BASE_DIR!\!SRC_ALIAS!" (
    echo [오류] 원본 계정 '!SRC_ALIAS!'이^(가^) 존재하지 않습니다.
    goto :EOF
)
if exist "!CONFIG_BASE_DIR!\!NEW_ALIAS!" (
    echo [오류] '!NEW_ALIAS!'은^(는^) 이미 계정 Alias로 등록되어 있습니다.
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

echo [안내] '!SRC_ALIAS!' 계정의 설정 파일을 복제하여 신규 계정 '!NEW_ALIAS!'을(를) 생성했습니다.
goto :EOF

:DO_RESET
echo claude_configs 폴더의 모든 데이터를 초기화합니다.
if exist "!CONFIG_BASE_DIR!" rmdir /s /q "!CONFIG_BASE_DIR!"
mkdir "!CONFIG_BASE_DIR!"
echo 초기화가 완료되었습니다.
goto :EOF

:DO_LOGOUT
set "LOGOUT_ALIAS=!ARG2!"
if "!LOGOUT_ALIAS!"=="" (
    echo [오류] 로그아웃할 계정 Alias를 입력하세요. 예: %~n0 logout a
    goto :EOF
)
if exist "!CONFIG_BASE_DIR!\!LOGOUT_ALIAS!" (
    rmdir /s /q "!CONFIG_BASE_DIR!\!LOGOUT_ALIAS!"
    echo [안내] '!LOGOUT_ALIAS!' 계정 정보가 삭제되었습니다.
    if exist "!LAST_ALIAS_FILE!" (
        set /p CUR_LAST_ALIAS=<"!LAST_ALIAS_FILE!"
        if "!CUR_LAST_ALIAS!"=="!LOGOUT_ALIAS!" del "!LAST_ALIAS_FILE!"
    )
) else (
    echo [오류] '!LOGOUT_ALIAS!' 계정 Alias를 찾을 수 없습니다.
)
goto :EOF

:DO_PATH
set "PA_NAME=!ARG2!"
set "PA_DIR=!ARG3!"
if "!PA_NAME!"=="" goto :LIST_PATH
call :CHECK_RESERVED "!PA_NAME!"
if "!RESERVED!"=="1" (
    echo [오류] '!PA_NAME!'은^(는^) 예약어이므로 경로 Alias로 사용할 수 없습니다.
    goto :EOF
)
if exist "!CONFIG_BASE_DIR!\!PA_NAME!" (
    echo [오류] '!PA_NAME!'은^(는^) 이미 계정 Alias로 등록되어 있습니다.
    goto :EOF
)
call :GET_PATH_ALIAS "!PA_NAME!"
if not "!RESOLVED_PATH!"=="" (
    echo [오류] '!PA_NAME!'은^(는^) 이미 경로 Alias로 등록되어 있습니다.
    goto :EOF
)
if "!PA_DIR!"=="" (
    echo [오류] 경로가 필요합니다. 예: %~n0 path ^<path alias^> ^<real path^>
    goto :EOF
)
if not exist "!PA_DIR!\" (
    echo [오류] 경로 '!PA_DIR!'가 존재하지 않습니다.
    goto :EOF
)
for %%I in ("!PA_DIR!") do set "PA_ABS=%%~fI"
echo !PA_NAME!=!PA_ABS!>>"!PATH_ALIAS_FILE!"
echo [안내] 경로 Alias '!PA_NAME!' -^> '!PA_ABS!' 등록 완료.
goto :EOF

:LIST_PATH
echo ==================================================
echo               등록된 경로 Alias 목록
echo ==================================================
if not exist "!PATH_ALIAS_FILE!" (
    echo 등록된 경로 Alias가 없습니다.
    echo 예: %~n0 path tabmerge C:\backup\C-Lab\gitsrc\TabMerge
    goto :EOF
)
for /f "usebackq tokens=1,* delims==" %%A in ("!PATH_ALIAS_FILE!") do (
    echo   %%A -^> %%B
)
echo ==================================================
goto :EOF

:DO_ALIAS
echo ==================================================
echo                   등록된 Alias 목록
echo ==================================================
echo [계정 Alias]
set "ALIAS_FOUND=0"
if exist "!CONFIG_BASE_DIR!" (
    for /d %%D in ("!CONFIG_BASE_DIR!\*") do (
        if /i not "%%~nxD"=="shared" (
            echo   %%~nxD
            set "ALIAS_FOUND=1"
        )
    )
)
if "!ALIAS_FOUND!"=="0" echo   ^(없음^)
echo.
echo [경로 Alias]
if not exist "!PATH_ALIAS_FILE!" (
    echo   ^(없음^)
    goto :ALIAS_DONE
)
set "PA_HAS=0"
for /f "usebackq tokens=1,* delims==" %%A in ("!PATH_ALIAS_FILE!") do (
    echo   %%A -^> %%B
    set "PA_HAS=1"
)
if "!PA_HAS!"=="0" echo   ^(없음^)
:ALIAS_DONE
echo ==================================================
goto :EOF

:DO_ACCOUNT
echo ==================================================
echo                사용자 계정 정보 목록
echo ==================================================
if not exist "!CONFIG_BASE_DIR!" (
    echo 사용자 계정 정보가 없습니다.
    goto :EOF
)

set "GLOBAL_LAST_PATH="
if exist "!GLOBAL_PATH_FILE!" set /p GLOBAL_LAST_PATH=<"!GLOBAL_PATH_FILE!"

if not "!GLOBAL_LAST_PATH!"=="" (
    echo [전역 마지막 경로]: !GLOBAL_LAST_PATH!
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

        set "A_PATH=설정되지 않음"
        if exist "%%D\last_path.txt" set /p A_PATH=<"%%D\last_path.txt"

        echo [계정 Alias: %%~nxD] !A_NAME! - !A_EMAIL!
        echo  - 경로: !A_PATH!

        set "SI="
        for /f "tokens=1,* delims==" %%A in ('type "!CONFIG_BASE_DIR!\temp_info.txt"') do (
            if "%%A"=="S_ID" (
                set "TMP_ID=%%B"
                set "SI=!TMP_ID:~0,36!"
            )
        )
        if "!SI!"=="" (
            echo  - 세션: 알 수 없음
        ) else (
            echo  - 세션: !SI!
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
if "!REMOTE_ALIAS!"=="" goto :LIST_REMOTE
if not exist "!CONFIG_BASE_DIR!\!REMOTE_ALIAS!" (
    echo [error] alias '!REMOTE_ALIAS!' profile not found. run %~n0 login first.
    goto :EOF
)
set "CLAUDE_CONFIG_DIR=!CONFIG_BASE_DIR!\!REMOTE_ALIAS!"
echo !REMOTE_ALIAS!>"!LAST_ALIAS_FILE!"

set "GLOBAL_CLAUDE_DIR=%USERPROFILE%\.claude"
if not exist "!GLOBAL_CLAUDE_DIR!\plugins" mkdir "!GLOBAL_CLAUDE_DIR!\plugins"
if not exist "!GLOBAL_CLAUDE_DIR!\hooks" mkdir "!GLOBAL_CLAUDE_DIR!\hooks"
if not exist "!GLOBAL_CLAUDE_DIR!\skills" mkdir "!GLOBAL_CLAUDE_DIR!\skills"
if not exist "!GLOBAL_CLAUDE_DIR!\agents" mkdir "!GLOBAL_CLAUDE_DIR!\agents"
for %%D in (plugins hooks skills agents) do (
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
    if exist "!REMOTE_PATH!\" (
        set "TARGET_PATH=!REMOTE_PATH!"
    ) else (
        call :GET_PATH_ALIAS "!REMOTE_PATH!"
        if not "!RESOLVED_PATH!"=="" (
            if exist "!RESOLVED_PATH!\" set "TARGET_PATH=!RESOLVED_PATH!"
        )
    )
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

:DO_CLOSE
set "CLOSE_ALIAS=!ARG2!"
if "!CLOSE_ALIAS!"=="" (
    echo [error] alias required. example: %~n0 close a
    goto :EOF
)
set "TITLE_PATTERN=claude-remote-!CLOSE_ALIAS!-*"
taskkill /F /FI "WINDOWTITLE eq !TITLE_PATTERN!" >nul 2>&1
if errorlevel 1 (
    echo [info] no remote window found for alias '!CLOSE_ALIAS!'
) else (
    echo [done] closed remote windows for alias '!CLOSE_ALIAS!'
)
goto :EOF

:LIST_REMOTE
echo ==================================================
echo               open remote sessions
echo ==================================================
powershell -NoProfile -Command "$ws = Get-Process | Where-Object { $_.MainWindowTitle -like 'claude-remote-*' } | Select-Object -ExpandProperty MainWindowTitle; if (-not $ws) { Write-Host '  no open remote sessions.' } else { $ws | ForEach-Object { Write-Host ('  ' + $_) } }"
echo ==================================================
goto :EOF

:SHOW_HELP
echo ==================================================
echo                Claude Code 사용자 도구 v!VERSION!
echo ==================================================
echo [사용법]
echo  %~n0                                  : 마지막 사용 프로파일·경로에서 실행
echo  %~n0 install                          : 사용자 PATH 에 현재 디렉터리 추가 (어디서나 %~n0 실행)
echo  %~n0 uninstall                        : 사용자 PATH 에서 현재 디렉터리 제거
echo  %~n0 login [Alias]                    : 새로운 계정 프로파일 생성 및 로그인 (Alias 생략 시 입력 프롬프트)
echo  %~n0 copy [원본Alias] [신규Alias]     : 기존 계정 설정을 복제하여 신규 계정 생성
echo  %~n0 logout [Alias]                   : 특정 계정 Alias 삭제
echo  %~n0 reset                            : 모든 계정·경로·설정 초기화
echo  %~n0 remote [Alias] [경로^|경로Alias]  : alias 프로파일로 백그라운드 'claude --remote-control' 실행
echo  %~n0 close [Alias]                    : 해당 alias 로 열려있는 remote 창 모두 종료
echo  %~n0 account                          : 사용자 계정 및 세션 정보 출력
echo  %~n0 alias                            : 등록된 계정/경로 Alias 목록 출력
echo  %~n0 version                          : 도구 버전 출력
echo  %~n0 path                             : 등록된 경로 Alias 목록 출력
echo  %~n0 path [경로Alias] [실제경로]      : 경로 Alias 등록
echo  %~n0 [계정 Alias]                     : 해당 프로파일로 마지막 경로에서 실행
echo  %~n0 [경로^|경로Alias]                : 마지막 프로파일로 지정 경로/경로Alias 에서 실행
echo  %~n0 [계정 Alias] [경로^|경로Alias]   : 지정 프로파일·경로/경로Alias 에서 실행
echo  %~n0 -h, --help                       : 도움말
echo.
echo [예약어 - 계정/경로 Alias 로 사용 불가]
echo  login, copy, reset, logout, remote, close, account, alias, version, path, install, uninstall, help, -h, --help
echo.
echo [환경 변수]
echo  - CLAUDE_CONFIG_DIR : 활성 프로파일 디렉터리로 설정됨
echo.
echo [예시]
echo  %~n0 login a                                        -^> 계정 Alias a 로 로그인
echo  %~n0 copy a a1                                      -^> a 설정 복제, a1 생성
echo  %~n0 a D:\workspace                                 -^> a 프로파일로 D:\workspace 작업
echo  %~n0 path tabmerge C:\backup\C-Lab\gitsrc\TabMerge  -^> 경로 Alias 등록
echo  %~n0 a tabmerge                                     -^> a 프로파일로 tabmerge 경로 Alias 위치에서 실행
echo  %~n0 remote a tabmerge                              -^> a 프로파일로 tabmerge 위치에서 원격 제어용 백그라운드 실행
echo  %~n0 alias                                          -^> 계정/경로 Alias 목록 출력
echo  %~n0 logout a1                                      -^> a1 계정 삭제
echo ==================================================
goto :EOF
