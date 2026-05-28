# AgentManager Windows installer
# Adds this repo's directory to the User PATH so `am` resolves to am.bat
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$repoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$batPath = Join-Path $repoDir 'am.bat'

if (-not (Test-Path $batPath)) {
    Write-Host "[오류] am.bat 가 $repoDir 에 없습니다." -ForegroundColor Red
    exit 1
}

$currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($null -eq $currentPath) { $currentPath = '' }

$parts = $currentPath -split ';' | Where-Object { $_ -ne '' }

if ($Uninstall) {
    if ($parts -contains $repoDir) {
        $newParts = $parts | Where-Object { $_ -ne $repoDir }
        [Environment]::SetEnvironmentVariable('Path', ($newParts -join ';'), 'User')
        Write-Host "[완료] PATH 에서 $repoDir 제거함."
    } else {
        Write-Host "[안내] $repoDir 가 PATH 에 등록되어 있지 않습니다."
    }
    exit 0
}

if ($parts -contains $repoDir) {
    Write-Host "[안내] 이미 설치되어 있습니다. PATH 에 $repoDir 등록됨."
} else {
    $newPath = if ($currentPath -eq '') { $repoDir } else { "$currentPath;$repoDir" }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "[완료] PATH 에 추가됨: $repoDir"
    Write-Host "[안내] 새 cmd/PowerShell 창에서 'am' 명령으로 실행 가능합니다."
}

# 현재 세션 PATH 도 갱신
if ($env:Path -notlike "*$repoDir*") {
    $env:Path = "$env:Path;$repoDir"
}

Write-Host ""
Write-Host "사용 예:"
Write-Host "  am               : 마지막 프로파일/경로에서 실행"
Write-Host "  am login         : 새 계정 프로파일 생성"
Write-Host "  am alias         : 계정/경로 Alias 목록"
Write-Host "  am -h            : 전체 도움말"
Write-Host ""
Write-Host "제거: powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall"
