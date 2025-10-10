Kindlasti! Serverite seadistamisel tekib alati väikseid vigu. Siin on põhjalik tõrkeotsingu (Troubleshooting) juhend, mis katab kõik peamised probleemid, mis võivad Apache2, MariaDB ja WordPressi virtual host'ide seadistamisel Debianis ette tulla.

---

## Tõrkeotsing: Apache2, MariaDB ja WordPress Virtual Host'id

### 1. Üldised Veebiserveri Probleemid (Apache2)

Need vead ilmnevad tavaliselt siis, kui proovite brauseris avada `http://minuleht.local` või `http://uusleht.local`.

#### Viga 1.1: Ei saa ühenduda / Veebisait ei avane

See on tihti hosts-faili või tulemüüri viga.

| Sümptom | Tõrkeotsing ja Lahendus | Selgitus |
| :--- | :--- | :--- |
| Brauser näitab **"Ei saa ühendust luua"** või **"Lehekülge ei leitud"** (kuid mitte 404). | **A. Kontrolli hosts-faili:** Veendu, et sinu lokaalse arvuti hosts-failis on serveri **õige IP-aadress** märgitud `minuleht.local` ja `uusleht.local` jaoks. **B. Kontrolli tulemüüri:** Kui serveril on UFW või muu tulemüür, veendu, et **port 80 (HTTP)** ja **port 443 (HTTPS)** on lubatud. Käsk UFW-s: `sudo ufw allow 'Apache Full'` või `sudo ufw allow 80/tcp`. **C. Kontrolli Apache2 staatust:** Veendu, et Apache2 teenus töötab: `sudo systemctl status apache2`. | Ühenduse loomine ebaõnnestub kas seetõttu, et su arvuti ei tea, kuhu minna (hosts-fail), või et server blokeerib päringu (tulemüür). |

#### Viga 1.2: Näete Apache'i Vaikimisi Tervituslehte

Näete lehte "It works!" või "Apache2 Debian Default Page".

| Sümptom | Tõrkeotsing ja Lahendus | Selgitus |
| :--- | :--- | :--- |
| Sisestate `minuleht.local`, kuid näete vaikimisi lehte. | **A. Virtual Host'ide lubamine:** Tõenäoliselt on ununenud lubada oma saidi konfiguratsioonifailid ja keelata vaikimisi fail. Kontrolli uuesti: `sudo a2ensite minuleht.local.conf` ja `sudo a2dissite 000-default.conf`. **B. Apache2 taaskäivitamine:** Pärast muudatusi veendu, et server on uuesti laetud: `sudo systemctl reload apache2`. | Kui vaikimisi konfiguratsioon (000-default) on lubatud, võib see Apache'i seadistuse ees püüda kõik päringud. |

#### Viga 1.3: Näete 403 Forbidden Viga

| Sümptom | Tõrkeotsing ja Lahendus | Selgitus |
| :--- | :--- | :--- |
| Server on leitav, kuid näitab **403 Forbidden** viga. | **A. Õiguste kontroll:** See on klassikaline failiõiguste viga. Kontrolli, kas veebiserveri kasutajal **`www-data`** on juurkataloogile ligipääs: `sudo chown -R www-data:www-data /var/www/minuleht.local/`. **B. Directory Directiiv:** Veendu, et sinu virtual host konfiguratsioonis on **`<Directory ...>`** plokk ja see sisaldab **`Require all granted`**. | Apache2 ei luba ligipääsu kataloogile, kuna tal puuduvad lugemisõigused või konfiguratsioonis pole lubatud ligipääsu. |

---

### 2. WordPressi ja PHP Probleemid

Need vead tekivad pärast seda, kui olete brauseris saidi avanud ja näete PHP või andmebaasiga seotud tõrkeid.

#### Viga 2.1: Näete veateadet "Error establishing a database connection"

See on kõige levinum WordPressi viga, mis viitab valedele andmebaasi seadetele.

| Sümptom | Tõrkeotsing ja Lahendus | Selgitus |
| :--- | :--- | :--- |
| WordPressi installi käivitades või lehte külastades ilmneb veateade. | **A. Kontrolli `wp-config.php`:** Avage fail `sudo nano /var/www/minuleht.local/html/wp-config.php` ja kontrolli hoolikalt: **DB_NAME**, **DB_USER** ja **DB_PASSWORD**. Isegi väike trükiviga on fataalne. **B. Kontrolli MariaDB staatust:** Veendu, et andmebaasiserver töötab: `sudo systemctl status mariadb`. **C. Kontrolli kasutajat MariaDB-s:** Logi sisse MariaDB-sse ja proovi sisse logida loodud kasutajana: `mysql -u minuadmin -p`. Kui see ebaõnnestub, pead looma kasutaja uuesti. | WordPress proovib ühenduda andmebaasiga, kuid pakutud parool, kasutaja või andmebaas on vigane või andmebaasiserver ei tööta. |

#### Viga 2.2: Näete PHP Koodi või Faili Allalaadimise Akent

| Sümptom | Tõrkeotsing ja Lahendus | Selgitus |
| :--- | :--- | :--- |
| Brauser näitab WordPressi saidi asemel puhast PHP koodi või proovib `index.php` faili alla laadida. | **A. PHP mooduli kontroll:** Apache2 ei töötle PHP-d. Veendu, et **`libapache2-mod-php`** on paigaldatud ja lubatud. **B. Taaskäivitamine:** Pärast mooduli installi pead Apache2 taaskäivitama: `sudo systemctl restart apache2`. | See tähendab, et veebiserver näeb PHP-faili, kuid ei tea, kuidas seda töödelda (st puudub PHP moodul või see pole lubatud). |

#### Viga 2.3: Püsiviited (Permalinks) Ei Tööta / Näete 404 Viga Postitustel

See ilmneb pärast WordPressi installimist ja püsiviidete muutmist halduspaneelis.

| Sümptom | Tõrkeotsing ja Lahendus | Selgitus |
| :--- | :--- | :--- |
| Kodu leht töötab, kuid postituste linkidel klikkides saate **404 Not Found** vea. | **A. `rewrite` moodul:** Veendu, et `rewrite` moodul on lubatud: `sudo a2enmod rewrite` ja `sudo systemctl reload apache2`. **B. `AllowOverride All`:** Kontrolli, et sinu virtual host konfiguratsioonis on **`<Directory ...>`** plokis olemas rida **`AllowOverride All`**. | Püsiviited sõltuvad Apache'i võimest kasutada **`.htaccess`** faili ja ümber kirjutamise reegleid (mod\_rewrite), et suunata puhtad URL-id (`/minu-postitus/`) tegelikule PHP skriptile. |

---

### 3. Failide Üleslaadimise ja Uuendamise Probleemid

Need vead tekivad WordPressi halduspaneelis (wp-admin).

#### Viga 3.1: Pluginate, Teemade või Tuumauuenduste Ebaõnnestumine

| Sümptom | Tõrkeotsing ja Lahendus | Selgitus |
| :--- | :--- | :--- |
| WordPress küsib FTP andmeid või ei suuda faile alla laadida/kirjutada. | **A. Omaniku õigused:** See on peaaegu alati seotud **failiõigustega**. Veendu, et veebiserveri kasutaja (`www-data`) on WordPressi failide omanik: `sudo chown -R www-data:www-data /var/www/minuleht.local/`. **B. Kaustade õigused:** Veendu, et kaustadel on kirjutamisõigused: `sudo find /var/www/minuleht.local/html -type d -exec chmod 755 {} \;`. | Kui veebiserver ei saa kirjutada, ei saa WordPress installida ega uuendada. Paroolide küsimine tähendab, et WordPress proovib kasutada FTP-d, kuna tal puuduvad otsesed kirjutamisõigused. |

---

### Tõrkeotsingu Meelespea

Kui probleem tekib, järgige seda kontrollnimekirja:

1.  **Kas ports on avatud?** (Tulemüür UFW / iptables)
2.  **Kas teenus töötab?** (`sudo systemctl status apache2` ja `sudo systemctl status mariadb`)
3.  **Kas domeeninimi suunab õigesse kohta?** (Lokaalne hosts-fail ja Apache'i logid)
4.  **Kas Apache'i konfiguratsioon on süntaktiliselt õige?** (`sudo apache2ctl configtest`)
5.  **Kas PHP töötab?** (Looge saidi juurkataloogi `info.php` fail sisuga `<?php phpinfo(); ?>` ja proovige seda avada. Kui näete PHP infot, töötab PHP õigesti.)
6.  **Kas `wp-config.php` on 100% õige?** (Kontrolli DB nime, kasutajat ja parooli.)
7.  **Kas failiõigused on `www-data`-le antud?** (Apache'i kirjutamisõigused on kõige sagedasem viga.)
