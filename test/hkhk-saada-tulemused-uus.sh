#!/bin/bash

# hkhk-saada-tulemused.sh - Täiendatud versioon osalise hindamisega (25%, 50%, 75%, 100%)
SERVER_URL="http://192.168.124.64:5050/api/upload" # Kohanda see õigeks Flask endpointiks
USER_NAME=$(whoami)
HOST_NAME=$(hostname)

# Algseadistame JSON massiivi
RESULTS_JSON="["
TOTAL_SCORE=0
MAX_SCORE=0

# Abifunktsioon JSON-i kirje lisamiseks
add_result() {
    local task_name="$1"
    local expected="$2"
    local actual="$3"
    local score="$4"
    local summary="$5"
    
    # Eemaldame reavahetused ja jutumärgid teksti seest JSON-i rikkumise vältimiseks
    actual=$(echo "$actual" | tr -d '"' | tr '
' ' ')
    summary=$(echo "$summary" | tr -d '"' | tr '
' ' ')
    
    if [ "$RESULTS_JSON" != "[" ]; then
        RESULTS_JSON="$RESULTS_JSON,"
    fi
    
    RESULTS_JSON="$RESULTS_JSON {
        "nimi": "$task_name",
        "noutud": "$expected",
        "tegelik": "$actual",
        "skoor": $score,
        "kokkuvote": "$summary"
    }"
    
    TOTAL_SCORE=$((TOTAL_SCORE + score))
    MAX_SCORE=$((MAX_SCORE + 100))
}

echo "Kogume andmeid serverist: $HOST_NAME"

# ==========================================
# KONTROLLID (Näidised piltide põhjal)
# ==========================================

if [[ "$HOST_NAME" == *"debian1"* || "$HOST_NAME" == *"web"* ]]; then
    # 1. Apache teenus
    TASK="Apache2 teenus"
    EXPECTED="active"
    ACTUAL=$(systemctl is-active apache2)
    if [ "$ACTUAL" == "active" ]; then
        add_result "$TASK" "$EXPECTED" "$ACTUAL" 100 "Apache jookseb korrektselt."
    elif systemctl status apache2 | grep -q "inactive"; then
        add_result "$TASK" "$EXPECTED" "inactive (peatatud)" 50 "Apache on paigaldatud, kuid pole käivitatud."
    else
        add_result "$TASK" "$EXPECTED" "puudub/viga" 0 "Apache ei ole paigaldatud või on tõsises veas."
    fi

    # 2. WordPress DB_HOST (Osalise hinde näide)
    TASK="WordPress DB_HOST (wordpress)"
    EXPECTED="10.0.10.25 (või teise serveri IP)"
    # Eeldame, et leiame wp-config.php faili
    WP_CONFIG="/var/www/html/wordpress/wp-config.php"
    if [ -f "$WP_CONFIG" ]; then
        ACTUAL=$(grep "'DB_HOST'" "$WP_CONFIG" | cut -d "'" -f 4)
        if [[ "$ACTUAL" == *"10.0."* ]]; then
            add_result "$TASK" "$EXPECTED" "$ACTUAL" 100 "Andmebaasi host on õigesti suunatud teise serveri IP-le."
        elif [ "$ACTUAL" == "localhost" ]; then
            add_result "$TASK" "$EXPECTED" "$ACTUAL" 25 "Andmebaasi host on jäänud localhosti peale, kaugühendust ei teki."
        else
            add_result "$TASK" "$EXPECTED" "$ACTUAL" 50 "Host on määratud, kuid IP tundub vale."
        fi
    else
        add_result "$TASK" "$EXPECTED" "Faili ei leitud" 0 "wp-config.php faili ei eksisteeri."
    fi

elif [[ "$HOST_NAME" == *"debian2"* || "$HOST_NAME" == *"db"* ]]; then
    # 1. MariaDB teenus
    TASK="MariaDB teenus"
    EXPECTED="active"
    ACTUAL=$(systemctl is-active mariadb)
    if [ "$ACTUAL" == "active" ]; then
        add_result "$TASK" "$EXPECTED" "$ACTUAL" 100 "MariaDB jookseb korrektselt."
    else
        add_result "$TASK" "$EXPECTED" "$ACTUAL" 0 "MariaDB ei tööta."
    fi
    
    # 2. MariaDB bind-address
    TASK="MariaDB bind-address"
    EXPECTED="0.0.0.0 või spetsiifiline IP (kaugühendus lubatud)"
    ACTUAL=$(grep -E "^bind-address" /etc/mysql/mariadb.conf.d/50-server.cnf | awk '{print $3}')
    if [ "$ACTUAL" == "127.0.0.1" ]; then
        add_result "$TASK" "$EXPECTED" "$ACTUAL" 0 "Bind-address on 127.0.0.1, kaugühendused on blokeeritud."
    elif [ -z "$ACTUAL" ]; then
        add_result "$TASK" "$EXPECTED" "Kommenteeritud/Puudub" 50 "Bind-address rida on puudu, võib töötada, aga pole korrektselt defineeritud."
    else
        add_result "$TASK" "$EXPECTED" "$ACTUAL" 100 "Bind-address võimaldab kaugühendusi."
    fi
else
    echo "Tundmatu masin. Ei oska kontrolle käivitada."
    exit 1
fi

RESULTS_JSON="$RESULTS_JSON]"

# Arvutame koondprotsendi
if [ $MAX_SCORE -gt 0 ]; then
    TOTAL_PERCENT=$(( (TOTAL_SCORE * 100) / MAX_SCORE ))
else
    TOTAL_PERCENT=0
fi

# Serveri-sisene lühike kokkuvõte
SERVER_SUMMARY="Selles serveris saavutati $TOTAL_PERCENT%. Ülesannete täitmisel esines "
if [ $TOTAL_PERCENT -eq 100 ]; then
    SERVER_SUMMARY="Suurepärane töö! Kõik selle serveri seadistused on korrektsed (100%)."
elif [ $TOTAL_PERCENT -ge 75 ]; then
    SERVER_SUMMARY="Suurem osa ($TOTAL_PERCENT%) on õigesti tehtud, kuid mõned väikesed seadistused vajavad tähelepanu."
elif [ $TOTAL_PERCENT -ge 50 ]; then
    SERVER_SUMMARY="Pool tööst ($TOTAL_PERCENT%) on tehtud. Kontrolli üle teenuste seadistused ja IP-aadressid."
else
    SERVER_SUMMARY="Enamik nõudeid on täitmata ($TOTAL_PERCENT%). Palun vaata juhendit uuesti ja alusta baasseadistustest."
fi

# Loome lõpliku JSON payload'i
JSON_PAYLOAD=$(cat <<EOF
{
  "opilane": "$USER_NAME",
  "masin": "$HOST_NAME",
  "koond_protsent": $TOTAL_PERCENT,
  "serveri_kokkuvote": "$SERVER_SUMMARY",
  "tulemused": $RESULTS_JSON
}
EOF
)

# Salvestame JSON-i korraks faili (debugimiseks)
echo "$JSON_PAYLOAD" > result.json

# Saadame Flask serverisse
echo "Saadan andmed serverisse $SERVER_URL..."
curl -X POST -H "Content-Type: application/json" -d @result.json "$SERVER_URL"

echo "Valmis!"
