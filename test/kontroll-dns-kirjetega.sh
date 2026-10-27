
#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================================
# HKHK – Debian labori kontroll
# Debian1: Apache2, PHP, WordPress, DB konfiguratsioon/ühendus
# Debian2: MariaDB, kasutaja/õigused, BIND9, DNS A- ja PTR-kirjed
# ==========================================================

DASHBOARD_URL="${DASHBOARD_URL:-http://192.168.124.64:5050}"
TOKEN_FILE="${TOKEN_FILE:-/etc/hkhk-dashboard-client.env}"
MACHINE="${1:-}"

DB_NAME_EXPECTED="kolmasdomeen_db"
DB_USER_EXPECTED="wpuser"

[[ $EUID -eq 0 ]] || { echo "Käivita sudo abil."; exit 1; }
[[ "$MACHINE" == "Debian1" || "$MACHINE" == "Debian2" ]] || {
    echo "Kasutamine: sudo $0 Debian1|Debian2"; exit 1;
}
command -v python3 >/dev/null || { echo "Paigalda python3."; exit 1; }
command -v curl >/dev/null || { echo "Paigalda curl."; exit 1; }
[[ -r "$TOKEN_FILE" ]] || { echo "Tokenifaili ei saa lugeda: $TOKEN_FILE"; exit 1; }

# shellcheck disable=SC1090
source "$TOKEN_FILE"
[[ -n "${UPLOAD_TOKEN:-}" ]] || { echo "UPLOAD_TOKEN puudub."; exit 1; }

read -r -p "Õpilase ees- ja perekonnanimi: " STUDENT_NAME
[[ -n "${STUDENT_NAME// /}" ]] || { echo "Nimi on kohustuslik."; exit 1; }

TMP="$(mktemp)"
RESPONSE="$(mktemp)"
trap 'rm -f "$TMP" "$RESPONSE"' EXIT

# Leia laborivõrgu X ning serverite IP-aadressid.
# Lubab ka keskkonnamuutujatega väärtusi käsitsi määrata.
X="${LAB_X:-}"
LOCAL_IP=""

for ip in $(hostname -I 2>/dev/null); do
    if [[ "$ip" =~ ^10\.0\.([0-9]+)\.(20|25)$ ]]; then
        X="${X:-${BASH_REMATCH[1]}}"
        LOCAL_IP="$ip"
        break
    fi
done

DEBIAN1_IP="${DEBIAN1_IP:-}"
DEBIAN2_IP="${DEBIAN2_IP:-}"

if [[ -n "$X" ]]; then
    DEBIAN1_IP="${DEBIAN1_IP:-10.0.${X}.20}"
    DEBIAN2_IP="${DEBIAN2_IP:-10.0.${X}.25}"
fi

export STUDENT_NAME MACHINE TMP

python3 - <<'PY'
import os, json, socket, subprocess, ipaddress

ips = []
try:
    output = subprocess.check_output(
        ["hostname", "-I"], text=True, stderr=subprocess.DEVNULL
    )
    for value in output.split():
        try:
            ip = ipaddress.ip_address(value)
            if ip.version == 4 and not ip.is_loopback:
                ips.append(str(ip))
        except ValueError:
            pass
except (OSError, subprocess.SubprocessError):
    pass

report = {
    "student_name": os.environ["STUDENT_NAME"].strip(),
    "machine": os.environ["MACHINE"],
    "hostname": socket.gethostname(),
    "ip_address": ips[0] if ips else "",
    "script_version": "4.1",
    "checks": []
}
with open(os.environ["TMP"], "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False)
PY

add_check() {
    python3 - "$TMP" "$1" "$2" "$3" "$4" "$5" "${6:-}" <<'PY'
import json, sys
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

service_check() {
    local svc="$1" id="$2" actual
    actual="$(systemctl is-active "$svc" 2>/dev/null || true)"
    if [[ "$actual" == "active" ]]; then
        add_check "$id" "$svc teenus" PASS \
            "Teenus peab töötama (active)" "$actual" \
            "systemctl kontroll näitas, et teenus töötab."
    else
        add_check "$id" "$svc teenus" FAIL \
            "Teenus peab töötama (active)" "${actual:-teadmata}" \
            "Kontrolli: systemctl status $svc"
    fi
}

check_command() {
    local cmd="$1" id="$2" title="$3"
    if command -v "$cmd" >/dev/null 2>&1; then
        add_check "$id" "$title" PASS \
            "Käsk $cmd peab olema paigaldatud" \
            "$(command -v "$cmd")" "Käsk on olemas."
    else
        add_check "$id" "$title" FAIL \
            "Käsk $cmd peab olema paigaldatud" \
            "Käsku ei leitud" "Paigalda vajalik pakett."
    fi
}

get_constant() {
    python3 - "$1" "$2" <<'PY'
import re, sys
path, key = sys.argv[1:3]
try:
    with open(path, encoding="utf-8", errors="replace") as f:
        content = f.read()
except OSError:
    print("")
    raise SystemExit
pattern = r"""define\s*\(\s*(['"])""" + re.escape(key) + r"""\1\s*,\s*(['"])(.*?)\2\s*\)"""
m = re.search(pattern, content, re.S)
print(m.group(3).strip() if m else "")
PY
}

# ==========================================================
# DEBIAN1 – Apache2 ja WordPress
# ==========================================================

if [[ "$MACHINE" == "Debian1" ]]; then

    service_check apache2 apache2
    check_command apache2ctl apache-config-command "Apache kontrollkäsk"

    if command -v apache2ctl >/dev/null 2>&1; then
        output="$(apache2ctl configtest 2>&1 || true)"
        if grep -q "Syntax OK" <<< "$output"; then
            add_check virtualhost apache-config PASS \
                "Apache konfiguratsioon peab olema korrektne (Syntax OK)" \
                "$output" "Apache konfiguratsiooni süntaks on korrektne."
        else
            add_check virtualhost apache-config FAIL \
                "Apache konfiguratsioon peab andma tulemuse Syntax OK" \
                "$output" "Kontrolli VirtualHosti ja Apache konfiguratsiooni."
        fi
    fi

    if command -v php >/dev/null 2>&1; then
        version="$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)"
        add_check php php-cli PASS "PHP peab olema paigaldatud" \
            "${version:-versioon teadmata}" "PHP CLI on olemas."

        if php -m 2>/dev/null | grep -qi '^mysqli$'; then
            add_check php-mysqli php-mysqli PASS \
                "PHP mysqli laiendus peab olema laaditud" "mysqli olemas" \
                "WordPress kasutab mysqli laiendust andmebaasiühenduseks."
        else
            add_check php-mysqli php-mysqli FAIL \
                "PHP mysqli laiendus peab olema laaditud" "mysqli puudub" \
                "Paigalda PHP mysqli laiendus."
        fi
    else
        add_check php php-cli FAIL "PHP peab olema paigaldatud" \
            "PHP puudub" "Paigalda PHP."
    fi

    # Leia WordPressi konfiguratsioonifailid
    declare -a CONFIGS=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && CONFIGS+=("$file")
    done < <(
        find /var/www -maxdepth 6 -type f -name wp-config.php \
            -print 2>/dev/null | sort -u
    )

    if ((${#CONFIGS[@]} == 0)); then
        add_check wordpress-files wordpress-files FAIL \
            "WordPressi kataloogis peab olema wp-config.php" \
            "wp-config.php ei leitud" \
            "Kontrolli WordPressi asukohta ja Apache DocumentRooti."
    else
        add_check wordpress-files wordpress-files PASS \
            "WordPressi wp-config.php peab olema olemas" \
            "$(printf '%s\n' "${CONFIGS[@]}")" \
            "Leitud failide DB_* väärtusi kontrollitakse eraldi."
    fi

    for cfg in "${CONFIGS[@]}"; do
        domain="$(basename "$(dirname "$cfg")")"
        name="$(get_constant "$cfg" DB_NAME)"
        user="$(get_constant "$cfg" DB_USER)"
        host="$(get_constant "$cfg" DB_HOST)"
        pass="$(get_constant "$cfg" DB_PASSWORD)"

        if [[ "$name" == "$DB_NAME_EXPECTED" ]]; then
            add_check "wp-db-name-$domain" "WordPress DB_NAME ($domain)" PASS \
                "DB_NAME peab olema $DB_NAME_EXPECTED" "$name" \
                "Andmebaasi nimi vastab ülesande nõudele."
        else
            add_check "wp-db-name-$domain" "WordPress DB_NAME ($domain)" FAIL \
                "DB_NAME peab olema $DB_NAME_EXPECTED" "${name:-väärtus puudub}" \
                "Paranda wp-config.php faili DB_NAME väärtus."
        fi

        if [[ "$user" == "$DB_USER_EXPECTED" ]]; then
            add_check "wp-db-user-$domain" "WordPress DB_USER ($domain)" PASS \
                "DB_USER peab olema $DB_USER_EXPECTED" "$user" \
                "Kasutajanimi vastab ülesande nõudele."
        else
            add_check "wp-db-user-$domain" "WordPress DB_USER ($domain)" FAIL \
                "DB_USER peab olema $DB_USER_EXPECTED" "${user:-väärtus puudub}" \
                "Paranda wp-config.php faili DB_USER väärtus."
        fi

        host_clean="${host%%:*}"
        host_clean="${host_clean#[}"
        host_clean="${host_clean%]}"

        if [[ -n "$host_clean" && "$host_clean" != "localhost" &&
              "$host_clean" != "127.0.0.1" ]]; then
            add_check "wp-db-host-$domain" "WordPress DB_HOST ($domain)" PASS \
                "DB_HOST peab viitama Debian2 kaugserverile, mitte localhost'ile" \
                "$host" "Kontrolli, et host on Debian2 IP või sellele vastav DNS-nimi."
        else
            add_check "wp-db-host-$domain" "WordPress DB_HOST ($domain)" FAIL \
                "DB_HOST peab viitama Debian2 kaugserverile" \
                "${host:-väärtus puudub}" \
                "WordPress ja MariaDB asuvad eri serverites; localhost ei sobi."
        fi

        if [[ -n "$name" && -n "$user" && -n "$host" && -n "$pass" ]] &&
           command -v php >/dev/null 2>&1 &&
           php -m 2>/dev/null | grep -qi '^mysqli$'; then

            if DBN="$name" DBU="$user" DBH="$host" DBP="$pass" php -r '
                $h=getenv("DBH"); $p=3306;
                if (preg_match("/^(.+):([0-9]+)$/", $h, $m)) {
                    $h=trim($m[1], "[]"); $p=(int)$m[2];
                }
                $c=@new mysqli($h,getenv("DBU"),getenv("DBP"),getenv("DBN"),$p);
                if ($c->connect_errno) {
                    fwrite(STDERR,$c->connect_error);
                    exit(1);
                }
                $c->close();
            ' 2>"$RESPONSE"; then
                add_check "wp-db-connect-$domain" "WordPressi DB-ühendus ($domain)" PASS \
                    "Ühendus peab õnnestuma: $DB_NAME_EXPECTED kasutajana $DB_USER_EXPECTED" \
                    "Ühendus õnnestus; DB_NAME=$name; DB_USER=$user; DB_HOST=$host" \
                    "PHP mysqli ühendus õnnestus."
            else
                add_check "wp-db-connect-$domain" "WordPressi DB-ühendus ($domain)" FAIL \
                    "Ühendus peab õnnestuma: $DB_NAME_EXPECTED kasutajana $DB_USER_EXPECTED" \
                    "Ühendus ebaõnnestus; DB_NAME=$name; DB_USER=$user; DB_HOST=$host" \
                    "$(cat "$RESPONSE" 2>/dev/null || echo 'Kontrolli parooli, õigusi ja võrku.')"
            fi
        else
            add_check "wp-db-connect-$domain" "WordPressi DB-ühendus ($domain)" WARN \
                "DB_NAME, DB_USER, DB_HOST, DB_PASSWORD ja PHP mysqli peavad olema määratud" \
                "Ühendust ei testitud" \
                "Puudub vajalik väärtus või PHP mysqli laiendus."
        fi
    done

    if command -v ss >/dev/null 2>&1; then
        listen="$(ss -lnt 2>/dev/null | awk '$4 ~ /:80$/ {print $4}')"
        if [[ -n "$listen" ]]; then
            add_check apache-port80 apache-port80 PASS \
                "Apache peab kuulama TCP porti 80" "$listen" "Port 80 kuulab."
        else
            add_check apache-port80 apache-port80 FAIL \
                "Apache peab kuulama TCP porti 80" "Port 80 ei kuula" \
                "Kontrolli Apache teenust ja portide konfiguratsiooni."
        fi
    fi

# ==========================================================
# DEBIAN2 – MariaDB, BIND9 ja DNS-kirjed
# ==========================================================

else
    service_check mariadb mariadb
    service_check bind9 bind9

    DBCLI="$(command -v mariadb || command -v mysql || true)"

    if [[ -z "$DBCLI" ]]; then
        add_check database-client database-client FAIL \
            "MariaDB klient peab olema paigaldatud" "Klienti ei leitud" \
            "Paigalda MariaDB klient."
    else
        dbs="$("$DBCLI" -N -B -e 'SHOW DATABASES;' 2>/dev/null || true)"
        if grep -Fxq "$DB_NAME_EXPECTED" <<< "$dbs"; then
            add_check database database PASS \
                "Andmebaas $DB_NAME_EXPECTED peab olemas olema" \
                "$DB_NAME_EXPECTED on olemas" "Nõutud andmebaas leiti."
        else
            add_check database database FAIL \
                "Andmebaas $DB_NAME_EXPECTED peab olemas olema" \
                "$(printf '%s\n' "$dbs" | paste -sd ', ' -)" \
                "Loo nõutud andmebaas või kontrolli nime."
        fi

        users="$("$DBCLI" -N -B -e \
            "SELECT CONCAT(User,'@',Host) FROM mysql.user WHERE User='$DB_USER_EXPECTED' ORDER BY Host;" \
            2>/dev/null || true)"

        if [[ -n "$users" ]]; then
            add_check db-user db-user PASS \
                "MariaDB kasutaja $DB_USER_EXPECTED peab olemas olema" \
                "$users" \
                "Kontrolli, et Host lubab ühenduse Debian1 IP-lt."
        else
            add_check db-user db-user FAIL \
                "MariaDB kasutaja $DB_USER_EXPECTED peab olemas olema" \
                "Kasutajat ei leitud" "Loo nõutud MariaDB kasutaja."
        fi

        grants="$("$DBCLI" -N -B -e \
            "SELECT Db,User,Host FROM mysql.db WHERE Db='$DB_NAME_EXPECTED' AND User='$DB_USER_EXPECTED';" \
            2>/dev/null || true)"

        if [[ -n "$grants" ]]; then
            add_check db-grants db-grants PASS \
                "Kasutajal $DB_USER_EXPECTED peab olema andmebaasile $DB_NAME_EXPECTED õiguserida" \
                "$grants" \
                "Õiguserida leiti; täpseid õigusi saab kontrollida käsuga SHOW GRANTS."
        else
            add_check db-grants db-grants FAIL \
                "Kasutajal $DB_USER_EXPECTED peab olema andmebaasile $DB_NAME_EXPECTED õiguserida" \
                "Sobivat õiguserida ei leitud" \
                "Anna kasutajale ülesandes nõutud õigused."
        fi

        bind="$("$DBCLI" -N -B -e \
            "SHOW VARIABLES LIKE 'bind_address';" 2>/dev/null | awk '{print $2}' || true)"

        if [[ -n "$bind" && "$bind" != "127.0.0.1" && "$bind" != "localhost" ]]; then
            add_check db-bind-address db-bind-address PASS \
                "MariaDB peab lubama kaugühendusi" "$bind" \
                "MariaDB ei kuula ainult loopback-aadressil."
        else
            add_check db-bind-address db-bind-address FAIL \
                "MariaDB peab lubama kaugühendusi" "${bind:-teadmata}" \
                "Paranda bind-address ja taaskäivita MariaDB."
        fi
    fi

    if command -v ss >/dev/null 2>&1; then
        listen="$(ss -lnt 2>/dev/null | awk '$4 ~ /:3306$/ {print $4}')"
        if [[ -n "$listen" ]]; then
            add_check db-listen db-listen PASS \
                "MariaDB peab kuulama TCP porti 3306" "$listen" "Port 3306 kuulab."
        else
            add_check db-listen db-listen FAIL \
                "MariaDB peab kuulama TCP porti 3306" "Port 3306 ei kuula" \
                "Kontrolli MariaDB teenust, porti ja bind-addressi."
        fi
    fi

    # BIND9 konfiguratsioon
    if command -v named-checkconf >/dev/null 2>&1; then
        if named-checkconf -z >"$RESPONSE" 2>&1; then
            add_check bind-config bind-config PASS \
                "BIND9 konfiguratsioon ja tsoonid peavad olema korrektsed" \
                "named-checkconf -z õnnestus" "Konfiguratsioon läbis kontrolli."
        else
            add_check bind-config bind-config FAIL \
                "BIND9 konfiguratsioon ja tsoonid peavad olema korrektsed" \
                "$(cat "$RESPONSE")" \
                "Kontrolli named.conf faile ja tsoonifaile."
        fi
    else
        add_check bind-config bind-config FAIL \
            "Käsk named-checkconf peab olemas olema" "Käsku ei leitud" \
            "Paigalda BIND9 tööriistad."
    fi

    # Leia tegelik .local edasisuunamise tsoon konfiguratsioonist.
    # Välista reverse-tsoonid ning BIND-i standardsed localhost-tsoonid.
    DOMAIN_DNS="${DOMAIN_DNS:-}"
    if [[ -z "$DOMAIN_DNS" ]]; then
        DOMAIN_DNS="$(
            grep -RhsE '^[[:space:]]*zone[[:space:]]+"' /etc/bind \
                --include='*.conf' 2>/dev/null |
            sed -nE 's/.*zone[[:space:]]+"([^"]+)".*/\1/p' |
            grep -E '\.local\.?$' |
            grep -Ev '(^|\.)(in-addr\.arpa|ip6\.arpa)\.?$|^(localhost|0\.0\.127\.in-addr\.arpa)\.?$' |
            head -n1 || true
        )"
    fi
    DOMAIN_DNS="${DOMAIN_DNS%.}"

    if [[ -z "$DOMAIN_DNS" ]]; then
        add_check bind-domain bind-domain FAIL \
            "BIND9-s peab olema labori edasisuunamise tsoon, näiteks perekonnanimi.local" \
            "Tsooni ei õnnestunud automaatselt tuvastada" \
            "Kontrolli /etc/bind/named.conf.local. Vajadusel määra DOMAIN_DNS keskkonnamuutujana."
    else
        DOMAIN_WP="kolmasdomeen.${DOMAIN_DNS}"
        DNS_SERVER="127.0.0.1"

        add_check bind-domain bind-domain PASS \
            "DNS-i domeen peab olema õpilase labori domeen, mitte näidisnimi" \
            "$DOMAIN_DNS; WordPressi domeen $DOMAIN_WP" \
            "Domeen tuvastati BIND9 tsooni konfiguratsioonist."

        # A-kirje kontroll: päring otse Debian2 kohalikule DNS-ile.
        check_a_record() {
            local id="$1" fqdn="$2" expected_ip="$3" title="$4"
            local actual
            actual="$(dig @"$DNS_SERVER" +time=2 +tries=1 +short A "$fqdn" 2>/dev/null |
                paste -sd ', ' - || true)"
            if [[ -n "$expected_ip" && "$actual" == "$expected_ip" ]]; then
                add_check "$id" "$title" PASS \
                    "$fqdn A peab olema $expected_ip" "$actual" \
                    "DNS A-kirje vastab oodatud IP-aadressile."
            else
                add_check "$id" "$title" FAIL \
                    "$fqdn A peab olema ${expected_ip:-oodatud serveri IP}" \
                    "${actual:-DNS-vastus puudub}" \
                    "Kontrolli tsoonifaili A-kirjet ja BIND9 laaditud tsooni."
            fi
        }

        if command -v dig >/dev/null 2>&1; then
            check_a_record dns-apex "$DOMAIN_DNS" "$DEBIAN2_IP" \
                "DNS A-kirje: domeeni põhinimi"
            check_a_record dns-ns1 "ns1.$DOMAIN_DNS" "$DEBIAN2_IP" \
                "DNS A-kirje: nimeserver ns1"
            check_a_record dns-www "www.$DOMAIN_DNS" "$DEBIAN1_IP" \
                "DNS A-kirje: www veebiserver"
            check_a_record dns-wordpress "$DOMAIN_WP" "$DEBIAN1_IP" \
                "DNS A-kirje: WordPressi domeen"

            # PTR kontroll: mõlemad serverid.
            check_ptr_record() {
                local id="$1" ip="$2" expected="$3" title="$4"
                local actual normalized expected_normalized
                if [[ -z "$ip" ]]; then
                    add_check "$id" "$title" WARN \
                        "PTR peab viitama $expected" \
                        "IP-aadressi ei tuvastatud" \
                        "Määra DEBIAN1_IP ja DEBIAN2_IP või kasuta 10.0.X.20/.25 aadresse."
                    return
                fi

                actual="$(dig @"$DNS_SERVER" +time=2 +tries=1 +short -x "$ip" 2>/dev/null |
                    sed 's/\.$//' | paste -sd ', ' - || true)"
                normalized="$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')"
                expected_normalized="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"

                if [[ "$normalized" == "$expected_normalized" ]]; then
                    add_check "$id" "$title" PASS \
                        "IP $ip PTR peab olema $expected" "${actual:-PTR puudub}" \
                        "Pöördotsingu vastus vastab nõudele."
                else
                    add_check "$id" "$title" FAIL \
                        "IP $ip PTR peab olema $expected" "${actual:-PTR-vastus puudub}" \
                        "Kontrolli pöördotsingu tsooni, PTR-kirjet ja tsooni laadimist."
                fi
            }

            check_ptr_record dns-ptr-debian2 "$DEBIAN2_IP" \
                "ns1.$DOMAIN_DNS" "DNS PTR: Debian2 nimeserver"

            # Debian1 PTR lubab ülesandes kasutatud veebinime:
            # kolmasdomeen.<domeen> või www.<domeen>.
            ptr1="$(dig @"$DNS_SERVER" +time=2 +tries=1 +short -x "$DEBIAN1_IP" 2>/dev/null |
                sed 's/\.$//' | tr '[:upper:]' '[:lower:]' || true)"
            if [[ "$ptr1" == "$(printf '%s' "$DOMAIN_WP" | tr '[:upper:]' '[:lower:]')" ||
                  "$ptr1" == "$(printf '%s' "www.$DOMAIN_DNS" | tr '[:upper:]' '[:lower:]')" ]]; then
                add_check dns-ptr-debian1 dns-ptr-debian1 PASS \
                    "IP $DEBIAN1_IP PTR peab olema $DOMAIN_WP või www.$DOMAIN_DNS" \
                    "$ptr1" "Debian1 pöördotsingu kirje vastab lubatud veebinimele."
            else
                add_check dns-ptr-debian1 dns-ptr-debian1 FAIL \
                    "IP $DEBIAN1_IP PTR peab olema $DOMAIN_WP või www.$DOMAIN_DNS" \
                    "${ptr1:-PTR-vastus puudub}" \
                    "Paranda Debian1 IP-aadressi PTR-kirje pöördotsingu tsoonis."
            fi
        else
            add_check dns-dig dns-dig FAIL \
                "Käsk dig peab olema paigaldatud" "Käsku ei leitud" \
                "Paigalda BIND9 DNS-i päringutööriistad."
        fi
    fi
fi

# ==========================================================
# Saada raport dashboardi
# ==========================================================

code="$(
    curl -sS -o "$RESPONSE" -w '%{http_code}' \
        --connect-timeout 5 --max-time 30 \
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
    echo "VIGA: raporti saatmine ebaõnnestus (HTTP ${code:-puudub})." >&2
    cat "$RESPONSE" 2>/dev/null || true
    exit 1
fi
