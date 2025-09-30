#!/usr/bin/env bash
set -Eeuo pipefail

CACHE="172.25.253.25:5000"      # votre cache
DAEMON="/etc/docker/daemon.json"
BACKUP="/etc/docker/daemon.json.bak"
TMP="$(mktemp)"

usage() {
  cat <<EOF
Usage: sudo $0 {on|off|status|test}

  on     : configure Docker pour utiliser le cache ${CACHE}
  off    : retire la configuration du cache
  status : affiche si un mirror est actif côté Docker
  test   : teste l'accessibilité du cache (${CACHE}/v2/)
EOF
}

need_root() { [ "${EUID:-$(id -u)}" -eq 0 ] || { echo "Exécuter en root (sudo)." >&2; exit 1; }; }

test_cache() {
  code="$(curl -s -o /dev/null -w "%{http_code}\n" "http://${CACHE}/v2/")" || code="000"
  echo "${code}"
}

merge_json_with_python() {
  # $1 = mode (add|remove)
  python3 - "$1" "$CACHE" "$DAEMON" <<'PY'
import json, os, sys, tempfile, shutil
mode, cache, daemon = sys.argv[1], sys.argv[2], sys.argv[3]

data = {}
if os.path.exists(daemon) and os.path.getsize(daemon) > 0:
    with open(daemon, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except Exception:
            # fichier corrompu -> on repart d'un objet vide
            data = {}

if mode == "add":
    # registry-mirrors pour accélérer Docker Hub via le proxy-cache
    mirrors = set(data.get("registry-mirrors", []))
    mirrors.add(f"http://{cache}")
    data["registry-mirrors"] = sorted(mirrors)

    # cache en HTTP → ajouter insecure-registries
    insecs = set(data.get("insecure-registries", []))
    insecs.add(cache)
    data["insecure-registries"] = sorted(insecs)

elif mode == "remove":
    if "registry-mirrors" in data:
        data["registry-mirrors"] = [m for m in data["registry-mirrors"] if m not in (f"http://{cache}", f"https://{cache}")]
        if not data["registry-mirrors"]:
            del data["registry-mirrors"]
    if "insecure-registries" in data:
        data["insecure-registries"] = [i for i in data["insecure-registries"] if i != cache]
        if not data["insecure-registries"]:
            del data["insecure-registries"]
else:
    print("Unknown mode", file=sys.stderr)
    sys.exit(2)

# Écrire de façon atomique
fd, tmp = tempfile.mkstemp(prefix="daemon.", suffix=".json")
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
shutil.move(tmp, daemon)
PY
}

docker_reload() {
  systemctl daemon-reload || true
  systemctl restart docker
}

cmd_on() {
  need_root
  code="$(test_cache)"
  if [ "$code" != "200" ]; then
    echo "Le cache n'est pas joignable (code HTTP: ${code}). Abandon." >&2
    exit 1
  fi

  # Sauvegarde (une seule fois)
  if [ -f "$DAEMON" ] && [ ! -f "$BACKUP" ]; then
    cp -a -- "$DAEMON" "$BACKUP"
  fi
  touch "$DAEMON"

  merge_json_with_python add

  docker_reload
  echo "✅ Cache activé: ${CACHE}"
  docker info --format '{{json .RegistryConfig.Mirrors}}'
}

cmd_off() {
  need_root
  if [ -f "$DAEMON" ]; then
    merge_json_with_python remove
    docker_reload
    echo "❎ Cache désactivé (entrées retirées)."
  else
    echo "Aucun fichier ${DAEMON}. Rien à faire."
  fi
}

cmd_status() {
  # Pas besoin d'être root
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker non installé ?" >&2; exit 1
  fi
  echo "Mirrors configurés côté Docker :"
  docker info --format '{{json .RegistryConfig.Mirrors}}' || true
  echo "Insecure registries :"
  docker info --format '{{json .RegistryConfig.InsecureRegistryCIDRs}}' || true
  echo "Test du cache (${CACHE}/v2/) : HTTP $(test_cache)"
}

case "${1:-}" in
  on)     cmd_on ;;
  off)    cmd_off ;;
  status) cmd_status ;;
  test)   echo "HTTP $(test_cache)" ;;
  *)      usage; exit 1 ;;
esac
