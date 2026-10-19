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


#!/usr/bin/env bash
set -Eeuo pipefail

# HKHK Debian-labori automaatne kontroll ja üleslaadimine
# Kasutamine:
#   sudo /usr/local/bin/hkhk-saada-tulemused.sh Debian1
#   sudo /usr/local/bin/hkhk-saada-tulemused.sh Debian2

SERVER_URL="http://192.168.124.64:5050/api/report"

# Sama väärtus peab olema Flaski serveri UPLOAD_TOKEN muutujas.
UPLOAD_TOKEN="fe67bb5eaa9d9e96d69aa2a0f8982ae7a56138ce1bbeb65291eb763dc8ab8210"

REPORT_DIR="/var/tmp/hkhk-report"

if [[ $EUID -ne 0 ]]; then
    echo "Käivita skript sudo abil."
    exit 1
fi

if [[ $# -ne 1 || ( "$1" != "Debian1" && "$1" != "Debian2" ) ]]; then
    echo "Kasutamine: $0 Debian1|Debian2"
    exit 1
fi

MACHINE="$1"

read -r -p "Õpilase ees- ja perekonnanimi: " STUDENT
STUDENT="${STUDENT#"${STUDENT%%[![:space:]]*}"}"
STUDENT="${STUDENT%"${STUDENT##*[![:space:]]}"}"

if [[ -z "$STUDENT" ]]; then
    echo "VIGA: nimi on kohustuslik."
    exit 1
fi

for cmd in python3 curl systemctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "VIGA: vajalik käsk puudub: $cmd"
        exit 1
    fi
done

CHECKS='[]'

add_check() {
    CHECKS="$CHECKS" ID="$1" DESCRIPTION="$2" \
    EXPECTED="$3" ACTUAL="$4" PASSED="$5" \
    python3 -c '
import json, os
checks = json.loads(os.environ["CHECKS"])
checks.append({
    "id": os.environ["ID"],
    "description": os.environ["DESCRIPTION"],
    "expected": os.environ["EXPECTED"],
    "actual": os.environ["ACTUAL"],
    "passed": os.environ["PASSED"] == "true"
})
print(json.dumps(checks, ensure_ascii=False))
' > /tmp/hkhk-checks.json
    CHECKS="$(cat /tmp/hkhk-checks.json)"
}

check_service() {
    local service="$1"
    local state="inactive"

    systemctl is-active --quiet "$service" && state="active" || true

    if [[ "$state" == "active" ]]; then
        add_check "$service" "$service teenus" "active" "$state" true
    else
        add_check "$service" "$service teenus" "active" "$state" false
    fi
}

case "$MACHINE" in
    Debian1)
        check_service apache2

        if command -v php >/dev/null 2>&1; then
            PHP_VERSION="$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)"
        else
            PHP_VERSION=""
        fi

        if [[ -n "$PHP_VERSION" ]]; then
            add_check php "PHP on paigaldatud" "olemas" "$PHP_VERSION" true
        else
            add_check php "PHP on paigaldatud" "olemas" "puudub" false
        fi

        WP_CONFIG="/var/www/html/wp-config.php"
        if [[ -f "$WP_CONFIG" ]]; then
            add_check wp_config "WordPressi konfiguratsioon" \
                "$WP_CONFIG olemas" "olemas" true
        else
            add_check wp_config "WordPressi konfiguratsioon" \
                "$WP_CONFIG olemas" "puudub" false
        fi
        ;;
    Debian2)
        check_service mariadb
        check_service bind9

        if command -v mariadb >/dev/null 2>&1; then
            DB_RESULT="$(mariadb -N -B -e \
                "SHOW DATABASES LIKE 'kolmasdomeen_db';" 2>/dev/null || true)"
        else
            DB_RESULT=""
        fi

        if [[ "$DB_RESULT" == "kolmasdomeen_db" ]]; then
            add_check db "WordPressi andmebaas" \
                "kolmasdomeen_db" "$DB_RESULT" true
        else
            add_check db "WordPressi andmebaas" \
                "kolmasdomeen_db" "${DB_RESULT:-puudub või ligipääs puudub}" false
        fi

        if command -v named-checkconf >/dev/null 2>&1 &&
           named-checkconf >/dev/null 2>&1; then
            add_check bind_config "BIND9 konfiguratsioon" "korras" "korras" true
        else
            add_check bind_config "BIND9 konfiguratsioon" "korras" "viga" false
        fi
        ;;
esac

mkdir -p "$REPORT_DIR"
chmod 700 "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/${MACHINE}.json"

STUDENT="$STUDENT" MACHINE="$MACHINE" CHECKS="$CHECKS" \
REPORT_FILE="$REPORT_FILE" python3 - <<'PY'
import json, os
from datetime import datetime, timezone

report = {
    "student": os.environ["STUDENT"],
    "machine": os.environ["MACHINE"],
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "checks": json.loads(os.environ["CHECKS"])
}

with open(os.environ["REPORT_FILE"], "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)

print(f"Raport koostatud: {os.environ['REPORT_FILE']}")
PY

echo "Saadan tulemused dashboardile..."

HTTP_CODE="$(
    curl --silent --show-error \
        --connect-timeout 5 --max-time 20 \
        -o /tmp/hkhk-upload-response.json \
        -w '%{http_code}' \
        -X POST "$SERVER_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $UPLOAD_TOKEN" \
        --data-binary "@$REPORT_FILE"
)" || {
    echo "VIGA: dashboard pole kättesaadav."
    echo "Raport jäi alles: $REPORT_FILE"
    exit 1
}

cat /tmp/hkhk-upload-response.json
echo

if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
    echo "OK: $MACHINE tulemused üles laaditud."
else
    echo "VIGA: üleslaadimine ebaõnnestus (HTTP $HTTP_CODE)."
    exit 1
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
