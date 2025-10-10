Seadistame esmalt lokaalse turvalise keskkonna ise-allkirjastatud sertifikaatidega (mis sobib teie VM-idele) ja anname seejärel teadmise, kuidas Let's Encryptiga avalikus keskkonnas edasi minna.

Siin on teie täielik juhend Apache2 ja WordPressi turvaliseks seadistamiseks kahe Virtual Host'iga, sisaldades mõlemat SSL-meetodit.

-----

## 1\. Eeltöö: Süsteemi Ettevalmistamine ja Tarkvara Paigaldus 🛠️

See osa kordab vajalikku baastarkvara paigaldust ja serveri turvalisuse parandamist.

### Samm 1.1: Süsteemi Uuendamine ja Baastarkvara Paigaldus

Paigaldame kõik vajalikud komponendid (Apache2, MariaDB, PHP, OpenSSL).

```bash
# Uuendame pakettide loendi
sudo apt update

# Paigaldame Apache2, MariaDB, PHP ja vajalikud laiendused (sh OpenSSL)
sudo apt install apache2 mariadb-server php libapache2-mod-php php-mysql php-cli php-curl php-gd php-mbstring php-xml php-zip unzip wget openssl -y

# Käivitame teenused ja seadistame automaatselt käivituma
sudo systemctl start apache2 mariadb
sudo systemctl enable apache2 mariadb
```

  * **Kommentaar:** **OpenSSL** on vajalik ise-allkirjastatud (Self-Signed) HTTPS sertifikaatide loomiseks, mida kasutame lokaalseks testimiseks.

### Samm 1.2: Apache'i Turvaseadete Tugevdamine (Üldkonfiguratsioon)

Avame Apache'i **`security.conf`** faili, et keelata ebavajalikud andmed ja lisada turvapäised.

```bash
sudo nano /etc/apache2/conf-available/security.conf
```

Lisa faili lõppu (või muuda olemasolevaid väärtusi) järgmised read:

```apache
# Keela serveri täisversiooni kuvamine veateadetes (Server Masking)
ServerTokens Prod
ServerSignature Off

# HTTP Strict Transport Security (HSTS) - sunnib brauserit kasutama AINULT HTTPS-i
<IfModule mod_headers.c>
    # See päis sunnib brausereid kasutama HTTPS-i isegi HTTP päringu korral
    Header always set Strict-Transport-Security "max-age=15768000; includeSubDomains"
    
    # Clickjacking vastane kaitse
    Header always append X-Frame-Options SAMEORIGIN
    
    # MIME-tüübi sniffing'u vastane kaitse (XSS)
    Header always set X-Content-Type-Options nosniff
    
    # Content Security Policy (Põhiline - lubab laadida faile ainult samast domeenist)
    Header always set Content-Security-Policy "default-src 'self' http: https: data: 'unsafe-inline' 'unsafe-eval'"
    
    # Määrab, millist teavet saata teistele saitidele liikudes
    Header always set Referrer-Policy "no-referrer-when-downgrade"
</IfModule>
```

  * **Kommentaar:** **`ServerTokens Prod`** piirab teavet, mida Apache veateadetes ründajale avaldab. Turvapäised nagu **HSTS** ja **X-Frame-Options** kaitsevad brauseripõhiste rünnakute, näiteks *Clickjacking'u* eest.

-----

## 2\. Apache2 ja Virtual Host'ide Seadistamine (HTTP ja HTTPS)

Seadistame mõlemad saidid koheselt **HTTPS-i** jaoks, kasutades lokaalset ise-allkirjastatud sertifikaati.

### Samm 2.1: Veebikataloogide ja Test-HTML-i Loomine

Loome kataloogid ja testfailid:

```bash
sudo mkdir -p /var/www/minuleht.local/html
sudo mkdir -p /var/www/uusleht.local/html

sudo sh -c 'echo "<html><body><h1>minuleht.local - Test OK</h1></body></html>" > /var/www/minuleht.local/html/index.html'
sudo sh -c 'echo "<html><body><h1>uusleht.local - Test OK</h1></body></html>" > /var/www/uusleht.local/html/index.html'
```

### Samm 2.2: Ise-allkirjastatud Sertifikaadi Loomine (Lokaalne SSL)

Loome ühe sertifikaadi, mis kehtib nii `minuleht.local` kui ka `uusleht.local` jaoks, kasutades **Subject Alternative Name (SAN)** laiendit. See on vajalik kaasaegsete brauserite puhul.

```bash
# Loo privaatvõti ja sertifikaat (kehtib 365 päeva)
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/local_dev.key \
    -out /etc/ssl/certs/local_dev.crt \
    -subj "/C=EE/ST=Harjumaa/L=Tallinn/O=Local Development/CN=minuleht.local" \
    -addext "subjectAltName = DNS:minuleht.local, DNS:uusleht.local"
```

  * **Kommentaar:** Sertifikaadi loomine OpenSSL-i abil tekitab kaks faili: **`.key`** (privaatvõti, mida hoiad saladuses) ja **`.crt`** (avalik sertifikaat). **`subjectAltName`** lubab ühel sertifikaadil kaitsta mitut domeeni.

### Samm 2.3: Virtual Host'ide Seadistamine HTTP-HTTPS Ümbersuunamisega

Me lubame Apache'i SSL-mooduli ja loome konfiguratsioonid pordile 80 (HTTP) ja 443 (HTTPS).

```bash
# Lubame SSL-mooduli
sudo a2enmod ssl

# Lubame headers mooduli (vajalik turvapäiste jaoks)
sudo a2enmod headers
```

#### minuleht.local konfiguratsioon (nano kasutades)

Loome faili **`/etc/apache2/sites-available/minuleht.local.conf`**:

```apache
# ----------------------------------------------------
# 1. HTTP PORDIL 80 (Suunab koheselt ümber HTTPS-ile)
# ----------------------------------------------------
<VirtualHost *:80>
    ServerName minuleht.local
    DocumentRoot /var/www/minuleht.local/html

    # Sunni HTTPS
    RewriteEngine On
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,R=permanent]
</VirtualHost>


# ----------------------------------------------------
# 2. HTTPS PORDIL 443 (Tegelik lehe sisu)
# ----------------------------------------------------
<VirtualHost *:443>
    ServerName minuleht.local
    DocumentRoot /var/www/minuleht.local/html

    <Directory /var/www/minuleht.local/html>
        Options Indexes FollowSymLinks
        AllowOverride All  
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/minuleht.local_error.log
    CustomLog ${APACHE_LOG_DIR}/minuleht.local_access.log combined

    # SSL/TLS SEADISTUSED
    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/local_dev.crt
    SSLCertificateKeyFile /etc/ssl/private/local_dev.key
</VirtualHost>
```

#### uusleht.local konfiguratsioon (nano kasutades)

Loome faili **`/etc/apache2/sites-available/uusleht.local.conf`** (muuda ainult `ServerName` ja logifaili nimed).

```apache
# OLEMASOLEV PLOKK PORDIL 80 (Suunab koheselt ümber HTTPS-ile)
<VirtualHost *:80>
    ServerName uusleht.local
    DocumentRoot /var/www/uusleht.local/html
    RewriteEngine On
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,R=permanent]
</VirtualHost>

# UUS PLOKK PORDIL 443 (Tegelik lehe sisu)
<VirtualHost *:443>
    ServerName uusleht.local
    DocumentRoot /var/www/uusleht.local/html

    <Directory /var/www/uusleht.local/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/uusleht.local_error.log
    CustomLog ${APACHE_LOG_DIR}/uusleht.local_access.log combined

    # SSL/TLS SEADISTUSED
    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/local_dev.crt
    SSLCertificateKeyFile /etc/ssl/private/local_dev.key
</VirtualHost>
```

### Samm 2.4: Virtual Host'ide Lubamine ja Testimine

```bash
# Lubame rewrite mooduli (vajalik HTTPS ümbersuunamiseks)
sudo a2enmod rewrite

# Keelame vaikimisi saidi
sudo a2dissite 000-default.conf

# Lubame uued saidid
sudo a2ensite minuleht.local.conf
sudo a2ensite uusleht.local.conf

# Kontrollime Apache'i süntaksi
sudo apache2ctl configtest

# Kui "Syntax OK", taaskäivitame
sudo systemctl restart apache2
```

  * **Kommentaar:** Mõlemal Virtual Host'il on nüüd kaks plokki: pordi 80 plokk tegeleb ainult **HTTP -\> HTTPS** suunamisega, ja pordi 443 plokk tegeleb tegeliku sisu serveerimise ja krüpteerimisega.

-----

## 3\. MariaDB, PHP ja WordPressi Paigaldus 🚀

See osa tegeleb andmebaaside loomise ja WordPressi failide konfigureerimisega.

### Samm 3.1: Andmebaaside Loomine

```bash
sudo mysql

# MariaDB käsureal sisesta järgmised käsud:
CREATE DATABASE `minuleht.local` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'minuadmin'@'localhost' IDENTIFIED BY 'tugevparool123_1';
GRANT ALL PRIVILEGES ON `minuleht.local`.* TO 'minuadmin'@'localhost';

CREATE DATABASE `uusleht.local` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'uusadmin'@'localhost' IDENTIFIED BY 'tugevparool123_2';
GRANT ALL PRIVILEGES ON `uusleht.local`.* TO 'uusadmin'@'localhost';

FLUSH PRIVILEGES;
EXIT;
```

### Samm 3.2: WordPressi Allalaadimine ja Failliikumine

```bash
# Kustutame eelnevalt loodud index.html failid
sudo rm /var/www/minuleht.local/html/index.html
sudo rm /var/www/uusleht.local/html/index.html

# Laadime alla ja pakime lahti WordPressi
cd /tmp
wget https://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz

# Kopeerime failid
sudo cp -R wordpress/* /var/www/minuleht.local/html/
sudo cp -R wordpress/* /var/www/uusleht.local/html/
```

### Samm 3.3: wp-config.php loomine ja Turvalisem Seadistamine

Loome ja seadistame **`wp-config.php`** faili andmebaasi ühenduse ja täiendavate turvaseadetega.

#### 3.3.1: minuleht.local konfiguratsioon (nano kasutades)

```bash
sudo cp /var/www/minuleht.local/html/wp-config-sample.php /var/www/minuleht.local/html/wp-config.php
sudo nano /var/www/minuleht.local/html/wp-config.php
```

Asenda DB detailid ja lisa turvaseaded (enne rida `/* That's all, stop editing! Happy publishing. */`):

```php
// DB ÜHENDUS
define( 'DB_NAME', 'minuleht.local' );
define( 'DB_USER', 'minuadmin' );
define( 'DB_PASSWORD', 'tugevparool123_1' ); // ASENDA OMA PAROOLIGA
define( 'DB_HOST', 'localhost' );

// TURVASEADED
// Muuda tabelite eesliidet (vähendab standardsete SQL Injection rünnakute riski)
$table_prefix = 'wp_'.rand(10000, 99999).'_'; 
// Keela failide redigeerimine administraatori paneelis
define( 'DISALLOW_FILE_EDIT', true );
// Sunni sisselogimine ja admin-paneel kasutama SSL/HTTPS-i
define( 'FORCE_SSL_ADMIN', true );
```

#### 3.3.2: uusleht.local konfiguratsioon (korda samme 3.3.1)

Korda sama protsess saidi `uusleht.local` jaoks, kasutades teise saidi DB andmeid ja parooli.

### Samm 3.4: Failiõiguste Seadistamine ja XML-RPC Keelamine

```bash
# Määrame omanikuks veebiserveri kasutaja (www-data)
sudo chown -R www-data:www-data /var/www/minuleht.local/
sudo chown -R www-data:www-data /var/www/uusleht.local/

# Seadistame turvalised õigused (kaustad 755, failid 644)
sudo find /var/www/minuleht.local/html -type d -exec chmod 755 {} \;
sudo find /var/www/minuleht.local/html -type f -exec chmod 644 {} \;
sudo find /var/www/uusleht.local/html -type d -exec chmod 755 {} \;
sudo find /var/www/uusleht.local/html -type f -exec chmod 644 {} \;

# XML-RPC keelamine .htaccess faili abil (vähendab rünnakupinda)
# Lisa see ka mõlema saidi .htaccess faili
echo '
# BLOCK XML-RPC ATTACKS
<Files xmlrpc.php>
Order Deny,Allow
Deny from all
</Files>' | sudo tee -a /var/www/minuleht.local/html/.htaccess
```

  * **Kommentaar:** **`DISALLOW_FILE_EDIT`** takistab administraatori paneelist koodi muutmise. **XML-RPC** on sageli rünnakute sihtmärk, seega on selle blokeerimine (kui seda ei kasutata) hea turvameede.

### Samm 3.5: Lõplik Paigaldus

Ava brauseris `https://minuleht.local` ja `https://uusleht.local`. Sinu brauser annab hoiatusi ise-allkirjastatud sertifikaadi tõttu, kuid saad ühenduse kinnitada. WordPress suunab sind administraatori konto loomise lehele.

-----

## 4\. B-OSA: Avaliku HTTPS-i Seadistamine (Let's Encryptiga)

Kui teie VM-id saavad avaliku IP-aadressi ja te kasutate **avalikult registreeritud domeene** (mitte `.local`), peaksite minema üle Let's Encryptile.

### Eeldused:

1.  Serveril on avalik IP.
2.  Domeeninimi on avalikult registreeritud ja suunatud sellele IP-le (A-kirje).
3.  Oled eelnevalt eemaldanud **ise-allkirjastatud SSL seaded** Virtual Host'idest.

### Samm 4.1: Certboti Paigaldamine

```bash
# Uuendame pakettide loendi ja paigaldame Certboti
sudo apt update
sudo apt install certbot python3-certbot-apache -y
```

### Samm 4.2: Sertifikaatide Hankimine

Certbot tunneb automaatselt ära teie Apache Virtual Host'id ja küsib, milliseid domeene valideerida:

```bash
sudo certbot --apache
```

  * **Kommentaar:** Valige interaktiivses viisardis mõlemad domeenid ja **valige "2: Redirect"** HTTP-liikluse automaatseks suunamiseks HTTPS-ile. Certbot muudab automaatselt teie Virtual Host'i faile (lisab SSL-seaded ja eemaldab isetehtud sertifikaatide read).

### Samm 4.3: Automaatse Uuendamise Kontroll

Let's Encrypti sertifikaadid kehtivad 90 päeva, kuid Certbot paigaldab automaatselt taustaprotsessi, mis neid uuendab.

```bash
# Testime uuendusprotsessi (dry-run)
sudo certbot renew --dry-run
```

Kui test on edukas, hoolitseb süsteem sertifikaatide uuendamise eest automaatselt.
