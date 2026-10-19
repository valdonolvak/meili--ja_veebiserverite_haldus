Jah — lisaks Flaski dashboardile peab olema eraldi üleslaadimisskript mõlemas Debian-serveris. Need skriptid kontrollivad oma serveri seadistust, koostavad JSON-raporti ja saadavad selle aadressile `192.168.124.64:5050`.

Sinu keskkonnas peab töövoog olema järgmine:

- Debian1 (`10.0.X.20`) – kontrollib Apache2, PHP, WordPressi ja veebiserveri seadistust.
- Debian2 (`10.0.X.25`) – kontrollib MariaDB-d, andmebaasi, kasutajaõigusi, BIND9 ja DNS-i.
- Dashboard (`192.168.124.64:5050`) – võtab raportid vastu ning seob need õpilase nimega.

Mõlemad skriptid küsivad õpilase nime, näiteks `Juku Juurikas`. Raport saadetakse eraldi masina identifikaatoriga, nii et tulemused ei kirjuta teineteist üle.

## 1. Üleslaadimise skriptid

Allpool on mõlema masina jaoks ühine Bash-skript. Sama fail töötab mõlemas masinas, kuid kontrollib ainult selle masina rolle, mille nime talle ette annad.

Loo Debian1 ja Debian2 masinas fail:

```
sudo nano /usr/local/bin/hkhk-saada-tulemused.sh
```

Lisa järgmine sisu:

```bash
 #!/usr/bin/env bash
set -Eeuo pipefail

# HKHK WordPress + MariaDB labori kontroll, versioon 2.2
# Debian1: ainult Apache/PHP/WordPress ning WordPressi ühendus Debian2-ga.
# Debian2: ainult MariaDB/andmebaas/kasutajaõigused/BIND9.
# Kasutamine: sudo /usr/local/bin/hkhk-saada-tulemused.sh Debian1|Debian2

DASHBOARD_URL="${DASHBOARD_URL:-http://192.168.124.64:5050}"
TOKEN_FILE="/etc/hkhk-dashboard-client.env"
REPORT_DIR="/var/tmp/hkhk-report"
MACHINE="${1:-}"

if [[ $EUID -ne 0 ]]; then echo "Käivita sudo abil."; exit 1; fi
if [[ "$MACHINE" != "Debian1" && "$MACHINE" != "Debian2" ]]; then
  echo "Kasutamine: sudo $0 Debian1|Debian2"; exit 1
fi
for cmd in python3 curl systemctl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Puudub vajalik käsk: $cmd"; exit 1; }
done
[[ -r "$TOKEN_FILE" ]] || { echo "Puudub $TOKEN_FILE."; exit 1; }
# shellcheck disable=SC1090
source "$TOKEN_FILE"
: "${UPLOAD_TOKEN:?UPLOAD_TOKEN pole seadistatud failis $TOKEN_FILE}"

read -r -p "Õpilase ees- ja perekonnanimi: " STUDENT_NAME
STUDENT_NAME="$(printf '%s' "$STUDENT_NAME" | xargs)"
[[ -n "$STUDENT_NAME" ]] || { echo "Õpilase nimi ei tohi olla tühi."; exit 1; }
read -r -p "Õpilase võrgu number X (10.0.X.20 / 10.0.X.25): " X
[[ "$X" =~ ^[0-9]{1,3}$ ]] && (( X >= 0 && X <= 255 )) || { echo "X peab olema 0–255."; exit 1; }
DEBIAN1_IP="10.0.${X}.20"
DEBIAN2_IP="10.0.${X}.25"
mkdir -p "$REPORT_DIR"; chmod 700 "$REPORT_DIR"
CHECKS_FILE="$(mktemp)"
REPORT_FILE="$REPORT_DIR/${MACHINE}.json"
trap 'rm -f "$CHECKS_FILE"' EXIT
printf '[]\n' > "$CHECKS_FILE"

add_check() {
  local id="$1" title="$2" expected="$3" actual="$4" status="$5" details="${6:-}"
  python3 - "$CHECKS_FILE" "$id" "$title" "$expected" "$actual" "$status" "$details" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); arr=json.loads(p.read_text())
arr.append({"id":sys.argv[2],"title":sys.argv[3],"expected":sys.argv[4],"actual":sys.argv[5],"status":sys.argv[6],"details":sys.argv[7]})
p.write_text(json.dumps(arr,ensure_ascii=False,indent=2))
PY
  printf '[%s] %s — %s\n' "$status" "$title" "$actual"
}
check_service() {
  local service="$1" id="$2" title="$3" actual status
  if systemctl is-active --quiet "$service"; then actual="active"; status="OK"
  else actual="$(systemctl is-active "$service" 2>/dev/null || true)"; actual="${actual:-inactive/puudub}"; status="FAIL"; fi
  add_check "$id" "$title" "active" "$actual" "$status"
}
find_wp_config() {
  local root f
  # Otsi ainult Debian1 veebiserveri kohalikest Apache seadistustest ja veebikataloogidest.
  while IFS= read -r root; do
    root="${root%\"}"; root="${root#\"}"; root="${root%\'}"; root="${root#\'}"
    [[ -n "$root" && -f "$root/wp-config.php" ]] && { printf '%s\n' "$root/wp-config.php"; return 0; }
  done < <(grep -RhoE '^[[:space:]]*DocumentRoot[[:space:]]+[^[:space:]]+' /etc/apache2/sites-enabled 2>/dev/null | awk '{print $2}')
  for f in /var/www/*/wp-config.php /var/www/html/wp-config.php; do
    [[ -f "$f" ]] && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}
get_php_constant() {
  python3 - "$1" "$2" <<'PY'
import re,sys
text=open(sys.argv[1],encoding='utf-8',errors='ignore').read(); key=re.escape(sys.argv[2])
m=re.search(r"define\s*\(\s*['\"]"+key+r"['\"]\s*,\s*(['\"])(.*?)\1\s*\)",text,re.S)
print(m.group(2).strip() if m else '')
PY
}

printf 'HKHK labori kontroll — %s — %s\n' "$MACHINE" "$STUDENT_NAME"

if [[ "$MACHINE" == "Debian1" ]]; then
  # Debian1 kontrollib ainult veebiserveri ja WordPressi osa.
  check_service apache2 apache2 "Apache2 teenus"
  if command -v php >/dev/null 2>&1; then
    ver="$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)"
    add_check php "PHP paigaldus" "PHP olemas" "${ver:-versioon teadmata}" OK
  else add_check php "PHP paigaldus" "PHP olemas" "PHP puudub" FAIL; fi

  if command -v apache2ctl >/dev/null 2>&1 && apache2ctl configtest >/dev/null 2>&1; then
    add_check virtualhost "Apache VirtualHosti konfiguratsioon" "Apache konfiguratsioon korras" "Konfiguratsioon korras" OK
  else add_check virtualhost "Apache VirtualHosti konfiguratsioon" "Apache konfiguratsioon korras" "Konfiguratsiooni viga või apache2ctl puudub" FAIL; fi

  wpconfig=""
  if wpconfig="$(find_wp_config)"; then
    add_check wordpress-files "WordPressi failid" "wp-config.php WordPressi DocumentRootis" "$wpconfig" OK
    [[ -r "$wpconfig" ]] && add_check wp-config "WordPressi konfiguratsioonifail" "Fail loetav" "Fail loetav" OK \
      || add_check wp-config "WordPressi konfiguratsioonifail" "Fail loetav" "Fail pole loetav" FAIL
```

See kasutab `curl`-i HTTP POST-päringut JSON-andmete saatmiseks. [curl-i JSON-päringute dokumentatsioon](https://everything.curl.dev/http/post/json.html?utm_source=chatgpt.com).

## 2. Paigalda skript mõlemasse masinasse

```
sudo chmod 750 /usr/local/bin/hkhk-saada-tulemused.sh
```

Käivita Debian1 masinas:

```
sudo /usr/local/bin/hkhk-saada-tulemused.sh Debian1
```

Käivita Debian2 masinas:

```
sudo /usr/local/bin/hkhk-saada-tulemused.sh Debian2
```

Skript salvestab enne saatmist kohaliku JSON-raporti kataloogi `/var/tmp/hkhk-report/` ning kuvab serveri vastuse. Kui üleslaadimine ebaõnnestub, jääb kohalik raport alles.

## 3. Tähtis: Flaski API peab sama formaati vastu võtma

Skripti üleslaadimine töötab ainult siis, kui Flaski rakenduses on `POST /api/report` marsruut, mis:

- kontrollib `Authorization: Bearer ...` võtit;
- loeb JSON-ist väljad `student`, `machine`, `timestamp` ja `checks`;
- salvestab raporti õpilase ja masina järgi;
- tagastab eduka salvestamise korral HTTP 200 või 201.

Oluline täpsustus: ülaltoodud skript on ühine näidis, mitte veel sinu ülesande täielik kontrollija. Debian1 näites on WordPressi konfiguratsioonifaili asukoht `/var/www/html/wp-config.php` ning Debian2 näites andmebaasi nimi `kolmasdomeen_db`. Kui sinu labor kasutab teistsugust dokumendijuurt, domeeni või andmebaasi, tuleb kontrollid vastavalt muuta. Samuti tuleb Flaski rakenduse API väljad ja autentimine selle skriptiga täpselt ühildada.


sudo grep -nE 'UPLOAD_TOKEN|X-Upload-Token|Authorization|curl' \
  /usr/local/bin/hkhk-saada-tulemused.sh


UPLOAD_TOKEN=fe67bb5eaa9d9e96d69aa2a0f8982ae7a56138ce1bbeb65291eb763dc8ab8210
ADMIN_USER=admin
ADMIN_PASSWORD=SalajaneParool123
FLASK_SECRET_KEY=2680b0daf78e5823b7d9e7cdc3c71f04650bb1a4eda14a477cb721c37b43cc83
DASHBOARD_DB=/var/lib/hkhk-dashboard/dashboard.sqlite3

