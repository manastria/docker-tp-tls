# Connexion VS Code à une VM Debian via SSH sous Windows

Il existe deux façons de configurer la connexion :

- Avec le script automatique (recommandé pour aller vite).
- Manuellement (si vous préférez exécuter chaque étape).

## 1. Procédure avec le script automatique

### Ce que fait le script

- Vérifie `ssh`, `scp`, `ssh-keygen` (OpenSSH Client Windows).
- Génère une clé **ed25519** si absente (`%USERPROFILE%\.ssh\id_ed25519`).
- Envoie la **clé publique** sur la VM (il demandera une seule fois le mot de passe du compte Linux).
- Crée/Met à jour `%USERPROFILE%\.ssh\config` avec un **alias** prêt pour VS Code.
- Teste la connexion par clé.

### Utilisation

1. Ouvre **PowerShell** (pas besoin d’admin).

2. Si nécessaire, autorise l’exécution d’un script dans la session courante :

   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

3. Exécute le script :

   ```powershell
   .\setup-vscode-ssh.ps1
   ```

4. Réponds aux questions :

   - IP de la VM (ex. `192.168.x.y` si Bridge).
   - Utilisateur Linux (ex. `student`).
   - Port (Entrée = 22).
   - Alias (Entrée = `debian-vm`).

5. Dans **VS Code** : installe l’extension **Remote – SSH**
   👉 [Remote – SSH (Visual Studio Marketplace)](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh)

   Puis : `F1` → **Remote-SSH: Connect to Host…** → choisis l’alias (par défaut `debian-vm`).

> Pré-requis côté VM (à faire une seule fois) :
>
> ```bash
> sudo apt update && sudo apt install -y openssh-server
> sudo systemctl enable --now ssh
> # (facultatif) si UFW : sudo ufw allow 22/tcp
> ```

---

## 2. Procédure manuelle

### A. Sur la VM Debian 12 (une fois)

```bash
sudo apt update && sudo apt install -y openssh-server
sudo systemctl enable --now ssh
## (si UFW actif) sudo ufw allow 22/tcp
ip --br -c a   # pour relever l’IP (ex. 192.168.x.y si Bridge)
```

**VirtualBox :**

- Les étudiants doivent configurer la carte réseau en **Bridge**.
  La VM obtient une adresse IP du réseau local → connexion directe sur port 22.

### B. Sous Windows (pour chaque étudiant)

1. **Générer une clé** (sans passphrase pour simplifier en contexte pédagogique) :

   ```powershell
   ssh-keygen -t ed25519 -C "$env:USERNAME@$(hostname)-$(Get-Date -Format yyyyMMddHHmmss)" -f "$env:USERPROFILE\.ssh\id_ed25519" -N ""
   ```

2. **Copier la clé publique sur la VM** (mot de passe demandé une seule fois) :

   ```powershell
   scp -o StrictHostKeyChecking=accept-new "$env:USERPROFILE\.ssh\id_ed25519.pub" student@192.168.x.y:/tmp/key.pub
   ssh -o StrictHostKeyChecking=accept-new student@192.168.x.y "mkdir -p ~/.ssh && chmod 700 ~/.ssh; touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys; cat /tmp/key.pub >> ~/.ssh/authorized_keys; sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys; rm /tmp/key.pub"
   ```

3. **Configurer `%USERPROFILE%\.ssh\config`** (crée le fichier si besoin) :

   ```default
   Host debian-vm
       HostName 192.168.x.y
       Port 22
       User student
       IdentityFile ~/.ssh/id_ed25519
       IdentitiesOnly yes
       StrictHostKeyChecking accept-new
       ServerAliveInterval 30
   ```

4. **Tester** :

   ```powershell
   ssh debian-vm
   ```

   Si tu arrives sans mot de passe : c’est bon ✅

5. **VS Code** :

   - Installer **Remote – SSH** : [lien direct](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh).
   - `F1` → **Remote-SSH: Connect to Host…** → `debian-vm`.
   - Ouvrir le dossier de travail sur la VM.

---

## Dépannage express

- **`Permission denied (publickey)`** : vérifier sur la VM

  ```bash
  ls -ld ~/.ssh && ls -l ~/.ssh/authorized_keys
  # droits attendus : .ssh = 700, authorized_keys = 600
  ```

- **Connexion refusée / Timeout** : vérifier `systemctl status ssh`, pare-feu, et que la VM est bien en Bridge (pas NAT).

- **Empreinte hôte a changé** (réinstall VM) :

  ```powershell
  ssh-keygen -R 192.168.x.y
  ```

- **VS Code ne liste pas l’alias** : le fichier `config` doit être dans `%USERPROFILE%\.ssh\config` (pas ailleurs) et sans extension.
