Jah. Teen nüüd skripti **täpselt sinu labori ülesehituse järgi**:

```text
10.0.X.20  → Apache2 + WordPress
10.0.X.25  → MariaDB + BIND9 DNS
```

Skript tuleb käivitada **`.25` serveris**, sest seal on korraga kontrollitav MariaDB ja BIND9 ning sealt saab kontrollida ka `.20` WordPressi/Apache serverit.

Ta näitab iga kontrolli juures **tegelikku väärtust ja oodatud väärtust**, kui need erinevad.

```bash
nano kontroll-wordpress-dns.sh
```

Pane sisse:

```bash
#!/usr/bin/env bash

# ============================================================
# HKHK – WordPress + MariaDB + BIND9 kontrollskript
#
# SERVER .20 = Apache2 + WordPress
# SERVER .25 = MariaDB + BIND9
#
# Skript käivitatakse SERVER .25 peal
#
# Näide:
#   10.0.15.20 = WordPress
#   10.0.15.25 = MariaDB + DNS
#
# ============================================================

set -u

# ------------------------------------------------------------
# TULEMUSED
# ------------------------------------------------------------

PASS=0
FAIL=0
WARN=0

ok() {
    echo "[OK]   $1"
    PASS=$((PASS+1))
}

fail() {
    echo "[VIGA] $1"
    FAIL=$((FAIL+1))
}

warn() {
    echo "[WARN] $1"
    WARN=$((WARN+1))
}

info() {
    echo "       $1"
}

separator() {
    echo
    echo "------------------------------------------------------------"
}

# ------------------------------------------------------------
# 1. LEIA 10.0.X VÕRK
# ------------------------------------------------------------

LOCAL_IP=$(ip -4 -o addr show |
    awk '$4 ~ /^10\.0\.[0-9]+\./ {print $4; exit}' |
    cut -d/ -f1)

if [[ -z "$LOCAL_IP" ]]; then
    echo "VIGA: 10.0.X.X IP-aadressi ei leitud."
    echo
    ip -4 -br addr
    exit 1
fi

X=$(echo "$LOCAL_IP" | cut -d. -f3)

EXPECTED_WEB="10.0.${X}.20"
EXPECTED_DNS_DB="10.0.${X}.25"

DOMAIN_DNS="minudomeen.local"
DNS_HOST="ns1.${DOMAIN_DNS}"

DOMAIN_WP="kolmasdomeen.perenimi.local"

DOCROOT="/var/www/${DOMAIN_WP}"
WP_CONFIG="${DOCROOT}/wp-config.php"

DB_NAME_EXPECTED="kolmasdomeen_db"
DB_USER_EXPECTED="wpuser"

REVERSE_ZONE="${X}.0.10.in-addr.arpa"

# ------------------------------------------------------------
# ALGINFO
# ------------------------------------------------------------

echo
echo "============================================================"
echo " HKHK – WORDPRESS + MARIADB + BIND9 KONTROLL"
echo "============================================================"
echo
echo "Kohalik IP:"
echo "  $LOCAL_IP"
echo
echo "Laborivõrk:"
echo "  10.0.${X}.0/24"
echo
echo "Oodatav WordPress:"
echo "  $EXPECTED_WEB"
echo
echo "Oodatav MariaDB + DNS:"
echo "  $EXPECTED_DNS_DB"
echo
echo "DNS domeen:"
echo "  $DOMAIN_DNS"
echo
echo "WordPress domeen:"
echo "  $DOMAIN_WP"

# ============================================================
# SERVER .25 KONTROLL
# ============================================================

echo
echo "============================================================"
echo " 1. SERVER .25 – MARIADB + BIND9"
echo "============================================================"

# ------------------------------------------------------------
# IP
# ------------------------------------------------------------

if [[ "$LOCAL_IP" == "$EXPECTED_DNS_DB" ]]; then

    ok "Serveri IP on $EXPECTED_DNS_DB"

else

    fail "Serveri IP ei ole oodatud .25"
    info "Tegelik: $LOCAL_IP"
    info "Oodatud: $EXPECTED_DNS_DB"

fi

# ============================================================
# MARIADB
# ============================================================

separator
echo "MARIADB"

if systemctl is-active --quiet mariadb 2>/dev/null; then

    ok "MariaDB töötab"

else

    fail "MariaDB ei tööta"
    info "Tegelik olek: $(systemctl is-active mariadb 2>/dev/null || echo teadmata)"

fi

# ------------------------------------------------------------
# PORT 3306
# ------------------------------------------------------------

echo
echo "MariaDB kuulamisport:"

MYSQL_LISTEN=$(ss -lntp 2>/dev/null | grep ':3306' || true)

if [[ -n "$MYSQL_LISTEN" ]]; then

    ok "MariaDB kuulab porti 3306"
    echo "$MYSQL_LISTEN" | sed 's/^/       /'

else

    fail "MariaDB ei kuula porti 3306"

fi

# ------------------------------------------------------------
# BIND ADDRESS
# ------------------------------------------------------------

echo
echo "MariaDB bind-address:"

BINDADDR=$(
    grep -RhsE \
    "^[[:space:]]*bind-address[[:space:]]*=" \
    /etc/mysql/mariadb.conf.d \
    /etc/mysql/mysql.conf.d \
    2>/dev/null |
    tail -1 |
    sed -E 's/.*=[[:space:]]*//'
)

echo "       Tegelik: ${BINDADDR:-PUUDUB}"

if [[ "$BINDADDR" == "0.0.0.0" ||
      "$BINDADDR" == "$EXPECTED_DNS_DB" ]]; then

    ok "MariaDB bind-address lubab võrguühendusi"

else

    fail "MariaDB bind-address on vale"
    info "Tegelik: ${BINDADDR:-PUUDUB}"
    info "Oodatud: 0.0.0.0 või $EXPECTED_DNS_DB"

fi

# ============================================================
# ANDMEBAAS
# ============================================================

separator
echo "ANDMEBAAS"

MYSQL_CMD=""

if command -v mariadb >/dev/null 2>&1; then
    MYSQL_CMD="mariadb"
elif command -v mysql >/dev/null 2>&1; then
    MYSQL_CMD="mysql"
fi

if [[ -z "$MYSQL_CMD" ]]; then

    fail "mysql/mariadb käsurea klient puudub"

else

    DB_RESULT=$(
        sudo "$MYSQL_CMD" -N -B \
        -e "SHOW DATABASES LIKE '${DB_NAME_EXPECTED}';" \
        2>/dev/null || true
    )

    if [[ "$DB_RESULT" == "$DB_NAME_EXPECTED" ]]; then

        ok "Andmebaas $DB_NAME_EXPECTED olemas"

    else

        fail "Andmebaasi $DB_NAME_EXPECTED ei ole"
        info "Tegelik päringu tulemus: ${DB_RESULT:-PUUDUB}"

    fi

fi

# ============================================================
# KASUTAJA
# ============================================================

separator
echo "MARIADB KASUTAJA"

if [[ -n "$MYSQL_CMD" ]]; then

    USER_RESULT=$(
        sudo "$MYSQL_CMD" -N -B \
        -e "SELECT CONCAT(User,'@',Host)
            FROM mysql.user
            WHERE User='${DB_USER_EXPECTED}';" \
        2>/dev/null || true
    )

    echo "Kasutaja tegelikud kirjed:"

    if [[ -n "$USER_RESULT" ]]; then
        echo "$USER_RESULT" | sed 's/^/       /'
    else
        echo "       PUUDUB"
    fi

    if echo "$USER_RESULT" |
        grep -Fq "${DB_USER_EXPECTED}@${EXPECTED_WEB}"; then

        ok "${DB_USER_EXPECTED}@${EXPECTED_WEB} olemas"

    else

        fail "${DB_USER_EXPECTED}@${EXPECTED_WEB} puudub"
        info "Oodatud: ${DB_USER_EXPECTED}@${EXPECTED_WEB}"

    fi

fi

# ============================================================
# ÕIGUSED
# ============================================================

separator
echo "MARIADB ÕIGUSED"

if [[ -n "$MYSQL_CMD" ]]; then

    GRANTS=$(
        sudo "$MYSQL_CMD" -N -B \
        -e "SHOW GRANTS FOR '${DB_USER_EXPECTED}'@'${EXPECTED_WEB}';" \
        2>/dev/null || true
    )

    echo "Tegelikud õigused:"

    if [[ -n "$GRANTS" ]]; then
        echo "$GRANTS" | sed 's/^/       /'
    else
        echo "       PUUDUVAD"
    fi

    if echo "$GRANTS" |
        grep -Fq "$DB_NAME_EXPECTED"; then

        ok "$DB_USER_EXPECTED omab $DB_NAME_EXPECTED õigusi"

    else

        fail "$DB_USER_EXPECTED õigusi andmebaasile ei leitud"

    fi

fi

# ============================================================
# BIND9
# ============================================================

separator
echo "BIND9"

BIND_SERVICE=""

if systemctl is-active --quiet bind9 2>/dev/null; then
    BIND_SERVICE="bind9"
elif systemctl is-active --quiet named 2>/dev/null; then
    BIND_SERVICE="named"
fi

if [[ -n "$BIND_SERVICE" ]]; then

    ok "BIND9 töötab"

else

    fail "BIND9 ei tööta"
    info "bind9 olek: $(systemctl is-active bind9 2>/dev/null || echo teadmata)"

fi

# ============================================================
# BIND9 KONFIGURATSIOON
# ============================================================

separator
echo "BIND9 KONFIGURATSIOON"

if [[ -f /etc/bind/named.conf.local ]]; then

    ok "/etc/bind/named.conf.local olemas"

else

    fail "/etc/bind/named.conf.local puudub"

fi

# ------------------------------------------------------------
# FORWARD ZONE
# ------------------------------------------------------------

if grep -Eq \
    "zone[[:space:]]+\"${DOMAIN_DNS}\"" \
    /etc/bind/named.conf.local 2>/dev/null; then

    ok "Forward zone $DOMAIN_DNS defineeritud"

else

    fail "Forward zone $DOMAIN_DNS puudub"

fi

# ------------------------------------------------------------
# REVERSE ZONE
# ------------------------------------------------------------

if grep -Eq \
    "zone[[:space:]]+\"${REVERSE_ZONE}\"" \
    /etc/bind/named.conf.local 2>/dev/null; then

    ok "Reverse zone $REVERSE_ZONE defineeritud"

else

    fail "Reverse zone puudub"
    info "Oodatud: $REVERSE_ZONE"

fi

# ============================================================
# NAMED-CHECKCONF
# ============================================================

separator
echo "BIND9 SÜNTAKS"

if command -v named-checkconf >/dev/null 2>&1; then

    CONF_RESULT=$(named-checkconf 2>&1 || true)

    if [[ -z "$CONF_RESULT" ]]; then

        ok "named-checkconf korras"

    else

        fail "named-checkconf annab vea"
        echo "$CONF_RESULT" | sed 's/^/       /'

    fi

fi

# ============================================================
# TSOONIFAILIDE LEIDMINE
# ============================================================

separator
echo "BIND9 TSOONIFAILID"

FORWARD_FILE=$(
    awk -v zone="$DOMAIN_DNS" '
        $1 == "zone" && $2 == "\"" zone "\"" {inside=1}
        inside && $1 == "file" {
            gsub(/[";]/,"",$2)
            print $2
            exit
        }
        inside && /^}/ {inside=0}
    ' /etc/bind/named.conf.local 2>/dev/null
)

REVERSE_FILE=$(
    awk -v zone="$REVERSE_ZONE" '
        $1 == "zone" && $2 == "\"" zone "\"" {inside=1}
        inside && $1 == "file" {
            gsub(/[";]/,"",$2)
            print $2
            exit
        }
        inside && /^}/ {inside=0}
    ' /etc/bind/named.conf.local 2>/dev/null
)

echo "Forward zone fail:"
echo "       ${FORWARD_FILE:-PUUDUB}"

echo "Reverse zone fail:"
echo "       ${REVERSE_FILE:-PUUDUB}"

# ============================================================
# FORWARD ZONE CHECK
# ============================================================

if [[ -n "$FORWARD_FILE" &&
      -f "$FORWARD_FILE" ]]; then

    FORWARD_RESULT=$(
        named-checkzone \
        "$DOMAIN_DNS" \
        "$FORWARD_FILE" \
        2>&1
    )

    echo
    echo "Forward zone kontroll:"
    echo "$FORWARD_RESULT" | sed 's/^/       /'

    if echo "$FORWARD_RESULT" | grep -q "loaded serial"; then

        ok "Forward zone on korrektne"

    else

        fail "Forward zone kontroll ebaõnnestus"

    fi

else

    fail "Forward zone faili ei leitud"

fi

# ============================================================
# REVERSE ZONE CHECK
# ============================================================

if [[ -n "$REVERSE_FILE" &&
      -f "$REVERSE_FILE" ]]; then

    REVERSE_RESULT=$(
        named-checkzone \
        "$REVERSE_ZONE" \
        "$REVERSE_FILE" \
        2>&1
    )

    echo
    echo "Reverse zone kontroll:"
    echo "$REVERSE_RESULT" | sed 's/^/       /'

    if echo "$REVERSE_RESULT" | grep -q "loaded serial"; then

        ok "Reverse zone on korrektne"

    else

        fail "Reverse zone kontroll ebaõnnestus"

    fi

else

    fail "Reverse zone faili ei leitud"

fi

# ============================================================
# DNS A-KIRJED
# ============================================================

separator
echo "DNS A-KIRJED"

if command -v dig >/dev/null 2>&1; then

    DNS_A=$(
        dig +short @127.0.0.1 "$DOMAIN_DNS" A |
        head -1
    )

    NS_A=$(
        dig +short @127.0.0.1 "$DNS_HOST" A |
        head -1
    )

    WWW_A=$(
        dig +short @127.0.0.1 "www.${DOMAIN_DNS}" A |
        head -1
    )

    WP_A=$(
        dig +short @127.0.0.1 "$DOMAIN_WP" A |
        head -1
    )

    echo
    echo "Tegelikud DNS-vastused:"
    echo "       $DOMAIN_DNS                 -> ${DNS_A:-PUUDUB}"
    echo "       $DNS_HOST                   -> ${NS_A:-PUUDUB}"
    echo "       www.$DOMAIN_DNS             -> ${WWW_A:-PUUDUB}"
    echo "       $DOMAIN_WP                  -> ${WP_A:-PUUDUB}"

    # minudomeen.local -> .25

    if [[ "$DNS_A" == "$EXPECTED_DNS_DB" ]]; then

        ok "$DOMAIN_DNS -> $EXPECTED_DNS_DB"

    else

        fail "$DOMAIN_DNS A-kirje vale"
        info "Tegelik: ${DNS_A:-PUUDUB}"
        info "Oodatud: $EXPECTED_DNS_DB"

    fi

    # ns1 -> .25

    if [[ "$NS_A" == "$EXPECTED_DNS_DB" ]]; then

        ok "$DNS_HOST -> $EXPECTED_DNS_DB"

    else

        fail "$DNS_HOST A-kirje vale"
        info "Tegelik: ${NS_A:-PUUDUB}"
        info "Oodatud: $EXPECTED_DNS_DB"

    fi

    # www -> .20

    if [[ "$WWW_A" == "$EXPECTED_WEB" ]]; then

        ok "www.$DOMAIN_DNS -> $EXPECTED_WEB"

    else

        fail "www.$DOMAIN_DNS A-kirje vale"
        info "Tegelik: ${WWW_A:-PUUDUB}"
        info "Oodatud: $EXPECTED_WEB"

    fi

    # WordPress domeen -> .20

    if [[ "$WP_A" == "$EXPECTED_WEB" ]]; then

        ok "$DOMAIN_WP -> $EXPECTED_WEB"

    else

        warn "$DOMAIN_WP DNS-kirje puudub või on vale"
        info "Tegelik: ${WP_A:-PUUDUB}"
        info "Oodatud: $EXPECTED_WEB"

    fi

fi

# ============================================================
# REVERSE DNS
# ============================================================

separator
echo "REVERSE DNS"

if command -v dig >/dev/null 2>&1; then

    PTR25=$(
        dig +short @127.0.0.1 \
        -x "$EXPECTED_DNS_DB" |
        sed 's/\.$//' |
        head -1
    )

    PTR20=$(
        dig +short @127.0.0.1 \
        -x "$EXPECTED_WEB" |
        sed 's/\.$//' |
        head -1
    )

    echo "Tegelik PTR:"
    echo "       $EXPECTED_DNS_DB -> ${PTR25:-PUUDUB}"
    echo "       $EXPECTED_WEB    -> ${PTR20:-PUUDUB}"

    if [[ "$PTR25" == "$DNS_HOST" ]]; then

        ok "$EXPECTED_DNS_DB -> $DNS_HOST"

    else

        fail "Reverse DNS .25 jaoks vale"
        info "Tegelik: ${PTR25:-PUUDUB}"
        info "Oodatud: $DNS_HOST"

    fi

    if [[ "$PTR20" == "$DOMAIN_WP" ||
          "$PTR20" == "www.${DOMAIN_DNS}" ]]; then

        ok "$EXPECTED_WEB reverse DNS korras"

    else

        warn "Reverse DNS .20 jaoks puudub või erineb ülesandest"
        info "Tegelik: ${PTR20:-PUUDUB}"
        info "Oodatud näiteks: $DOMAIN_WP"

    fi

fi

# ============================================================
# SERVER .20 VÕRGUÜHENDUS
# ============================================================

echo
echo "============================================================"
echo " 2. SERVER .20 – APACHE + WORDPRESS"
echo "============================================================"

# ------------------------------------------------------------
# PING
# ------------------------------------------------------------

if ping -c 2 -W 2 "$EXPECTED_WEB" >/dev/null 2>&1; then

    ok "Server .20 vastab pingile"

else

    fail "Server .20 ei vasta pingile"
    info "Testitud: $EXPECTED_WEB"

fi

# ------------------------------------------------------------
# HTTP PORT 80
# ------------------------------------------------------------

if command -v nc >/dev/null 2>&1; then

    if nc -z -w 3 "$EXPECTED_WEB" 80 >/dev/null 2>&1; then

        ok "$EXPECTED_WEB:80 on kättesaadav"

    else

        fail "$EXPECTED_WEB:80 ei ole kättesaadav"

    fi

fi

# ------------------------------------------------------------
# HTTP
# ------------------------------------------------------------

if command -v curl >/dev/null 2>&1; then

    HTTP_RESULT=$(
        curl -s \
        -o /dev/null \
        -w '%{http_code}' \
        --max-time 5 \
        -H "Host: $DOMAIN_WP" \
        "http://${EXPECTED_WEB}/" \
        2>/dev/null
    )

    echo
    echo "WordPress HTTP staatus:"
    echo "       Tegelik: $HTTP_RESULT"

    if [[ "$HTTP_RESULT" == "200" ||
          "$HTTP_RESULT" == "301" ||
          "$HTTP_RESULT" == "302" ||
          "$HTTP_RESULT" == "303" ]]; then

        ok "WordPress HTTP vastab"

    else

        fail "WordPress HTTP ei vasta korrektselt"
        info "Oodatud HTTP staatus: 200/301/302/303"

    fi

fi

# ============================================================
# WORDPRESS DNS + HTTP
# ============================================================

separator
echo "WORDPRESS DOMEEN"

if command -v dig >/dev/null 2>&1; then

    WP_DNS=$(
        dig +short @127.0.0.1 "$DOMAIN_WP" A |
        head -1
    )

    echo "DNS:"
    echo "       $DOMAIN_WP -> ${WP_DNS:-PUUDUB}"

    if [[ "$WP_DNS" == "$EXPECTED_WEB" ]]; then

        ok "WordPress domeen lahendub .20 peale"

    else

        fail "WordPress domeeni DNS on vale"
        info "Tegelik: ${WP_DNS:-PUUDUB}"
        info "Oodatud: $EXPECTED_WEB"

    fi

fi

# ============================================================
# LÕPPSUMMARY
# ============================================================

echo
echo "============================================================"
echo " KOKKUVÕTE"
echo "============================================================"
echo
echo "OK    : $PASS"
echo "VIGA  : $FAIL"
echo "WARN  : $WARN"
echo

if [[ "$FAIL" -eq 0 ]]; then

    echo "TULEMUS: KÕIK KOHUSTUSLIKUD KONTROLLID LÄBITUD"

    if [[ "$WARN" -gt 0 ]]; then
        echo "Märkus: leidus $WARN hoiatust."
    fi

    exit 0

else

    echo "TULEMUS: TÖÖS ON VIGU"
    echo
    echo "Vaata ülalolevaid [VIGA] ridu."
    echo "Iga vea juures on toodud tegelik ja oodatud väärtus."

    exit 2

fi
```

### Käivitamine

`.25` serveris:

```bash
chmod +x kontroll-wordpress-dns.sh
sudo ./kontroll-wordpress-dns.sh
```

Kui näiteks õpilase võrk on `10.0.17.0/24`, tuvastab skript ise:

```text
Kohalik IP:
  10.0.17.25

Oodatav WordPress:
  10.0.17.20

Oodatav MariaDB + DNS:
  10.0.17.25
```

ja kontrollib automaatselt:

```text
10.0.17.20
 ├── kas masin vastab
 ├── kas port 80 töötab
 ├── kas WordPress vastab
 └── kas kolmasdomeen.perenimi.local jõuab .20 peale

10.0.17.25
 ├── MariaDB töötab
 ├── MariaDB :3306
 ├── bind-address
 ├── kolmasdomeen_db
 ├── wpuser@10.0.17.20
 ├── wpuser õigused
 ├── BIND9 töötab
 ├── named.conf.local
 ├── forward zone
 ├── reverse zone
 ├── A-kirjed
 └── PTR-kirjed
```

**Üks asi, mida ma soovitan sinu ülesande juures veel parandada:** DNS-i algses juhendis on `minudomeen.local` näide, aga WordPressi ülesandes on `kolmasdomeen.perenimi.local`. Kui need on mõeldud ühe ja sama õpilase töö osaks, tasub teha DNS-i ülesanne nii, et BIND9 sisaldaks ka **`kolmasdomeen.perenimi.local` tsooni või vastavat A-kirjet**, muidu ei ole WordPressi domeeninimi ja DNS-i ülesanne omavahel täielikult seotud.
