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

# HKHK WordPress + MariaDB labori kontroll
# Kasutamine: sudo /usr/local/bin/hkhk-saada-tulemused.sh Debian1|Debian2
# Võti pannakse eraldi faili /etc/hkhk-dashboard-client.env:
# UPLOAD_TOKEN='...'
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
if [[ ! -r "$TOKEN_FILE" ]]; then
  echo "Puudub $TOKEN_FILE. Loo see ja lisa UPLOAD_TOKEN='serveri sama võti'."; exit 1
fi
# shellcheck disable=SC1090
source "$TOKEN_FILE"
: "${UPLOAD_TOKEN:?UPLOAD_TOKEN pole seadistatud failis $TOKEN_FILE}"

read -r -p "Õpilase ees- ja perekonnanimi: " STUDENT_NAME
STUDENT_NAME="$(printf '%s' "$STUDENT_NAME" | xargs)"
[[ -n "$STUDENT_NAME" ]] || { echo "Õpilase nimi ei tohi olla tühi."; exit 1; }

mkdir -p "$REPORT_DIR"
chmod 700 "$REPORT_DIR"
CHECKS_FILE="$(mktemp)"
REPORT_FILE="$REPORT_DIR/${MACHINE}.json"
trap 'rm -f "$CHECKS_FILE"' EXIT
printf '[]\n' > "$CHECKS_FILE"

add_check() {
  local id="$1" title="$2" expected="$3" actual="$4" status="$5" details="${6:-}"
  python3 - "$CHECKS_FILE" "$id" "$title" "$expected" "$actual" "$status" "$details" <<'PY'
import json, sys
from pathlib import Path
p=Path(sys.argv[1])
arr=json.loads(p.read_text())
arr.append({"id":sys.argv[2],"title":sys.argv[3],"expected":sys.argv[4],
            "actual":sys.argv[5],"status":sys.argv[6],"details":sys.argv[7]})
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
  local f root
  # Juhendi DocumentRoot on /var/www/kolmasdomeen.perenimi.local.
  # Otsi esmalt aktiivsete VirtualHostide DocumentRoot kataloogidest.
  while IFS= read -r root; do
    root="${root%\"}"; root="${root#\"}"; root="${root%\'}"; root="${root#\'}"
    [[ -n "$root" && -f "$root/wp-config.php" ]] && { echo "$root/wp-config.php"; return 0; }
  done < <(grep -RhoE '^[[:space:]]*DocumentRoot[[:space:]]+[^[:space:]]+' /etc/apache2/sites-enabled 2>/dev/null | awk '{print $2}')
  for f in /var/www/*/wp-config.php /var/www/html/wp-config.php; do
    [[ -f "$f" ]] && { echo "$f"; return 0; }
  done
  return 1
}
get_php_constant() {
  local file="$1" key="$2"
  python3 - "$file" "$key" <<'PY'
import re,sys
text=open(sys.argv[1],encoding="utf-8",errors="ignore").read()
key=re.escape(sys.argv[2])
m=re.search(r"define\s*\(\s*['\"]"+key+r"['\"]\s*,\s*(['\"])(.*?)\1\s*\)",text,re.S)
print(m.group(2).strip() if m else "")
PY
}

echo "HKHK labori kontroll — $MACHINE — $STUDENT_NAME"

if [[ "$MACHINE" == "Debian1" ]]; then
  check_service apache2 apache2 "Apache2 teenus"
  if command -v php >/dev/null 2>&1; then
    ver="$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)"
    add_check php "PHP paigaldus" "PHP olemas" "${ver:-versioon teadmata}" OK
  else add_check php "PHP paigaldus" "PHP olemas" "PHP puudub" FAIL; fi

  # Kontrolli Apache konfiguratsiooni ja saidi aktiveeritust.
  if command -v apache2ctl >/dev/null 2>&1 && apache2ctl configtest >/dev/null 2>&1; then
    add_check virtualhost "Apache VirtualHosti konfiguratsioon" "Apache konfiguratsioon korras" "Konfiguratsioon korras" OK
  else add_check virtualhost "Apache VirtualHosti konfiguratsioon" "Apache konfiguratsioon korras" "Konfiguratsiooni viga või apache2ctl puudub" FAIL; fi

  wpconfig=""
  if wpconfig="$(find_wp_config)"; then
    wpdir="$(dirname "$wpconfig")"
    add_check wordpress-files "WordPressi failid" "WordPressi wp-config.php olemas sobivas DocumentRootis" "$wpconfig" OK
    if [[ -r "$wpconfig" ]]; then
      add_check wp-config "WordPressi konfiguratsioonifail" "Fail loetav" "Fail loetav" OK
    else add_check wp-config "WordPressi konfiguratsioonifail" "Fail loetav" "Fail pole loetav" FAIL; fi

    dbname="$(get_php_constant "$wpconfig" DB_NAME)"
    dbuser="$(get_php_constant "$wpconfig" DB_USER)"
    dbhost="$(get_php_constant "$wpconfig" DB_HOST)"
    [[ -n "$dbname" ]] || dbname="MÄÄRAMATA"
    [[ -n "$dbuser" ]] || dbuser="MÄÄRAMATA"
    [[ -n "$dbhost" ]] || dbhost="MÄÄRAMATA"

    [[ "$dbname" == "kolmasdomeen_db" ]] && s=OK || s=FAIL
    add_check wp-db-name "WordPress DB_NAME" "kolmasdomeen_db" "$dbname" "$s"

    [[ "$dbuser" == "wpuser" ]] && s=OK || s=FAIL
    add_check wp-db-user "WordPress DB_USER" "wpuser" "$dbuser" "$s"

    # Võrguosa 10.0.X.25 võib erineda; hosti kontrollitakse IP-na või DNS-nimena.
    if [[ "$dbhost" =~ ^10\.0\.[0-9]{1,3}\.25$ ]]; then s=OK
    else s=FAIL; fi
    add_check wp-db-host "WordPress DB_HOST" "10.0.X.25 (MariaDB server)" "$dbhost" "$s"

    # Kasuta PHP mysqli ühendust, kui saadaval; parooli ei kuvata.
    if php -m 2>/dev/null | grep -qi '^mysqli$'; then
      dbpass="$(get_php_constant "$wpconfig" DB_PASSWORD)"
      if DBHOST="$dbhost" DBUSER="$dbuser" DBPASS="$dbpass" DBNAME="$dbname" php -r '
        $c=@new mysqli(getenv("DBHOST"),getenv("DBUSER"),getenv("DBPASS"),getenv("DBNAME"));
        if ($c->connect_errno) {fwrite(STDERR,"connection failed"); exit(1);}
        echo "Ühendus õnnestus"; $c->close();
      ' >/dev/null 2>&1; then
        add_check wp-db-connect "WordPressi ühendus MariaDB-ga" "Kaugühendus toimib" "Ühendus õnnestus" OK
      else
        add_check wp-db-connect "WordPressi ühendus MariaDB-ga" "Kaugühendus toimib" "Ühendus ebaõnnestus (kontrolli võrku, kasutajat, õigusi ja parooli)" FAIL
      fi
    else
      add_check wp-db-connect "WordPressi ühendus MariaDB-ga" "PHP mysqli ühendus" "PHP mysqli laiendus puudub; ühendust ei saanud testida" WARN
    fi
  else
    add_check wordpress-files "WordPressi failid" "wp-config.php WordPressi DocumentRootis" "wp-config.php ei leitud" FAIL
    add_check wp-config "WordPressi konfiguratsioonifail" "wp-config.php olemas" "Fail puudub" FAIL
    add_check wp-db-name "WordPress DB_NAME" "kolmasdomeen_db" "Ei saa kontrollida: wp-config.php puudub" FAIL
    add_check wp-db-user "WordPress DB_USER" "wpuser" "Ei saa kontrollida: wp-config.php puudub" FAIL
    add_check wp-db-host "WordPress DB_HOST" "10.0.X.25" "Ei saa kontrollida: wp-config.php puudub" FAIL
    add_check wp-db-connect "WordPressi ühendus MariaDB-ga" "Kaugühendus toimib" "Ei saa kontrollida: wp-config.php puudub" FAIL
  fi

elif [[ "$MACHINE" == "Debian2" ]]; then
  check_service mariadb mariadb "MariaDB teenus"
  check_service bind9 bind9 "BIND9 teenus"

  if command -v mariadb >/dev/null 2>&1; then
    if dbs="$(mariadb -N -e "SHOW DATABASES LIKE 'kolmasdomeen_db';" 2>/dev/null)" && [[ "$dbs" == "kolmasdomeen_db" ]]; then
      add_check database "MariaDB andmebaas" "kolmasdomeen_db olemas" "$dbs" OK
    else
      add_check database "MariaDB andmebaas" "kolmasdomeen_db olemas" "Puudub või kohalik admin-autentimine ei võimaldanud kontrollida" FAIL
    fi
    # User/host/grants kontroll; kasutajate loend eeldab kohalikku adminõigust.
    if grants="$(mariadb -N -e "SELECT CONCAT(User,'@',Host) FROM mysql.user WHERE User='wpuser';" 2>/dev/null)"; then
      if printf '%s\n' "$grants" | grep -Eq '^wpuser@10\.0\.[0-9]{1,3}\.20$'; then
        add_check db-user "MariaDB kasutaja wpuser" "wpuser@10.0.X.20" "$(printf '%s\n' "$grants" | paste -sd ', ' -)" OK
      else
        add_check db-user "MariaDB kasutaja wpuser" "wpuser@10.0.X.20" "${grants:-wpuser kasutaja puudub või vale Host}" FAIL
      fi
      if privs="$(mariadb -N -e "SHOW GRANTS FOR 'wpuser'@'$(printf '%s\n' "$grants" | sed -n 's/^wpuser@//p' | grep -E '^10\.0\.[0-9]{1,3}\.20$' | head -n1)';" 2>/dev/null)" && printf '%s\n' "$privs" | grep -Fq 'kolmasdomeen_db'; then
        add_check db-grants "MariaDB õigused" "wpuser õigused kolmasdomeen_db.* andmebaasile" "$(printf '%s\n' "$privs" | paste -sd '; ' -)" OK
      else
        add_check db-grants "MariaDB õigused" "wpuser õigused kolmasdomeen_db.* andmebaasile" "Õigusi ei saanud kinnitada" FAIL
      fi
    else
      add_check db-user "MariaDB kasutaja wpuser" "wpuser@10.0.X.20" "Kohalik admin-autentimine ei võimaldanud kasutajat kontrollida" WARN
      add_check db-grants "MariaDB õigused" "wpuser õigused kolmasdomeen_db.* andmebaasile" "Kohalik admin-autentimine ei võimaldanud õigusi kontrollida" WARN
    fi
  else
    add_check database "MariaDB andmebaas" "kolmasdomeen_db olemas" "mariadb klient puudub" FAIL
    add_check db-user "MariaDB kasutaja wpuser" "wpuser@10.0.X.20" "mariadb klient puudub" FAIL
    add_check db-grants "MariaDB õigused" "wpuser õigused kolmasdomeen_db.* andmebaasile" "mariadb klient puudub" FAIL
  fi

  if command -v named-checkconf >/dev/null 2>&1 && named-checkconf >/dev/null 2>&1; then
    add_check bind-config "BIND9 konfiguratsioon" "named-checkconf edukas" "Konfiguratsioon korras" OK
  else
    add_check bind-config "BIND9 konfiguratsioon" "named-checkconf edukas" "Konfiguratsiooni viga või käsk puudub" FAIL
  fi

  if command -v ss >/dev/null 2>&1; then
    listen="$(ss -ltn 2>/dev/null | awk '$4 ~ /:3306$/ {print $4}' | paste -sd ', ' -)"
    if [[ -n "$listen" ]] && [[ "$listen" != *"127.0.0.1:3306"* ]]; then
      add_check db-listen "MariaDB TCP kuulamine" "3306 port kuulab kaugühendusi" "$listen" OK
    else
      add_check db-listen "MariaDB TCP kuulamine" "3306 port kuulab kaugühendusi" "${listen:-3306 port ei kuula}" FAIL
    fi
  else
    add_check db-listen "MariaDB TCP kuulamine" "3306 port kuulab kaugühendusi" "ss käsk puudub" WARN
  fi

  bindfile="/etc/mysql/mariadb.conf.d/50-server.cnf"
  bindval="$(awk -F= '/^[[:space:]]*bind-address[[:space:]]*=/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$bindfile" 2>/dev/null || true)"
  if [[ "$bindval" == "0.0.0.0" || "$bindval" =~ ^10\.0\.[0-9]{1,3}\.25$ ]]; then
    add_check db-bind-address "MariaDB bind-address" "0.0.0.0 või Debian2 IP" "$bindval" OK
  else
    add_check db-bind-address "MariaDB bind-address" "0.0.0.0 või Debian2 IP" "${bindval:-seadistust ei leitud}" FAIL
  fi
fi

python3 - "$STUDENT_NAME" "$MACHINE" "$CHECKS_FILE" "$REPORT_FILE" <<'PY'
import json, socket, sys
from pathlib import Path
name,machine,checks_file,report_file=sys.argv[1:]
report={"student_name":name,"machine":machine,
        "checks":json.loads(Path(checks_file).read_text()),
        "hostname":socket.gethostname(),"script_version":"2.1"}
Path(report_file).write_text(json.dumps(report,ensure_ascii=False,indent=2))
PY
chmod 600 "$REPORT_FILE"

echo
echo "Raport salvestati: $REPORT_FILE"
echo "Saadan tulemused dashboardi..."
http_code="$(curl --silent --show-error --connect-timeout 5 --max-time 20 \
  --output "$REPORT_DIR/response.json" --write-out '%{http_code}' \
  -X POST "$DASHBOARD_URL/api/report" \
  -H 'Content-Type: application/json' \
  -H "X-Upload-Token: $UPLOAD_TOKEN" \
  --data-binary "@$REPORT_FILE")" || {
    echo "VIGA: dashboardiga ei saanud ühendust."; exit 1;
  }
echo "HTTP vastus: $http_code"
if [[ "$http_code" == "201" || "$http_code" == "200" ]]; then
  cat "$REPORT_DIR/response.json"; echo
  echo "Üleslaadimine õnnestus."
else
  cat "$REPORT_DIR/response.json" 2>/dev/null || true
  echo "Üleslaadimine ebaõnnestus."; exit 1
fi



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
