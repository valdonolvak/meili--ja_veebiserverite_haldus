

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
# HKHK dünaamiline WordPress/MariaDB/BIND9 kontroll
# Debian1: kõik Apache vhostid ja /var/www/**/wp-config.php failid.
# Debian2: kõik kasutajaandmebaasid, MariaDB kasutajad/õigused, BIND9.
# Raporti API säilib: POST /api/report, X-Upload-Token, student_name/machine/checks.

MACHINE="${1:-}"
DASHBOARD_URL="${DASHBOARD_URL:-http://192.168.124.64:5050}"
TOKEN_FILE="/etc/hkhk-dashboard-client.env"
REPORT_DIR="/var/tmp/hkhk-report"

[[ $EUID -eq 0 ]] || { echo "Käivita sudo abil."; exit 1; }
[[ "$MACHINE" == Debian1 || "$MACHINE" == Debian2 ]] || { echo "Kasutamine: sudo $0 Debian1|Debian2"; exit 1; }
for cmd in python3 curl systemctl; do command -v "$cmd" >/dev/null 2>&1 || { echo "Puudub vajalik käsk: $cmd"; exit 1; }; done
[[ -r "$TOKEN_FILE" ]] || { echo "Puudub $TOKEN_FILE."; exit 1; }
# shellcheck disable=SC1090
source "$TOKEN_FILE"
: "${UPLOAD_TOKEN:?UPLOAD_TOKEN pole seadistatud failis $TOKEN_FILE}"

read -r -p "Õpilase ees- ja perekonnanimi: " STUDENT_NAME
STUDENT_NAME="$(printf '%s' "$STUDENT_NAME" | xargs)"
[[ -n "$STUDENT_NAME" ]] || { echo "Õpilase nimi ei tohi olla tühi."; exit 1; }

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
p=Path(sys.argv[1]); arr=json.loads(p.read_text(encoding="utf-8"))
arr.append({"id":sys.argv[2],"title":sys.argv[3],"expected":sys.argv[4],"actual":sys.argv[5],"status":sys.argv[6],"details":sys.argv[7]})
p.write_text(json.dumps(arr,ensure_ascii=False,indent=2),encoding="utf-8")
PY
  printf '[%s] %s — %s\n' "$status" "$title" "$actual"
}
check_service() {
  local service="$1" id="$2" title="$3" actual status
  if systemctl is-active --quiet "$service"; then actual=active; status=OK
  else actual="$(systemctl is-active "$service" 2>/dev/null || true)"; actual="${actual:-inactive/puudub}"; status=FAIL; fi
  add_check "$id" "$title" active "$actual" "$status"
}
get_php_constant() {
  python3 - "$1" "$2" <<'PY'
import re,sys
text=open(sys.argv[1],encoding="utf-8",errors="ignore").read()
key=re.escape(sys.argv[2])
m=re.search(r"define\s*\(\s*['\"]"+key+r"['\"]\s*,\s*(['\"])(.*?)\1\s*\)",text,re.S)
print(m.group(2).strip() if m else "")
PY
}
sid() { printf '%s' "$1" | tr -cs 'A-Za-z0-9_.-' '_' | cut -c1-90; }

get_vhost_map() {
python3 <<'PY'
from pathlib import Path
import re
for f in sorted(Path("/etc/apache2/sites-enabled").glob("*")):
    if not f.is_file(): continue
    try: text=f.read_text(errors="ignore")
    except OSError: continue
    for block in re.findall(r"<VirtualHost\b[^>]*>(.*?)</VirtualHost>",text,re.I|re.S):
        root=re.search(r"^\s*DocumentRoot\s+['\"]?([^'\"\s]+)",block,re.I|re.M)
        if not root: continue
        names=re.findall(r"^\s*ServerName\s+([^\s#]+)",block,re.I|re.M)
        aliases=re.findall(r"^\s*ServerAlias\s+(.+)$",block,re.I|re.M)
        for n in names: print(f"{n}\t{root.group(1)}")
        for line in aliases:
            for n in line.split():
                if not n.startswith("#"): print(f"{n}\t{root.group(1)}")
PY
}

echo "HKHK dünaamiline labori kontroll — $MACHINE — $STUDENT_NAME"

if [[ "$MACHINE" == Debian1 ]]; then
  check_service apache2 apache2 "Apache2 teenus"
  if command -v php >/dev/null 2>&1; then
    ver="$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)"
    add_check php "PHP paigaldus" "PHP olemas" "${ver:-versioon teadmata}" OK
  else add_check php "PHP paigaldus" "PHP olemas" "PHP puudub" FAIL; fi

  if command -v apache2ctl >/dev/null 2>&1 && apache2ctl configtest >/dev/null 2>&1; then
    add_check virtualhost "Apache VirtualHosti konfiguratsioon" "Apache konfiguratsioon korras" "Konfiguratsioon korras" OK
  else add_check virtualhost "Apache VirtualHosti konfiguratsioon" "Apache konfiguratsioon korras" "Viga või apache2ctl puudub" FAIL; fi

  VHOST_MAP="$(get_vhost_map || true)"
  if [[ -n "$VHOST_MAP" ]]; then
    while IFS=$'\t' read -r domain root; do
      [[ -n "${domain:-}" ]] && add_check "vhost-$(sid "$domain")" "VirtualHost: $domain" "Domeen ja DocumentRoot tuvastatud" "$root" OK
    done <<< "$VHOST_MAP"
  else add_check vhost-discovery "Apache VirtualHostide leidmine" "ServerName ja DocumentRoot" "VirtualHoste ei leitud" FAIL; fi

  # Kontrolli KÕIKI saite, mitte esimest suvalist wp-config.php faili.
  mapfile -t CONFIGS < <(find /var/www -type f -name wp-config.php -not -path '*/.git/*' 2>/dev/null | sort)
  if ((${#CONFIGS[@]} == 0)); then
    add_check wordpress-discovery "WordPressi leidmine" "wp-config.php fail /var/www all" "WordPressi konfiguratsiooni ei leitud" FAIL
  else
    add_check wordpress-discovery "WordPressi leidmine" "Kõik WordPressi saidid" "${#CONFIGS[@]} wp-config.php faili leitud" OK
    for config in "${CONFIGS[@]}"; do
      root="$(dirname "$config")"; folder="${root##*/}"
      domains="$(awk -F '\t' -v r="$root" '$2==r {if(o!="")o=o", ";o=o$1} END{print o}' <<< "$VHOST_MAP")"
      [[ -n "$domains" ]] || domains="$folder (ServerName ei leitud)"
      prefix="wp-$(sid "$folder")"
      add_check "$prefix-files" "WordPress $domains — failid" "wp-config.php saidi kataloogis" "$config" OK
      [[ -r "$config" ]] && add_check "$prefix-readable" "WordPress $domains — konfiguratsioon" "Fail loetav" "Fail loetav" OK || add_check "$prefix-readable" "WordPress $domains — konfiguratsioon" "Fail loetav" "Fail pole loetav" FAIL

      dbname="$(get_php_constant "$config" DB_NAME)"; dbuser="$(get_php_constant "$config" DB_USER)"
      dbhost="$(get_php_constant "$config" DB_HOST)"; dbpass="$(get_php_constant "$config" DB_PASSWORD)"
      [[ -n "$dbname" ]] || dbname=MÄÄRAMATA; [[ -n "$dbuser" ]] || dbuser=MÄÄRAMATA; [[ -n "$dbhost" ]] || dbhost=MÄÄRAMATA

      # Väärtused on iga saidi kohta eraldi näha; ei eelda fikseeritud domeeni/DB nime.
      add_check "$prefix-db-map" "WordPress $domains — andmebaasi seaded" "DB_NAME, DB_USER ja DB_HOST tuvastatud" "DB_NAME=$dbname; DB_USER=$dbuser; DB_HOST=$dbhost" OK

      # Ülesande põhinõue: DB peab asuma eraldi .25 serveris. DB nime ei fikseerita.
      if [[ "$dbhost" =~ ^10\.0\.[0-9]{1,3}\.25$ ]]; then
        add_check "$prefix-db-host" "WordPress $domains — kaugandmebaasi host" "DB_HOST on 10.0.X.25" "$dbhost" OK
      else
        add_check "$prefix-db-host" "WordPress $domains — kaugandmebaasi host" "DB_HOST on 10.0.X.25" "$dbhost" FAIL
      fi

      if [[ "$dbname" != MÄÄRAMATA && "$dbuser" != MÄÄRAMATA && "$dbhost" != MÄÄRAMATA ]] && command -v php >/dev/null 2>&1 && php -m 2>/dev/null | grep -qi '^mysqli$'; then
        if DBHOST="$dbhost" DBUSER="$dbuser" DBPASS="$dbpass" DBNAME="$dbname" php -r '
          mysqli_report(MYSQLI_REPORT_OFF);
          $c=@new mysqli(getenv("DBHOST"),getenv("DBUSER"),getenv("DBPASS"),getenv("DBNAME"),3306);
          if ($c->connect_errno) exit(1); $c->close();
        ' >/dev/null 2>&1; then
          add_check "$prefix-db-connect" "WordPress $domains — MariaDB ühendus" "Ühendus kasutades wp-config.php seadeid" "Ühendus õnnestus; parooli ei kuvata" OK
        else
          add_check "$prefix-db-connect" "WordPress $domains — MariaDB ühendus" "Ühendus kasutades wp-config.php seadeid" "Ühendus ebaõnnestus: kontrolli võrku, MariaDB kasutajat/õigusi ja parooli" FAIL
        fi
      else
        add_check "$prefix-db-connect" "WordPress $domains — MariaDB ühendus" "PHP mysqli ühendus" "Ei saanud testida: DB väärtused puuduvad või PHP mysqli laiendus puudub" WARN
      fi
    done
  fi

elif [[ "$MACHINE" == Debian2 ]]; then
  check_service mariadb mariadb "MariaDB teenus"
  check_service bind9 bind9 "BIND9 teenus"

  if command -v mariadb >/dev/null 2>&1; then
    if dbs="$(mariadb --batch --skip-column-names -e "SHOW DATABASES;" 2>/dev/null)"; then
      userdbs="$(printf '%s\n' "$dbs" | grep -Ev '^(information_schema|mysql|performance_schema|sys)$' | sed '/^$/d' || true)"
      if [[ -n "$userdbs" ]]; then
        while IFS= read -r db; do [[ -n "$db" ]] && add_check "database-$(sid "$db")" "MariaDB andmebaas: $db" "Andmebaas olemas" "$db" OK; done <<< "$userdbs"
        add_check database-list "MariaDB andmebaaside kokkuvõte" "Kasutajaandmebaasid loetletud" "$(printf '%s\n' "$userdbs" | paste -sd ', ' -)" OK
      else add_check database-list "MariaDB andmebaaside kokkuvõte" "Vähemalt üks kasutajaandmebaas" "Kasutajaandmebaase ei leitud" FAIL; fi
    else add_check database-list "MariaDB andmebaaside kokkuvõte" "SHOW DATABASES õnnestub" "Kohalik admin-autentimine ei võimaldanud andmeid lugeda" FAIL; fi

    if users="$(mariadb --batch --skip-column-names -e "SELECT CONCAT(User,'@',Host) FROM mysql.user WHERE User NOT IN ('mariadb.sys','mysql','root');" 2>/dev/null)"; then
      add_check mariadb-users "MariaDB kasutajad ja lubatud hostid" "Kasutajate loend loetav" "$(printf '%s\n' "$users" | sed '/^$/d' | paste -sd ', ' -)" OK
      while IFS= read -r userhost; do
        [[ -n "$userhost" ]] || continue
        user="${userhost%@*}"; host="${userhost#*@}"
        grants="$(mariadb --batch --skip-column-names -e "SHOW GRANTS FOR '$user'@'$host';" 2>/dev/null || true)"
        if [[ -n "$grants" ]]; then
          add_check "grant-$(sid "$userhost")" "MariaDB õigused: $userhost" "Kasutaja õiguste kirje olemas" "$(printf '%s\n' "$grants" | paste -sd '; ' -)" OK
        else add_check "grant-$(sid "$userhost")" "MariaDB õigused: $userhost" "Õigused loetavad" "Õigusi ei saanud lugeda" WARN; fi
      done <<< "$users"
    else add_check mariadb-users "MariaDB kasutajad ja lubatud hostid" "Kasutajate loend loetav" "Kohalik admin-autentimine ei võimaldanud lugeda" WARN; fi
  else add_check database-list "MariaDB andmebaaside kokkuvõte" "mariadb klient olemas" "mariadb klient puudub" FAIL; fi

  if command -v named-checkconf >/dev/null 2>&1 && named-checkconf >/dev/null 2>&1; then
    add_check bind-config "BIND9 konfiguratsioon" "named-checkconf edukas" "Konfiguratsioon korras" OK
  else add_check bind-config "BIND9 konfiguratsioon" "named-checkconf edukas" "Viga või käsk puudub" FAIL; fi

  if command -v ss >/dev/null 2>&1; then
    listeners="$(ss -ltn 2>/dev/null | awk '$4 ~ /:3306$/ {print $4}' | paste -sd ', ' -)"
    if [[ -n "$listeners" ]] && ! grep -Eq '(^|[ ,])127\.0\.0\.1:3306($|[ ,])' <<< "$listeners"; then
      add_check db-listen "MariaDB TCP kuulamine" "Port 3306 on kaugühenduseks avatud" "$listeners" OK
    else add_check db-listen "MariaDB TCP kuulamine" "Port 3306 on kaugühenduseks avatud" "${listeners:-port ei kuula}" FAIL; fi
  else add_check db-listen "MariaDB TCP kuulamine" "ss käsk olemas" "ss puudub" WARN; fi

  bindfile="/etc/mysql/mariadb.conf.d/50-server.cnf"
  bindval="$(awk -F= '/^[[:space:]]*bind-address[[:space:]]*=/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$bindfile" 2>/dev/null || true)"
  if [[ "$bindval" == 0.0.0.0 || "$bindval" =~ ^10\.0\.[0-9]{1,3}\.25$ ]]; then
    add_check db-bind-address "MariaDB bind-address" "0.0.0.0 või Debian2 IP" "$bindval" OK
  else add_check db-bind-address "MariaDB bind-address" "0.0.0.0 või Debian2 IP" "${bindval:-seadistust ei leitud failist $bindfile}" FAIL; fi

  # Tuvasta tsoonid BIND konfiguratsioonifailidest.
  zones="$(grep -RhoE 'zone[[:space:]]+["'\"'][^"'\"']+["'\"']' /etc/bind 2>/dev/null | sed -E 's/zone[[:space:]]+["'\"']([^"'\"']+)["'\"'].*/\1/' | sort -u || true)"
  if [[ -n "$zones" ]]; then
    while IFS= read -r zone; do [[ -n "$zone" ]] && add_check "bind-zone-$(sid "$zone")" "BIND9 tsoon: $zone" "Tsoon deklaratsioon tuvastatud" "$zone" OK; done <<< "$zones"
  else add_check bind-zones "BIND9 tsoonide leidmine" "Vähemalt üks tsoon" "Tsoone ei leitud /etc/bind alt" WARN; fi
fi

python3 - "$STUDENT_NAME" "$MACHINE" "$CHECKS_FILE" "$REPORT_FILE" <<'PY'
import json,socket,sys
from pathlib import Path
name,machine,checks_file,report_file=sys.argv[1:]
report={"student_name":name,"machine":machine,"checks":json.loads(Path(checks_file).read_text(encoding="utf-8")),"hostname":socket.gethostname(),"script_version":"3.0"}
Path(report_file).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
PY
chmod 600 "$REPORT_FILE"
echo
echo "Raport salvestati: $REPORT_FILE"
echo "Saadan tulemused dashboardi..."
http_code="$(curl --silent --show-error --connect-timeout 5 --max-time 20 --output "$REPORT_DIR/response.json" --write-out '%{http_code}' -X POST "${DASHBOARD_URL%/}/api/report" -H 'Content-Type: application/json' -H "X-Upload-Token: $UPLOAD_TOKEN" --data-binary "@$REPORT_FILE")" || { echo "VIGA: dashboardiga ei saanud ühendust."; exit 1; }
echo "HTTP vastus: $http_code"
if [[ "$http_code" == 201 || "$http_code" == 200 ]]; then
  cat "$REPORT_DIR/response.json"; echo
  echo "Üleslaadimine õnnestus."
else
  cat "$REPORT_DIR/response.json" 2>/dev/null || true
  echo "Üleslaadimine ebaõnnestus."; exit 1
fi


```
Kui bash -n ei väljasta midagi, on Bash-süntaks korras.

Kontrolli ka Python-plokkide süntaksit, käivitades skripti testkeskkonnas ei ole vaja midagi muuta — allpool olev käsk kontrollib skriptist eraldatud Python-plokke:


```bash
sudo python3 - <<'PY'
import re
import subprocess

path = "/home/kasutaja/kontroll.sh"
text = open(path, encoding="utf-8").read()

blocks = re.findall(r"<<'PY'\n(.*?)\nPY", text, re.S)

for number, block in enumerate(blocks, 1):
    result = subprocess.run(
        ["python3", "-c", "import ast,sys; ast.parse(sys.stdin.read())"],
        input=block,
        text=True,
        capture_output=True
    )
    if result.returncode:
        print(f"Python-plokk {number}: VIGA")
        print(result.stderr)
        raise SystemExit(1)

print(f"Korras: kõik {len(blocks)} Python-plokki on süntaktiliselt õiged.")
PY


```
