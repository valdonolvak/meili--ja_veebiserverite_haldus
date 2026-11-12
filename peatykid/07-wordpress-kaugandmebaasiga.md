## 7. WordPress kaugandmebaasiga (Debian + Ubuntu)

Suuremates süsteemides on veebiserver ja andmebaas **eri masinates**: andmebaasi saab eraldi varundada, skaleerida ja kaitsta ning mitu veebiserverit saab kasutada sama andmebaasi. Selles peatükis paigaldame teise WordPressi saidile `blogi.perenimi.local` (Debian), mille andmebaas on **Ubuntus** (192.168.XXX.20). Ubuntu on laboris ka meiliserver – andmebaasiserver ja meiliserver võivad samas masinas rahulikult koos elada, sest Roundcube kasutab oma SQLite'i ega puutu MariaDB-d.

![WordPress ühes masinas, andmebaas teises](joonised/06-kaug-andmebaas.png)

*Joonis 7.1: Kolm lukku, mis peavad olema lahti*

### 7.1 Mõisted

| Termin | Selgitus |
| --- | --- |
| `bind-address` | Millisel IP-aadressil MariaDB ühendusi ootab. `127.0.0.1` = ainult kohalikud, `0.0.0.0` = kõik liidesed. |
| Port 3306 | MariaDB/MySQL vaikeport (TCP). |
| `'kasutaja'@'host'` | Host näitab, **kust** kasutaja tohib ühenduda: `'%'` = igalt poolt (väldi!), `'192.168.XXX.10'` = ainult Debianist. |
| Vähima õiguse põhimõte | Iga konto saab ainult need õigused, mida tal on vaja – üks andmebaas, üks lähte-IP. |

Kõik kolm lukku peavad olema lahti, et ühendus töötaks – ja ainult Debiani jaoks:

1. **MariaDB kuulab võrgus** (`bind-address`);
2. **kasutaja tohib tulla Debiani IP-lt** (`'blogi_kasutaja'@'192.168.XXX.10'`);
3. **tulemüür lubab pordi 3306** ainult Debianist.

### 7.2 MariaDB paigaldus Ubuntule

**Ubuntu:**

```bash
sudo apt install -y mariadb-server
sudo systemctl enable --now mariadb
sudo mariadb-secure-installation        # vastused nagu peatükis 6.3 (Ubuntu MariaDB 10.11 – samad küsimused)
```

### 7.3 Lukk 1: kuula võrgus

**Ubuntu:**

```bash
sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf
```

Leia rida `bind-address = 127.0.0.1` ja muuda:

```ini
bind-address            = 0.0.0.0
```

```bash
sudo systemctl restart mariadb
sudo ss -tlnp | grep 3306          # 0.0.0.0:3306 ... mariadbd
```

Turvalisem variant on `bind-address = 192.168.XXX.20` – siis kuulab MariaDB ainult labori võrgu liidesel.

### 7.4 Lukk 2: andmebaas ja kaugkasutaja

**Ubuntu:**

```bash
sudo mariadb
```

```sql
CREATE DATABASE blogi_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'blogi_kasutaja'@'192.168.XXX.10' IDENTIFIED BY 'BlogiParool.2026!';
GRANT ALL PRIVILEGES ON blogi_db.* TO 'blogi_kasutaja'@'192.168.XXX.10';
FLUSH PRIVILEGES;
SELECT user, host FROM mysql.user;
EXIT;
```

### 7.5 Lukk 3: tulemüür

**Ubuntu:**

```bash
sudo ufw allow from 192.168.XXX.10 to any port 3306 proto tcp
sudo ufw status
```

### 7.6 Ühenduse test Debianist

Enne WordPressi testi ühendust käsurealt – nii näed vea kohe ja selge tekstina.

**Debian:**

```bash
mariadb -h 192.168.XXX.20 -u blogi_kasutaja -p blogi_db -e "SELECT CURRENT_USER(), @@hostname;"
```

Oodatav vastus:

```text
+------------------------------+------------+
| CURRENT_USER()               | @@hostname |
+------------------------------+------------+
| blogi_kasutaja@192.168.XXX.10   | mail       |
+------------------------------+------------+
```

| Viga | Mis lukk on kinni |
| --- | --- |
| `Can't connect to server on '192.168.XXX.20' (115)` / ajalõpp | tulemüür (lukk 3) või MariaDB ei kuula võrgus (lukk 1) |
| `Can't connect … (111) Connection refused` | MariaDB kuulab ainult 127.0.0.1 (lukk 1) |
| `Host '192.168.XXX.10' is not allowed to connect` | kasutaja on loodud teise hosti jaoks (lukk 2) |
| `Access denied for user 'blogi_kasutaja'@'192.168.XXX.10'` | vale parool või puudub GRANT (lukk 2) |

Kontrolli ka, et teistelt **ei pääse** ligi:

- **Ubuntus endas** `mariadb -h 192.168.XXX.20 -u blogi_kasutaja -p` – ühendus tuleb nüüd IP-lt 192.168.XXX.20, mitte Debianist, seega `Host '192.168.XXX.20' is not allowed` või `Access denied`.
- **Windowsi kliendis** (PowerShell) `Test-NetConnection 192.168.XXX.20 -Port 3306` → `TcpTestSucceeded : False` – tulemüür ei lase.

### 7.7 WordPress saidile blogi.perenimi.local

Vhost on peatükis 5 juba tehtud.

**Debian:**

```bash
sudo rm -f /var/www/blogi.perenimi.local/index.html
sudo cp -a /tmp/wordpress/. /var/www/blogi.perenimi.local/
cd /var/www/blogi.perenimi.local
sudo cp wp-config-sample.php wp-config.php
sudo nano wp-config.php
```

```php
define( 'DB_NAME', 'blogi_db' );
define( 'DB_USER', 'blogi_kasutaja' );
define( 'DB_PASSWORD', 'BlogiParool.2026!' );
define( 'DB_HOST', '192.168.XXX.20' );       // <-- andmebaas teises masinas
define( 'DB_CHARSET', 'utf8mb4' );
```

Lisa uued turvavõtmed (`curl -s https://api.wordpress.org/secret-key/1.1/salt/`) ning `FS_METHOD` ja `DISALLOW_FILE_EDIT` read nagu peatükis 6.6. Õigused:

```bash
sudo chown -R www-data:www-data /var/www/blogi.perenimi.local
sudo find /var/www/blogi.perenimi.local -type d -exec chmod 755 {} \;
sudo find /var/www/blogi.perenimi.local -type f -exec chmod 644 {} \;
sudo chmod 640 /var/www/blogi.perenimi.local/wp-config.php
```

**Windowsi klient:** `http://blogi.perenimi.local` → paigalda nagu peatükis 6.8.

### 7.8 Kontroll: andmed on tõesti Ubuntus

**Ubuntu:**

```bash
sudo mariadb -e "SHOW TABLES FROM blogi_db;"
sudo mariadb -e "SELECT post_title FROM blogi_db.wp_posts WHERE post_status='publish';"
```

Tee WordPressis uus postitus ja käivita päring uuesti – postitus ilmub Ubuntu andmebaasi.

**Debian:** `sudo mariadb -e "SHOW DATABASES;"` – `blogi_db` siin **ei ole**.

### 7.9 Mida veel tootmises teeks

- **TLS andmebaasiühendusele** – praegu liigub parool ja andmed võrgus krüptimata. MariaDB toetab TLS-i (`require_secure_transport = ON`, WordPressis `MYSQL_CLIENT_FLAGS`).
- **Eraldi andmebaasivõrk** – veebi- ja andmebaasiserver suhtlevad eraldi VLAN-is, kuhu kliendid ei pääse.
- **Varundus** – `mariadb-dump blogi_db > blogi_db.sql` igal ööl ja koopia teise masinasse.

> Varasem juhend (teiste IP-dega): [Wordpressi paigaldus teisele serverile](../Veebiserver/Iseseisevt%C3%B6%C3%B6/Wordpressi%20paigaldus%20teisele%20serverile.md).
