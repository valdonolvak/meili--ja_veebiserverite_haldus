Juhend on jaotatud kaheks osaks. 
Esmalt Apache2 seadistamine koos testimisega HTML-lehtedega, ja seejärel WordPressi paigaldamine koos andmebaaside loomisega.

**Tähtis eelteade:** See juhend eeldab, et oled sisse logitud **root-kasutajana** või kasutad käskude ees eesliidet **`sudo`**. Asenda kõik näidisparoolid (`tugevparool123`) oma turvaliste paroolidega.

-----

## Osa 1: Apache2 Veebiserveri ja Virtual Host'ide seadistamine ning testimine 🛠️

See osa hõlmab Apache2 paigaldamist, saidikataloogide loomist ja virtual host'ide seadistamist ning testimist lihtsate HTML-lehtedega.

### Samm 1.1: Süsteemi uuendamine ja Apache2 paigaldus

Enne tarkvara paigaldamist uuendame pakettide loendi ja paigaldame veebiserveri.

```bash
# Uuendame pakettide loendi (tagab, et paigaldatakse uusim versioon)
sudo apt update

# Paigaldame Apache2 veebiserveri
sudo apt install apache2 -y

# Käivitame Apache2 teenuse ja seadistame selle automaatselt käivituma
sudo systemctl start apache2
sudo systemctl enable apache2
```

  * **Kommentaar:** Apache2 on üks maailma populaarsemaid veebiservereid. **`systemctl enable apache2`** tagab, et veebiserver käivitub automaatselt iga kord, kui server taaskäivitub.

### Samm 1.2: Veebikataloogide struktuuri loomine

Loome eraldi juurkataloogid mõlemale virtual host'le kataloogi `/var/www/` alla. See on standardne koht veebisaitide hoidmiseks Debianis.

```bash
# Loome juurkataloogid
sudo mkdir -p /var/www/minuleht.local/html
sudo mkdir -p /var/www/uusleht.local/html
```

  * **Kommentaar:** Kasutame alamkataloogi **`/html`**, et eraldada veebisisu teistest võimalikest saidiga seotud failidest (nt logid või privaatsed skriptid), kuigi see pole kohustuslik.

### Samm 1.3: Loome test-HTML-lehed

Loome kummalegi saidile lihtsa **`index.html`** faili, et saaksime hiljem testida, kas virtual host'id töötavad õigesti.

#### minuleht.local testleht

```bash
sudo sh -c 'echo "<html><body><h1>Tere tulemast lehele minuleht.local!</h1><p>Apache2 virtual host töötab.</p></body></html>" > /var/www/minuleht.local/html/index.html'
```

#### uusleht.local testleht

```bash
sudo sh -c 'echo "<html><body><h1>Tere tulemast lehele uusleht.local!</h1><p>Apache2 virtual host töötab.</p></body></html>" > /var/www/uusleht.local/html/index.html'
```

### Samm 1.4: Virtual Host'ide konfiguratsioonifailide loomine

Loome Apache2 jaoks konfiguratsioonifailid kataloogi **`/etc/apache2/sites-available/`**.

#### minuleht.local konfiguratsioon

Loome faili **`/etc/apache2/sites-available/minuleht.local.conf`**:

```bash
sudo nano /etc/apache2/sites-available/minuleht.local.conf
```

Lisa järgmine sisu:

```apache
<VirtualHost *:80>
    ServerAdmin webmaster@minuleht.local
    ServerName minuleht.local
    # ServerAlias www.minuleht.local  # Lisa see rida, kui soovid toetada ka www eesliidet
    DocumentRoot /var/www/minuleht.local/html

    <Directory /var/www/minuleht.local/html>
        Options Indexes FollowSymLinks
        AllowOverride All  # Vajalik Wordpressi jaoks (püsiviited)
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/minuleht.local_error.log
    CustomLog ${APACHE_LOG_DIR}/minuleht.local_access.log combined
</VirtualHost>
```

#### uusleht.local konfiguratsioon

Loome faili **`/etc/apache2/sites-available/uusleht.local.conf`**:

```bash
sudo nano /etc/apache2/sites-available/uusleht.local.conf
```

Lisa järgmine sisu:

```apache
<VirtualHost *:80>
    ServerAdmin webmaster@uusleht.local
    ServerName uusleht.local
    DocumentRoot /var/www/uusleht.local/html

    <Directory /var/www/uusleht.local/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/uusleht.local_error.log
    CustomLog ${APACHE_LOG_DIR}/uusleht.local_access.log combined
</VirtualHost>
```

  * **Kommentaar:** **`<VirtualHost *:80>`** ütleb Apache'ile, et see konfiguratsioon kehtib kõigi pordile 80 (HTTP) saabuvate päringute puhul. **`ServerName`** määratleb, millisele domeeninimele see konfiguratsioon reageerib. **`DocumentRoot`** on veebisaidi juurkataloog.

### Samm 1.5: Virtual Host'ide lubamine ja testimine

Nüüd anname Apache'ile käsu uute konfiguratsioonide kasutamiseks ja testime süntaksit.

```bash
# Keelame vaikimisi saidi (000-default.conf), et vältida konflikte
sudo a2dissite 000-default.conf

# Lubame uued saidid
sudo a2ensite minuleht.local.conf
sudo a2ensite uusleht.local.conf

# Lubame 'rewrite' mooduli (vajalik WordPressi püsiviitade jaoks)
sudo a2enmod rewrite

# Kontrollime Apache'i konfiguratsiooni süntaksit
sudo apache2ctl configtest

# Kui näed "Syntax OK", laadime konfiguratsiooni uuesti
sudo systemctl reload apache2
```

### Samm 1.6: Kohalik domeeni map'imine (Väljaspool serverit)

Et saaksid oma arvutist (brauserist) ligi pääseda domeenidele **minuleht.local** ja **uusleht.local**, pead map'ima need oma serveri IP-aadressile oma lokaalses arvutis hosts-failis.

Oma lokaalses arvutis (mitte Debian serveris):

```bash
# Linux/macOS
sudo nano /etc/hosts

# Windowsis leia C:\Windows\System32\drivers\etc\hosts ja muuda seda administraatorina
```

Lisa järgmised read, asendades **`SINU_SERVERI_IP`** serveri tegeliku IP-aadressiga:

```hosts
SINU_SERVERI_IP    minuleht.local
SINU_SERVERI_IP    uusleht.local
```

### Samm 1.7: Testimine

Ava oma brauseris `http://minuleht.local` ja `http://uusleht.local`. Peaksid nägema vastavaid "Tere tulemast" HTML-lehti, mis kinnitab, et Apache2 ja virtual host'id töötavad korrektselt.

-----


## Osa 2: PHP, MariaDB ja WordPressi paigaldus ja seadistamine 🚀

See osa eeldab, et Apache2 ja virtual host'id (minuleht.local, uusleht.local) töötavad ning vastavad juurkataloogid on loodud.

### Samm 2.1: MariaDB ja PHP Paigaldamine

Paigaldame andmebaasiserveri ja WordPressi jaoks vajaliku PHP.

```bash
# Paigaldame MariaDB, PHP ja vajalikud laiendused. 
# -y valik kinnitab paigalduse automaatselt.
sudo apt install mariadb-server php php-mysql php-cli php-curl php-gd php-mbstring php-xml php-zip unzip wget -y
```

  * **Kommentaar:** **`mariadb-server`** on andmebaasiserver, mis salvestab kõik teie WordPressi sisu (postitused, kasutajad, seaded). **`php-mysql`** on PHP laiendus, mis võimaldab PHP-koodil (WordPressi tuum) suhelda MariaDB andmebaasiga. Teised laiendused on vajalikud näiteks piltide töötlemiseks (`php-gd`) või ZIP-failide käitlemiseks.

### Samm 2.2: Andmebaaside loomine

Loome spetsiifilised andmebaasid ja kasutajad vastavalt teie soovidele. See eraldatus on oluline turvalisuse tagamiseks.

```bash
# Logime sisse MariaDB käsureale. Kasutame sudo, kuna vaikimisi on Debianis/Ubuntu's MariaDB juurkasutaja seotud süsteemi juurkasutajaga.
sudo mysql
```

**MariaDB käsureal (`MariaDB [(none)]>`) sisesta järgmised käsud, asendades paroolid:**

```sql
-- 1. minuleht.local andmebaas ja kasutaja
-- CHARACTER SET ja COLLATE on vajalikud, et WordPress toetaks kõiki keeli ja erimärke (sh emotikone).
CREATE DATABASE `minuleht.local` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Loome kasutaja 'minuadmin', kes saab ühenduda ainult localhost'ist, ja seadistame tugeva parooli.
CREATE USER 'minuadmin'@'localhost' IDENTIFIED BY 'tugevparool123_1';

-- Anname kasutajale 'minuadmin' täielikud õigused (ALL PRIVILEGES) loodud andmebaasile.
GRANT ALL PRIVILEGES ON `minuleht.local`.* TO 'minuadmin'@'localhost';

-- 2. uusleht.local andmebaas ja kasutaja
CREATE DATABASE `uusleht.local` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'uusadmin'@'localhost' IDENTIFIED BY 'tugevparool123_2';
GRANT ALL PRIVILEGES ON `uusleht.local`.* TO 'uusadmin'@'localhost';

-- Rakendame uued õigused koheselt. See on alati vajalik peale GRANT või REVOKE käskude kasutamist.
FLUSH PRIVILEGES;

-- Väljumine MariaDB käsurealt
EXIT;
```

### Samm 2.3: WordPressi Allalaadimine ja Failliikumine

Eemaldame eelmises osas loodud test-HTML failid ja asendame need WordPressi failidega.

```bash
# Liigume ajutisse kataloogi
cd /tmp

# Laadime alla WordPressi uusima versiooni
wget https://wordpress.org/latest.tar.gz

# Pakime faili lahti, luues kausta "wordpress"
tar -xzvf latest.tar.gz

# Kopeerime WordPressi failid minuleht.local juurkataloogi
# -R tähendab rekursiivset kopeerimist
sudo cp -R wordpress/* /var/www/minuleht.local/html/

# Kopeerime WordPressi failid uusleht.local juurkataloogi
sudo cp -R wordpress/* /var/www/uusleht.local/html/
```

### Samm 2.4: wp-config.php loomine ja seadistamine ⚠️ (Kriitiline samm)

Iga WordPressi sait vajab oma konfiguratsioonifaili **`wp-config.php`**, mis sisaldab andmebaasi ühenduse detailid. Loome selle koopia abil **`wp-config-sample.php`**.

#### 2.4.1: minuleht.local konfiguratsioon

```bash
# Loome konfiguratsioonifaili minuleht.local jaoks
sudo cp /var/www/minuleht.local/html/wp-config-sample.php /var/www/minuleht.local/html/wp-config.php

# Avame faili redigeerimiseks nano-ga
sudo nano /var/www/minuleht.local/html/wp-config.php
```

Leidke failist järgmised read ja asendage need vastavate andmebaasi detailidega:

```php
// Vanad read:
// define( 'DB_NAME', 'database_name_here' );
// define( 'DB_USER', 'username_here' );
// define( 'DB_PASSWORD', 'password_here' );

// Uued seadistused:
define( 'DB_NAME', 'minuleht.local' );
define( 'DB_USER', 'minuadmin' );
define( 'DB_PASSWORD', 'tugevparool123_1' ); // ASENDA OMA PAROOLIGA
define( 'DB_HOST', 'localhost' ); // MariaDB asub samas serveris

// DB_CHARSET ja DB_COLLATE jätke muutmata, need on juba õigesti.
```

Salvestage ja sulgege fail (vajuta **Ctrl+O**, siis **Enter**, siis **Ctrl+X**).

#### 2.4.2: uusleht.local konfiguratsioon

```bash
# Loome konfiguratsioonifaili uusleht.local jaoks
sudo cp /var/www/uusleht.local/html/wp-config-sample.php /var/www/uusleht.local/html/wp-config.php

# Avame faili redigeerimiseks nano-ga
sudo nano /var/www/uusleht.local/html/wp-config.php
```

Leidke failist samad read ja asendage need teise saidi detailidega:

```php
// Uued seadistused:
define( 'DB_NAME', 'uusleht.local' );
define( 'DB_USER', 'uusadmin' );
define( 'DB_PASSWORD', 'tugevparool123_2' ); // ASENDA OMA PAROOLIGA
define( 'DB_HOST', 'localhost' );
```

Salvestage ja sulgege fail.

### Samm 2.5: Failiõiguste Seadistamine

Veendume, et veebiserveri kasutaja **`www-data`** (keda Apache2 kasutab) on failide omanik. See on oluline, et WordPress saaks faile kirjutada ja uuendusi paigaldada.

```bash
# Määrame omanikuks veebiserveri kasutaja (www-data)
sudo chown -R www-data:www-data /var/www/minuleht.local/
sudo chown -R www-data:www-data /var/www/uusleht.local/

# Määrame kaustadele õigused 755 ja failidele 644 (standardne turvaline seadistus)
# Kataloogidele 755: omanik saab lugeda/kirjutada/käivitada, teised saavad lugeda/käivitada.
sudo find /var/www/minuleht.local/html -type d -exec chmod 755 {} \;
sudo find /var/www/uusleht.local/html -type d -exec chmod 755 {} \;

# Failidele 644: omanik saab lugeda/kirjutada, teised saavad ainult lugeda.
sudo find /var/www/minuleht.local/html -type f -exec chmod 644 {} \;
sudo find /var/www/uusleht.local/html -type f -exec chmod 644 {} \;
```

  * **Kommentaar:** Õigused on turvalisuse jaoks üliolulised. Kui õigused on liiga laiad (nt 777), võib pahavara need ära kasutada. Standardiks on **kaustadele 755** ja **failidele 644**.

### Samm 2.6: Lõplik veebipõhine install

Kuna **`wp-config.php`** on nüüd seadistatud, avage oma brauseris:

1.  `http://minuleht.local`
2.  `http://uusleht.local`

WordPress peaks teid suunama keelevaliku lehele ja seejärel saidi pealkirja, administraatori kasutajanime ja parooli seadmise lehele. Andmebaasi detailide leht jääb nüüd vahele, sest need on juba failis `wp-config.php` defineeritud.

Nüüd peaksid olema mõlemad WordPressi lehed on nüüd valmis ja ligipääsetavad.


## Kokkuvõttev osa: Seadistusprotsessi loogika

Kogu seadistusprotsess järgib standardset **LAMP** (Linux, Apache, MariaDB/MySQL, PHP) virna ja on jagatud kolmeks loogiliseks osaks: veebiserveri ülesseadmine, andmebaasi ettevalmistus ja rakenduse (WordPressi) paigaldus.

### 1\. Veebiserveri kiht (Apache2)

| Eesmärk | Tegevus | Olulisus |
| :--- | :--- | :--- |
| **Apache2 Install** | Paigaldada server ja lubada see teenusena. | Veebiserver, mis võtab vastu HTTP-päringud. |
| **Kataloogide loomine** | Luua `/var/www/minuleht.local/html` ja `/var/www/uusleht.local/html`. | Iga saidi sisu peab olema füüsiliselt eraldatud. |
| **Virtual Host'id** | Luua ja lubada **`.conf`** failid (nt `minuleht.local.conf`). | Ütleb Apache'ile, et kui tuleb päring domeenilt `minuleht.local`, näita sisu kataloogist `/var/www/minuleht.local/html`. |
| **`rewrite` moodul** | Lubada moodul `a2enmod rewrite`. | Vajalik WordPressi **püsiviitade** (permalinks) ja suunamisreeglite töötamiseks. |
| **Hosts Faili Muutmine** | Lisada domeenid serveri IP-le lokaalses arvutis. | Testimise eesmärgil simuleerida domeeninime süsteemi (DNS). |

### 2\. Andmebaasi ja PHP kiht

| Eesmärk | Tegevus | Olulisus |
| :--- | :--- | :--- |
| **MariaDB & PHP Install** | Paigaldada MariaDB ja PHP koos `php-mysql` laiendusega. | WordPress on PHP-põhine ja vajab andmete salvestamiseks andmebaasi. |
| **Andmebaasid/Kasutajad**| Luua neli erinevat objekti: `minuleht.local` DB, `minuadmin` USER, `uusleht.local` DB, `uusadmin` USER. | **Turvalisus:** Igal saidil on oma eraldiseisev andmehoidla ja piiratud õigustega kasutaja. |

### 3\. WordPressi rakenduse kiht

| Eesmärk | Tegevus | Olulisus |
| :--- | :--- | :--- |
| **Failide kopeerimine** | Kopeerida WordPressi tuumfailid juurkataloogidesse. | Paigaldada rakendus, mida veebiserver hakkab näitama. |
| **`wp-config.php`** | Luua ja redigeerida see fail kummaski saidikataloogis. | Määrata WordPressi jaoks kriitilised parameetrid, sealhulgas andmebaasi nime, kasutaja ja parooli. **Ilma selleta ei saa WordPress andmebaasiga ühenduda.** |
| **Õiguste seadistus** | Muuta omanikuks **`www-data`** ja seadistada kaustadele 755/failidele 644 õigused. | Lubada WordPressil iseseisvalt faile muuta (uuendused) ja üleslaadimisi vastu võtta. |
| **Veebipõhine install**| Külastada saite brauseris. | Viimane samm, mis seadistab saidi pealkirja, administraatori konto ja lõpetab WordPressi tabelite loomise andmebaasis. |




