## 4. Apache2 ja virtuaalhostid (Debian1)

Apache2 on üks levinumaid veebiservereid. Üks Apache võib teenindada sadu saite ühe IP-aadressi pealt – iga saidi kohta tehakse **virtuaalhost** (*virtual host*, *vhost*). Selles peatükis paneme Debian1-le püsti kolm saiti: `www.perenimi.local`, `wp.perenimi.local` ja `blogi.perenimi.local`.

![Apache valib virtuaalhosti päise Host: järgi](joonised/04-apache-vhost.png)

*Joonis 4.1: Nimepõhine virtuaalhost*

### 4.1 Mõisted

| Termin | Selgitus | Näide laboris |
| --- | --- | --- |
| HTTP päring | Brauseri küsimus serverile: meetod, tee, päised. | `GET /index.html HTTP/1.1` |
| `Host:` päis | Millist saiti brauser tahab. Selle järgi valib Apache vhosti. | `Host: wp.perenimi.local` |
| Virtuaalhost | `<VirtualHost>` plokk: millistele nimedele vastata ja kust failid võtta. | `wp.perenimi.local.conf` |
| `ServerName` / `ServerAlias` | Saidi põhinimi / lisanimed. | `ServerAlias perenimi.local` |
| `DocumentRoot` | Kaust, mille sisu veebis näidatakse. | `/var/www/wp.perenimi.local` |
| Vaikehost | Kui `Host:` ei sobi ühegi vhostiga, vastab **esimene laetud** vhost (tähestiku järjekorras sites-enabled kaustas). | `000-vaike.conf` |
| Moodul | Apache lisavõimekus. | `rewrite`, `ssl`, `headers`, `php8.4` |
| `.htaccess` | Kaustapõhine seadistusfail; töötab ainult, kui `AllowOverride` lubab. | WordPressi püsiviited |
| HTTP olekukood | 200 OK · 301/302 suunamine · 403 keelatud · 404 ei leitud · 500 serveri viga | |
| `www-data` | Kasutaja, kelle õigustes Apache töötab. | failide omanik |

### 4.2 Paigaldus

**Debian1:**

```bash
sudo apt install -y apache2
sudo systemctl enable --now apache2
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

Windowsi kliendis ava `http://10.0.XXX.10` – näed lehte „Apache2 Debian Default Page“.

### 4.3 Seadistuse kaustad

![Apache2 seadistuse kaustad Debianis](joonised/04-apache-kaustad.png)

*Joonis 4.2: Apache2 kaustad ja abikäsud*

| Käsk | Mida teeb |
| --- | --- |
| `a2ensite nimi` / `a2dissite nimi` | lubab / keelab saidi (sümbolink `sites-enabled/`) |
| `a2enmod rewrite` / `a2dismod` | lubab / keelab mooduli |
| `a2enconf` / `a2disconf` | lubab / keelab üldise seadistusfaili |
| `apache2ctl configtest` | kontrollib süntaksit – **käivita alati enne reload'i** |
| `apache2ctl -S` | näitab kõiki vhoste, nende järjekorda ja vaikehosti |
| `apache2ctl -M` | näitab laetud mooduleid |

### 4.4 Saitide kaustad ja testlehed

**Debian1:**

```bash
for s in www wp blogi; do
  sudo mkdir -p /var/www/$s.perenimi.local
  echo "<h1>$s.perenimi.local</h1><p>Debian1 · Apache2 vhost töötab.</p>" \
    | sudo tee /var/www/$s.perenimi.local/index.html
done
sudo chown -R www-data:www-data /var/www
```

`for` tsükkel teeb sama asja kolm korda – iga saidi nimega.

### 4.5 Vaikehost (püüab kinni tundmatud nimed)

Kui keegi pöördub serveri poole IP-aadressiga või tundmatu nimega, ei tohiks ta juhuslikult näha ühte sinu saitidest. Teeme eraldi vaikehosti.

**Debian1:**

```bash
sudo mkdir -p /var/www/vaike
echo "<h1>Tundmatu sait</h1>" | sudo tee /var/www/vaike/index.html
sudo nano /etc/apache2/sites-available/000-vaike.conf
```

```apache
# Esimene laetud vhost = vaikehost
<VirtualHost *:80>
    ServerName debian1.perenimi.local
    DocumentRoot /var/www/vaike
    ErrorLog  ${APACHE_LOG_DIR}/vaike_error.log
    CustomLog ${APACHE_LOG_DIR}/vaike_access.log combined
</VirtualHost>
```

### 4.6 Saitide virtuaalhostid

**Debian1:**

```bash
sudo nano /etc/apache2/sites-available/www.perenimi.local.conf
```

```apache
<VirtualHost *:80>
    ServerName  www.perenimi.local
    ServerAlias perenimi.local
    ServerAdmin admin@perenimi.local
    DocumentRoot /var/www/www.perenimi.local

    <Directory /var/www/www.perenimi.local>
        # -Indexes: ära näita failide nimekirja, kui index-faili pole
        Options -Indexes +FollowSymLinks
        # staatiline sait, .htaccess faile ei loeta
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog  ${APACHE_LOG_DIR}/www.perenimi.local_error.log
    CustomLog ${APACHE_LOG_DIR}/www.perenimi.local_access.log combined
</VirtualHost>
```

`wp.perenimi.local.conf` ja `blogi.perenimi.local.conf` on samasugused, kuid WordPress vajab `.htaccess` faili, seega **`AllowOverride All`**:

```bash
sudo nano /etc/apache2/sites-available/wp.perenimi.local.conf
```

```apache
<VirtualHost *:80>
    ServerName  wp.perenimi.local
    ServerAdmin admin@perenimi.local
    DocumentRoot /var/www/wp.perenimi.local

    <Directory /var/www/wp.perenimi.local>
        Options -Indexes +FollowSymLinks
        # WordPressi .htaccess (püsiviited) peab töötama
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog  ${APACHE_LOG_DIR}/wp.perenimi.local_error.log
    CustomLog ${APACHE_LOG_DIR}/wp.perenimi.local_access.log combined
</VirtualHost>
```

Tee `blogi.perenimi.local.conf` kopeerides ja asendades nime:

```bash
sudo sed 's/wp\.perenimi/blogi.perenimi/g' /etc/apache2/sites-available/wp.perenimi.local.conf \
  | sudo tee /etc/apache2/sites-available/blogi.perenimi.local.conf
```

> Apache seadistuses peab `#` kommentaar olema **eraldi real**. Rea lõppu kirjutatud kommentaar (`AllowOverride All # selgitus`) annab `configtest`-il vea, sest Apache loeb `#` ja sellele järgnevad sõnad direktiivi argumentideks.

### 4.7 Lubamine ja kontroll

**Debian1:**

```bash
sudo a2dissite 000-default
sudo a2ensite 000-vaike www.perenimi.local wp.perenimi.local blogi.perenimi.local
sudo a2enmod rewrite headers
sudo apache2ctl configtest            # Syntax OK
sudo systemctl reload apache2
sudo apache2ctl -S
```

`apache2ctl -S` väljund:

```text
VirtualHost configuration:
*:80                   is a NameVirtualHost
         default server debian1.perenimi.local (/etc/apache2/sites-enabled/000-vaike.conf:2)
         port 80 namevhost debian1.perenimi.local (/etc/apache2/sites-enabled/000-vaike.conf:2)
         port 80 namevhost blogi.perenimi.local (/etc/apache2/sites-enabled/blogi.perenimi.local.conf:1)
         port 80 namevhost wp.perenimi.local (/etc/apache2/sites-enabled/wp.perenimi.local.conf:1)
         port 80 namevhost www.perenimi.local (/etc/apache2/sites-enabled/www.perenimi.local.conf:1)
                 alias perenimi.local
```

### 4.8 Testimine

Käsurealt saab vhosti valikut testida ka **ilma DNS-ita**, saates `Host:` päise käsitsi:

**Debian1:**

```bash
curl -s -H "Host: wp.perenimi.local"   http://127.0.0.1/
curl -s -H "Host: blogi.perenimi.local" http://127.0.0.1/
curl -s -H "Host: olematu.ee"          http://127.0.0.1/     # Tundmatu sait
curl -sI http://127.0.0.1/                                    # ainult päised
```

**Windowsi klient:** ava brauseris `http://www.perenimi.local`, `http://wp.perenimi.local`, `http://blogi.perenimi.local`, `http://perenimi.local` ja `http://10.0.XXX.10`.

> **Kui DNS veel ei tööta**, saab nimed ajutiselt lisada Windowsi faili `C:\Windows\System32\drivers\etc\hosts` (Notepad administraatorina): `10.0.XXX.10 wp.perenimi.local`. Pärast DNS-i valmimist **kustuta need read**, muidu otsid hiljem viga valest kohast.

### 4.9 Serveri info peitmine

Vaikimisi ütleb Apache igas vastuses oma versiooni ja OS-i (`Server: Apache/2.4.65 (Debian)`), mis aitab ründajal sobivat haavatavust valida.

**Debian1:**

```bash
sudo nano /etc/apache2/conf-available/security.conf
```

```apache
ServerTokens Prod
ServerSignature Off
TraceEnable Off
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -sI http://127.0.0.1/ | grep Server        # Server: Apache
```

### 4.10 Logid

| Fail | Sisu |
| --- | --- |
| `/var/log/apache2/<sait>_access.log` | iga päring: IP, aeg, URL, olekukood, brauser |
| `/var/log/apache2/<sait>_error.log` | vead: PHP vead, keelatud ligipääs, puuduvad failid |
| `/var/log/apache2/error.log` | Apache enda vead (käivitus, moodulid) |

```bash
sudo tail -f /var/log/apache2/wp.perenimi.local_access.log
```

Ava samal ajal Windowsis leht ja vaata, kuidas päring logisse ilmub.

> Varasem juhend: [Veebiserveri Apache ja Wordpressi paigaldus](../Veebiserver/1.%20Veebiserveri%20Apache%20ja%20Wordpressi%20paigaldus.md).
