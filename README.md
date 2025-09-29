# Docker TP TLS

Activité pédagogique : mise en place d’une **infrastructure TLS locale** à base de **Docker Compose**.

L’objectif est d’apprendre à :

* comprendre la notion de **PKI** (autorité de certification, certificat serveur, chaîne de confiance) ;
* générer ses propres certificats avec **OpenSSL** ;
* configurer un serveur web (**Nginx**) en HTTPS ;
* utiliser un serveur DNS local (**CoreDNS**) pour résoudre un nom de domaine interne.

---

## Structure de l’activité

```
.
├── coredns/
│   ├── Corefile              # Configuration principale de CoreDNS
│   └── zones/
│       └── sio.home.arpa.db  # Zone DNS locale (site1.sio.home.arpa, etc.)
│
├── nginx/
│   ├── conf.d/
│   │   └── site1.conf        # Virtual host Nginx (HTTP → HTTPS)
│   └── html/
│       └── index.html        # Page de test
│
├── pki/                      # Répertoire qui contiendra la PKI générée
│   ├── rootCA.crt            # Certificat de la CA (à générer)
│   ├── rootCA.key            # Clé privée de la CA (à générer, à garder secrète)
│   ├── site1.crt             # Certificat du site (à générer)
│   └── site1.key             # Clé privée du site (à générer)
│
├── docs/
│   └── vscode-ssh-windows.md # Guide pour connexion VS Code ↔ VM Debian (Windows)
│
├── setup-vscode-ssh.ps1      # Script d’automatisation pour configurer l’accès SSH
├── docker-compose.yml        # Orchestration des services
└── README.md                 # Ce fichier
```

---

## Démarrage avec Git et GitHub

### 1. Créer votre travail à partir de ce modèle

La meilleure façon de commencer est d’utiliser ce dépôt comme **modèle** pour votre propre activité.

1. Cliquez sur le bouton vert **« Use this template »** en haut de la page GitHub.
2. Choisissez **« Create a new repository »**.
3. Donnez un nom à votre nouveau dépôt (par exemple : `tp-tls-mon-nom`).
4. Rendez-le public ou privé selon vos besoins.

### 2. Cloner votre dépôt personnel

Une fois votre dépôt personnel créé, clonez-le sur votre machine locale et naviguez à l’intérieur :

```bash
# Remplacez <votre-nom-d-utilisateur> et <nom-du-depot>
git clone https://github.com/<votre-nom-d-utilisateur>/<nom-du-depot>.git
cd <nom-du-depot>
```

---

## Cas particulier : Windows + VM Debian

Si vous travaillez sous **Windows** avec une **machine virtuelle Debian**, un guide est disponible dans [`docs/vscode-ssh-windows.md`](docs/vscode-ssh-windows.md).
Ce guide explique comment utiliser **VS Code** et l’extension **Remote – SSH** pour travailler directement sur la VM.

Un script PowerShell est fourni à la racine (`setup-vscode-ssh.ps1`) pour automatiser la configuration : génération de clé, copie sur la VM et création d’un alias utilisable par VS Code.

---

## Notes importantes

* Ce dépôt est prévu **uniquement pour un usage pédagogique en réseau local**.
* Les certificats générés sont auto-signés par une CA interne : ils **ne doivent pas être utilisés en production**.
* Chaque utilisateur est invité à personnaliser et compléter la configuration afin de bien comprendre les concepts étudiés.

## Licence

Cette activité est sous licence [MIT](LICENSE). N’hésitez pas à l’utiliser, le modifier et le partager !
