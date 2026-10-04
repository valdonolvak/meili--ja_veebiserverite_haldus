Jah. Siin on mõistlik skript juba natuke põhjalikumalt ümber teha, sest praegune versioon kontrollib `.25` pealt küll DNS-i ja MariaDB-d, kuid **ei saa ainult võrguühenduse põhjal kindlaks teha, kas `.20` WordPressi `wp-config.php` kasutab päriselt `.25` MariaDB-d**.

Allolev versioon teeb seda järgmiselt:

* domeen antakse skriptile käsurealt;
* `perenimi.local` ja `minudomeen.local` ei ole enam kuskil kõvakodeeritud;
* `.20` kontrollitakse SSH kaudu, kui SSH ühendus on võimalik;
* kontrollib, kas `.20` peal on **Apache2 paigaldatud**;
* kontrollib, kas Apache2 töötab;
* otsib `.20` pealt **kõik WordPressi paigaldused**;
* otsib ka `.25` pealt lokaalselt kõik WordPressi paigaldused;
* näitab iga WordPressi puhul `wp-config.php` põhjal:

  * `DB_NAME`
  * `DB_USER`
  * `DB_HOST`
* kontrollib spetsiaalselt, et `kolmasdomeen.<õpilase-domeen>` WordPress kasutaks MariaDB serverit `.25`;
* kontrollib, et WordPress ei kasutaks lokaalset `localhost` / `127.0.0.1` andmebaasi;
* kontrollib Apache VirtualHost'i;
* kontrollib MariaDB kasutajat ja tema hosti;
* kontrollib MariaDB õigusi;
* kontrollib BIND9 forward- ja reverse-zone'i;
* kontrollib DNS A- ja PTR-kirjeid;
* kontrollib HTTP kaudu WordPressi;
* lõpus annab **kokkuvõtte**, kus on eraldi:

  * mis on OK;
  * mis on VIGA;
  * mis erineb ülesandest;
  * nimeserveri kokkuvõte;
  * WordPressi kokkuvõte;
  * MariaDB kokkuvõte.

---

# Täielikult parandatud skript

Salvesta näiteks:

```bash
nano kontroll-wordpress-dns.sh
```

ja pane sinna kogu järgnev sisu:

```bash
#!/usr/bin/env bash

# ============================================================
# HKHK – WordPress + MariaDB + BIND9 kontrollskript
#
# ARHITEKTUUR:
#
# SERVER .20 = Apache2 + WordPress
# SERVER .25 = MariaDB + BIND9
#
# Skript käivitatakse SERVER .25 peal.
#
# KASUTAMINE:
#
#   sudo ./kontroll-wordpress-dns.sh tamm.local
#
# Näiteks:
#
#   10.0.13.20 = Apache2 + WordPress
#   10.0.13.25 = MariaDB + BIND9
#   tamm.local = õpilase tegelik domeen
#
# Sellisel juhul kontrollitakse:
#
#   tamm.local
#   ns1.tamm.local
#   www.tamm.local
#   kolmasdomeen.tamm.local
#
# ============================================================

set -u

# ============================================================
# VÄRVID
# ============================================================

RED=""
GREEN=""
YELLOW=""
BLUE=""
NC=""

# Kui terminal toetab värve
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;36m'
    NC='\033[0m'
fi

# ============================================================
# LOENDURID
# ============================================================

PASS=0
FAIL=0
WARN=0

# ============================================================
# KOKKUVÕTTE LISTID
# ============================================================

OK_LIST=()
FAIL_LIST=()
WARN_LIST=()

ok() {
    echo -e "${GREEN}[OK]${NC}   $1"
    PASS=$((PASS+1))
    OK_LIST+=("$1")
}

fail() {
    echo -e "${RED}[VIGA]${NC} $1"
    FAIL=$((FAIL+1))
    FAIL_LIST+=("$1")
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARN=$((WARN+1))
    WARN_LIST+=("$1")
}

info() {
    echo "       $1"
}

separator() {
    echo
    echo "------------------------------------------------------------"
}

# ============================================================
# ARGUMENDID
# ============================================================

if [[ $# -ne 1 ]]; then

    echo
    echo "Kasutamine:"
    echo
    echo "  sudo $0 <domeen>"
    echo
    echo "Näide:"
    echo
    echo "  sudo $0 tamm.local"
    echo
    echo "Kui õpilase domeen on näiteks saar.local:"
    echo
    echo "  sudo $0 saar.local"
    echo

    exit 1
fi

DOMAIN_DNS="$1"

# ============================================================
# DOMENI LIHTNE KONTROLL
# ============================================================

if [[ "$DOMAIN_DNS" == "minudomeen.local" ||
      "$DOMAIN_DNS" == "perenimi.local" ]]; then

    warn "Kasutatud on võimalikku näidis-/placeholder-domeeni: $DOMAIN_DNS"
    info "Kontrolli, et õpilane ei jätnud ülesande näidisväärtust kasutamata."

fi

DNS_HOST="ns1.${DOMAIN_DNS}"

DOMAIN_WWW="www.${DOMAIN_DNS}"

DOMAIN_WP="kolmasdomeen.${DOMAIN_DNS}"

DB_NAME_EXPECTED="kolmasdomeen_db"

DB_USER_EXPECTED="wpuser"

# ============================================================
# 10.0.X VÕRGU LEIDMINE
# ============================================================

LOCAL_IP=$(
    ip -4 -o addr show |
    awk '$4 ~ /^10\.0\.[0-9]+\./ {print $4; exit}' |
    cut -d/ -f1
)

if [[ -z "$LOCAL_IP" ]]; then

    echo
    echo "VIGA: 10.0.X.X IP-aadressi ei leitud."
    echo
    ip -4 -br addr
    exit 1

fi

X=$(echo "$LOCAL_IP" | cut -d. -f3)

EXPECTED_WEB="10.0.${X}.20"
EXPECTED_DNS_DB="10.0.${X}.25"

REVERSE_ZONE="${X}.0.10.in-addr.arpa"

DOCROOT_EXPECTED="/var/www/${DOMAIN_WP}"

WP_CONFIG_EXPECTED="${DOCROOT_EXPECTED}/wp-config.php"

# ============================================================
# SSH SEADISTUS
# ============================================================
#
# Vaikimisi proovime root kasutajat.
#
# Vajadusel saab kasutada:
#
#   SSH_USER=haldur sudo ./kontroll-wordpress-dns.sh tamm.local
#
# ============================================================

SSH_USER="${SSH_USER:-root}"

REMOTE="${SSH_USER}@${EXPECTED_WEB}"

REMOTE_SSH_OK=0

# ============================================================
# ALGINFO
# ============================================================

echo
echo "============================================================"
echo " HKHK – WORDPRESS + MARIADB + BIND9 KONTROLL"
echo "============================================================"
echo

echo "KONTROLLI PARAMEETRID"
echo
echo "Õpilase domeen:"
echo "  $DOMAIN_DNS"
echo
echo "Nimeserver:"
echo "  $DNS_HOST"
echo
echo "WWW:"
echo "  $DOMAIN_WWW"
echo
echo "WordPress:"
echo "  $DOMAIN_WP"
echo
echo "WordPress server:"
echo "  $EXPECTED_WEB"
echo
echo "MariaDB + DNS server:"
echo "  $EXPECTED_DNS_DB"
echo
echo "MariaDB andmebaas:"
echo "  $DB_NAME_EXPECTED"
echo
echo "MariaDB kasutaja:"
echo "  $DB_USER_EXPECTED@$EXPECTED_WEB"
echo
echo "Reverse zone:"
echo "  $REVERSE_ZONE"

# ============================================================
# SSH TEST
# ============================================================

separator
echo "SSH ÜHENDUS WORDPRESS SERVERIGA"

if command -v ssh >/dev/null 2>&1; then

    if ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=4 \
        -o StrictHostKeyChecking=no \
        "$REMOTE" \
        "echo SSH_OK" 2>/dev/null |
        grep -q "SSH_OK"; then

        REMOTE_SSH_OK=1

        ok "SSH ühendus serveriga $EXPECTED_WEB töötab"
        info "SSH kasutaja: $SSH_USER"

    else

        warn "SSH ühendust serveriga $EXPECTED_WEB ei õnnestunud luua"
        info "Proovitud: $REMOTE"
        info "Apache/WordPress detailne lokaalne kontroll .20 peal jääb tegemata"
        info "Kui SSH-võti puudub, käivita näiteks: SSH_USER=haldur sudo $0 $DOMAIN_DNS"

    fi

else

    warn "SSH klient puudub"
    info "Serveri .20 detailset lokaalset kontrolli ei saa teha"

fi

# ============================================================
# SERVER .25
# ============================================================

echo
echo "============================================================"
echo " 1. SERVER .25 – MARIADB + BIND9"
echo "============================================================"

# ============================================================
# IP
# ============================================================

separator
echo "SERVERI IP"

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

# ============================================================
# MARIADB PAIGALDUS
# ============================================================

if dpkg-query -W -f='${Status}' mariadb-server 2>/dev/null |
    grep -q "install ok installed"; then

    ok "MariaDB server on paigaldatud"

else

    fail "MariaDB server ei ole paigaldatud"

fi

# ============================================================
# PORT 3306
# ============================================================

echo
echo "MariaDB kuulamisport:"

MYSQL_LISTEN=$(
    ss -lntp 2>/dev/null |
    grep ':3306' ||
    true
)

if [[ -n "$MYSQL_LISTEN" ]]; then

    ok "MariaDB kuulab porti 3306"
    echo "$MYSQL_LISTEN" | sed 's/^/       /'

else

    fail "MariaDB ei kuula porti 3306"

fi

# ============================================================
# BIND ADDRESS
# ============================================================

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
# MYSQL KÄSK
# ============================================================

MYSQL_CMD=""

if command -v mariadb >/dev/null 2>&1; then

    MYSQL_CMD="mariadb"

elif command -v mysql >/dev/null 2>&1; then

    MYSQL_CMD="mysql"

fi

# ============================================================
# ANDMEBAAS
# ============================================================

separator
echo "ANDMEBAAS"

if [[ -z "$MYSQL_CMD" ]]; then

    fail "mysql/mariadb käsurea klient puudub"

else

    DB_RESULT=$(
        sudo "$MYSQL_CMD" -N -B \
        -e "SHOW DATABASES LIKE '${DB_NAME_EXPECTED}';" \
        2>/dev/null ||
        true
    )

    echo "Andmebaasi tegelik tulemus:"
    echo "       ${DB_RESULT:-PUUDUB}"

    if [[ "$DB_RESULT" == "$DB_NAME_EXPECTED" ]]; then

        ok "Andmebaas $DB_NAME_EXPECTED on olemas"

    else

        fail "Andmebaasi $DB_NAME_EXPECTED ei ole"
        info "Tegelik: ${DB_RESULT:-PUUDUB}"
        info "Oodatud: $DB_NAME_EXPECTED"

    fi

fi

# ============================================================
# MARIADB KASUTAJA
# ============================================================

separator
echo "MARIADB KASUTAJA"

USER_RESULT=""

if [[ -n "$MYSQL_CMD" ]]; then

    USER_RESULT=$(
        sudo "$MYSQL_CMD" -N -B \
        -e "SELECT CONCAT(User,'@',Host)
            FROM mysql.user
            WHERE User='${DB_USER_EXPECTED}';" \
        2>/dev/null ||
        true
    )

    echo "Kasutaja tegelikud kirjed:"

    if [[ -n "$USER_RESULT" ]]; then

        echo "$USER_RESULT" |
            sed 's/^/       /'

    else

        echo "       PUUDUB"

    fi

    if echo "$USER_RESULT" |
        grep -Fq "${DB_USER_EXPECTED}@${EXPECTED_WEB}"; then

        ok "${DB_USER_EXPECTED}@${EXPECTED_WEB} olemas"

    else

        fail "${DB_USER_EXPECTED}@${EXPECTED_WEB} puudub"

        info "Oodatud: ${DB_USER_EXPECTED}@${EXPECTED_WEB}"

        if [[ -n "$USER_RESULT" ]]; then
            info "Tegelik kasutaja/host:"
            echo "$USER_RESULT" | sed 's/^/              /'
        fi

    fi

fi

# ============================================================
# MARIADB ÕIGUSED
# ============================================================

separator
echo "MARIADB ÕIGUSED"

GRANTS=""

if [[ -n "$MYSQL_CMD" ]]; then

    GRANTS=$(
        sudo "$MYSQL_CMD" -N -B \
        -e "SHOW GRANTS FOR '${DB_USER_EXPECTED}'@'${EXPECTED_WEB}';" \
        2>/dev/null ||
        true
    )

    echo "Tegelikud õigused:"

    if [[ -n "$GRANTS" ]]; then

        echo "$GRANTS" |
            sed 's/^/       /'

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
# BIND9 TEENUS
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
    info "Teenuse nimi: $BIND_SERVICE"

else

    fail "BIND9 ei tööta"

    info "bind9 olek: $(systemctl is-active bind9 2>/dev/null || echo teadmata)"

fi

# ============================================================
# BIND9 PAIGALDUS
# ============================================================

if dpkg-query -W -f='${Status}' bind9 2>/dev/null |
    grep -q "install ok installed"; then

    ok "BIND9 on paigaldatud"

else

    fail "BIND9 ei ole paigaldatud"

fi

# ============================================================
# DNS PORT 53
# ============================================================

separator
echo "DNS KUULAMINE"

DNS_LISTEN=$(
    ss -lunpt 2>/dev/null |
    grep -E '(:53[[:space:]]|:53$)' ||
    true
)

if [[ -n "$DNS_LISTEN" ]]; then

    ok "DNS port 53 on kuulamisel"

    echo "$DNS_LISTEN" |
        sed 's/^/       /'

else

    fail "DNS port 53 ei ole kuulamisel"

fi

# ============================================================
# BIND9 KONFIGURATSIOON
# ============================================================

separator
echo "BIND9 KONFIGURATSIOON"

NAMED_LOCAL="/etc/bind/named.conf.local"

if [[ -f "$NAMED_LOCAL" ]]; then

    ok "$NAMED_LOCAL olemas"

else

    fail "$NAMED_LOCAL puudub"

fi

# ============================================================
# FORWARD ZONE
# ============================================================

if grep -Eq \
    "zone[[:space:]]+\"${DOMAIN_DNS}\"" \
    "$NAMED_LOCAL" 2>/dev/null; then

    ok "Forward zone $DOMAIN_DNS on defineeritud"

else

    fail "Forward zone $DOMAIN_DNS puudub"
    info "Oodatud: zone \"$DOMAIN_DNS\""

fi

# ============================================================
# REVERSE ZONE
# ============================================================

if grep -Eq \
    "zone[[:space:]]+\"${REVERSE_ZONE}\"" \
    "$NAMED_LOCAL" 2>/dev/null; then

    ok "Reverse zone $REVERSE_ZONE on defineeritud"

else

    fail "Reverse zone $REVERSE_ZONE puudub"
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

        ok "named-checkconf on korras"

    else

        fail "named-checkconf annab vea"

        echo "$CONF_RESULT" |
            sed 's/^/       /'

    fi

else

    fail "named-checkconf puudub"

fi

# ============================================================
# TSOONIFAILIDE LEIDMINE
# ============================================================

separator
echo "BIND9 TSOONIFAILID"

FORWARD_FILE=$(
    awk -v zone="$DOMAIN_DNS" '
        $1 == "zone" && $2 == "\"" zone "\"" {
            inside=1
        }

        inside && $1 == "file" {
            gsub(/[";]/,"",$2)
            print $2
            exit
        }

        inside && /^}/ {
            inside=0
        }
    ' "$NAMED_LOCAL" 2>/dev/null
)

REVERSE_FILE=$(
    awk -v zone="$REVERSE_ZONE" '
        $1 == "zone" && $2 == "\"" zone "\"" {
            inside=1
        }

        inside && $1 == "file" {
            gsub(/[";]/,"",$2)
            print $2
            exit
        }

        inside && /^}/ {
            inside=0
        }
    ' "$NAMED_LOCAL" 2>/dev/null
)

echo "Forward zone fail:"
echo "       ${FORWARD_FILE:-PUUDUB}"

echo
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
    echo "$FORWARD_RESULT" |
        sed 's/^/       /'

    if echo "$FORWARD_RESULT" |
        grep -q "loaded serial"; then

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
    echo "$REVERSE_RESULT" |
        sed 's/^/       /'

    if echo "$REVERSE_RESULT" |
        grep -q "loaded serial"; then

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

DNS_A=""
NS_A=""
WWW_A=""
WP_A=""

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
        dig +short @127.0.0.1 "$DOMAIN_WWW" A |
        head -1
    )

    WP_A=$(
        dig +short @127.0.0.1 "$DOMAIN_WP" A |
        head -1
    )

    echo
    echo "Tegelikud DNS-vastused:"
    echo
    echo "  $DOMAIN_DNS"
    echo "       -> ${DNS_A:-PUUDUB}"
    echo
    echo "  $DNS_HOST"
    echo "       -> ${NS_A:-PUUDUB}"
    echo
    echo "  $DOMAIN_WWW"
    echo "       -> ${WWW_A:-PUUDUB}"
    echo
    echo "  $DOMAIN_WP"
    echo "       -> ${WP_A:-PUUDUB}"

    # --------------------------------------------------------
    # ROOT DOMAIN
    # --------------------------------------------------------

    if [[ "$DNS_A" == "$EXPECTED_DNS_DB" ]]; then

        ok "$DOMAIN_DNS -> $EXPECTED_DNS_DB"

    else

        fail "$DOMAIN_DNS A-kirje vale"
        info "Tegelik: ${DNS_A:-PUUDUB}"
        info "Oodatud: $EXPECTED_DNS_DB"

    fi

    # --------------------------------------------------------
    # NS1
    # --------------------------------------------------------

    if [[ "$NS_A" == "$EXPECTED_DNS_DB" ]]; then

        ok "$DNS_HOST -> $EXPECTED_DNS_DB"

    else

        fail "$DNS_HOST A-kirje vale"
        info "Tegelik: ${NS_A:-PUUDUB}"
        info "Oodatud: $EXPECTED_DNS_DB"

    fi

    # --------------------------------------------------------
    # WWW
    # --------------------------------------------------------

    if [[ "$WWW_A" == "$EXPECTED_WEB" ]]; then

        ok "$DOMAIN_WWW -> $EXPECTED_WEB"

    else

        fail "$DOMAIN_WWW A-kirje vale"
        info "Tegelik: ${WWW_A:-PUUDUB}"
        info "Oodatud: $EXPECTED_WEB"

    fi

    # --------------------------------------------------------
    # WORDPRESS
    # --------------------------------------------------------

    if [[ "$WP_A" == "$EXPECTED_WEB" ]]; then

        ok "$DOMAIN_WP -> $EXPECTED_WEB"

    else

        fail "$DOMAIN_WP DNS-kirje vale"
        info "Tegelik: ${WP_A:-PUUDUB}"
        info "Oodatud: $EXPECTED_WEB"

    fi

else

    fail "dig puudub"

fi

# ============================================================
# REVERSE DNS
# ============================================================

separator
echo "REVERSE DNS"

PTR25=""
PTR20=""

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
    echo
    echo "  $EXPECTED_DNS_DB"
    echo "       -> ${PTR25:-PUUDUB}"
    echo
    echo "  $EXPECTED_WEB"
    echo "       -> ${PTR20:-PUUDUB}"

    # .25

    if [[ "$PTR25" == "$DNS_HOST" ]]; then

        ok "$EXPECTED_DNS_DB -> $DNS_HOST"

    else

        fail "Reverse DNS .25 jaoks vale"
        info "Tegelik: ${PTR25:-PUUDUB}"
        info "Oodatud: $DNS_HOST"

    fi

    # .20

    if [[ "$PTR20" == "$DOMAIN_WP" ||
          "$PTR20" == "$DOMAIN_WWW" ]]; then

        ok "$EXPECTED_WEB reverse DNS on olemas"
        info "Tegelik PTR: $PTR20"

    else

        warn "Reverse DNS .20 jaoks puudub või erineb ülesandest"
        info "Tegelik: ${PTR20:-PUUDUB}"
        info "Oodatud näiteks: $DOMAIN_WP"

    fi

fi

# ============================================================
# LOKAALSED WORDPRESS PAIGALDUSED SERVERIL .25
# ============================================================

separator
echo "WORDPRESSI PAIGALDUSED SERVERIL .25"

LOCAL_WP_LIST=""

for SEARCH_DIR in /var/www /srv/www /opt/www; do

    if [[ -d "$SEARCH_DIR" ]]; then

        while IFS= read -r FILE; do
            LOCAL_WP_LIST="${LOCAL_WP_LIST}${FILE}"$'\n'
        done < <(
            find "$SEARCH_DIR" \
                -maxdepth 5 \
                -type f \
                -name "wp-config.php" \
                2>/dev/null
        )

    fi

done

if [[ -n "$LOCAL_WP_LIST" ]]; then

    echo "Serveril .25 leitud WordPressi konfiguratsioonid:"
    echo

    echo "$LOCAL_WP_LIST" |
        sed '/^$/d' |
        sed 's/^/       /'

    warn "Serveril .25 on lokaalne WordPressi paigaldus"
    info "Ülesande arhitektuuris peab WordPress olema serveril .20."
    info "Server .25 peaks olema MariaDB + BIND9."

else

    ok "Serveril .25 ei leitud lokaalset WordPressi paigaldust"

fi

# ============================================================
# SERVER .20 VÕRGUÜHENDUS
# ============================================================

echo
echo "============================================================"
echo " 2. SERVER .20 – APACHE2 + WORDPRESS"
echo "============================================================"

# ============================================================
# PING
# ============================================================

separator
echo "VÕRGUÜHENDUS"

if ping -c 2 -W 2 "$EXPECTED_WEB" >/dev/null 2>&1; then

    ok "Server .20 vastab pingile"

else

    fail "Server .20 ei vasta pingile"
    info "Testitud: $EXPECTED_WEB"

fi

# ============================================================
# PORT 80
# ============================================================

if command -v nc >/dev/null 2>&1; then

    if nc -z -w 3 "$EXPECTED_WEB" 80 >/dev/null 2>&1; then

        ok "$EXPECTED_WEB:80 on kättesaadav"

    else

        fail "$EXPECTED_WEB:80 ei ole kättesaadav"

    fi

fi

# ============================================================
# APACHE2 REMOTE
# ============================================================

separator
echo "APACHE2"

REMOTE_APACHE_INSTALLED="PUUDUB"
REMOTE_APACHE_SERVICE="PUUDUB"

if [[ "$REMOTE_SSH_OK" -eq 1 ]]; then

    REMOTE_APACHE_INSTALLED=$(
        ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=4 \
        -o StrictHostKeyChecking=no \
        "$REMOTE" \
        "dpkg-query -W -f='\${Status}' apache2 2>/dev/null || true" \
        2>/dev/null
    )

    REMOTE_APACHE_SERVICE=$(
        ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=4 \
        -o StrictHostKeyChecking=no \
        "$REMOTE" \
        "systemctl is-active apache2 2>/dev/null || true" \
        2>/dev/null
    )

    echo "Apache2 paigaldus:"
    echo "       Tegelik: ${REMOTE_APACHE_INSTALLED:-PUUDUB}"

    if echo "$REMOTE_APACHE_INSTALLED" |
        grep -q "install ok installed"; then

        ok "Apache2 on serveril .20 paigaldatud"

    else

        fail "Apache2 ei ole serveril .20 paigaldatud"
        info "Tegelik: ${REMOTE_APACHE_INSTALLED:-PUUDUB}"

    fi

    echo
    echo "Apache2 teenus:"
    echo "       Tegelik: ${REMOTE_APACHE_SERVICE:-PUUDUB}"

    if [[ "$REMOTE_APACHE_SERVICE" == "active" ]]; then

        ok "Apache2 töötab serveril .20"

    else

        fail "Apache2 ei tööta serveril .20"
        info "Tegelik olek: ${REMOTE_APACHE_SERVICE:-PUUDUB}"

    fi

else

    warn "Apache2 lokaalset paigaldust .20 peal ei saanud kontrollida"
    info "SSH ühendus puudub."
    info "Port 80 kontroll tehti eraldi."

fi

# ============================================================
# APACHE VIRTUALHOST
# ============================================================

separator
echo "APACHE VIRTUALHOST"

VHOST_RESULT=""

if [[ "$REMOTE_SSH_OK" -eq 1 ]]; then

    VHOST_RESULT=$(
        ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=4 \
        -o StrictHostKeyChecking=no \
        "$REMOTE" \
        "apache2ctl -S 2>&1 || true" \
        2>/dev/null
    )

    echo "$VHOST_RESULT" |
        sed 's/^/       /'

    if echo "$VHOST_RESULT" |
        grep -Fq "$DOMAIN_WP"; then

        ok "Apache VirtualHost $DOMAIN_WP on defineeritud"

    else

        fail "Apache VirtualHost $DOMAIN_WP ei leitud"
        info "Oodatud VirtualHost: $DOMAIN_WP"

    fi

else

    warn "Apache VirtualHosti ei saanud lokaalselt kontrollida"

fi

# ============================================================
# WORDPRESSI PAIGALDUSED SERVERIL .20
# ============================================================

separator
echo "WORDPRESSI PAIGALDUSED SERVERIL .20"

REMOTE_WP_LIST=""

if [[ "$REMOTE_SSH_OK" -eq 1 ]]; then

    REMOTE_WP_LIST=$(
        ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        "$REMOTE" \
        '
        for d in /var/www /srv/www /opt/www; do
            if [ -d "$d" ]; then
                find "$d" -maxdepth 5 -type f -name wp-config.php 2>/dev/null
            fi
        done
        ' \
        2>/dev/null |
        sort -u
    )

    if [[ -n "$REMOTE_WP_LIST" ]]; then

        echo "Serveril .20 leitud WordPressi konfiguratsioonid:"
        echo

        echo "$REMOTE_WP_LIST" |
            sed 's/^/       /'

        echo
        ok "Serveril .20 on vähemalt üks WordPressi paigaldus"

    else

        fail "Serveril .20 ei leitud WordPressi paigaldust"
        info "Otsiti wp-config.php faile kataloogidest /var/www, /srv/www ja /opt/www"

    fi

else

    warn "Serveri .20 WordPressi paigalduste nimekirja ei saanud lugeda"

fi

# ============================================================
# OODATUD WORDPRESS
# ============================================================

separator
echo "OODATUD WORDPRESS: $DOMAIN_WP"

EXPECTED_WP_FOUND=0

if [[ "$REMOTE_SSH_OK" -eq 1 ]]; then

    if echo "$REMOTE_WP_LIST" |
        grep -Fq "$WP_CONFIG_EXPECTED"; then

        EXPECTED_WP_FOUND=1

        ok "Oodatud WordPress asub kataloogis $DOCROOT_EXPECTED"

    else

        fail "Oodatud WordPressi kataloogi $DOCROOT_EXPECTED ei leitud"

        info "Oodatud wp-config.php:"
        info "  $WP_CONFIG_EXPECTED"

        if [[ -n "$REMOTE_WP_LIST" ]]; then

            info "Leitud WordPressi paigaldused:"
            echo "$REMOTE_WP_LIST" |
                sed 's/^/              /'

        fi

    fi

fi

# ============================================================
# WORDPRESSI VERSIOONID
# ============================================================

separator
echo "WORDPRESSI VERSIOONID SERVERIL .20"

if [[ "$REMOTE_SSH_OK" -eq 1 &&
      -n "$REMOTE_WP_LIST" ]]; then

    while IFS= read -r WP_CONFIG; do

        [[ -z "$WP_CONFIG" ]] && continue

        WP_DIR=$(dirname "$WP_CONFIG")

        WP_VERSION=$(
            ssh \
            -o BatchMode=yes \
            -o ConnectTimeout=4 \
            -o StrictHostKeyChecking=no \
            "$REMOTE" \
            "if [ -f '$WP_DIR/wp-includes/version.php' ]; then grep -E '^\$wp_version[[:space:]]*=' '$WP_DIR/wp-includes/version.php' | head -1; else echo 'PUUDUB'; fi" \
            2>/dev/null
        )

        echo "WordPress:"
        echo "       $WP_DIR"
        echo "       Versioon: ${WP_VERSION:-PUUDUB}"
        echo

    done <<< "$REMOTE_WP_LIST"

fi

# ============================================================
# WORDPRESS DB KONFIGURATSIOON
# ============================================================

separator
echo "WORDPRESS + MARIADB ÜHENDUS"

REMOTE_WP_CONFIG_LINES=""

if [[ "$REMOTE_SSH_OK" -eq 1 &&
      -n "$REMOTE_WP_LIST" ]]; then

    while IFS= read -r WP_CONFIG; do

        [[ -z "$WP_CONFIG" ]] && continue

        echo
        echo "WordPress:"
        echo "       $WP_CONFIG"

        WP_DB_NAME=$(
            ssh \
            -o BatchMode=yes \
            -o ConnectTimeout=4 \
            -o StrictHostKeyChecking=no \
            "$REMOTE" \
            "grep -E \"define[[:space:]]*\\([[:space:]]*['\\\"]DB_NAME['\\\"]\" '$WP_CONFIG' 2>/dev/null | head -1" \
            2>/dev/null
        )

        WP_DB_USER=$(
            ssh \
            -o BatchMode=yes \
            -o ConnectTimeout=4 \
            -o StrictHostKeyChecking=no \
            "$REMOTE" \
            "grep -E \"define[[:space:]]*\\([[:space:]]*['\\\"]DB_USER['\\\"]\" '$WP_CONFIG' 2>/dev/null | head -1" \
            2>/dev/null
        )

        WP_DB_HOST=$(
            ssh \
            -o BatchMode=yes \
            -o ConnectTimeout=4 \
            -o StrictHostKeyChecking=no \
            "$REMOTE" \
            "grep -E \"define[[:space:]]*\\([[:space:]]*['\\\"]DB_HOST['\\\"]\" '$WP_CONFIG' 2>/dev/null | head -1" \
            2>/dev/null
        )

        echo "       DB_NAME: $WP_DB_NAME"
        echo "       DB_USER: $WP_DB_USER"
        echo "       DB_HOST: $WP_DB_HOST"

        # ----------------------------------------------------
        # DB NAME
        # ----------------------------------------------------

        if echo "$WP_DB_NAME" |
            grep -Eq "['\\\"]DB_NAME['\\\"][[:space:]]*,[[:space:]]*['\\\"]${DB_NAME_EXPECTED}['\\\"]"; then

            ok "WordPress kasutab andmebaasi $DB_NAME_EXPECTED"

        else

            fail "WordPressi DB_NAME on vale"
            info "Tegelik: ${WP_DB_NAME:-PUUDUB}"
            info "Oodatud: $DB_NAME_EXPECTED"

        fi

        # ----------------------------------------------------
        # DB USER
        # ----------------------------------------------------

        if echo "$WP_DB_USER" |
            grep -Eq "['\\\"]DB_USER['\\\"][[:space:]]*,[[:space:]]*['\\\"]${DB_USER_EXPECTED}['\\\"]"; then

            ok "WordPress kasutab kasutajat $DB_USER_EXPECTED"

        else

            fail "WordPressi DB_USER on vale"
            info "Tegelik: ${WP_DB_USER:-PUUDUB}"
            info "Oodatud: $DB_USER_EXPECTED"

        fi

        # ----------------------------------------------------
        # DB HOST
        # ----------------------------------------------------

        WP_DB_HOST_VALUE=$(
            echo "$WP_DB_HOST" |
            sed -E "s/.*['\\\"]DB_HOST['\\\"][[:space:]]*,[[:space:]]*['\\\"]([^'\\\"]+)['\\\"].*/\1/"
        )

        echo
        echo "       Tegelik DB_HOST väärtus:"
        echo "       ${WP_DB_HOST_VALUE:-PUUDUB}"

        if [[ "$WP_DB_HOST_VALUE" == "$EXPECTED_DNS_DB" ||
              "$WP_DB_HOST_VALUE" == "${EXPECTED_DNS_DB}:3306" ]]; then

            ok "WordPress kasutab kaugserveri MariaDB-d $EXPECTED_DNS_DB"

        else

            fail "WordPress ei kasuta ülesandes nõutud kaug-MariaDB serverit"

            info "Tegelik DB_HOST: ${WP_DB_HOST_VALUE:-PUUDUB}"
            info "Oodatud DB_HOST: $EXPECTED_DNS_DB"
            info "Lubatud ka: $EXPECTED_DNS_DB:3306"

            if [[ "$WP_DB_HOST_VALUE" == "localhost" ||
                  "$WP_DB_HOST_VALUE" == "127.0.0.1" ||
                  "$WP_DB_HOST_VALUE" == "::1" ]]; then

                fail "WordPress kasutab lokaalset MariaDB-d"
                info "See tähendab, et WordPress ei kasuta serveril .25 olevat andmebaasi."

            fi

        fi

    done <<< "$REMOTE_WP_LIST"

else

    warn "WordPressi wp-config.php ei saanud serverilt .20 lugeda"

fi

# ============================================================
# WORDPRESS HTTP
# ============================================================

separator
echo "WORDPRESS HTTP"

HTTP_RESULT=""

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

    echo "WordPress HTTP staatus:"
    echo "       Tegelik: ${HTTP_RESULT:-PUUDUB}"

    if [[ "$HTTP_RESULT" == "200" ||
          "$HTTP_RESULT" == "301" ||
          "$HTTP_RESULT" == "302" ||
          "$HTTP_RESULT" == "303" ]]; then

        ok "WordPress veebileht vastab HTTP kaudu"

    else

        fail "WordPress veebileht ei vasta korrektselt"
        info "Oodatud HTTP staatus: 200/301/302/303"
        info "Tegelik: ${HTTP_RESULT:-PUUDUB}"

    fi

fi

# ============================================================
# WORDPRESS DNS
# ============================================================

separator
echo "WORDPRESS DOMEEN DNS"

if command -v dig >/dev/null 2>&1; then

    WP_DNS=$(
        dig +short @127.0.0.1 "$DOMAIN_WP" A |
        head -1
    )

    echo "$DOMAIN_WP -> ${WP_DNS:-PUUDUB}"

    if [[ "$WP_DNS" == "$EXPECTED_WEB" ]]; then

        ok "$DOMAIN_WP lahendub serverile .20"

    else

        fail "$DOMAIN_WP DNS-kirje on vale"
        info "Tegelik: ${WP_DNS:-PUUDUB}"
        info "Oodatud: $EXPECTED_WEB"

    fi

fi

# ============================================================
# KÕIK WORDPRESSI PAIGALDUSED – KOONDTABEL
# ============================================================

separator
echo "WORDPRESSI PAIGALDUSTE ÜLEVAADE"

echo
echo "SERVER .25 – lokaalsed WordPressid:"
echo

if [[ -n "$LOCAL_WP_LIST" ]]; then

    echo "$LOCAL_WP_LIST" |
        sed '/^$/d' |
        sed 's/^/  /'

else

    echo "  PUUDUVAD"

fi

echo
echo "SERVER .20 – WordPressid:"
echo

if [[ -n "$REMOTE_WP_LIST" ]]; then

    echo "$REMOTE_WP_LIST" |
        sed '/^$/d' |
        sed 's/^/  /'

else

    echo "  PUUDUVAD või SSH puudub"

fi

# ============================================================
# LÕPLIK NIMESERVERI KOKKUVÕTE
# ============================================================

separator
echo "NIMESERVERI SEADISTUSE KOKKUVÕTE"

echo
echo "BIND9:"
echo "  Teenus:          ${BIND_SERVICE:-PUUDUB}"
echo "  Forward zone:    $DOMAIN_DNS"
echo "  Reverse zone:    $REVERSE_ZONE"
echo "  Zone fail:       ${FORWARD_FILE:-PUUDUB}"
echo "  Reverse fail:    ${REVERSE_FILE:-PUUDUB}"

echo
echo "DNS A-kirjed:"
echo "  $DOMAIN_DNS"
echo "       Tegelik: ${DNS_A:-PUUDUB}"
echo "       Oodatud: $EXPECTED_DNS_DB"

echo "  $DNS_HOST"
echo "       Tegelik: ${NS_A:-PUUDUB}"
echo "       Oodatud: $EXPECTED_DNS_DB"

echo "  $DOMAIN_WWW"
echo "       Tegelik: ${WWW_A:-PUUDUB}"
echo "       Oodatud: $EXPECTED_WEB"

echo "  $DOMAIN_WP"
echo "       Tegelik: ${WP_A:-PUUDUB}"
echo "       Oodatud: $EXPECTED_WEB"

echo
echo "Reverse DNS:"
echo "  $EXPECTED_DNS_DB -> ${PTR25:-PUUDUB}"
echo "  $EXPECTED_WEB    -> ${PTR20:-PUUDUB}"

# ============================================================
# WORDPRESS LÕPLIK KOKKUVÕTE
# ============================================================

separator
echo "WORDPRESSI SEADISTUSE KOKKUVÕTE"

echo
echo "Oodatud WordPress:"
echo "  Domeen:       $DOMAIN_WP"
echo "  Server:       $EXPECTED_WEB"
echo "  DocumentRoot: $DOCROOT_EXPECTED"

echo
echo "Apache2:"
echo "  Paigaldatud:  ${REMOTE_APACHE_INSTALLED:-PUUDUB}"
echo "  Teenus:       ${REMOTE_APACHE_SERVICE:-PUUDUB}"

echo
echo "HTTP:"
echo "  URL:          http://${DOMAIN_WP}/"
echo "  HTTP staatus: ${HTTP_RESULT:-PUUDUB}"

echo
echo "Andmebaas:"
echo "  Server:       $EXPECTED_DNS_DB"
echo "  Andmebaas:    $DB_NAME_EXPECTED"
echo "  Kasutaja:     $DB_USER_EXPECTED@$EXPECTED_WEB"

# ============================================================
# ERINEVUSTE KOKKUVÕTE
# ============================================================

separator
echo "MIS EI OLE ÜLESANDEGA KOOSKÕLAS"

if [[ "$FAIL" -eq 0 &&
      "$WARN" -eq 0 ]]; then

    echo
    echo "  Puuduvad."
    echo "  Kõik kontrollid on korras."

else

    if [[ "$FAIL" -gt 0 ]]; then

        echo
        echo "VIGADE KOKKUVÕTE:"
        echo

        for ITEM in "${FAIL_LIST[@]}"; do
            echo "  [VIGA] $ITEM"
        done

    fi

    if [[ "$WARN" -gt 0 ]]; then

        echo
        echo "HOIATUSED / ERINEVUSED:"
        echo

        for ITEM in "${WARN_LIST[@]}"; do
            echo "  [WARN] $ITEM"
        done

    fi

fi

# ============================================================
# LÕPPSUMMARY
# ============================================================

echo
echo "============================================================"
echo " LÕPPTULEMUS"
echo "============================================================"
echo

echo "OK    : $PASS"
echo "VIGA  : $FAIL"
echo "WARN  : $WARN"

echo

if [[ "$FAIL" -eq 0 ]]; then

    echo "TULEMUS: KOHUSTUSLIKUD KONTROLLID LÄBITUD"

else

    echo "TULEMUS: TÖÖS ON VIGU"

fi

echo
echo "------------------------------------------------------------"
echo " KONTROLLITUD ARHITEKTUUR"
echo "------------------------------------------------------------"
echo
echo "  WordPress / Apache2 : $EXPECTED_WEB"
echo "  MariaDB / BIND9     : $EXPECTED_DNS_DB"
echo "  DNS domeen          : $DOMAIN_DNS"
echo "  WordPress domeen    : $DOMAIN_WP"
echo "  MariaDB             : $EXPECTED_DNS_DB"
echo "  DB nimi             : $DB_NAME_EXPECTED"
echo "  DB kasutaja         : $DB_USER_EXPECTED@$EXPECTED_WEB"
echo

# ============================================================
# EXIT CODE
# ============================================================

if [[ "$FAIL" -eq 0 ]]; then

    exit 0

else

    exit 2

fi
```

## Käivitamine

Näiteks kui õpilane valis domeeniks:

```text
tamm.local
```

siis:

```bash
chmod +x kontroll-wordpress-dns.sh
sudo ./kontroll-wordpress-dns.sh tamm.local
```

Kui domeen on:

```text
mets.local
```

siis:

```bash
sudo ./kontroll-wordpress-dns.sh mets.local
```

Skript moodustab ise:

```text
DNS domeen       = mets.local
Nimeserver       = ns1.mets.local
WWW              = www.mets.local
WordPress        = kolmasdomeen.mets.local
```

Seega **`perenimi.local` ei ole enam kontrollskriptis kasutatav fikseeritud väärtus**.

---

### Üks oluline täiendus selles versioonis

Näiteks kui õpilase `.20` serveri `wp-config.php` sisaldab:

```php
define( 'DB_HOST', 'localhost' );
```

siis skript näitab:

```text
[VIGA] WordPress ei kasuta ülesandes nõutud kaug-MariaDB serverit
       Tegelik DB_HOST: localhost
       Oodatud DB_HOST: 10.0.13.25
[VIGA] WordPress kasutab lokaalset MariaDB-d
       See tähendab, et WordPress ei kasuta serveril .25 olevat andmebaasi.
```

Kui seal on õigesti:

```php
define( 'DB_HOST', '10.0.13.25' );
```

siis:

```text
[OK]   WordPress kasutab kaugserveri MariaDB-d 10.0.13.25
```

See on sinu ülesande puhul palju olulisem kontroll kui ainult see, kas port `3306` on lahti.

### Samuti näitab lõpp nüüd näiteks

```text
NIMESERVERI SEADISTUSE KOKKUVÕTE

BIND9:
  Teenus:          bind9
  Forward zone:    tamm.local
  Reverse zone:    13.0.10.in-addr.arpa
  Zone fail:       /etc/bind/db.tamm.local
  Reverse fail:    /etc/bind/db.10

DNS A-kirjed:
  tamm.local
       Tegelik: 10.0.13.25
       Oodatud: 10.0.13.25

  ns1.tamm.local
       Tegelik: 10.0.13.25
       Oodatud: 10.0.13.25

  www.tamm.local
       Tegelik: 10.0.13.20
       Oodatud: 10.0.13.20

  kolmasdomeen.tamm.local
       Tegelik: 10.0.13.20
       Oodatud: 10.0.13.20
```

Ja WordPressi kohta:

```text
WORDPRESSI SEADISTUSE KOKKUVÕTE

Oodatud WordPress:
  Domeen:       kolmasdomeen.tamm.local
  Server:       10.0.13.20
  DocumentRoot: /var/www/kolmasdomeen.tamm.local

Apache2:
  Paigaldatud:  install ok installed
  Teenus:       active

HTTP:
  URL:          http://kolmasdomeen.tamm.local/
  HTTP staatus: 200

Andmebaas:
  Server:       10.0.13.25
  Andmebaas:    kolmasdomeen_db
  Kasutaja:     wpuser@10.0.13.20
```

Ja lõpus:

```text
MIS EI OLE ÜLESANDEGA KOOSKÕLAS

VIGADE KOKKUVÕTE:

  [VIGA] WordPress ei kasuta ülesandes nõutud kaug-MariaDB serverit
  [VIGA] www.tamm.local A-kirje vale

HOIATUSED / ERINEVUSED:

  [WARN] Serveril .25 on lokaalne WordPressi paigaldus
```

**Üks praktiline eeldus:** `.20` detailseks kontrollimiseks peab `.25` saama SSH võtmega `.20` sisse. Kui HKHK laboris on õpilaste serverid omavahel SSH-ga ligipääsetavad, saab skript kontrollida päriselt ka `.20` `apache2` paketti, VirtualHost'i, kõiki `wp-config.php` faile ja `DB_HOST` väärtust. Kui SSH puudub, annab skript selle kohta `[WARN]` ega teeskle, et Apache või WordPressi lokaalne konfiguratsioon on kontrollitud.
