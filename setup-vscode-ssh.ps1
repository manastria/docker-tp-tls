<#
.SYNOPSIS
  Configure rapidement l’accès VS Code via SSH à une VM Debian 12 depuis Windows.
  - Génère une clé SSH (ed25519) si absente
  - Pousse automatiquement la clé publique sur la VM
  - Crée/Met à jour ~/.ssh/config avec un alias pour VS Code
  - Vérifie/active l’agent ssh et ajoute la clé si possible
  - Teste la connexion

.PRÉREQUIS
  - Windows 10/11 avec le client OpenSSH installé.
  - VM Debian 12 avec le serveur OpenSSH actif.

.EXÉCUTION DU SCRIPT POWERSHELL
  - Pour autoriser l’exécution *dans la session courante uniquement* :
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
  - Pour autoriser l’exécution *de manière persistante* (nécessite une fenêtre PowerShell relancée) :
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
    Ensuite, exécutez :
        .\setup-vscode-ssh.ps1
#>

[CmdletBinding()]
param()

# ===================================================================
# MODE DEBUG : Passez à $true pour utiliser les variables de test
# ===================================================================
$debugMode = $false

if ($debugMode) {
  $testVmHost = "192.168.56.50"
  $testUser   = "etudiant"
  $testPort   = 22
  $testAlias  = "debian-vm-test"
}
# ===================================================================

#region Fonctions Utilitaires
function Require-Command {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Hint
  )
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Write-Warning "$Name introuvable. Tentative d'installation du client OpenSSH..."
    try {
      Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -ErrorAction Stop | Out-Null
      Write-Host "Client OpenSSH installé. Relancez le script si les commandes ne sont pas encore disponibles." -ForegroundColor Green
    }
    catch {
      Write-Error "$Name introuvable et installation automatique échouée. $Hint"
      exit 1
    }
  }
}

function Ensure-SshAgent {
  # ... (contenu de la fonction inchangé)
  Write-Host "Vérification du service ssh-agent..." -ForegroundColor Cyan
  try { $svc = Get-Service -Name 'ssh-agent' -ErrorAction Stop } catch { Write-Warning "Service ssh-agent introuvable."; return $false }
  if ($svc.StartType -ne 'Automatic') {
    try { Set-Service -Name 'ssh-agent' -StartupType Automatic; Write-Host "ssh-agent configuré en démarrage automatique." -ForegroundColor Green } catch { Write-Warning "Impossible de définir le démarrage automatique (droits admin requis)." }
  }
  if ($svc.Status -ne 'Running') {
    try { Start-Service -Name 'ssh-agent'; Write-Host "ssh-agent démarré." -ForegroundColor Green } catch { Write-Warning "Impossible de démarrer ssh-agent (droits admin requis)."; return $false }
  }
  return $true
}
#endregion

# 1) Vérif des outils
Require-Command -Name 'ssh' -Hint "Installez le client OpenSSH."
Require-Command -Name 'ssh-keygen' -Hint "Installez le client OpenSSH."
Require-Command -Name 'ssh-add' -Hint "Installez le client OpenSSH."

# 2) Collecte d'infos et VALIDATION
Write-Host "=== Configuration de l'accès SSH pour VS Code ===" -ForegroundColor Cyan
if ($debugMode) {
  Write-Host "--- MODE DEBUG ACTIF ---" -ForegroundColor Yellow
  $VmHost = $testVmHost; $User = $testUser; $Port = $testPort; $Alias = $testAlias
  Write-Host "Utilisation des valeurs de test : Hôte: $VmHost, Utilisateur: $User, Port: $Port, Alias: $Alias"
} else {
  # ... (saisie manuelle inchangée)
  $VmHost = Read-Host "Adresse IP ou nom de la VM (ex: 192.168.x.y)"; if ([string]::IsNullOrWhiteSpace($VmHost) -or $VmHost -match '[;&|`]') { Write-Error "Adresse IP / nom invalide."; exit 1 }
  $User = Read-Host "Nom d'utilisateur Linux (ex: student)"; if ([string]::IsNullOrWhiteSpace($User) -or $User -match '\s|[^a-zA-Z0-9_.-]') { Write-Error "Nom d'utilisateur invalide."; exit 1 }
  $PortRaw = Read-Host "Port SSH [Entrée = 22]"; $Port = if ([string]::IsNullOrWhiteSpace($PortRaw)) { 22 } else { [int]$PortRaw }
  $DefaultAlias = 'debian-vm'; $AliasRaw = Read-Host "Alias SSH/VSCode [Entrée = $DefaultAlias]"; $Alias = if ([string]::IsNullOrWhiteSpace($AliasRaw)) { $DefaultAlias } else { $AliasRaw }; if ($Alias -match '\s|[^a-zA-Z0-9_.-]') { Write-Error "Alias invalide."; exit 1 }
}

# 3) Génération clé et gestion de l'agent
$UserProfile = [Environment]::GetFolderPath('UserProfile'); $SshDir  = Join-Path $UserProfile ".ssh"; $keyBase = Join-Path $SshDir "id_ed25519"; $pubKey  = "$keyBase.pub"
if (-not (Test-Path $SshDir)) { New-Item -Path $SshDir -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $keyBase)) {
  Write-Host "Génération d'une clé ed25519 (sans passphrase)..." -ForegroundColor Yellow
  $comment = "$($env:USERNAME)@$([System.Net.Dns]::GetHostName())-$(Get-Date -Format 'yyyyMMddHHmmss')"
  $argLine = "-t ed25519 -f `"$keyBase`" -C `"$comment`" -N `"`""; $p = Start-Process -FilePath 'ssh-keygen' -ArgumentList $argLine -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "ssh-keygen a échoué (code $($p.ExitCode))." }
} else { Write-Host "Clé existante détectée : $keyBase" -ForegroundColor Green }
if (-not (Test-Path $pubKey)) { Write-Error "Clé publique introuvable : $pubKey"; exit 1 }
$agentOk = Ensure-SshAgent
if ($agentOk) {
  try {
    $pubContent = (Get-Content $pubKey -Raw).Trim(); $loaded = (& ssh-add -L 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0 -or -not ($loaded -like "*$pubContent*")) { & ssh-add $keyBase | Out-Null; if ($LASTEXITCODE -eq 0) { Write-Host "Clé ajoutée à l'agent ssh." -ForegroundColor Green } } else { Write-Host "Clé déjà présente dans l'agent ssh." -ForegroundColor Green }
  } catch { Write-Warning "Impossible d'ajouter la clé à l'agent ssh." }
}

# 4) Dépôt de la clé sur la VM via le pipe (méthode robuste)
Write-Host "Envoi et ajout de la clé publique via SSH..." -ForegroundColor Yellow
$pubKeyContent = Get-Content -Path $pubKey -Raw
$remoteCmd = 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && cat >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys'

# ⚠️ On utilise 'accept-new' pour la simplicité dans ce contexte de labo. Ne pas faire en production.
$sshOptions = "-o StrictHostKeyChecking=accept-new"
$pubKeyContent | ssh -p "$Port" $sshOptions "$($User)@$($VmHost)" $remoteCmd

if ($LASTEXITCODE -ne 0) {
  Write-Error "Échec de l'envoi de la clé (code $LASTEXITCODE)."; exit 1
}
Write-Host "Clé ajoutée avec succès sur la VM." -ForegroundColor Green

# 5) Configuration ~/.ssh/config
$configPath = Join-Path $SshDir 'config'
$block = @"
Host $Alias
    HostName $VmHost
    User $User
    Port $Port
    IdentityFile "$keyBase"
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
"@
if (Test-Path $configPath) {
  $raw = Get-Content $configPath -Raw; $pattern = "(?ms)^\s*Host\s+$([regex]::Escape($Alias))\b.*?(?=^\s*Host\s+\S|\Z)"; $new = [regex]::Replace($raw, $pattern, '').TrimEnd()
  $backup = "$configPath.bak.$(Get-Date -Format yyyyMMddHHmmss)"; Copy-Item $configPath $backup
  $final = if ($new) { $new + [System.Environment]::NewLine * 2 + $block } else { $block }; $final | Set-Content -Path $configPath -Encoding UTF8
  Write-Host "Config mise à jour. Sauvegarde : $backup" -ForegroundColor Green
} else {
  $block | Set-Content -Path $configPath -Encoding UTF8
  Write-Host "Config créée : $configPath" -ForegroundColor Green
}

# 6) Test de connexion par alias
Write-Host "Test de connexion SSH via alias '$Alias'..." -ForegroundColor Cyan
& ssh $Alias "echo Connexion OK"
if ($LASTEXITCODE -eq 0) {
  Write-Host "Succès : authentification par clé opérationnelle." -ForegroundColor Green
  Write-Host "Dans VS Code : F1 -> 'Remote-SSH: Connect to Host...' -> '$Alias'" -ForegroundColor Green
} else {
  Write-Warning "La connexion via alias a échoué (code $LASTEXITCODE). Vérifiez la configuration ou exécutez : ssh -vvv $Alias"
}
