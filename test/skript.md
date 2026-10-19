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

# HKHK tulemuste üleslaadimine Flaski dashboardile
SERVER_URL="http://192.168.124.64:5050/api/report"
REPORT_DIR="/var/tmp/hkhk-report"

if [[ $EUID -ne 0 ]]; then
    echo "Käivita skript sudo abil:"
    echo "sudo $0 Debian1"
    echo "sudo $0 Debian2"
    exit 1
fi

if [[ $# -ne 1 || ( "$1" != "Debian1" && "$1" != "Debian2" ) ]]; then
    echo "Kasutamine: sudo $0 Debian1|Debian2"
    exit 1
fi

MACHINE="$1"

read -r -p "Sisesta ees- ja perekonnanimi: " STUDENT
if [[ -z "${STUDENT//[[:space:]]/}" ]]; then
    echo "VIGA: nimi on kohustuslik."
    exit 1
fi

read -r -s -p "Üleslaadimise võti: " UPLOAD_TOKEN
echo
if [[ -z "$UPLOAD_TOKEN" ]]; then
    echo "VIGA: üleslaadimise võti puudub."
    exit 1
fi

mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/${MACHINE}.json"

# Kontrolli tööriistu
for cmd in python3 curl systemctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "VIGA: puudub käsk $cmd"
        exit 1
    fi
done

# Ühised abifunktsioonid
CHECKS='[]'

add_check() {
    local id="$1"
    local description="$2"
    local expected="$3"
    local actual="$4"
    local passed="$5"

    CHECKS=$(
        CHECKS="$CHECKS" ID="$id" DESCRIPTION="$description" \
        EXPECTED="$expected" ACTUAL="$actual" PASSED="$passed" \
        python3 -c '
import json, os
a = json.loads(os.environ["CHECKS"])
a.append({
    "id": os.environ["ID"],
    "description": os.environ["DESCRIPTION"],
    "expected": os.environ["EXPECTED"],
    "actual": os.environ["ACTUAL"],
    "passed": os.environ["PASSED"] == "true"
})
print(json.dumps(a, ensure_ascii=False))
'
    )
}

check_service() {
    local service="$1"
    local description="$2"
    local state="inactive"
    systemctl is-active --quiet "$service" && state="active" || true

    if [[ "$state" == "active" ]]; then
        add_check "$service" "$description" "active" "$state" true
    else
        add_check "$service" "$description" "active" "$state" false
    fi
}

case "$MACHINE" in
    Debian1)
        check_service apache2 "Apache2 veebiserver"
        check_service mariadb "MariaDB teenus (vajaduse korral Debian1 rolli kohanda)"

        php_version="$(php -r 'echo PHP_VERSION;' 2>/dev/null || echo PUUDUB)"
        if [[ "$php_version" != "PUUDUB" ]]; then
            add_check php "PHP on paigaldatud" "PHP olemas" "$php_version" true
        else
            add_check php "PHP on paigaldatud" "PHP olemas" "$php_version" false
        fi

        if [[ -f /var/www/html/wp-config.php ]]; then
            add_check wp_config "WordPressi konfiguratsioon" \
                "/var/www/html/wp-config.php" "olemas" true
        else
            add_check wp_config "WordPressi konfiguratsioon" \
                "/var/www/html/wp-config.php" "puudub" false
        fi
        ;;
    Debian2)
        check_service mariadb "MariaDB andmebaas"
        check_service bind9 "BIND9 nimeserver"

        if command -v mariadb >/dev/null 2>&1; then
            db_result="$(mariadb -N -B -e \
                "SHOW DATABASES LIKE 'kolmasdomeen_db';" 2>/dev/null || true)"
            if [[ "$db_result" == "kolmasdomeen_db" ]]; then
                add_check db "WordPressi andmebaas" \
                    "kolmasdomeen_db" "$db_result" true
            else
                add_check db "WordPressi andmebaas" \
                    "kolmasdomeen_db" "${db_result:-puudub/ligipääs puudub}" false
            fi
        else
            add_check db "MariaDB klient" "paigaldatud" "puudub" false
        fi

        if command -v named-checkconf >/dev/null 2>&1; then
            if named-checkconf >/dev/null 2>&1; then
                add_check bind_config "BIND9 konfiguratsiooni süntaks" \
                    "korras" "korras" true
            else
                add_check bind_config "BIND9 konfiguratsiooni süntaks" \
                    "korras" "viga" false
            fi
        else
            add_check bind_config "BIND9 kontrolltööriist" \
                "named-checkconf" "puudub" false
        fi
        ;;
esac

# Koosta JSON-raport
STUDENT="$STUDENT" MACHINE="$MACHINE" CHECKS="$CHECKS" \
REPORT_FILE="$REPORT_FILE" python3 - <<'PY'
import json, os
from datetime import datetime, timezone

report = {
    "student": os.environ["STUDENT"].strip(),
    "machine": os.environ["MACHINE"],
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "checks": json.loads(os.environ["CHECKS"])
}

with open(os.environ["REPORT_FILE"], "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)

print(json.dumps(report, ensure_ascii=False, indent=2))
PY

echo
echo "Saadan raporti aadressile $SERVER_URL ..."

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
    echo "VIGA: serveriga ei saadud ühendust."
    echo "Kohalik raport: $REPORT_FILE"
    exit 1
}

cat /tmp/hkhk-upload-response.json
echo

if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
    echo "OK: $MACHINE raport saadeti serverisse (HTTP $HTTP_CODE)."
else
    echo "VIGA: üleslaadimine ebaõnnestus (HTTP $HTTP_CODE)."
    echo "Kontrolli Flaski API aadressi, võtit ja serveri logisid."
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
