Jah — alljärgnevalt koostan **täieliku, süstemaatilise ja õpetamiskõlbuliku juhendi**, mis lisab:

---

# 🆕 **Uued nõuded, mis juhendisse integreeritud:**

### ✔ **Andmebaasipõhine kasutajahaldus (MySQL/MariaDB)**

* Postfix kasutab **virtuaalkasutajaid** (mitte Linuxi süsteemikontosid)
* Dovecot loeb kasutajad ja domeenid **MySQList**
* Paroolid salvestatakse **turvaliselt (SHA512-CRYPT või Argon2)**

### ✔ **Administraatori veebiliides kasutajate haldamiseks**

* Anname **moderna veebiliidese** kasutajate halduseks:
  ▶ **PostfixAdmin** (PHP + MySQL)
  Mida PostfixAdmin võimaldab:

  * domeenide lisamine
  * kasutajate lisamine
  * postkastide loomine
  * aliaste lisamine
  * paroolide taastamine
  * quota haldus

### ✔ **Veebipõhine e-post (webmail)**

* Anname **kaasaegse IMAP webmaili**:
  ▶ **Roundcube Webmail**

### ✔ Toimivad teenused:

* Postfix (SMTP)
* Dovecot (IMAP, LMTB, SASL)
* BIND9 DNS (MX, SPF, DKIM, DMARC)
* MariaDB/MySQL (virtuaalkasutajad + PostfixAdmin)
* PHP 8.2 + Nginx/Apache
* Roundcube (webmail)
* OpenDKIM

---

# 🧩 ÜLDINE ARHITEKTUUR (ÕPPEJOONIS)

```
                        +-----------------------+
  User Web Browser ---> |    PostfixAdmin       | <-- Admin haldab kasutajaid
                        +----------+------------+
                                   |
                                   | MySQL päringud
                             +-----v------+
                             |  MariaDB   |
                             +-----+------+
                                   |
    E-post saadetakse:             | kasutajad, domeenid
+-----------------------+          |
|       Postfix         |<---------+
|  SMTP + DKIM + SPF    |  
+----------+------------+
           |
           | LMTP
+----------v------------+
|       Dovecot         |
|   IMAP/POP3 server    |
+----------+------------+
           |
           | IMAP
+----------v------------+
|      Roundcube        |  <-- Webmail kasutajatele
+-----------------------+
```

---

# 📘 1. TEOORIA — MIKS ON VAJA VIRTUAALKASUTAJAID?

Linuxi süsteemi kasutajakontod ei sobi suurele e-posti süsteemile:

| Probleem                    | Selgitus                                                |
| --------------------------- | ------------------------------------------------------- |
| **Turvarisk**               | Iga kasutaja oleks Linuxi kasutaja → ligipääs serverile |
| **Ei skaaleeru**            | 1000 e-posti kontot = 1000 Linuxi kasutajat             |
| **Poliitikad puuduvad**     | Quota, domeenid, aliaste haldus keeruline               |
| **Raskused veebihaldusega** | Ei saa kasutajaid juhtida veebiliidesest                |

**Virtuaalkasutajad lahendavad kõik probleemid**:

* kasutaja on ainult MySQL tabeli kirje
* paroolid on krüpteeritud
* Dovecot kontrollib kasutaja parooli andmebaasist
* Postfix kontrollib domeene ja aliaste reegleid MySQL päringutega
* PostfixAdmin pakub mugavat veebihaldust

---

# 📘 2. VAJALIKUD PAKETID

```bash
sudo apt update
sudo apt install mariadb-server postfix postfix-mysql dovecot-core dovecot-imapd dovecot-lmtpd dovecot-mysql \
opendkim opendkim-tools bind9 php php-fpm php-mysql php-intl php-xml php-mbstring php-zip php-curl \
nginx git unzip -y
```

---

# 📘 3. MARIA DB ANDMEBAAS

## 3.1 MariaDB turvamine

```bash
sudo mysql_secure_installation
```

Vali:

* paroolipoliitika: 0
* Eemalda anonüümsed kasutajad: Y
* Keela root remote login: Y
* Eemalda test andmebaas: Y
* Reload privileges: Y

---

## 3.2 PostfixAdmin andmebaasi loomine

Mine MariaDB konsooli:

```bash
sudo mysql
```

Loo andmebaas:

```sql
CREATE DATABASE postfix;
GRANT ALL ON postfix.* TO 'postfixuser'@'localhost' IDENTIFIED BY 'VägaTugevParool123!';
FLUSH PRIVILEGES;
EXIT;
```

---

# 📘 4. POSTFIXADMIN PAIGALDUS (WEB UI)

## 4.1 Lae alla ja paigalda PostfixAdmin

```bash
cd /var/www/
sudo git clone https://github.com/postfixadmin/postfixadmin.git
sudo chown -R www-data:www-data /var/www/postfixadmin
```

### 4.2 Vali konfiguratsioonifail

```bash
cd postfixadmin/
cp config.inc.php.sample config.inc.php-backup
nano config.inc.php
```

Muuda:

```php
$CONF['database_type'] = 'mysql';
$CONF['database_user'] = 'postfixuser';
$CONF['database_password'] = 'VägaTugevParool123!';
$CONF['database_name'] = 'postfix';

$CONF['encrypt'] = 'dovecot:SHA512-CRYPT';
$CONF['default_language'] = 'en';

$CONF['configured'] = true;
```

### 4.3 Loo Nginx konfig

```bash
sudo nano /etc/nginx/sites-available/postfixadmin
```

Sisestus:

```
server {
    listen 80;
    server_name mail.perenimi.local;

    root /var/www/postfixadmin/public;
    index index.php index.html;

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php-fpm.sock;
    }
}
```

Aktiveeri:

```bash
sudo ln -s /etc/nginx/sites-available/postfixadmin /etc/nginx/sites-enabled/
sudo systemctl restart nginx
```

---

# 📘 5. POSTFIX KONFIGURATSIOON (MYSQL VIRTUAALKASUTAJATEGA)

## 5.1 Loo Postfixile MySQL päringufailid

### 5.1.1 Virtual domains

`/etc/postfix/mysql-virtual-mailbox-domains.cf`:

```
user = postfixuser
password = VägaTugevParool123!
hosts = localhost
dbname = postfix
query = SELECT domain FROM domain WHERE domain='%s'
```

### 5.1.2 Virtual users

`/etc/postfix/mysql-virtual-mailbox-maps.cf`:

```
user = postfixuser
password = VägaTugevParool123!
hosts = localhost
dbname = postfix
query = SELECT username FROM mailbox WHERE username='%s'
```

### 5.1.3 Aliased

`/etc/postfix/mysql-virtual-alias-maps.cf`:

```
user = postfixuser
password = VägaTugevParool123!
hosts = localhost
dbname = postfix
query = SELECT destination FROM alias WHERE source='%s'
```

---

## 5.2 Postfix `main.cf` olulised lisad

```bash
sudo nano /etc/postfix/main.cf
```

Lisa:

```
virtual_mailbox_domains = mysql:/etc/postfix/mysql-virtual-mailbox-domains.cf
virtual_mailbox_maps = mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf
virtual_alias_maps = mysql:/etc/postfix/mysql-virtual-alias-maps.cf

virtual_transport = lmtp:unix:private/dovecot-lmtp
```

---

# 📘 6. DOVECOT KONFIGURATSIOON (MYSQL JA MAILDIR)

## 6.1 Maildir

`/etc/dovecot/conf.d/10-mail.conf`:

```
mail_location = maildir:/var/mail/vhosts/%d/%n
```

## 6.2 MySQL ühendus

`/etc/dovecot/dovecot-sql.conf.ext`:

```
driver = mysql
connect = host=localhost dbname=postfix user=postfixuser password=VägaTugevParool123!

default_pass_scheme = SHA512-CRYPT

password_query = SELECT username AS user, password FROM mailbox WHERE username='%u';
user_query = SELECT '/var/mail/vhosts/%d/%n' AS home, 'maildir:/var/mail/vhosts/%d/%n' AS mail;
```

## 6.3 LMTB ja SASL

`/etc/dovecot/conf.d/10-master.conf`:

```
unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
}

unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
}
```

---

# 📘 7. MAILDIR KAUSTADE STRUKTUUR

```
sudo mkdir -p /var/mail/vhosts/perenimi.local
sudo chown -R dovecot:dovecot /var/mail/vhosts
sudo chmod -R 770 /var/mail/vhosts
```

---

# 📘 8. ROUNDCUBE WEBMAIL

```bash
sudo apt install roundcube roundcube-mysql -y
```

Vali andmebaasiks *postfix* või loo eraldi.

Loo Nginx konfig sarnaselt PostfixAdminiga.

---

# 📘 9. POSTFIXADMIN WEB INSTALLERI LÄBIMINE

Mine brauseris:

```
http://mail.perenimi.local/setup.php
```

* Loo administraator
* Loo domeen **perenimi.local**
* Loo kasutaja (virtuaalkasutaja, mitte Linux user)

---

# 📘 10. DKIM, SPF, DMARC (sama loogika nagu varem)

* DKIM privaatvõti (serveris)
* DKIM avalik võti (DNS-is)
* SPF TXT kirje
* DMARC poliitika

---

# 📘 11. KONTROLL

### Kontrolli IMAP:

```
openssl s_client -connect mail.perenimi.local:143
```

### Kontrolli SMTP (AUTH):

```
openssl s_client -connect mail.perenimi.local:587
```

### Kontrolli DNS:

```
dig MX perenimi.local
dig TXT perenimi.local
dig TXT mail._domainkey.perenimi.local
dig TXT _dmarc.perenimi.local
```

---

# 🎉 VALMIS: Täisfunktsionaalne ettevõtte tasemel meiliserver

Sisaldab:

* Postfix virtuaalkasutajatega (MySQL)
* Dovecot (IMAP, LMTP)
* PostfixAdmin (web UI)
* Roundcube (webmail)
* DKIM, SPF, DMARC
* BIND9 DNS
* Turvaline paroolihaldus + quota + aliaste haldus

---

# ❓ Kas soovid, et paneksin sellest kokku:

### ✔ Täieliku PDF-õppematerjali

### ✔ Skeemid ja arhitektuuri joonised

### ✔ Ühe bash skripti, mis teeb *kogu installi automaatselt*

### ✔ Konfifailide komplekti ZIP-failina

Ütle vaid, mida neist soovid!
