Siin on põhjalik samm-sammuline juhend, kuidas seadistada **Debian Linux serverile** kaks WordPressi saiti — üks **Apache2** ja teine **Nginx** veebiserveriga. Mõlemad kasutavad **virtuaalhoste** ja eraldi **MySQL andmebaase**.

---

## 🧱 Eeltingimused

- Debian server (näiteks Debian 11 või 12)
- Root või sudo õigused
- Internetiühendus
- Domeenid: `minuleht.local` ja `uusleht.local` (kasutame neid testimiseks /hosts failis)

---

## 1️⃣ Apache2 + WordPress + VirtualHost

### 1. Paigalda vajalikud paketid

```bash
sudo apt update
sudo apt install apache2 mysql-server php php-mysql libapache2-mod-php unzip curl
```

### 2. Loo MySQL andmebaasid ja kasutajad

```bash
sudo mysql
```

```sql
CREATE DATABASE `minuleht.local`;
CREATE USER 'minuadmin'@'localhost' IDENTIFIED BY 'minuadminsalasona';
GRANT ALL PRIVILEGES ON `minuleht.local`.* TO 'minuadmin'@'localhost';

CREATE DATABASE `uusleht.local`;
CREATE USER 'uusadmin'@'localhost' IDENTIFIED BY 'uusadminsalasona';
GRANT ALL PRIVILEGES ON `uusleht.local`.* TO 'uusadmin'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### 3. Laadi alla WordPress ja paigalda

```bash
cd /var/www/
sudo curl -O https://wordpress.org/latest.zip
sudo unzip latest.zip
sudo mv wordpress minuleht.local
sudo cp -r minuleht.local uusleht.local
```

### 4. Konfigureeri wp-config.php

```bash
cd /var/www/minuleht.local
sudo cp wp-config-sample.php wp-config.php
sudo nano wp-config.php
```

Muuda:

```php
define('DB_NAME', 'minuleht.local');
define('DB_USER', 'minuadmin');
define('DB_PASSWORD', 'minuadminsalasona');
```

Tee sama `uusleht.local` jaoks:

```bash
cd /var/www/uusleht.local
sudo cp wp-config-sample.php wp-config.php
sudo nano wp-config.php
```

Muuda:

```php
define('DB_NAME', 'uusleht.local');
define('DB_USER', 'uusadmin');
define('DB_PASSWORD', 'uusadminsalasona');
```

### 5. Loo Apache VirtualHost failid

```bash
sudo nano /etc/apache2/sites-available/minuleht.local.conf
```

```apache
<VirtualHost *:80>
    ServerName minuleht.local
    DocumentRoot /var/www/minuleht.local
    <Directory /var/www/minuleht.local>
        AllowOverride All
    </Directory>
</VirtualHost>
```

```bash
sudo nano /etc/apache2/sites-available/uusleht.local.conf
```

```apache
<VirtualHost *:80>
    ServerName uusleht.local
    DocumentRoot /var/www/uusleht.local
    <Directory /var/www/uusleht.local>
        AllowOverride All
    </Directory>
</VirtualHost>
```

### 6. Aktiveeri saidid ja mod_rewrite

```bash
sudo a2ensite minuleht.local.conf
sudo a2ensite uusleht.local.conf
sudo a2enmod rewrite
sudo systemctl restart apache2
```

### 7. Lisa /etc/hosts kirjed (kohalikuks testimiseks)

```bash
sudo nano /etc/hosts
```

Lisa:

```
127.0.0.1 minuleht.local
127.0.0.1 uusleht.local
```

---

## 2️⃣ Nginx + WordPress + VirtualHost

### 1. Paigalda vajalikud paketid

```bash
sudo apt install nginx php-fpm php-mysql unzip curl
```

### 2. Loo MySQL andmebaasid ja kasutajad (juba tehtud, kui eelmine osa tehtud)

### 3. Laadi alla WordPress ja paigalda

```bash
cd /var/www/
sudo curl -O https://wordpress.org/latest.zip
sudo unzip latest.zip
sudo mv wordpress minuleht.local.nginx
sudo cp -r minuleht.local.nginx uusleht.local.nginx
```

### 4. Konfigureeri wp-config.php

```bash
cd /var/www/minuleht.local.nginx
sudo cp wp-config-sample.php wp-config.php
sudo nano wp-config.php
```

Muuda:

```php
define('DB_NAME', 'minuleht.local');
define('DB_USER', 'minuadmin');
define('DB_PASSWORD', 'minuadminsalasona');
```

Tee sama `uusleht.local.nginx` jaoks.

### 5. Loo Nginx server block'id

```bash
sudo nano /etc/nginx/sites-available/minuleht.local
```

```nginx
server {
    listen 80;
    server_name minuleht.local;
    root /var/www/minuleht.local.nginx;

    index index.php index.html;
    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php7.4-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
```

```bash
sudo nano /etc/nginx/sites-available/uusleht.local
```

```nginx
server {
    listen 80;
    server_name uusleht.local;
    root /var/www/uusleht.local.nginx;

    index index.php index.html;
    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php7.4-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
```

### 6. Aktiveeri saidid

```bash
sudo ln -s /etc/nginx/sites-available/minuleht.local /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/uusleht.local /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

### 7. Lisa /etc/hosts kirjed

```bash
sudo nano /etc/hosts
```

Lisa:

```
127.0.0.1 minuleht.local
127.0.0.1 uusleht.local
```

---

## ✅ Kokkuvõte

| Server | Domeen | Andmebaas | Kasutaja |
|--------|--------|-----------|----------|
| Apache2 | minuleht.local | minuleht.local | minuadmin |
| Apache2 | uusleht.local | uusleht.local | uusadmin |
| Nginx | minuleht.local | minuleht.local | minuadmin |
| Nginx | uusleht.local | uusleht.local | uusadmin |

Kui soovid, võin lisada ka **SSL (Let's Encrypt)**, **failiõiguste** või **automaatse installi skripti**. Kas soovid neid?
