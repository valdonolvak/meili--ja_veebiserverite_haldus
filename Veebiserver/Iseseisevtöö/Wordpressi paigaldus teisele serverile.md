Eeldused:

* **Apache2 + WordPress** on juba olemas serveris **10.0.x.20**
* **MySQL/MariaDB tuleb alles seadistada** serveris **10.0.x.25**
* Õpilase ülesanne: seadistada MySQL, luua andmebaas, seadistada VirtualHost ja ühendada WordPress andmebaasiga

Allpool on **õpilasele sobiv samm-sammuline juhend**.

---

# 🟦 TÖÖJUHEND — WordPress paigaldamine domeenile `kolmasdomeen.local`

### (Apache2 juba olemas serveris 10.0.x.20, MySQL seadistatakse serveris 10.0.x.25)

---

## ✅ SERVER 1 – WordPress + Apache2 (10.0.x.20)

Apache2 on juba olemas, vaja teha:

1. **VirtualHost domeenile kolmasdomeen.local**
2. **WordPressi failid ja konfiguratsioon**

---

### 1. Loo VirtualHost `kolmasdomeen.local`

#### 1.1. Loo kataloog WordPressi jaoks:

```bash
sudo mkdir -p /var/www/kolmasdomeen.local
sudo chown -R $USER:$USER /var/www/kolmasdomeen.local
```

#### 1.2. Loo VirtualHost konfiguratsioon:

```bash
sudo nano /etc/apache2/sites-available/kolmasdomeen.local.conf
```

Lisa:

```apacheconf
<VirtualHost *:80>
    ServerName kolmasdomeen.local
    DocumentRoot /var/www/kolmasdomeen.local

    <Directory /var/www/kolmasdomeen.local>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/kolmasdomeen_error.log
    CustomLog ${APACHE_LOG_DIR}/kolmasdomeen_access.log combined
</VirtualHost>
```

#### 1.3. Luba sait ja mod_rewrite:

```bash
sudo a2ensite kolmasdomeen.local.conf
sudo a2enmod rewrite
sudo systemctl reload apache2
```

---

### 2. Paigalda WordPress

Mine saidi kausta:

```bash
cd /var/www/kolmasdomeen.local
```

Laadi WordPress:

```bash
curl -O https://wordpress.org/latest.zip
unzip latest.zip
mv wordpress/* .
rm -r wordpress latest.zip
```

Seadista õigused:

```bash
sudo chown -R www-data:www-data /var/www/kolmasdomeen.local
sudo chmod -R 755 /var/www/kolmasdomeen.local
```

---

### 3. Lisa /etc/hosts (testimiseks lokaalselt)

```bash
sudo nano /etc/hosts
```

Lisa rida:

```
10.0.x.20   kolmasdomeen.local
```

> Nüüd peaks brauseri aadressis `http://kolmasdomeen.local` avanema WordPress installeri leht.
> Aga installimine ei saa jätkuda enne andmebaasi loomist teises serveris.

---

## ✅ SERVER 2 – MySQL/MariaDB server (10.0.x.25)

### 4. Paigalda MySQL / MariaDB

```bash
sudo apt update
sudo apt install mariadb-server
```

Käivita turvaskript:

```bash
sudo mysql_secure_installation
```

Küsimustele soovitatavad vastused:

| Küsimus                               | Vastus  |
| ------------------------------------- | ------- |
| Switch to unix_socket authentication? | N (ei)  |
| Set root password?                    | Y (jah) |
| Remove anonymous users?               | Y       |
| Disallow remote root login?           | Y       |
| Remove test database?                 | Y       |
| Reload privilege tables?              | Y       |

---

### 5. Loo WordPressi andmebaas ja kasutaja

Logi andmebaasi:

```bash
sudo mysql -u root -p
```

Sisesta SQL käsud **(asenda x oma võrgunumbriga)**:

```sql
CREATE DATABASE kolmasdomeen_db;
CREATE USER 'wpuser'@'10.0.x.20' IDENTIFIED BY 'Salasõna123!';
GRANT ALL PRIVILEGES ON kolmasdomeen_db.* TO 'wpuser'@'10.0.x.20';
FLUSH PRIVILEGES;
EXIT;
```

> Kasutaja wpuser saab ühenduda **ainult WordPressi serverist (10.0.x.20)**.

---

## ✅ SERVER 1 – WordPress serveri lõppkonfiguratsioon

### 6. Seadista WordPress kasutama MySQL serverit

Mine kausta:

```bash
cd /var/www/kolmasdomeen.local
cp wp-config-sample.php wp-config.php
nano wp-config.php
```

Muuda järgmised read:

```php
define( 'DB_NAME', 'kolmasdomeen_db' );
define( 'DB_USER', 'wpuser' );
define( 'DB_PASSWORD', 'Salasõna123!' );
define( 'DB_HOST', '10.0.x.25' );
```

Salvesta fail.

---

## 🚀 7. Testi WordPressi

Ava brauser ja sisesta:

```
http://kolmasdomeen.local
```

Peaks avanema WordPress installeri leht.
Täida saidi nimi, admin kasutaja, parool jne.

---

## 🎉 ÜLESANNE ON VALMIS

Õpilane on seadistanud:

* ✅ VirtualHost domeenile **kolmasdomeen.local**
* ✅ WordPressi serveris **10.0.x.20**
* ✅ MySQL serveri **10.0.x.25**
* ✅ WordPress ühendub üle võrgu MySQL serveriga

Veebileht kolmasdomeen.local peab avanema ka Windows klient masinas

---


