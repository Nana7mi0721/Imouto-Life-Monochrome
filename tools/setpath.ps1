
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir -or -not (Test-Path $ScriptDir)) {
  $ScriptDir = 'E:\Study\github program\Imouto Life Monochrome\tools'
}

$dirs = @(
  (Join-Path $ScriptDir 'bin'),
  (Join-Path $ScriptDir 'cmake\bin'),
  (Join-Path $ScriptDir 'ffmpeg\bin'),
  "$env:USERPROFILE\.cargo\bin"
)
$cur = [Environment]::GetEnvironmentVariable('Path','User'); if ($null -eq $cur) { $cur='' }
$parts = $cur -split ';' | Where-Object { $_ -ne '' }
foreach ($p in $dirs) { if ($parts -notcontains $p) { $parts += $p; Write-Output "ADDED=$p" } }
[Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
Write-Output "FINAL=$([Environment]::GetEnvironmentVariable('Path','User'))"
