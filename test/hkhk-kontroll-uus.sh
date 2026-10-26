#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================================
# HKHK – Debian labori kontroll ja tulemuste üleslaadimine
#
# Kasutamine:
#   sudo /home/kasutaja/kontroll.sh Debian1
#   sudo /home/kasutaja/kontroll.sh Debian2
#
# Debian1: Apache2, PHP, WordPress ja andmebaasiühendus
# Debian2: MariaDB, andmebaasid, kasutajad ja BIND9
# ==========================================================

DASHBOARD_URL="${DASHBOARD_URL:-http://192.168.124.64:5050}"
TOKEN_FILE="${TOKEN_FILE:-/etc/hkhk-dashboard-client.env}"
MACHINE="${1:-}"
SCRIPT_VERSION="3.1"

if [[ "$EUID" -ne 0 ]]; then
    echo "VIGA: käivita skript sudo abil." >&2
    exit 1
fi

if [[ "$MACHINE" != "Debian1" && "$MACHINE" != "Debian2" ]]; then
    echo "Kasutus: sudo $0 Debian1|Debian2" >&2
    exit 1
fi

for cmd in python3 curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "VIGA: vajalik käsk puudub: $cmd" >&2
        exit 1
    fi
done

if [[ ! -r "$TOKEN_FILE" ]]; then
    echo "VIGA: tokenifaili ei saa lugeda: $TOKEN_FILE" >&2
    exit 1
fi

# Tokenifail sisaldab rida kujul:
# UPLOAD_TOKEN='...'
# Ära lisa tokenit skripti endasse.
# shellcheck disable=SC1090
source "$TOKEN_FILE"

if [[ -z "${UPLOAD_TOKEN:-}" ]]; then
    echo "VIGA: UPLOAD_TOKEN puudub tokenifailis." >&2
    exit 1
fi

read -r -p "Õpilase ees- ja perekonnanimi: " STUDENT_NAME

if [[ -z "${STUDENT_NAME//[[:space:]]/}" ]]; then
    echo "VIGA: õpilase nimi on kohustuslik." >&2
    exit 1
fi

TMP="$(mktemp /tmp/hkhk-report.XXXXXX.json)"
RESPONSE="$(mktemp /tmp/hkhk-response.XXXXXX)"
trap 'rm -f "$TMP" "$RESPONSE" /tmp/hkhk-named-check' EXIT

export STUDENT_NAME MACHINE TMP SCRIPT_VERSION

# ----------------------------------------------------------
# Raporti algstruktuur
# ----------------------------------------------------------
python3 - <<'PY'
import os
import json
import socket
import subprocess
import ipaddress

ips = []

try:
    output = subprocess.check_output(
        ["hostname", "-I"],
        text=True,
        stderr=subprocess.DEVNULL
    )

    for value in output.split():
        try:
            ip = ipaddress.ip_address(value)

            if ip.version == 4 and not ip.is_loopback:
                ips.append(str(ip))

        except ValueError:
            pass

except (subprocess.SubprocessError, OSError):
    pass

report = {
    "student_name": os.environ["STUDENT_NAME"].strip(),
    "machine": os.environ["MACHINE"],
    "hostname": socket.gethostname(),
    "ip_address": ips[0] if ips else "",
    "script_version": os.environ["SCRIPT_VERSION"],
    "checks": []
}

with open(os.environ["TMP"], "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False)
PY

# ----------------------------------------------------------
# Kontrolli lisamine raportisse
# ----------------------------------------------------------
add_check() {
    python3 - "$TMP" "$1" "$2" "$3" "$4" "$5" "${6:-}" <<'PY'
import json
import sys

path, check_id, title, status, expected, actual, details = sys.argv[1:]

with open(path, "r", encoding="utf-8") as f:
    report = json.load(f)

report["checks"].append({
    "id": check_id,
    "title": title,
    "status": status.upper(),
    "expected": expected,
    "actual": actual,
    "details": details
})

with open(path, "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False)
PY
}

# ----------------------------------------------------------
# Teenuse kontroll
# ----------------------------------------------------------
service_check() {
    local svc="$1"
    local title="$2"
    local id="$3"
    local actual

    actual="$(systemctl is-active "$svc" 2>/dev/null || true)"

    if [[ "$actual" == "active" ]]; then
        add_check "$id" "$title" PASS "active" "$actual"
    else
        add_check "$id" "$title" FAIL "active" "${actual:-failed}"
    fi
}

# ----------------------------------------------------------
# WordPressi wp-config.php konstantide lugemine
# ----------------------------------------------------------
get_constant() {
    python3 - "$1" "$2" <<'PY'
import re
import sys

path, key = sys.argv[1], sys.argv[2]

try:
    with open(path, encoding="utf-8", errors="replace") as f:
        content = f.read()
except OSError:
    print("")
    raise SystemExit(0)

pattern = (
    r"""define\s*\(\s*(['"])"""
    + re.escape(key)
    + r"""\1\s*,\s*(['"])(.*?)\2\s*\)"""
)

match = re.search(pattern, content, re.S)
print(match.group(3).strip() if match else "")
PY
}

# ==========================================================
# DEBIAN1 – Apache2, PHP ja WordPress
# ==========================================================
if [[ "$MACHINE" == "Debian1" ]]; then

    service_check apache2 "Apache2 teenus" apache2

    # Apache konfiguratsiooni süntaks
    if command -v apache2ctl >/dev/null 2>&1; then
        apache_output="$(apache2ctl configtest 2>&1 || true)"

        if grep -q "Syntax OK" <<< "$apache_output"; then
            add_check virtualhost \
                "Apache VirtualHosti konfiguratsioon" \
                PASS "Apache konfiguratsioon korras" "Konfiguratsioon korras"
        else
            add_check virtualhost \
                "Apache VirtualHosti konfiguratsioon" \
                FAIL "Apache konfiguratsioon korras" "$apache_output"
        fi
    else
        add_check virtualhost \
            "Apache VirtualHosti konfiguratsioon" \
            WARN "Apache konfiguratsioon korras" "apache2ctl käsk puudub"
    fi

    # PHP olemasolu
    if command -v php >/dev/null 2>&1; then
        add_check php "PHP paigaldus" PASS \
            "PHP olemas" "$(php -r 'echo PHP_VERSION;' 2>/dev/null || echo "olemas")"
    else
        add_check php "PHP paigaldus" FAIL "PHP olemas" "puudub"
    fi

    # Leia WordPressi konfiguratsioonifailid.
    mapfile -t configs < <(
        {
            grep -RhsE '^[[:space:]]*DocumentRoot[[:space:]]+' \
                /etc/apache2/sites-enabled \
                /etc/apache2/sites-available \
                2>/dev/null | awk '{print $2}'

            printf '%s\n' /var/www/* /var/www/html
        } |
        while IFS= read -r directory; do
            [[ -d "$directory" ]] || continue

            find "$directory" \
                -maxdepth 6 \
                -type f \
                -name wp-config.php \
                -print 2>/dev/null
        done |
        sort -u
    )

    if ((${#configs[@]})); then
        add_check wordpress-files \
            "WordPressi failid" PASS \
            "wp-config.php WordPressi DocumentRootis" "${configs[*]}"

        for cfg in "${configs[@]}"; do
            domain="$(basename "$(dirname "$cfg")")"

            add_check "wp-config-$domain" \
                "WordPressi konfiguratsioonifail" PASS \
                "Fail loetav" "Fail loetav"

            name="$(get_constant "$cfg" DB_NAME)"
            user="$(get_constant "$cfg" DB_USER)"
            host="$(get_constant "$cfg" DB_HOST)"
            pass="$(get_constant "$cfg" DB_PASSWORD)"

            # DB_NAME
            if [[ -n "$name" ]]; then
                add_check "wp-db-name-$domain" \
                    "WordPress DB_NAME" PASS \
                    "$name" "$name"
            else
                add_check "wp-db-name-$domain" \
                    "WordPress DB_NAME" FAIL \
                    "määratud" "puudub"
            fi

            # DB_USER
            if [[ -n "$user" ]]; then
                add_check "wp-db-user-$domain" \
                    "WordPress DB_USER" PASS \
                    "$user" "$user"
            else
                add_check "wp-db-user-$domain" \
                    "WordPress DB_USER" FAIL \
                    "määratud" "puudub"
            fi

            # DB_HOST
            if [[ -n "$host" ]]; then
                add_check "wp-db-host-$domain" \
                    "WordPress DB_HOST" PASS \
                    "$host" "$host"
            else
                add_check "wp-db-host-$domain" \
                    "WordPress DB_HOST" FAIL \
                    "määratud" "puudub"
            fi

            # Kontrolli, kas DB_HOST viitab kaugserverile.
            hp="${host%%:*}"
            hp="${hp#[}"
            hp="${hp%]}"

            if [[ -n "$hp" &&
                  "$hp" != "localhost" &&
                  "$hp" != "127.0.0.1" ]]; then
                add_check "wp-db-remote-$domain" \
                    "Kaugandmebaasi kasutamine" PASS \
                    "Kaugserveri IP ($host)" "$host"
            else
                add_check "wp-db-remote-$domain" \
                    "Kaugandmebaasi kasutamine" FAIL \
                    "Kaugserveri IP" "${host:-puudub}"
            fi

            # Testi tegelikku MySQL/MariaDB ühendust.
            if command -v php >/dev/null 2>&1 &&
               php -m 2>/dev/null | grep -qi '^mysqli$' &&
               [[ -n "$name" && -n "$user" &&
                  -n "$host" && -n "$pass" ]]; then

                if DBN="$name" DBU="$user" DBH="$host" DBP="$pass" \
                    php -r '
                        mysqli_report(MYSQLI_REPORT_OFF);

                        $host = getenv("DBH");
                        $port = 3306;

                        if (preg_match("/^(.+):([0-9]+)$/", $host, $m)) {
                            $host = trim($m[1], "[]");
                            $port = (int)$m[2];
                        } else {
                            $host = trim($host, "[]");
                        }

                        $db = @new mysqli(
                            $host,
                            getenv("DBU"),
                            getenv("DBP"),
                            getenv("DBN"),
                            $port
                        );

                        if ($db->connect_errno) {
                            exit(1);
                        }

                        $db->close();
                    ' >/dev/null 2>&1; then

                    add_check "wp-db-connect-$domain" \
                        "WordPressi ühendus MariaDB-ga" PASS \
                        "Ühendus aadressile $host toimib" "Ühendus õnnestus"
                else
                    add_check "wp-db-connect-$domain" \
                        "WordPressi ühendus MariaDB-ga" FAIL \
                        "Ühendus aadressile $host toimib" "Ühendus ebaõnnestus"
                fi
            else
                add_check "wp-db-connect-$domain" \
                    "WordPressi ühendus MariaDB-ga" WARN \
                    "Ühendus aadressile $host toimib" \
                    "ei testitud"
            fi
        done
    else
        add_check wordpress-files \
            "WordPressi failid" FAIL \
            "wp-config.php WordPressi DocumentRootis" "ei leitud"
    fi

# ==========================================================
# DEBIAN2 – MariaDB ja BIND9
# ==========================================================
else

    service_check mariadb "MariaDB teenus" mariadb
    service_check bind9 "BIND9 teenus" bind9

    DBCLI="$(command -v mariadb || command -v mysql || true)"

    if [[ -n "$DBCLI" ]]; then

        # Andmebaaside loetelu
        if dbs="$("$DBCLI" -N -B -e 'SHOW DATABASES;' 2>/dev/null)"; then

            dbs="$(printf '%s\n' "$dbs" |
                awk '$0!="information_schema" &&
                     $0!="performance_schema" &&
                     $0!="mysql" &&
                     $0!="sys" &&
                     NF')"

            if [[ -n "$dbs" ]]; then
                dbs_display="$(printf '%s\n' "$dbs" | paste -sd ', ' -)"

                add_check database \
                    "MariaDB andmebaasid" PASS \
                    "andmebaas olemas" "$dbs_display"

                while IFS= read -r dbn; do
                    [[ -n "$dbn" ]] || continue

                    add_check "database-$dbn" \
                        "MariaDB andmebaas" PASS \
                        "$dbn olemas" "$dbn"
                done <<< "$dbs"
            else
                add_check database \
                    "MariaDB andmebaasid" FAIL \
                    "vähemalt üks andmebaas" "ei leitud"
            fi
        else
            add_check database \
                "MariaDB andmebaaside loetelu" FAIL \
                "päring õnnestub" "päring ebaõnnestus"
        fi

        # Rakenduse kasutajad
        users="$("$DBCLI" -N -B -e "
            SELECT CONCAT(User,'@',Host)
            FROM mysql.user
            WHERE User NOT IN (
                'mariadb.sys','mysql','root','debian-sys-maint'
            )
            ORDER BY User,Host;
        " 2>/dev/null || true)"

        if [[ -n "$users" ]]; then
            users_display="$(printf '%s\n' "$users" | paste -sd ', ' -)"

            add_check db-user \
                "MariaDB kasutaja" PASS \
                "kasutaja olemas" "$users_display"
        else
            add_check db-user \
                "MariaDB kasutaja" WARN \
                "kasutajad loetavad" \
                "ei leitud või ligipääs puudub"
        fi

        # MariaDB õigused (grants)
        db_privs="$("$DBCLI" -N -B -e "
            SELECT CONCAT(User, ' õigused ', Db, '.* andmebaasile') 
            FROM mysql.db 
            WHERE User NOT IN ('mariadb.sys','mysql','root','debian-sys-maint');
        " 2>/dev/null || true)"

        if [[ -n "$db_privs" ]]; then
            while IFS= read -r priv; do
                [[ -z "$priv" ]] || add_check "db-grants-$priv" \
                    "MariaDB õigused" PASS \
                    "$priv" "Leiti ${priv/*õigused /} õiguste kirje"
            done <<< "$db_privs"
        else
            add_check db-grants \
                "MariaDB õigused" FAIL \
                "Kasutajale andmebaasi õigused määratud" "Ei leitud"
        fi

        # MariaDB bind-address
        bind_address="$("$DBCLI" -N -B -e \
            "SHOW VARIABLES LIKE 'bind_address';" 2>/dev/null |
            awk '{print $2}' || true)"

        case "$bind_address" in
            127.0.0.1|localhost)
                add_check db-bind-address \
                    "MariaDB bind-address" FAIL \
                    "0.0.0.0 või 10.0.10.25" "$bind_address"
                ;;
            "")
                add_check db-bind-address \
                    "MariaDB bind-address" WARN \
                    "väärtus loetav" "ei saanud lugeda"
                ;;
            *)
                add_check db-bind-address \
                    "MariaDB bind-address" PASS \
                    "0.0.0.0 või 10.0.10.25" "$bind_address"
                ;;
        esac
    else
        add_check database "MariaDB klient" FAIL \
            "mariadb/mysql olemas" "puudub"
    fi

    # TCP-port 3306
    if command -v ss >/dev/null 2>&1; then
        listen="$(ss -lnt 2>/dev/null |
            awk '$4 ~ /:3306$/ {print $4}' |
            paste -sd ', ' -)"

        if [[ -n "$listen" ]]; then
            add_check db-listen "MariaDB TCP kuulamine" PASS \
                "3306 port kuulab kaugühendusi" "$listen"
        else
            add_check db-listen "MariaDB TCP kuulamine" FAIL \
                "3306 port kuulab kaugühendusi" "port ei kuula"
        fi
    else
        add_check db-listen "MariaDB TCP kuulamine" WARN \
            "3306 port kuulab kaugühendusi" "käsk puudub"
    fi

    # BIND9 konfiguratsioon ja tsoonid
    if command -v named-checkconf >/dev/null 2>&1; then
        if named-checkconf -z >/tmp/hkhk-named-check 2>&1; then
            add_check bind-config \
                "BIND9 konfiguratsioon" PASS \
                "named-checkconf edukas" "Konfiguratsioon korras"
        else
            add_check bind-config \
                "BIND9 konfiguratsioon" FAIL \
                "named-checkconf edukas" \
                "$(cat /tmp/hkhk-named-check)"
        fi

        rm -f /tmp/hkhk-named-check
    else
        add_check bind-config \
            "BIND9 konfiguratsioon" WARN \
            "named-checkconf edukas" "Käsk puudub"
    fi
fi

# ----------------------------------------------------------
# Saada raport dashboardile
# ----------------------------------------------------------
CHECK_COUNT="$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    print(len(json.load(f)["checks"]))
' "$TMP")"

echo
echo "Õpilane:  $STUDENT_NAME"
echo "Masin:    $MACHINE"
echo "Host:     $(hostname)"
echo "Kontrolle: $CHECK_COUNT"
echo "Dashboard: ${DASHBOARD_URL%/}/api/report"
echo

HTTP_CODE="$(
    curl -sS \
        -o "$RESPONSE" \
        -w '%{http_code}' \
        --connect-timeout 5 \
        --max-time 30 \
        -H "X-Upload-Token: $UPLOAD_TOKEN" \
        -H 'Content-Type: application/json' \
        --data-binary "@$TMP" \
        "${DASHBOARD_URL%/}/api/report" || true
)"

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    echo "Õnnestus: raport saadeti dashboardile (HTTP $HTTP_CODE)."
    cat "$RESPONSE"
    echo
else
    echo "VIGA: raporti saatmine ebaõnnestus (HTTP ${HTTP_CODE:-puudub})." >&2

    if [[ -s "$RESPONSE" ]]; then
        cat "$RESPONSE" >&2
        echo >&2
    fi

    echo "Kontrolli dashboardi aadressi, tokenit ja serveri logisid." >&2
    exit 1
fi
