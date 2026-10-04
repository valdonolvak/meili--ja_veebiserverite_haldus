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
# SSH:
#   .25 -> kasutaja@10.0.X.20
#
# Eeldus:
#   kasutaja saab .20 serverisse SSH võtmega
#   ning kasutajal on sudoõigus
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

# ------------------------------------------------------------
# ÕPILASE SSH KASUTAJA
# ------------------------------------------------------------

REMOTE_USER="kasutaja"
REMOTE_HOST="$EXPECTED_WEB"

SSH_TARGET="${REMOTE_USER}@${REMOTE_HOST}"

# SSH seaded
SSH_OPTS=(
    -o BatchMode=yes
    -o ConnectTimeout=5
    -o StrictHostKeyChecking=no
)

DOMAIN_DNS="minudomeen.local"
DNS_HOST="ns1.${DOMAIN_DNS}"

DOMAIN_WP="kolmasdomeen.perenimi.local"

DOCROOT="/var/www/${DOMAIN_WP}"
WP_CONFIG="${DOCROOT}/wp-config.php"

DB_NAME_EXPECTED="kolmasdomeen_db"
DB_USER_EXPECTED="wpuser"

REVERSE_ZONE="${X}.0.10.in-addr.arpa"

# ============================================================
# ALGINFO
# ============================================================

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
echo "WordPress / Apache server:"
echo "  $EXPECTED_WEB"
echo
echo "MariaDB + DNS server:"
echo "  $EXPECTED_DNS_DB"
echo
echo "SSH kontroll:"
echo "  $SSH_TARGET"
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
# MARIADB KASUTAJA
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
# MARIADB ÕIGUSED
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

    if [[ "$DNS_A" == "$EXPECTED_DNS_DB" ]]; then

        ok "$DOMAIN_DNS -> $EXPECTED_DNS_DB"

    else

        fail "$DOMAIN_DNS A-kirje vale"
        info "Tegelik: ${DNS_A:-PUUDUB}"
        info "Oodatud: $EXPECTED_DNS_DB"

    fi

    if [[ "$NS_A" == "$EXPECTED_DNS_DB" ]]; then

        ok "$DNS_HOST -> $EXPECTED_DNS_DB"

    else

        fail "$DNS_HOST A-kirje vale"
        info "Tegelik: ${NS_A:-PUUDUB}"
        info "Oodatud: $EXPECTED_DNS_DB"

    fi

    if [[ "$WWW_A" == "$EXPECTED_WEB" ]]; then

        ok "www.$DOMAIN_DNS -> $EXPECTED_WEB"

    else

        fail "www.$DOMAIN_DNS A-kirje vale"
        info "Tegelik: ${WWW_A:-PUUDUB}"
        info "Oodatud: $EXPECTED_WEB"

    fi

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
# SSH ÜHENDUS SERVER .20
# ============================================================

echo
echo "============================================================"
echo " 2. SERVER .20 – SSH + APACHE + WORDPRESS"
echo "============================================================"

separator
echo "SSH VÕTMEAUTENTIMINE"

echo "Kontrollitav:"
echo "       $SSH_TARGET"

SSH_TEST=$(
    ssh "${SSH_OPTS[@]}" \
    "$SSH_TARGET" \
    'echo SSH_OK' \
    2>&1
)

if [[ "$SSH_TEST" == "SSH_OK" ]]; then

    ok "SSH võtmeautentimine töötab"
    info "Ühendus: $SSH_TARGET"

else

    fail "SSH ühendus serverisse .20 ebaõnnestus"
    info "Sihtkoht: $SSH_TARGET"
    info "SSH vastus:"
    echo "$SSH_TEST" | sed 's/^/       /'

    echo
    echo "Serveri .20 kontrolli ei saa SSH kaudu jätkata."

    FAIL=$((FAIL+1))

    # Hüppame Apache/WordPress kontrollidest üle
    # ja läheme kokkuvõttesse.
    goto_summary=true
fi

# ============================================================
# KÕIK .20 KONTROLLID TEHAKSE SSH KAUDU
# ============================================================

if [[ "${goto_summary:-false}" != "true" ]]; then

    # --------------------------------------------------------
    # APACHE2
    # --------------------------------------------------------

    separator
    echo "APACHE2"

    APACHE_STATUS=$(
        ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
        'sudo systemctl is-active apache2 2>/dev/null || true'
    )

    echo "Apache2 olek:"
    echo "       Tegelik: ${APACHE_STATUS:-PUUDUB}"

    if [[ "$APACHE_STATUS" == "active" ]]; then

        ok "Apache2 töötab"

    else

        fail "Apache2 ei tööta"
        info "Oodatud: active"

    fi

    # --------------------------------------------------------
    # APACHE2 PORT 80
    # --------------------------------------------------------

    separator
    echo "APACHE2 PORT 80"

    APACHE_PORT=$(
        ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
        'sudo ss -lntp 2>/dev/null | grep ":80 " || true'
    )

    if [[ -n "$APACHE_PORT" ]]; then

        ok "Apache kuulab porti 80"
        echo "$APACHE_PORT" | sed 's/^/       /'

    else

        fail "Apache ei kuula porti 80"

    fi

    # --------------------------------------------------------
    # PHP
    # --------------------------------------------------------

    separator
    echo "PHP"

    PHP_VERSION=$(
        ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
        'php -v 2>/dev/null | head -1 || true'
    )

    if [[ -n "$PHP_VERSION" ]]; then

        ok "PHP on paigaldatud"
        info "$PHP_VERSION"

    else

        fail "PHP käsurea programm puudub"

    fi

    # --------------------------------------------------------
    # WORDPRESS DOCUMENT ROOT
    # --------------------------------------------------------

    separator
    echo "WORDPRESS"

    DOCROOT_RESULT=$(
        ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
        "if [[ -d '$DOCROOT' ]]; then echo EXISTS; else echo MISSING; fi"
    )

    if [[ "$DOCROOT_RESULT" == "EXISTS" ]]; then

        ok "WordPress document root olemas"
        info "$DOCROOT"

    else

        fail "WordPress document root puudub"
        info "Oodatud: $DOCROOT"

    fi

    # --------------------------------------------------------
    # WORDPRESS KONFIGURATSIOON
    # --------------------------------------------------------

    WP_CONFIG_RESULT=$(
        ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
        "if [[ -f '$WP_CONFIG' ]]; then echo EXISTS; else echo MISSING; fi"
    )

    if [[ "$WP_CONFIG_RESULT" == "EXISTS" ]]; then

        ok "wp-config.php olemas"
        info "$WP_CONFIG"

    else

        fail "wp-config.php puudub"
        info "Oodatud: $WP_CONFIG"

    fi

    # --------------------------------------------------------
    # WORDPRESS ANDMEBAASI SEADED
    # --------------------------------------------------------

    separator
    echo "WORDPRESS → MARIADB"

    if [[ "$WP_CONFIG_RESULT" == "EXISTS" ]]; then

        WP_DB_NAME=$(
            ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
            "sudo grep -E \"define\\([[:space:]]*['\\\"]DB_NAME['\\\"]\" '$WP_CONFIG' 2>/dev/null |
             sed -E \"s/.*DB_NAME['\\\"]?[[:space:]]*,[[:space:]]*['\\\"]([^'\\\"]+).*/\\1/\""
        )

        WP_DB_USER=$(
            ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
            "sudo grep -E \"define\\([[:space:]]*['\\\"]DB_USER['\\\"]\" '$WP_CONFIG' 2>/dev/null |
             sed -E \"s/.*DB_USER['\\\"]?[[:space:]]*,[[:space:]]*['\\\"]([^'\\\"]+).*/\\1/\""
        )

        WP_DB_HOST=$(
            ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
            "sudo grep -E \"define\\([[:space:]]*['\\\"]DB_HOST['\\\"]\" '$WP_CONFIG' 2>/dev/null |
             sed -E \"s/.*DB_HOST['\\\"]?[[:space:]]*,[[:space:]]*['\\\"]([^'\\\"]+).*/\\1/\""
        )

        echo "WordPress wp-config.php väärtused:"
        echo "       DB_NAME: ${WP_DB_NAME:-PUUDUB}"
        echo "       DB_USER: ${WP_DB_USER:-PUUDUB}"
        echo "       DB_HOST: ${WP_DB_HOST:-PUUDUB}"

        if [[ "$WP_DB_NAME" == "$DB_NAME_EXPECTED" ]]; then

            ok "WordPress DB_NAME on õige"

        else

            fail "WordPress DB_NAME on vale"
            info "Tegelik: ${WP_DB_NAME:-PUUDUB}"
            info "Oodatud: $DB_NAME_EXPECTED"

        fi

        if [[ "$WP_DB_USER" == "$DB_USER_EXPECTED" ]]; then

            ok "WordPress DB_USER on õige"

        else

            fail "WordPress DB_USER on vale"
            info "Tegelik: ${WP_DB_USER:-PUUDUB}"
            info "Oodatud: $DB_USER_EXPECTED"

        fi

        if [[ "$WP_DB_HOST" == "$EXPECTED_DNS_DB" ||
              "$WP_DB_HOST" == "${EXPECTED_DNS_DB}:3306" ]]; then

            ok "WordPress DB_HOST viitab serverile .25"

        else

            fail "WordPress DB_HOST on vale"
            info "Tegelik: ${WP_DB_HOST:-PUUDUB}"
            info "Oodatud: $EXPECTED_DNS_DB"

        fi

    fi

    # --------------------------------------------------------
    # APACHE VIRTUAL HOST
    # --------------------------------------------------------

    separator
    echo "APACHE VIRTUAL HOST"

    VHOST_RESULT=$(
        ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
        'sudo apache2ctl -S 2>&1 || true'
    )

    echo "$VHOST_RESULT" |
        grep -F "$DOMAIN_WP" |
        sed 's/^/       /' || true

    if echo "$VHOST_RESULT" |
        grep -Fq "$DOMAIN_WP"; then

        ok "Apache VirtualHost sisaldab $DOMAIN_WP"

    else

        fail "Apache VirtualHost domeenile $DOMAIN_WP puudub"
        info "Kontrollitud apache2ctl -S väljundit"

    fi

    # --------------------------------------------------------
    # HTTP .20
    # --------------------------------------------------------

    separator
    echo "WORDPRESS HTTP"

    HTTP_RESULT=$(
        curl -s \
        -o /dev/null \
        -w '%{http_code}' \
        --max-time 5 \
        -H "Host: $DOMAIN_WP" \
        "http://${EXPECTED_WEB}/" \
        2>/dev/null
    )

    echo "HTTP staatus:"
    echo "       Tegelik: ${HTTP_RESULT:-PUUDUB}"

    if [[ "$HTTP_RESULT" == "200" ||
          "$HTTP_RESULT" == "301" ||
          "$HTTP_RESULT" == "302" ||
          "$HTTP_RESULT" == "303" ]]; then

        ok "WordPress HTTP vastab"

    else

        fail "WordPress HTTP ei vasta korrektselt"
        info "Oodatud HTTP staatus: 200/301/302/303"

    fi

    # --------------------------------------------------------
    # WORDPRESS FAILIDE ÕIGUSED
    # --------------------------------------------------------

    separator
    echo "WORDPRESS ÕIGUSED"

    WP_OWNER=$(
        ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
        "sudo stat -c '%U:%G' '$DOCROOT' 2>/dev/null || true"
    )

    echo "Document root omanik:"
    echo "       ${WP_OWNER:-PUUDUB}"

    if [[ -n "$WP_OWNER" ]]; then

        if [[ "$WP_OWNER" == "www-data:www-data" ]]; then

            ok "WordPress document root kuulub www-data kasutajale"

        else

            warn "WordPress document root omanik erineb oodatust"
            info "Tegelik: $WP_OWNER"
            info "Oodatud: www-data:www-data"

        fi

    fi

fi

# ============================================================
# WORDPRESS DNS
# ============================================================

separator
echo "WORDPRESS DOMEEN + DNS"

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
