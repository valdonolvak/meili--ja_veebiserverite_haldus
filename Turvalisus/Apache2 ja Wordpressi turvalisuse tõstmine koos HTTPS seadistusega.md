---
# Juhend: Turvaline Apache2 ja Kaks WordPressi Virtual Host'i Debianis 🛡️

See juhend seadistab kahele lokaalsele Virtual Host'ile (minuleht.local ja uusleht.local) **HTTPS-i** (ise-allkirjastatud sertifikaadiga) ning rakendab olulised turvaparameetrid.

-----

## 1\. Eeltöö: Süsteemi Ettevalmistamine ja Vundamendi Rajamine 🛠️

See sektsioon tagab vajaliku tarkvara paigalduse ja seab turvalisuse alused.

### Samm 1.1: Süsteemi Värskendamine ja Komponentide Paigaldus

```bash
# Esmalt värskendame kohalikku pakettide registrit. 
# See on esmane turvameede, et tagada uusimate, turvaparandustega versioonide paigaldus.
sudo apt update

# Paigaldame Apache2, MariaDB (andmebaasiserver), PHP koos laiendustega (wordpressile vajalikud) ja OpenSSL (SSL-sertifikaatide loomiseks).
sudo apt install apache2 mariadb-server php libapache2-mod-php php-mysql php-cli php-curl php-gd php-mbstring php-xml php-zip unzip wget openssl -y

# Käivitame teenused ja seadistame need automaatselt käivituma.
sudo systemctl start apache2 mariadb
sudo systemctl enable apache2 mariadb
```

  * **Kommentaar (Tarkvara Roll):** **`libapache2-mod-php`** integreerib PHP otse Apache'iga (nn. LAMP-seadistus). **`php-mysql`** on vältimatu, et WordPress saaks andmebaasiga suhelda. **`openssl`** on kriitiline tööriist ise-allkirjastatud sertifikaadi loomiseks, mida teie VM-keskkond vajab.

### Samm 1.2: Apache'i Üldise Turvalisuse Tugevdamine (Security Headers)

Lisame HTTP vastustele turvapäiseid, mis kaitsevad **brauseripõhiste rünnakute** eest.

```bash
# Avame Apache'i üldise turvakonfiguratsiooni faili
sudo nano /etc/apache2/conf-available/security.conf
```

Lisa/muuda failis järgmisi sätteid:

```apache
# Keelab Apache'i täpse versiooninumbri ja OS info kuvamise veateadetes.
# Ründajal on nii vähem infot spetsiifiliste haavatavuste ärakasutamiseks.
ServerTokens Prod
ServerSignature Off

# Lubame "headers" mooduli, mis on vajalik alltoodud turvapäiste jaoks
<IfModule mod_headers.c>
    # HTTP Strict Transport Security (HSTS): Sunnib brauserit antud domeeni külastama AINULT HTTPS-i kaudu.
    Header always set Strict-Transport-Security "max-age=15768000; includeSubDomains"
    
    # X-Frame-Options SAMEORIGIN: Kaitseb Clickjacking rünnakute eest.
    # See keelab lehe laadimise iframe'ides teistel domeenidel.
    Header always append X-Frame-Options SAMEORIGIN
    
    # X-Content-Type-Options nosniff: Takistab brauserit oletamast failitüüpi.
    # Kaitse MIME-tüübi sniffing'u (XSS) eest.
    Header always set X-Content-Type-Options nosniff
    
    # Content-Security-Policy (CSP): Piirab, kust brauser tohib laadida skripte, stiile jne.
    # See on eluline kaitse Cross-Site Scripting (XSS) rünnakute vastu.
    Header always set Content-Security-Policy "default-src 'self' https: data: 'unsafe-inline' 'unsafe-eval'"
    
    # Referrer-Policy: Määrab, millist infot saata teistele saitidele liikudes.
    Header always set Referrer-Policy "no-referrer-when-downgrade"
</IfModule>
```

Salvesta ja sulge.

-----

## 2\. MariaDB Andmebaaside Loomine ja Turvaline Eraldamine 🗃️

See osa rakendab **väikseima vajaliku privileegi printsiipi** andmebaasi tasandil.

### Samm 2.1: Loo Eraldatud Andmebaasid ja Kasutajad

```bash
sudo mysql
```

**MariaDB käsureal sisesta järgmised käsud:**

```sql
-- 1. minuleht.local andmebaas ja kasutaja
CREATE DATABASE `minuleht.local` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
-- Kasutaja 'minuadmin'@'localhost' saab ühenduda AINULT serverist endast.
CREATE USER 'minuadmin'@'localhost' IDENTIFIED BY 'tugevparool123_1';
-- GRANT ALL PRIVILEGES ON `minuleht.local`.* - Anname õigused AINULT sellele andmebaasile. 
-- See on turvaline viis, sest kui üks sait kompromiteeritakse (nt SQL Injection rünnaku kaudu), 
-- ei saa ründaja automaatselt ligi teise saidi (uusleht.local) andmetele.
GRANT ALL PRIVILEGES ON `minuleht.local`.* TO 'minuadmin'@'localhost';

-- 2. uusleht.local andmebaas ja kasutaja
CREATE DATABASE `uusleht.local` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'uusadmin'@'localhost' IDENTIFIED BY 'tugevparool123_2';
GRANT ALL PRIVILEGES ON `uusleht.local`.* TO 'uusadmin'@'localhost';

FLUSH PRIVILEGES; # Rakendab muudatused koheselt
EXIT;
```

-----

## 3\. Apache2 Virtual Host'ide ja HTTPS-i Seadistus 🌐

Seadistame virtual host'id ja loome ise-allkirjastatud sertifikaadi, mis sobib teie lokaalsete VM-ide jaoks.

### Samm 3.1: Veebikataloogide Loomine ja Sertifikaadi Genereerimine

```bash
# Loome juurkataloogid
sudo mkdir -p /var/www/minuleht.local/html
sudo mkdir -p /var/www/uusleht.local/html

# Loo ise-allkirjastatud sertifikaat, mis kehtib mitmele domeenile (Subject Alternative Name - SAN)
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/local_dev.key \
    -out /etc/ssl/certs/local_dev.crt \
    -subj "/C=EE/ST=Harjumaa/L=Tallinn/O=Local Dev/CN=minuleht.local" \
    -addext "subjectAltName = DNS:minuleht.local, DNS:uusleht.local"
```

  * **Kommentaar:** Lokaalses keskkonnas on **ise-allkirjastatud sertifikaat** ainus viis HTTPS-i saamiseks, kuna Let's Encrypt ei saa valideerida domeene, millel puudub avalik IP. **SAN laiend** on vajalik, et brauserid aktsepteeriksid ühte sertifikaati mõlema domeeni jaoks.

### Samm 3.2: Virtual Host'ide Konfiguratsioon (HTTPS Sunnitud)

Loome failid `/etc/apache2/sites-available/minuleht.local.conf` ja `uusleht.local.conf`.

**Näide `minuleht.local.conf` sisu:**

```bash
sudo nano /etc/apache2/sites-available/minuleht.local.conf
```

```apache
# ----------------------------------------------------
# 1. HTTP PORDIL 80: Ainult ÜMBERSUUNAMINE
# ----------------------------------------------------
<VirtualHost *:80>
    ServerName minuleht.local
    DocumentRoot /var/www/minuleht.local/html
    # RewriteEngine ja RewriteRule sunnivad brauserit kasutama HTTPS-i (püsiv ümbersuunamine)
    RewriteEngine On
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,R=permanent]
</VirtualHost>

# ----------------------------------------------------
# 2. HTTPS PORDIL 443: Tegelik Sisu Serveerimine
# ----------------------------------------------------
<VirtualHost *:443>
    ServerName minuleht.local
    DocumentRoot /var/www/minuleht.local/html

    <Directory /var/www/minuleht.local/html>
        Options Indexes FollowSymLinks
        # AllowOverride All on VÄLTIMATU WordPressi .htaccess faili (püsiviidete) töötlemiseks
        AllowOverride All  
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/minuleht.local_error.log
    CustomLog ${APACHE_LOG_DIR}/minuleht.local_access.log combined

    # Ise-allkirjastatud SSL/TLS SEADISTUSED
    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/local_dev.crt
    SSLCertificateKeyFile /etc/ssl/private/local_dev.key
</VirtualHost>
```

**(Korda sama `uusleht.local.conf` jaoks.)**

### Samm 3.3: Konfiguratsiooni Rakendamine

```bash
# Lubame rewrite mooduli (vajalik ümbersuunamiseks)
sudo a2enmod rewrite

# Keelame vaikimisi saidi ja lubame uued
sudo a2dissite 000-default.conf
sudo a2ensite minuleht.local.conf
sudo a2ensite uusleht.local.conf

# Kontrollime süntaksi ja taaskäivitame Apache'i
sudo apache2ctl configtest
sudo systemctl restart apache2
```

-----

## 4\. WordPressi Turvaline Paigaldus ja Tugevdamine 🚀

### Samm 4.1: WordPressi Failide Paigaldus

```bash
# Kopeerime failid juurkataloogidesse
cd /tmp
wget https://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz

sudo cp -R wordpress/* /var/www/minuleht.local/html/
sudo cp -R wordpress/* /var/www/uusleht.local/html/
```

### Samm 4.2: wp-config.php Seadistamine ja Turvaparameetrid

Loome **`wp-config.php`** faili ja lisame turvaseaded, mis kaitsevad koodi süstimise ja teema muutmise eest.

#### minuleht.local konfiguratsioon (nano kasutades)

```bash
sudo cp /var/www/minuleht.local/html/wp-config-sample.php /var/www/minuleht.local/html/wp-config.php
sudo nano /var/www/minuleht.local/html/wp-config.php
```

Asenda DB detailid ja **lisa järgmised turvaseaded** enne rida `/* That's all, stop editing! Happy publishing. */`:

```php
// ... DB ÜHENDUSE DETAILID ...
define( 'DB_NAME', 'minuleht.local' );
define( 'DB_USER', 'minuadmin' );
define( 'DB_PASSWORD', 'tugevparool123_1' ); 
define( 'DB_HOST', 'localhost' );

// TURVASEADED
// Muudab tabeli eesliidet standardse wp_ asemel juhuslikuks (nt wp_84321_).
// See raskendab SQL Injection rünnakuid, mis eeldavad standardset tabelinime struktuuri.
$table_prefix = 'wp_'.rand(10000, 99999).'_'; 

// DISALLOW_FILE_EDIT: VÄGA TÄHTIS TURVAMEEDE. Keelab administraatori paneelist teema/plugina koodi muutmise.
// Kui ründaja peaks saama administraatorina sisse, ei saa ta otse pahavara süstida.
define( 'DISALLOW_FILE_EDIT', true );

// FORCE_SSL_ADMIN: Sunnib sisselogimise ja admin-paneeli kasutama HTTPS-i.
define( 'FORCE_SSL_ADMIN', true );
```

### Samm 4.3: Failiõiguste Seadistamine ja XML-RPC Keelamine

```bash
# Määrame omanikuks veebiserveri kasutaja (www-data)
sudo chown -R www-data:www-data /var/www/minuleht.local/
sudo chown -R www-data:www-data /var/www/uusleht.local/

# Seadistame turvalised õigused (kaustad 755, failid 644)
sudo find /var/www/minuleht.local/html -type d -exec chmod 755 {} \;
sudo find /var/www/minuleht.local/html -type f -exec chmod 644 {} \;

# XML-RPC keelamine .htaccess faili abil.
echo '
# BLOCK XML-RPC ATTACKS
<Files xmlrpc.php>
Order Deny,Allow
Deny from all
</Files>' | sudo tee -a /var/www/minuleht.local/html/.htaccess
```

  * **Kommentaar:** **`www-data`** peab olema omanik, et WordPress saaks faile kirjutada (uuendused, piltide üleslaadimine). **XML-RPC** on vana API, mida ründajad kasutavad **paroolide jõurünnakuteks** (Brute Force), saates ühes päringus palju sisselogimiskatseid. Selle keelamine vähendab ründepinda.

### Samm 4.4: Lõplik Paigaldus

Ava brauseris `https://minuleht.local` ja `https://uusleht.local`. Nüüd saad luua administraatori konto (kasuta **unikaalset kasutajanime** ja **tugevat parooli**, vältides "admin").

-----

## 5\. B-OSA: Avaliku HTTPS-i Seadistamine Let's Encryptiga (Tootmises) 🌎

Kui liikute avalikku keskkonda, kus teil on avalik IP ja registreeritud domeenid, peate kasutama Let's Encrypti, kuna see on avalikult usaldusväärne.

### Samm 5.1: Certboti Paigaldamine

```bash
# Eemalda eelnevalt loodud ise-allkirjastatud SSL seaded Virtual Host'ist!
sudo apt install certbot python3-certbot-apache -y
```

### Samm 5.2: Sertifikaatide Hankimine

```bash
sudo certbot --apache
```

  * **Kommentaar:** **Certbot** kontrollib teie domeeni üle avaliku interneti (Domain Validation). Valige interaktiivses viisardis mõlemad domeenid ja **valige "2: Redirect"** HTTP-liikluse automaatseks suunamiseks HTTPS-ile. Certbot muudab automaatselt teie `.conf` faile, lisades sinna usaldusväärse SSL-i ja seadistades automaatse uuenduse.
