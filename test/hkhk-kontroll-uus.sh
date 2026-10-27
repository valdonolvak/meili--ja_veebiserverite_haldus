#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================================
# HKHK – Debian labori kontroll
#
# Debian1: Apache2, PHP, WordPress, wp-config.php, DB-ühendus
# Debian2: MariaDB, kolmasdomeen_db, wpuser, BIND9
#
# Kasutamine:
#   sudo ./kontroll.sh Debian1
#   sudo ./kontroll.sh Debian2
#
# Raporti saatmine dashboardi:
#   DASHBOARD_URL
#   TOKEN_FILE
# ==========================================================

DASHBOARD_URL="${DASHBOARD_URL:-http://192.168.124.64:5050}"
TOKEN_FILE="${TOKEN_FILE:-/etc/hkhk-dashboard-client.env}"
MACHINE="${1:-}"

DB_NAME_EXPECTED="kolmasdomeen_db"
DB_USER_EXPECTED="wpuser"

[[ $EUID -eq 0 ]] || {
    echo "VIGA: käivita skript sudo abil."
    exit 1
}

[[ "$MACHINE" == "Debian1" || "$MACHINE" == "Debian2" ]] || {
    echo "Kasutamine: sudo $0 Debian1|Debian2"
    exit 1
}

command -v python3 >/dev/null || {
    echo "VIGA: python3 puudub."
    exit 1
}

command -v curl >/dev/null || {
    echo "VIGA: curl puudub."
    exit 1
}

[[ -r "$TOKEN_FILE" ]] || {
    echo "VIGA: tokenifaili ei saa lugeda: $TOKEN_FILE"
    exit 1
}

# shellcheck disable=SC1090
source "$TOKEN_FILE"

[[ -n "${UPLOAD_TOKEN:-}" ]] || {
    echo "VIGA: UPLOAD_TOKEN puudub."
    exit 1
}

read -r -p "Õpilase ees- ja perekonnanimi: " STUDENT_NAME

[[ -n "${STUDENT_NAME// /}" ]] || {
    echo "VIGA: nimi on kohustuslik."
    exit 1
}

TMP="$(mktemp)"
RESPONSE="$(mktemp)"
trap 'rm -f "$TMP" "$RESPONSE"' EXIT

export STUDENT_NAME MACHINE TMP

# ----------------------------------------------------------
# Üldandmed
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
            continue

except (OSError, subprocess.SubprocessError):
    pass

report = {
    "student_name": os.environ["STUDENT_NAME"].strip(),
    "machine": os.environ["MACHINE"],
    "hostname": socket.gethostname(),
    "ip_address": ips[0] if ips else "",
    "script_version": "4.0",
    "checks": []
}

with open(os.environ["TMP"], "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False)
PY

# ----------------------------------------------------------
# Kontrolli lisamine raportisse
#
# argumendid:
# id, pealkiri, staatus, oodatud, tegelik, selgitus
# ----------------------------------------------------------

add_check() {
    python3 - "$TMP" "$1" "$2" "$3" "$4" "$5" "${6:-}" <<'PY'
import json
import sys

path, check_id, title, status, expected, actual, details = sys.argv[1:]

with open(path, encoding="utf-8") as f:
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
# Abifunktsioonid
# ----------------------------------------------------------

service_check() {
    local service="$1"
    local id="$2"
    local actual

    actual="$(systemctl is-active "$service" 2>/dev/null || true)"

    if [[ "$actual" == "active" ]]; then
        add_check "$id" "$service teenus" PASS \
            "Teenus peab töötama (active)" "$actual" \
            "Teenuse olek kontrolliti käsuga systemctl is-active."
    else
        add_check "$id" "$service teenus" FAIL \
            "Teenus peab töötama (active)" "${actual:-teadmata}" \
            "Kontrolli teenuse olekut käsuga systemctl status $service."
    fi
}

check_command() {
    local command_name="$1"
    local id="$2"
    local title="$3"

    if command -v "$command_name" >/dev/null 2>&1; then
        add_check "$id" "$title" PASS \
            "Käsk $command_name peab olema paigaldatud" \
            "$(command -v "$command_name")" \
            "Vajalik käsk on süsteemis olemas."
    else
        add_check "$id" "$title" FAIL \
            "Käsk $command_name peab olema paigaldatud" \
            "Käsku ei leitud" \
            "Paigalda puuduv tarkvarapakett."
    fi
}

get_constant() {
    python3 - "$1" "$2" <<'PY'
import re
import sys

path, key = sys.argv[1:3]

try:
    with open(path, encoding="utf-8", errors="replace") as f:
        content = f.read()
except OSError:
    print("")
    raise SystemExit

pattern = (
    r"""define\s*\(\s*(['"])"""
    + re.escape(key)
    + r"""\1\s*,\s*(['"])(.*?)\2\s*\)"""
)

match = re.search(pattern, content, re.S)
print(match.group(3).strip() if match else "")
PY
}

# ----------------------------------------------------------
# Debian1 – Apache2 ja WordPress
# ----------------------------------------------------------

if [[ "$MACHINE" == "Debian1" ]]; then

    service_check apache2 apache2

    check_command apache2ctl apache-config-command \
        "Apache kontrollkäsk"

    if command -v apache2ctl >/dev/null 2>&1; then
        apache_output="$(apache2ctl configtest 2>&1 || true)"

        if grep -q "Syntax OK" <<< "$apache_output"; then
            add_check virtualhost apache-config PASS \
                "Apache konfiguratsioon peab olema süntaktiliselt korrektne" \
                "$apache_output" \
                "Apache konfiguratsiooni süntaks on korrektne."
        else
            add_check virtualhost apache-config FAIL \
                "Apache konfiguratsioon peab andma tulemuse Syntax OK" \
                "$apache_output" \
                "Kontrolli VirtualHosti ja Apache konfiguratsioonifaile."
        fi
    fi

    check_command php php-cli "PHP CLI olemasolu"

    if command -v php >/dev/null 2>&1; then
        php_version="$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)"

        add_check php-version php-version PASS \
            "PHP peab olema paigaldatud" \
            "${php_version:-versioon teadmata}" \
            "PHP versioon loeti käsurealt."

        if php -m 2>/dev/null | grep -qi '^mysqli$'; then
            add_check php-mysqli php-mysqli PASS \
                "PHP mysqli laiendus peab olema olemas" \
                "mysqli on laaditud" \
                "WordPress vajab MariaDB/MySQL ühenduseks mysqli laiendust."
        else
            add_check php-mysqli php-mysqli FAIL \
                "PHP mysqli laiendus peab olema olemas" \
                "mysqli puudub" \
                "Paigalda PHP mysqli laiendus ja taaskäivita Apache."
        fi
    else
        add_check php-mysqli php-mysqli FAIL \
            "PHP ja mysqli peavad olema olemas" \
            "PHP puudub" \
            "Paigalda PHP ning vajalikud laiendused."
    fi

    # Leia WordPressi konfiguratsioonifailid Apache DocumentRootidest
    mapfile -t DOCROOTS < <(
        grep -RhsE '^[[:space:]]*DocumentRoot[[:space:]]+' \
            /etc/apache2/sites-enabled /etc/apache2/sites-available \
            2>/dev/null |
        awk '{print $2}' |
        sort -u
    )

    CONFIGS=()

    for root in "${DOCROOTS[@]}"; do
        [[ -d "$root" ]] || continue

        while IFS= read -r file; do
            [[ -n "$file" ]] && CONFIGS+=("$file")
        done < <(
            find "$root" -maxdepth 5 -type f \
                -name wp-config.php -print 2>/dev/null
        )
    done

    # Varukontroll levinud WordPressi asukohtades
    for root in /var/www /var/www/html; do
        [[ -d "$root" ]] || continue

        while IFS= read -r file; do
            [[ -n "$file" ]] && CONFIGS+=("$file")
        done < <(
            find "$root" -maxdepth 5 -type f \
                -name wp-config.php -print 2>/dev/null
        )
    done

    mapfile -t CONFIGS < <(
        printf '%s\n' "${CONFIGS[@]}" |
        sed '/^$/d' |
        sort -u
    )

    if ((${#CONFIGS[@]} == 0)); then
        add_check wordpress-files wordpress-files FAIL \
            "WordPressi DocumentRootis peab olema wp-config.php" \
            "wp-config.php ei leitud" \
            "Kontrolli Apache DocumentRooti ja WordPressi failide asukohta."
    else
        add_check wordpress-files wordpress-files PASS \
            "Vähemalt üks WordPressi wp-config.php peab olema leitav" \
            "$(printf '%s\n' "${CONFIGS[@]}")" \
            "Leitud failid kontrollitakse eraldi."
    fi

    for cfg in "${CONFIGS[@]}"; do
        domain="$(basename "$(dirname "$cfg")")"

        name="$(get_constant "$cfg" DB_NAME)"
        user="$(get_constant "$cfg" DB_USER)"
        host="$(get_constant "$cfg" DB_HOST)"
        pass="$(get_constant "$cfg" DB_PASSWORD)"

        # DB_NAME
        if [[ "$name" == "$DB_NAME_EXPECTED" ]]; then
            add_check "wp-db-name-$domain" \
                "WordPress DB_NAME ($domain)" PASS \
                "DB_NAME peab olema $DB_NAME_EXPECTED" "$name" \
                "wp-config.php andmebaasi nimi vastab ülesande nõudele."
        else
            add_check "wp-db-name-$domain" \
                "WordPress DB_NAME ($domain)" FAIL \
                "DB_NAME peab olema $DB_NAME_EXPECTED" \
                "${name:-väärtus puudub}" \
                "Muuda wp-config.php faili DB_NAME väärtust."
        fi

        # DB_USER
        if [[ "$user" == "$DB_USER_EXPECTED" ]]; then
            add_check "wp-db-user-$domain" \
                "WordPress DB_USER ($domain)" PASS \
                "DB_USER peab olema $DB_USER_EXPECTED" "$user" \
                "wp-config.php kasutajanimi vastab ülesande nõudele."
        else
            add_check "wp-db-user-$domain" \
                "WordPress DB_USER ($domain)" FAIL \
                "DB_USER peab olema $DB_USER_EXPECTED" \
                "${user:-väärtus puudub}" \
                "Muuda wp-config.php faili DB_USER väärtust."
        fi

        # DB_HOST – peab olema kaugserver, mitte localhost
        host_clean="${host%%:*}"
        host_clean="${host_clean#[}"
        host_clean="${host_clean%]}"

        if [[ -n "$host_clean" &&
              "$host_clean" != "localhost" &&
              "$host_clean" != "127.0.0.1" ]]; then
            add_check "wp-db-host-$domain" \
                "WordPress DB_HOST ($domain)" PASS \
                "DB_HOST peab viitama Debian2 MariaDB serverile, mitte localhost'ile" \
                "$host" \
                "DB_HOST on seadistatud kaugühenduseks. Kontrolli, et aadress on Debian2 IP."
        else
            add_check "wp-db-host-$domain" \
                "WordPress DB_HOST ($domain)" FAIL \
                "DB_HOST peab viitama Debian2 MariaDB serverile, mitte localhost'ile" \
                "${host:-väärtus puudub}" \
                "WordPress ja MariaDB asuvad eri serverites. Kasuta Debian2 IP-aadressi."
        fi

        # Tegelik andmebaasiühendus
        if [[ -n "$name" && -n "$user" && -n "$host" && -n "$pass" ]] &&
           command -v php >/dev/null 2>&1 &&
           php -m 2>/dev/null | grep -qi '^mysqli$'; then

            if DBN="$name" DBU="$user" DBH="$host" DBP="$pass" \
                php -r '
                    $host = getenv("DBH");
                    $port = 3306;
                    if (preg_match("/^(.+):([0-9]+)$/", $host, $m)) {
                        $host = trim($m[1], "[]");
                        $port = (int)$m[2];
                    }
                    $db = @new mysqli(
                        $host, getenv("DBU"), getenv("DBP"),
                        getenv("DBN"), $port
                    );
                    if ($db->connect_errno) {
                        fwrite(STDERR, $db->connect_error);
                        exit(1);
                    }
                    $db->close();
                ' 2>"$RESPONSE"; then

                add_check "wp-db-connect-$domain" \
                    "WordPressi DB-ühendus ($domain)" PASS \
                    "Ühendus peab õnnestuma andmebaasiga $DB_NAME_EXPECTED kasutajana $DB_USER_EXPECTED" \
                    "Ühendus õnnestus: DB_NAME=$name; DB_USER=$user; DB_HOST=$host" \
                    "PHP mysqli sai ühenduse loodud."
            else
                add_check "wp-db-connect-$domain" \
                    "WordPressi DB-ühendus ($domain)" FAIL \
                    "Ühendus peab õnnestuma andmebaasiga $DB_NAME_EXPECTED kasutajana $DB_USER_EXPECTED" \
                    "Ühendus ebaõnnestus: DB_NAME=$name; DB_USER=$user; DB_HOST=$host" \
                    "$(cat "$RESPONSE" 2>/dev/null || echo 'Kontrolli DB_HOST-i, parooli, õigusi ja võrguühendust.')"
            fi
        else
            add_check "wp-db-connect-$domain" \
                "WordPressi DB-ühendus ($domain)" WARN \
                "PHP mysqli ja kõik DB_* väärtused peavad olema määratud" \
                "Ühendust ei testitud" \
                "Vajalikud konfiguratsiooniväärtused või mysqli laiendus puuduvad."
        fi

    done

    # Apache HTTP port
    if command -v ss >/dev/null 2>&1; then
        listen80="$(ss -lnt 2>/dev/null | awk '$4 ~ /:80$/ {print $4}')"

        if [[ -n "$listen80" ]]; then
            add_check apache-port80 apache-port80 PASS \
                "Apache peab kuulama TCP porti 80" "$listen80" \
                "TCP port 80 kuulab."
        else
            add_check apache-port80 apache-port80 FAIL \
                "Apache peab kuulama TCP porti 80" \
                "Port 80 ei kuula" \
                "Kontrolli Apache teenust ja portide seadistust."
        fi
    fi

# ----------------------------------------------------------
# Debian2 – MariaDB ja BIND9
# ----------------------------------------------------------

else

    service_check mariadb mariadb
    service_check bind9 bind9

    DBCLI="$(command -v mariadb || command -v mysql || true)"

    if [[ -z "$DBCLI" ]]; then
        add_check database-client database-client FAIL \
            "MariaDB/MySQL klient peab olema paigaldatud" \
            "Klienti ei leitud" \
            "Paigalda MariaDB klient."
    else
        # Andmebaasi olemasolu
        if dbs="$("$DBCLI" -N -B -e 'SHOW DATABASES;' 2>/dev/null)"; then
            if grep -Fxq "$DB_NAME_EXPECTED" <<< "$dbs"; then
                add_check database database PASS \
                    "Andmebaas $DB_NAME_EXPECTED peab olemas olema" \
                    "$DB_NAME_EXPECTED on olemas" \
                    "MariaDB andmebaas leiti."
            else
                add_check database database FAIL \
                    "Andmebaas $DB_NAME_EXPECTED peab olemas olema" \
                    "$(printf '%s\n' "$dbs" | paste -sd ', ' -)" \
                    "Loo nõutud andmebaas või kontrolli selle nime."
            fi
        else
            add_check database database FAIL \
                "MariaDB päring SHOW DATABASES peab õnnestuma" \
                "Päring ebaõnnestus" \
                "Kontrolli MariaDB kohalikku administraatori autentimist."
        fi

        # Kasutaja peab olema wpuser@10.0.X.20
        users="$("$DBCLI" -N -B -e \
            "SELECT CONCAT(User,'@',Host) FROM mysql.user WHERE User='$DB_USER_EXPECTED' ORDER BY Host;" \
            2>/dev/null || true)"

        if [[ -n "$users" ]]; then
            add_check db-user db-user PASS \
                "MariaDB kasutaja peab olema $DB_USER_EXPECTED ja lubama ühenduse Debian1 IP-lt" \
                "$users" \
                "Kontrolli, et kasutaja Host väärtus piiraks ühenduse Debian1 aadressiga."
        else
            add_check db-user db-user FAIL \
                "MariaDB kasutaja $DB_USER_EXPECTED peab olemas olema" \
                "Kasutajat ei leitud" \
                "Loo nõutud kasutaja MariaDB-s."
        fi

        # Õigused nõutud andmebaasile
        grants="$("$DBCLI" -N -B -e \
            "SELECT Db, User, Host FROM mysql.db WHERE Db='$DB_NAME_EXPECTED' AND User='$DB_USER_EXPECTED';" \
            2>/dev/null || true)"

        if [[ -n "$grants" ]]; then
            add_check db-grants db-grants PASS \
                "Kasutajal $DB_USER_EXPECTED peab olema õigus andmebaasile $DB_NAME_EXPECTED" \
                "$grants" \
                "Andmebaasipõhine õiguserida leiti. Vajadusel kontrolli täpseid õigusi käsuga SHOW GRANTS."
        else
            add_check db-grants db-grants FAIL \
                "Kasutajal $DB_USER_EXPECTED peab olema õigus andmebaasile $DB_NAME_EXPECTED" \
                "Sobivat õiguserida ei leitud" \
                "Anna kasutajale nõutud andmebaasiõigused ja kontrolli SHOW GRANTS väljundit."
        fi

        # bind-address
        bind="$("$DBCLI" -N -B -e \
            "SHOW VARIABLES LIKE 'bind_address';" 2>/dev/null |
            awk '{print $2}' || true)"

        if [[ -n "$bind" && "$bind" != "127.0.0.1" && "$bind" != "localhost" ]]; then
            add_check db-bind-address db-bind-address PASS \
                "MariaDB peab lubama kaugühendusi, mitte kuulama ainult localhost'il" \
                "$bind" \
                "bind_address ei ole ainult loopback-aadress."
        else
            add_check db-bind-address db-bind-address FAIL \
                "MariaDB peab lubama kaugühendusi" \
                "${bind:-väärtus teadmata}" \
                "Muuda MariaDB bind-address sobivaks ning taaskäivita teenus."
        fi
    fi

    # MariaDB TCP port
    if command -v ss >/dev/null 2>&1; then
        listen3306="$(ss -lnt 2>/dev/null | awk '$4 ~ /:3306$/ {print $4}')"

        if [[ -n "$listen3306" ]]; then
            add_check db-listen db-listen PASS \
                "MariaDB peab kuulama TCP porti 3306" "$listen3306" \
                "TCP port 3306 kuulab."
        else
            add_check db-listen db-listen FAIL \
                "MariaDB peab kuulama TCP porti 3306" \
                "Port 3306 ei kuula" \
                "Kontrolli MariaDB teenust, bind-addressi ja porti."
        fi
    fi

    # BIND9 konfiguratsioon ja tsoonid
    if command -v named-checkconf >/dev/null 2>&1; then
        if named-checkconf -z >/dev/null 2>"$RESPONSE"; then
            add_check bind-config bind-config PASS \
                "BIND9 konfiguratsioon ja tsoonid peavad läbima named-checkconf -z kontrolli" \
                "Kontroll õnnestus" \
                "BIND9 konfiguratsiooni ja laaditavate tsoonide kontroll õnnestus."
        else
            add_check bind-config bind-config FAIL \
                "BIND9 konfiguratsioon ja tsoonid peavad olema korrektsed" \
                "$(cat "$RESPONSE")" \
                "Kontrolli named.conf faile, tsoonifailide nimesid ja süntaksit."
        fi
    else
        add_check bind-config bind-config FAIL \
            "Käsk named-checkconf peab olema olemas" \
            "Käsku ei leitud" \
            "Paigalda BIND9."
    fi

    # Kontrolli, kas tsoonide seadistuses on perekonnanimepõhine domeen.
    # Skript ei eelda fikseeritud domeeni nagu minudomeen.local.
    zones="$(
        grep -RhsE '^[[:space:]]*zone[[:space:]]+"' \
            /etc/bind/named.conf /etc/bind/named.conf.local \
            /etc/bind/named.conf.default-zones 2>/dev/null |
        sed -nE 's/.*zone[[:space:]]+"([^"]+)".*/\1/p' |
        sort -u
    )"

    if [[ -n "$zones" ]]; then
        add_check bind-zones bind-zones PASS \
            "BIND9-s peavad olema ülesandes kasutatava domeeni tsoonid" \
            "$zones" \
            "Leitud tsoonid. Kontrolli, et vajalik edasi- ja pöördotsingu tsoon oleksid olemas ning õigete kirjete sisuga."
    else
        add_check bind-zones bind-zones FAIL \
            "BIND9-s peavad olema ülesande tsoonid" \
            "Tsoone ei leitud" \
            "Kontrolli /etc/bind/named.conf ja /etc/bind/named.conf.local faile."
    fi

    check_command dig dns-dig "DNS kontrollkäsk dig"

fi

# ----------------------------------------------------------
# Raporti saatmine dashboardi
# ----------------------------------------------------------

code="$(
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

if [[ "$code" == "200" || "$code" == "201" ]]; then
    echo
    echo "Tulemused saadeti dashboardi (HTTP $code)."
    cat "$RESPONSE"
    echo
else
    echo
    echo "VIGA: raporti saatmine ebaõnnestus (HTTP ${code:-puudub})." >&2
    cat "$RESPONSE" 2>/dev/null || true
    exit 1
fi
