<#
.SYNOPSIS
  Configure rapidement l’accès VS Code via SSH à une VM Debian 12 depuis Windows.
  - Génère une clé SSH (ed25519) si absente
  - Pousse automatiquement la clé publique sur la VM
  - Crée/Met à jour ~/.ssh/config avec un alias pour VS Code
  - Vérifie/active l’agent ssh et ajoute la clé si possible
  - Teste la connexion

.PRÉREQUIS
  - Windows 10/11. Si les commandes ssh/scp/ssh-keygen manquent, installez le client OpenSSH avec PowerShell (administrateur) :
        Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
    (alternative DISM si besoin) :
        DISM /Online /Add-Capability /CapabilityName:OpenSSH.Client~~~~0.0.1.0

  - Le serveur SSH doit être actif sur la VM Debian :
        sudo apt update && sudo apt install -y openssh-server
        sudo systemctl enable --now ssh

.EXÉCUTION DU SCRIPT POWERSHELL
  - Pour autoriser l’exécution *dans la session courante uniquement* :
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    Ensuite, exécutez :
        .\setup-vscode-ssh.ps1

  - Pour rendre l’agent SSH persistant au démarrage et le lancer immédiatement (PowerShell admin) :
        Set-Service -Name ssh-agent -StartupType Automatic
        Start-Service -Name ssh-agent

.AUTEUR
  Script prêt pour un usage pédagogique.
#>

[CmdletBinding()]
param()

function Require-Command {
  param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$Hint)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Write-Warning "$Name introuvable. Tentative d'installation du client OpenSSH..."
    try {
      # Nécessite PowerShell lancé en Administrateur
      Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -ErrorAction Stop | Out-Null
      Write-Host "Client OpenSSH installé. Relancez le script si les commandes ne sont pas encore disponibles." -ForegroundColor Green
    } catch {
      Write-Error "$Name introuvable et installation automatique échouée. $Hint"
      exit 1
    }
  }
}

function Ensure-SshAgent {
  Write-Host "Vérification du service ssh-agent..." -ForegroundColor Cyan
  try {
    $svc = Get-Service -Name 'ssh-agent' -ErrorAction Stop
  } catch {
    Write-Warning "Service ssh-agent introuvable. Il est fourni par le Client OpenSSH de Windows 10/11."
    return $false
  }
  if ($svc.StartType -ne 'Automatic') {
    try {
      Set-Service -Name 'ssh-agent' -StartupType Automatic
      Write-Host "ssh-agent configuré en démarrage automatique." -ForegroundColor Green
    } catch {
      Write-Warning "Impossible de définir le démarrage automatique (droits admin requis)."
    }
  }
  if ($svc.Status -ne 'Running') {
    try {
      Start-Service -Name 'ssh-agent'
      Write-Host "ssh-agent démarré." -ForegroundColor Green
    } catch {
      Write-Warning "Impossible de démarrer ssh-agent (droits admin requis). Lancez en admin : Start-Service ssh-agent"
      return $false
    }
  }
  return $true
}

# 1) Vérif des outils (tentative d'auto-install si manquants)
Require-Command -Name 'ssh' -Hint "Installez le client OpenSSH : Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 (PowerShell admin)."
Require-Command -Name 'scp' -Hint "Installez le client OpenSSH : Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 (PowerShell admin)."
Require-Command -Name 'ssh-keygen' -Hint "Installez le client OpenSSH : Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 (PowerShell admin)."

# 2) Collecte d'infos
Write-Host "=== Configuration de l'accès SSH pour VS Code ===" -ForegroundColor Cyan

$DefaultAlias = 'debian-vm'
$Host = Read-Host "Adresse IP ou nom de la VM (ex: 127.0.0.1 si NAT avec redirection 2222)"
if ([string]::IsNullOrWhiteSpace($Host)) { Write-Error "Adresse IP / nom requis."; exit 1 }
$User = Read-Host "Nom d'utilisateur Linux (ex: student)"
if ([string]::IsNullOrWhiteSpace($User)) { Write-Error "Nom d'utilisateur requis."; exit 1 }
$PortRaw = Read-Host "Port SSH [Entrée = 22, ou 2222 si NAT]"
$Port = if ([string]::IsNullOrWhiteSpace($PortRaw)) { 22 } else { [int]$PortRaw }
$AliasRaw = Read-Host "Alias SSH/VSCode [Entrée = $DefaultAlias]"
$Alias = if ([string]::IsNullOrWhiteSpace($AliasRaw)) { $DefaultAlias } else { $AliasRaw }

# 3) Génération clé si besoin
$Home = $HOME
$SshDir = Join-Path $Home ".ssh"
$keyBase = Join-Path $SshDir "id_ed25519"
$pubKey = "$keyBase.pub"

if (-not (Test-Path $SshDir)) { New-Item -Path $SshDir -ItemType Directory -Force | Out-Null }

if (-not (Test-Path $keyBase)) {
  Write-Host "Génération d'une clé ed25519..." -ForegroundColor Yellow
  $comment = "$($env:USERNAME)@$([System.Net.Dns]::GetHostName())-$(Get-Date -Format yyyyMMddHHmmss)"
  & ssh-keygen -t ed25519 -f $keyBase -N "" -C $comment | Out-Null
} else {
  Write-Host "Clé existante détectée : $keyBase" -ForegroundColor Green
}

if (-not (Test-Path $pubKey)) { Write-Error "Clé publique introuvable : $pubKey"; exit 1 }

# 3.1) Agent : activer/démarrer + ajouter la clé (utile si clé avec passphrase)
$agentOk = Ensure-SshAgent
if ($agentOk) {
  try {
    # Ajoute la clé si non déjà chargée
    $keys = & ssh-add -l 2>$null
    $alreadyLoaded = $false
    if ($LASTEXITCODE -eq 0 -and $keys) {
      $alreadyLoaded = ($keys -match [Regex]::Escape((Get-Content $pubKey -Raw).Trim()))
    }
    if (-not $alreadyLoaded) {
      & ssh-add $keyBase | Out-Null
      if ($LASTEXITCODE -eq 0) {
        Write-Host "Clé ajoutée à l'agent ssh." -ForegroundColor Green
      }
    } else {
      Write-Host "Clé déjà présente dans l'agent ssh." -ForegroundColor Green
    }
  } catch {
    Write-Warning "Impossible d'ajouter la clé à l'agent ssh (peut nécessiter une passphrase ou des droits)."
  }
} else {
  Write-Warning "ssh-agent indisponible. Vous pouvez l'activer en admin :`n  Set-Service ssh-agent -StartupType Automatic ; Start-Service ssh-agent"
}

# 4) Dépôt de la clé sur la VM
$remoteTmp = "/tmp/winpubkey_$([System.Guid]::NewGuid().ToString('N')).pub"
Write-Host "Envoi de la clé publique vers $User@$Host:$remoteTmp ..." -ForegroundColor Yellow
$scpCmd = @('scp', '-P', "$Port", '-o', 'StrictHostKeyChecking=accept-new', $pubKey, "$User@$Host:$remoteTmp")
$scp = Start-Process -FilePath $scpCmd[0] -ArgumentList $scpCmd[1..($scpCmd.Count-1)] -NoNewWindow -PassThru -Wait
if ($scp.ExitCode -ne 0) { Write-Error "Échec du scp (code $($scp.ExitCode)). Vérifiez IP/port/utilisateur et que le service SSH est actif."; exit 1 }

Write-Host "Ajout au ~/.ssh/authorized_keys sur la VM..." -ForegroundColor Yellow
$remoteCmd = @"
set -e
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
cat $remoteTmp >> ~/.ssh/authorized_keys
sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys
rm -f $remoteTmp
"@

$sshCmd = @('ssh', '-p', "$Port", '-o', 'StrictHostKeyChecking=accept-new', "$User@$Host", $remoteCmd)
$ssh = Start-Process -FilePath $sshCmd[0] -ArgumentList $sshCmd[1..($sshCmd.Count-1)] -NoNewWindow -PassThru -Wait
if ($ssh.ExitCode -ne 0) { Write-Error "Échec lors de l'ajout de la clé (code $($ssh.ExitCode))."; exit 1 }

# 5) Configuration ~/.ssh/config
$configPath = Join-Path $SshDir 'config'
$block = @"
Host $Alias
    HostName $Host
    User $User
    Port $Port
    IdentityFile $keyBase
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
    ServerAliveInterval 30
"@

if (Test-Path $configPath) {
  $raw = Get-Content $configPath -Raw
  $pattern = "(?ms)^\s*Host\s+$([regex]::Escape($Alias))\b.*?(?=^\s*Host\s+\S|\Z)"
  $new = [regex]::Replace($raw, $pattern, '').TrimEnd()
  $backup = "$configPath.bak.$(Get-Date -Format yyyyMMddHHmmss)"
  Copy-Item $configPath $backup
  $final = if ($new) { $new + "`r`n`r`n" + $block } else { $block }
  $final -replace "`n", "`r`n" | Set-Content -Path $configPath -Encoding UTF8
  Write-Host "Config mise à jour. Sauvegarde : $backup" -ForegroundColor Green
} else {
  $block -replace "`n", "`r`n" | Set-Content -Path $configPath -Encoding UTF8
  Write-Host "Config créée : $configPath" -ForegroundColor Green
}

# 6) Test de connexion par alias
Write-Host "Test de connexion SSH via alias '$Alias'..." -ForegroundColor Cyan
$test = Start-Process -FilePath 'ssh' -ArgumentList @($Alias, 'echo', 'OK') -NoNewWindow -PassThru -Wait
if ($test.ExitCode -eq 0) {
  Write-Host "Succès : authentification par clé opérationnelle." -ForegroundColor Green
  Write-Host "Dans VS Code : extension 'Remote - SSH' → 'Connect to Host…' → $Alias" -ForegroundColor Green
} else {
  Write-Warning "La connexion via alias a échoué (code $($test.ExitCode)). Vérifiez le pare-feu, le port, ou exécutez : ssh -vvv $Alias"
}
