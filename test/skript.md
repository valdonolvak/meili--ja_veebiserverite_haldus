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

```
```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================================
# HKHK – Debian labori tulemuste kontroll ja üleslaadimine
# Käivitamine:
#   sudo /usr/local/bin/hkhk-saada-tulemused.sh Debian1
#   sudo /usr/local/bin/hkhk-saada-tulemused.sh Debian2
# ==========================================================

DASHBOARD_URL="http://192.168.124.64:5050"
REPORT_DIR="/var/tmp/hkhk-report"

# Pane siia sama võti, mis on Ubuntu dashboardi serveri
# failis /etc/hkhk-dashboard.env.
# Ära jaga seda võtit teistega.
UPLOAD_TOKEN="ASENDA_SIIA_SERVERI_SAMA_64_MARGILINE_VOTI"

MACHINE="${1:-}"

if [[ $EUID -ne 0 ]]; then
    echo "VIGA: käivita skript sudo abil."
    exit 1
fi

if [[ "$MACHINE" != "Debian1" && "$MACHINE" != "Debian2" ]]; then
    echo "Kasutamine:"
    echo "  sudo $0 Debian1"
    echo "  sudo $0 Debian2"
    exit 1
fi

for cmd in python3 curl systemctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "VIGA: puudub käsk $cmd"
        echo "Paigalda see enne skripti käivitamist."
        exit 1
    fi
done

if [[ "$UPLOAD_TOKEN" == "ASENDA_SIIA_SERVERI_SAMA_64_MARGILINE_VOTI" ]]; then
    echo "VIGA: määra skriptis serveriga sama UPLOAD_TOKEN."
    exit 1
fi

read -r -p "Õpilase ees- ja perekonnanimi: " STUDENT_NAME
STUDENT_NAME="$(printf '%s' "$STUDENT_NAME" | xargs)"

if [[ -z "$STUDENT_NAME" ]]; then
    echo "VIGA: õpilase nimi ei tohi olla tühi."
    exit 1
fi

mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/${MACHINE}.json"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

CHECKS_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE" "$CHECKS_FILE"' EXIT

add_check() {
    local id="$1"
    local title="$2"
    local expected="$3"
    local actual="$4"
    local status="$5"

    python3 - "$CHECKS_FILE" "$id" "$title" "$expected" "$actual" "$status" <<'PY'
import json
import sys
from pathlib import Path

path, check_id, title, expected, actual, status = sys.argv[1:]
p = Path(path)

checks = []
if p.exists() and p.stat().st_size:
    checks = json.loads(p.read_text(encoding="utf-8"))

checks.append({
    "id": check_id,
    "title": title,
    "expected": expected,
    "actual": actual,
    "status": status
})

p.write_text(
    json.dumps(checks, ensure_ascii=False, indent=2),
    encoding="utf-8"
)
PY

    if [[ "$status" == "OK" ]]; then
        printf '[OK]  %s — tegelik: %s\n' "$title" "$actual"
    else
        printf '[VIGA] %s — oodatud: %s; tegelik: %s\n' \
            "$title" "$expected" "$actual"
    fi
}

check_service() {
    local service="$1"
    local title="$2"
    local actual status

    if systemctl is-active --quiet "$service"; then
        actual="active"
        status="OK"
    else
        actual="$(systemctl is-active "$service" 2>/dev/null || true)"
        [[ -n "$actual" ]] || actual="inactive/puudub"
        status="FAIL"
    fi

    add_check "$service" "$title" "active" "$actual" "$status"
}

# Alusta tühja kontrollide nimekirjaga.
printf '[]\n' > "$CHECKS_FILE"

echo
echo "=========================================="
echo "HKHK – Debian labori kontroll"
echo "Õpilane: $STUDENT_NAME"
echo "Masin:   $MACHINE"
echo "=========================================="
echo

if [[ "$MACHINE" == "Debian1" ]]; then
    # Debian1: Apache2, PHP ja WordPress
    check_service "apache2" "Apache2 teenus"

    if command -v php >/dev/null 2>&1; then
        php_version="$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)"
        add_check "php" "PHP paigaldus" "PHP paigaldatud" \
            "${php_version:-versioon teadmata}" "OK"
    else
        add_check "php" "PHP paigaldus" "PHP paigaldatud" \
            "PHP puudub" "FAIL"
    fi

    if [[ -f /var/www/html/wp-config.php ]]; then
        add_check "wp-config" "WordPressi konfiguratsioon" \
            "/var/www/html/wp-config.php olemas" "Fail olemas" "OK"
    else
        add_check "wp-config" "WordPressi konfiguratsioon" \
            "/var/www/html/wp-config.php olemas" "Fail puudub" "FAIL"
    fi

    if [[ -f /var/www/html/wp-config.php ]]; then
        add_check "wordpress-files" "WordPressi konfiguratsioonifail" \
            "Fail loetav" \
            "$([[ -r /var/www/html/wp-config.php ]] && echo loetav || echo pole-loetav)" \
            "$([[ -r /var/www/html/wp-config.php ]] && echo OK || echo FAIL)"
    fi

elif [[ "$MACHINE" == "Debian2" ]]; then
    # Debian2: MariaDB, BIND9 ja andmebaas
    check_service "mariadb" "MariaDB teenus"
    check_service "bind9" "BIND9 teenus"

    if command -v mariadb >/dev/null 2>&1; then
        if mariadb -N -e \
            "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='kolmasdomeen_db';" \
            2>/dev/null | grep -qx 'kolmasdomeen_db'; then
            add_check "database" "MariaDB andmebaas" \
                "kolmasdomeen_db olemas" "kolmasdomeen_db olemas" "OK"
        else
            add_check "database" "MariaDB andmebaas" \
                "kolmasdomeen_db olemas" \
                "Andmebaasi ei leitud või ligipääs puudub" "FAIL"
        fi
    else
        add_check "database" "MariaDB andmebaas" \
            "kolmasdomeen_db olemas" "mariadb klient puudub" "FAIL"
    fi

    if command -v named-checkconf >/dev/null 2>&1; then
        if named-checkconf >/dev/null 2>&1; then
            add_check "bind-config" "BIND9 konfiguratsioon" \
                "named-checkconf edukas" "Konfiguratsioon korras" "OK"
        else
            add_check "bind-config" "BIND9 konfiguratsioon" \
                "named-checkconf edukas" "Konfiguratsiooni viga" "FAIL"
        fi
    else
        add_check "bind-config" "BIND9 konfiguratsioon" \
            "named-checkconf olemas" "Käsk puudub" "FAIL"
    fi
fi

# Koosta dashboardile saadetav JSON.
python3 - "$STUDENT_NAME" "$MACHINE" "$CHECKS_FILE" "$TMP_FILE" <<'PY'
import json
import sys
from pathlib import Path

student_name, machine, checks_file, output_file = sys.argv[1:]
checks = json.loads(Path(checks_file).read_text(encoding="utf-8"))

report = {
    "student_name": student_name,
    "machine": machine,
    "checks": checks
}

Path(output_file).write_text(
    json.dumps(report, ensure_ascii=False, indent=2),
    encoding="utf-8"
)
PY

cp "$TMP_FILE" "$REPORT_FILE"

echo
echo "Kohalik raport: $REPORT_FILE"
echo
echo "Saadan tulemused dashboardi..."

# OLULINE PARANDUS:
# Server app.py loeb X-Upload-Token päist.
HTTP_CODE="$(
    curl --silent --show-error \
        --connect-timeout 5 \
        --max-time 20 \
        --output "$REPORT_DIR/response.json" \
        --write-out '%{http_code}' \
        -X POST "$DASHBOARD_URL/api/report" \
        -H "Content-Type: application/json" \
        -H "X-Upload-Token: $UPLOAD_TOKEN" \
        --data-binary "@$REPORT_FILE"
)" || {
    echo "VIGA: dashboardi serveriga ei õnnestunud ühendust luua."
    echo "Kontrolli aadressi: $DASHBOARD_URL"
    exit 1
}

echo "HTTP vastus: $HTTP_CODE"

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    echo "Tulemused saadeti edukalt dashboardi."
    cat "$REPORT_DIR/response.json"
    echo
else
    echo "VIGA: tulemuste üleslaadimine ebaõnnestus."
    echo "Serveri vastus:"
    cat "$REPORT_DIR/response.json" 2>/dev/null || true
    echo
    echo "Kohalik raport on alles: $REPORT_FILE"
    exit 1
fi
```



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
