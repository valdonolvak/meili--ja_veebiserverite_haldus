#!/usr/bin/env bash
set -Eeuo pipefail
# Kasutus: sudo hkhk-saada-tulemused.sh Debian1|Debian2
DASHBOARD_URL="${DASHBOARD_URL:-http://192.168.124.64:5050}"
TOKEN_FILE="${TOKEN_FILE:-/etc/hkhk-dashboard-client.env}"
MACHINE="${1:-}"
[[ $EUID -eq 0 ]] || { echo "Käivita sudo abil." >&2; exit 1; }
[[ "$MACHINE" == Debian1 || "$MACHINE" == Debian2 ]] || { echo "Argument peab olema Debian1 või Debian2." >&2; exit 1; }
command -v python3 >/dev/null && command -v curl >/dev/null || { echo "Paigalda python3 ja curl." >&2; exit 1; }
[[ -r "$TOKEN_FILE" ]] || { echo "Tokenifaili ei saa lugeda: $TOKEN_FILE" >&2; exit 1; }
# Fail sisaldab rida: UPLOAD_TOKEN='...'
# shellcheck disable=SC1090
source "$TOKEN_FILE"
[[ -n "${UPLOAD_TOKEN:-}" ]] || { echo "UPLOAD_TOKEN puudub." >&2; exit 1; }
read -r -p "Õpilase ees- ja perekonnanimi: " STUDENT_NAME
[[ -n "${STUDENT_NAME// /}" ]] || { echo "Nimi on kohustuslik." >&2; exit 1; }
TMP="$(mktemp)"
trap 'rm -f "$TMP" /tmp/hkhk-report-response' EXIT
export STUDENT_NAME MACHINE TMP
python3 - <<'PY'
import os,json,socket,subprocess,ipaddress
ips=[]
try:
 for s in subprocess.check_output(["hostname","-I"],text=True).split():
  try:
   ip=ipaddress.ip_address(s)
   if ip.version==4 and not ip.is_loopback: ips.append(str(ip))
  except ValueError: pass
json.dump({"student_name":os.environ["STUDENT_NAME"].strip(),"machine":os.environ["MACHINE"],
 "hostname":socket.gethostname(),"ip_address":ips[0] if ips else "","script_version":"3.0","checks":[]},
 open(os.environ["TMP"],"w",encoding="utf-8"),ensure_ascii=False)
PY
add_check() {
 python3 - "$TMP" "$1" "$2" "$3" "$4" "$5" "${6:-}" <<'PY'
import json,sys
p,i,t,s,e,a,d=sys.argv[1:]
x=json.load(open(p,encoding="utf-8"))
x["checks"].append({"id":i,"title":t,"status":s,"expected":e,"actual":a,"details":d})
json.dump(x,open(p,"w",encoding="utf-8"),ensure_ascii=False)
PY
}
service_check() {
 local svc="$1" id="$2" actual
 actual="$(systemctl is-active "$svc" 2>/dev/null || true)"
 if [[ "$actual" == active ]]; then add_check "$id" "$svc teenus" PASS active "$actual"
 else add_check "$id" "$svc teenus" FAIL active "${actual:-not-installed}"; fi
}
get_constant() {
 python3 - "$1" "$2" <<'PY'
import re,sys
try: text=open(sys.argv[1],encoding="utf-8",errors="ignore").read()
except OSError: print(""); raise SystemExit
key=sys.argv[2]
pat=r"""define\s*\(\s*(['"])"""+re.escape(key)+r"""\1\s*,\s*(['"])(.*?)\2\s*\)"""
m=re.search(pat,text,re.S)
print(m.group(3).strip() if m else "")
PY
}
if [[ "$MACHINE" == Debian1 ]]; then
 service_check apache2 apache2
 if apache2ctl configtest 2>&1 | grep -q 'Syntax OK'; then add_check virtualhost "Apache konfiguratsiooni süntaks" PASS "Syntax OK" "Syntax OK"
 else add_check virtualhost "Apache konfiguratsiooni süntaks" FAIL "Syntax OK" "$(apache2ctl configtest 2>&1 || true)"; fi
 if command -v php >/dev/null; then add_check php "PHP CLI olemasolu" PASS "php olemas" "$(php -v | head -n1)"
 else add_check php "PHP CLI olemasolu" FAIL "php olemas" "puudub"; fi
 mapfile -t configs < <({ grep -RhsE '^[[:space:]]*DocumentRoot[[:space:]]+' /etc/apache2/sites-enabled /etc/apache2/sites-available 2>/dev/null | awk '{print $2}'; printf '%s\n' /var/www/* /var/www/html; } | while read -r d; do [[ -d "$d" ]] && find "$d" -maxdepth 5 -type f -name wp-config.php -print 2>/dev/null; done | sort -u)
 if ((${#configs[@]})); then
  add_check wordpress-files "WordPressi konfiguratsioonifailid" PASS "wp-config.php olemas" "${configs[*]}"
  for cfg in "${configs[@]}"; do
   domain="$(basename "$(dirname "$cfg")")"
   name="$(get_constant "$cfg" DB_NAME)"; user="$(get_constant "$cfg" DB_USER)"
   host="$(get_constant "$cfg" DB_HOST)"; pass="$(get_constant "$cfg" DB_PASSWORD)"
   [[ -n "$name" ]] && add_check "wp-db-name-$domain" "WordPress DB_NAME ($domain)" PASS "wp-config.php väärtus" "$name" || add_check "wp-db-name-$domain" "WordPress DB_NAME ($domain)" FAIL "määratud" "puudub"
   [[ -n "$user" ]] && add_check "wp-db-user-$domain" "WordPress DB_USER ($domain)" PASS "wp-config.php väärtus" "$user" || add_check "wp-db-user-$domain" "WordPress DB_USER ($domain)" FAIL "määratud" "puudub"
   [[ -n "$host" ]] && add_check "wp-db-host-$domain" "WordPress DB_HOST ($domain)" PASS "määratud" "$host" || add_check "wp-db-host-$domain" "WordPress DB_HOST ($domain)" FAIL "määratud" "puudub"
   hp="${host%%:*}"; hp="${hp#[}"; hp="${hp%]}"
   if [[ -n "$hp" && "$hp" != localhost && "$hp" != 127.0.0.1 ]]; then add_check "wp-db-remote-$domain" "Kaugandmebaasi kasutamine ($domain)" PASS "DB_HOST kaugserver" "$host"
   else add_check "wp-db-remote-$domain" "Kaugandmebaasi kasutamine ($domain)" FAIL "DB_HOST kaugserver" "$host"; fi
   if command -v php >/dev/null && php -m 2>/dev/null | grep -qi mysqli && [[ -n "$name" && -n "$user" && -n "$host" && -n "$pass" ]]; then
    if DBN="$name" DBU="$user" DBH="$host" DBP="$pass" php -r '$h=getenv("DBH");$p=3306;if(preg_match("/^(.+):([0-9]+)$/",$h,$m)){$h=$m[1];$p=(int)$m[2];}$c=@new mysqli($h,getenv("DBU"),getenv("DBP"),getenv("DBN"),$p);if($c->connect_errno)exit(1);$c->close();' >/dev/null 2>&1; then
     add_check "wp-db-connect-$domain" "WordPressi DB-ühendus ($domain)" PASS "ühendus õnnestub" "ühendus õnnestus"
    else add_check "wp-db-connect-$domain" "WordPressi DB-ühendus ($domain)" FAIL "ühendus õnnestub" "ühendus ebaõnnestus" "Kontrolli parooli, DB_HOST-i, õigusi ja võrku."; fi
   else add_check "wp-db-connect-$domain" "WordPressi DB-ühendus ($domain)" WARN "PHP mysqli ja DB parameetrid" "ühendust ei testitud"; fi
  done
 else add_check wordpress-files "WordPressi konfiguratsioonifailid" FAIL "wp-config.php leitav" "ei leitud" "Kontrolli VirtualHosti DocumentRooti."; fi
else
 service_check mariadb mariadb
 service_check bind9 bind9
 DBCLI="$(command -v mariadb || command -v mysql || true)"
 if [[ -n "$DBCLI" ]]; then
  if dbs="$("$DBCLI" -N -B -e 'SHOW DATABASES;' 2>/dev/null)"; then
   dbs="$(printf '%s\n' "$dbs" | awk '$0!="information_schema" && $0!="performance_schema" && $0!="mysql" && $0!="sys" && NF')"
   if [[ -n "$dbs" ]]; then
    add_check database "MariaDB rakenduse andmebaasid" PASS "andmebaas olemas" "$(printf '%s\n' "$dbs" | paste -sd ', ' -)"
    while read -r dbn; do [[ -n "$dbn" ]] && add_check "database-$dbn" "MariaDB andmebaas: $dbn" PASS "olemas" "$dbn"; done <<< "$dbs"
   else add_check database "MariaDB rakenduse andmebaasid" FAIL "vähemalt üks andmebaas" "ei leitud"; fi
  else add_check database "MariaDB andmebaaside loetelu" FAIL "päring õnnestub" "päring ebaõnnestus" "Kontrolli kohalikku MariaDB autentimist."; fi
  users="$("$DBCLI" -N -B -e "SELECT CONCAT(User,'@',Host) FROM mysql.user WHERE User NOT IN ('mariadb.sys','mysql','root','debian-sys-maint') ORDER BY User,Host;" 2>/dev/null || true)"
  if [[ -n "$users" ]]; then add_check db-user "MariaDB rakenduse kasutajad" PASS "kasutaja olemas" "$(printf '%s\n' "$users" | paste -sd ', ' -)"
  else add_check db-user "MariaDB rakenduse kasutajad" WARN "kasutajad loetavad" "ei leitud või ligipääs puudub"; fi
  bind="$("$DBCLI" -N -B -e "SHOW VARIABLES LIKE 'bind_address';" 2>/dev/null | awk '{print $2}' || true)"
  if [[ "$bind" == 127.0.0.1 || "$bind" == localhost ]]; then add_check db-bind-address "MariaDB bind-address" FAIL "kaugühendused lubatud" "$bind"
  elif [[ -n "$bind" ]]; then add_check db-bind-address "MariaDB bind-address" PASS "kaugühendused lubatud" "$bind"
  else add_check db-bind-address "MariaDB bind-address" WARN "väärtus loetav" "ei saanud lugeda"; fi
 else add_check database "MariaDB klient" FAIL "mariadb/mysql olemas" "puudub"; fi
 if command -v ss >/dev/null; then
  listen="$(ss -lnt 2>/dev/null | awk '$4 ~ /:3306$/ {print $4}' | paste -sd ', ' -)"
  if [[ -n "$listen" ]]; then add_check db-listen "MariaDB TCP 3306" PASS "kuulab" "$listen"; else add_check db-listen "MariaDB TCP 3306" FAIL "kuulab" "port ei kuula"; fi
 fi
 if command -v named-checkconf >/dev/null; then
  if named-checkconf -z >/tmp/hkhk-named-check 2>&1; then add_check bind-config "BIND9 konfiguratsioon ja tsoonid" PASS "named-checkconf -z" "kontroll õnnestus"
  else add_check bind-config "BIND9 konfiguratsioon ja tsoonid" FAIL "named-checkconf -z" "$(cat /tmp/hkhk-named-check)"; fi
  rm -f /tmp/hkhk-named-check
 else add_check bind-config "BIND9 konfiguratsiooni kontroll" WARN "named-checkconf olemas" "käsk puudub"; fi
fi
code="$(curl -sS -o /tmp/hkhk-report-response -w '%{http_code}' --connect-timeout 5 --max-time 30 -H "X-Upload-Token: $UPLOAD_TOKEN" -H 'Content-Type: application/json' --data-binary "@$TMP" "${DASHBOARD_URL%/}/api/report" || true)"
if [[ "$code" == 200 || "$code" == 201 ]]; then echo "Tulemused saadetud dashboardi (HTTP $code)."; cat /tmp/hkhk-report-response
else echo "VIGA: raporti saatmine ebaõnnestus (HTTP ${code:-puudub})." >&2; cat /tmp/hkhk-report-response 2>/dev/null || true; exit 1; fi
