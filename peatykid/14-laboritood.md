## 14. Laboritööd

Laborid on järjestikused: iga järgmine eeldab eelmise tulemust. Iga labori lõpus on **kontrollpunkt** (mis peab töötama, enne kui edasi lähed) ja **küsimused**, millele vasta lühidalt laboripäevikus. Tee enne iga laborit Proxmoxis kõigist Linuxi masinatest hetktõmmis.

| Labor | Teema | Masinad | Peatükk | Aeg (ak h) |
| --- | --- | --- | --- | --- |
| 1 | Linuxi serverite ettevalmistus | Debian, Ubuntu | 2 | 3 |
| 2 | Nimeserver BIND9 | Debian | 3 | 3 |
| 3 | DHCP-server Kea | Debian, Windows | 4 | 3 |
| 4 | Apache2 ja virtuaalhostid | Debian | 5 | 3 |
| 5 | WordPress samas masinas | Debian | 6 | 3 |
| 6 | WordPress kaugandmebaasiga | Debian, Ubuntu | 7 | 3 |
| 7 | Labori CA ja HTTPS | Debian, Ubuntu, Windows | 8 | 3 |
| 8 | Postfix ja Dovecot | Ubuntu | 9–10 | 5 |
| 9 | DKIM, SPF, DMARC ja fail2ban | Ubuntu, Debian | 11 | 4 |
| 10 | Veebimeil Roundcube | Ubuntu, Windows | 12 | 3 |
| 11 | Väljaminev post relay kaudu | Ubuntu | 13 | 2 |
| 12 | Tõrkeotsingu harjutus | kõik | 15 | 3 |

Osa III (andmebaasipõhine meiliserver) laborid **13–15** on peatükis [20](20-osa3-haldus-laborid-torkeotsing.md#204-laboritööd).

---

### Labor 1. Linuxi serverite ettevalmistus

**Eesmärk:** mõlemal Linuxi serveril on õige nimi, staatiline IP, toimiv nimelahendus, SSH, `sudo`, uuendused ja tulemüür.

**Sammud:**

1. Pane kirja oma vneti number XXX ja perenimi. Kontrolli Proxmoxis, et kõigi kolme VM-i võrgukaart on sinu vnetis ja et SDN-i alamvõrgul **pole** DHCP Range'i (1.2, 4.4).
2. Debian: kontrolli `sudo whoami`; vajadusel lisa kasutaja `sudo` rühma (2.2).
3. Leia mõlemas serveris võrguliidese nimi (`ip -br link`).
4. Seadista staatiline IP: Debian `.10` (`/etc/network/interfaces`, 2.4), Ubuntu `.20` (netplan, 2.5).
5. Nimeserver: Debianis ajutiselt `1.1.1.1` (BIND9 tuleb laboris 2), Ubuntus `192.168.XXX.10` (töötab pärast laborit 2).
6. Hostinimed: `debian` ja `mail` + `/etc/hosts` (2.6).
7. `sudo apt update && sudo apt full-upgrade -y` ja põhitööriistad (2.7).
8. `ufw`: luba OpenSSH ja lülita sisse mõlemas (2.10).
9. Windowsi klient jääb DHCP peale (vaikeseade). Kuni DHCP-serverit pole (labor 3), on tal `169.254.x.x` aadress – see on ootuspärane.

**Kontrollpunkt:**

```bash
hostname -f                 # debian.perenimi.local / mail.perenimi.local
ip -br addr                 # õige IP
ping -c 2 192.168.XXX.1     # lüüs vastab
ping -c 2 debian.org        # Debianis: internet ja DNS töötavad
sudo ufw status             # Status: active, 22/tcp ALLOW
```

**Küsimused:**

1. Mis vahe on hostinimel ja FQDN-il? Miks meiliserveril on FQDN eriti oluline?
2. Miks ei tohi serveril olla DHCP-ga saadud aadress? Miks eriti Debianil?
3. Miks tuleb `ufw allow OpenSSH` teha **enne** `ufw enable`?
4. Kus asub Debian 13-s ja kus Ubuntu 24.04-s võrguseadistus? Miks need erinevad?
5. Mis on Proxmoxi SDN vnet ja milleks on alamvõrgu lüüs `.1`?

---

### Labor 2. Nimeserver BIND9

**Eesmärk:** Debian on domeeni `perenimi.local` autoriteetne nimeserver ja kogu labori rekursiivne nimelahendaja.

**Sammud:**

1. Paigalda BIND9 (3.3).
2. Seadista `named.conf.options`: ACL `labor`, rekursioon ainult laborile, edastajad (3.4).
3. Kirjelda tsoonid `named.conf.local`-is (3.5).
4. Loo edasisuunatud tsoonifail kõigi kirjetega 3.6 järgi.
5. Loo pöördtsoonifail (3.7).
6. Kontrolli `named-checkconf` ja `named-checkzone`, taaskäivita `named` (3.8).
7. Muuda Debiani nimeserveriks `127.0.0.1`; Ubuntus peab netplanis olema `192.168.XXX.10`.
8. Luba tulemüüris port 53 TCP ja UDP labori võrgust (3.10).
9. Testi Debianis ja Ubuntus (`dig`, `resolvectl query mail.perenimi.local`).

**Kontrollpunkt:**

```bash
dig +short mail.perenimi.local            # 192.168.XXX.20
dig +short wp.perenimi.local              # debian.perenimi.local. 192.168.XXX.10
dig +short perenimi.local MX              # 10 mail.perenimi.local.
dig +short -x 192.168.XXX.20              # mail.perenimi.local.
dig +short debian.org                     # IP (edastajad töötavad)
```

**Küsimused:**

1. Mis vahe on autoriteetsel ja rekursiivsel nimeserveril? Kumb on Debian nime `debian.org` puhul?
2. Miks `allow-recursion` peab olema piiratud?
3. Miks `mail` on A-kirje, aga `wp` võib olla CNAME?
4. Mis on punkti tähendus tsoonifailis `mail.perenimi.local.` lõpus? Mis juhtub, kui see ununeb?

---

### Labor 3. DHCP-server Kea

**Eesmärk:** Windowsi klient saab Debianilt automaatselt aadressi vahemikust `.50–.99`, lüüsi, nimeserveri ja domeeni; Windows leiab kõik `*.perenimi.local` nimed.

**Sammud:**

1. Kontrolli, et Proxmoxi SDN-i DHCP on väljas (4.4).
2. Paigalda `kea-dhcp4-server` (4.5).
3. Kirjuta `/etc/kea/kea-dhcp4.conf` peatüki 4.6 järgi. Kontrolli `kea-dhcp4 -t` (4.7).
4. Taaskäivita teenus, vaata logist `listening on interface` rida. Luba tulemüüris UDP 67 (4.8).
5. Windowsis `ipconfig /release`, `ipconfig /renew`, `ipconfig /all` – täida laboripäevikus tabel 2.11 (4.9).
6. Debianis vaata rendifaili ja logi: leia oma Windowsi MAC ja aadress (4.9).
7. Windowsis: `nslookup mail.perenimi.local`, `nslookup -type=MX perenimi.local`, `ping wp`.
8. **Reserveering:** tee Windowsile reserveering `.100` (4.10), lisa DNS-i `win11` A-kirje. Kontrolli `ipconfig /all` ja `nslookup win11`.
9. **Rikkekatse:** peata Kea (`sudo systemctl stop kea-dhcp4-server`), tee Windowsis `ipconfig /release` ja `ipconfig /renew`. Mis aadressi Windows sai? Mis on veateade? Käivita Kea uuesti.
10. **Vahemälu katse:** küsi Windowsis `nslookup www.perenimi.local`. Muuda tsoonis `www` IP-ks `192.168.XXX.99`, **ära suurenda seerianumbrit**, tee `sudo rndc reload perenimi.local`. Vaata `sudo journalctl -u named -n 5` – mis hoiatus on? Mida vastab `dig @127.0.0.1 www.perenimi.local` Debianis ja mida `ping www.perenimi.local` Windowsis? Tee Windowsis `ipconfig /displaydns`, siis `ipconfig /flushdns` ja proovi uuesti. Taasta IP ja suurenda seerianumbrit.

**Kontrollpunkt:**

```powershell
ipconfig /all            # DHCP Server 192.168.XXX.10, DNS Servers 192.168.XXX.10, IPv4 .50–.99 (või .100)
nslookup blogi.perenimi.local      # Address 192.168.XXX.10, Aliases: blogi.perenimi.local
```

```bash
sudo cat /var/lib/kea/kea-leases4.csv   # Windowsi MAC ja aadress
```

**Küsimused:**

1. Nimeta DORA neli sõnumit. Miks saadab klient DISCOVER-i ja REQUEST-i levisõnumina?
2. Mis juhtub T1 ja T2 ajal? Mis juhtub, kui DHCP-server on terve rendiaja maas?
3. Miks ei tohi vahemik sisaldada serverite aadresse `.10` ja `.20`?
4. Mis juhtuks, kui Proxmoxi SDN DHCP oleks samuti sees? Kuidas seda Windowsis märkaksid?
5. Mis vahe on staatilisel aadressil ja reserveeringul? Millal kasutada kumbagi?
6. Miks nägid sammus 10 Debian ja Windows erinevaid vastuseid? Kes kasutab seerianumbrit ja kes TTL-i?
7. Miks soovitab ISC kasutada Kead, mitte `isc-dhcp-server`-it?

---

### Labor 4. Apache2 ja virtuaalhostid

**Eesmärk:** Debian teenindab kolme saiti ühelt IP-lt ja tundmatutele nimedele vastab eraldi vaikehost.

**Sammud:**

1. Paigalda Apache2 ja ava tulemüüris 80 ja 443 (5.2).
2. Loo kolm saidikausta ja testlehed (5.4).
3. Loo vaikehost `000-vaike.conf` (5.5).
4. Loo kolm vhosti (5.6).
5. Keela `000-default`, luba oma saidid ja moodulid `rewrite`, `headers` (5.7).
6. Kontrolli `apache2ctl -S` väljundit: milline on *default server*?
7. Testi `curl -H "Host: …"` käskudega (5.8).
8. Windowsis ava kõik kolm saiti nime järgi ja `http://192.168.XXX.10` IP järgi.
9. Peida serveri versioon (5.9).
10. Jälgi `tail -f` access-logi ja ava sait Windowsis.

**Kontrollpunkt:** iga sait näitab oma pealkirja; IP-ga avades näed „Tundmatu sait“; `curl -sI http://127.0.0.1/ | grep Server` → `Server: Apache`.

**Küsimused:**

1. Kuidas valib Apache, millist saiti näidata, kui kõik saidid on samal IP-l ja pordil?
2. Mis juhtuks ilma `000-vaike.conf` failita, kui avad saidi IP-aadressiga?
3. Mis vahe on `systemctl reload` ja `restart` vahel? Millal on vaja `restart`-i?
4. Miks `Options -Indexes`?
5. Mis on `sites-available` ja `sites-enabled` erinevus? Mida teeb `a2ensite` tegelikult failisüsteemis (`ls -l /etc/apache2/sites-enabled/`)?

---

### Labor 5. WordPress samas masinas

**Eesmärk:** `wp.perenimi.local` on töötav WordPress, mille andmebaas on samas masinas ja kättesaamatu võrgust.

**Sammud:**

1. Paigalda MariaDB ja PHP (6.2), kontrolli PHP tööd `info.php`-ga ja kustuta see.
2. `mariadb-secure-installation` (6.3).
3. Loo andmebaas `wp_db` ja kasutaja `wp_kasutaja@localhost` (6.4).
4. Laadi alla WordPress ja kopeeri saidi kausta (6.5).
5. Seadista `wp-config.php` koos unikaalsete turvavõtmetega (6.6).
6. Määra failiõigused (6.7).
7. Paigalda WordPress brauseris, lülita sisse püsiviited „Postituse nimi“ (6.8).
8. Tee üks postitus ja leia see andmebaasist käsurealt.

**Kontrollpunkt:**

```bash
sudo mariadb -e "SELECT post_title FROM wp_db.wp_posts WHERE post_status='publish';"
sudo ss -tlnp | grep 3306                       # 127.0.0.1:3306
ls -l /var/www/wp.perenimi.local/wp-config.php  # -rw-r----- www-data www-data
```

**Küsimused:**

1. Joonista (või kirjelda) LAMP-päringu teekond brauserist andmebaasini ja tagasi.
2. Miks on andmebaasi kasutaja `'wp_kasutaja'@'localhost'`, mitte `root`?
3. Mis juhtub, kui `AllowOverride` on `None` ja lülitad sisse püsiviited?
4. Milleks on `wp-config.php` turvavõtmed? Mis juhtub, kui neid muudad?
5. Miks `chmod 640` `wp-config.php` failile?

---

### Labor 6. WordPress kaugandmebaasiga

**Eesmärk:** `blogi.perenimi.local` töötab Debianis, andmebaas on Ubuntus ja sellele pääseb ligi ainult Debian.

**Sammud:**

1. Paigalda Ubuntule MariaDB ja turva see (7.2).
2. Lukk 1: `bind-address` (7.3).
3. Lukk 2: andmebaas `blogi_db`, kasutaja `blogi_kasutaja@192.168.XXX.10` (7.4).
4. Lukk 3: tulemüür (7.5).
5. Testi ühendust Debianist käsurealt (7.6). **Proovi sama Ubuntus endas** ja Windowsist `Test-NetConnection 192.168.XXX.20 -Port 3306` – peavad ebaõnnestuma. Kirjuta veateated päevikusse.
6. Paigalda WordPress saidile `blogi.perenimi.local` (7.7).
7. Kontrolli, et postitused on Ubuntu andmebaasis (7.8).
8. **Rikkekatse:** sulge Ubuntus tulemüüris port 3306 (`sudo ufw delete allow from 192.168.XXX.10 to any port 3306 proto tcp`). Mis näitab brauser? Mis on Apache error-logis? Taasta reegel.

**Kontrollpunkt:** `mariadb -h 192.168.XXX.20 -u blogi_kasutaja -p -e "SELECT CURRENT_USER();"` Debianist töötab; Ubuntus endas annab vea; brauseris töötab `http://blogi.perenimi.local`.

**Küsimused:**

1. Millised kolm „lukku“ pidid olema lahti? Mis veateate annab iga kinnine lukk?
2. Miks mitte luua kasutajat `'blogi_kasutaja'@'%'`?
3. Mis eelised ja puudused on andmebaasi eraldi serveris hoidmisel?
4. Liigub praegu andmebaasi parool võrgus krüptitult? Kuidas seda kontrollida (`tcpdump`) ja parandada?

---

### Labor 7. Labori CA ja HTTPS

**Eesmärk:** kõik veebisaidid töötavad HTTPS-iga ja Windowsi brauser usaldab neid ilma hoiatuseta.

**Sammud:**

1. Loo Debianis labori CA (8.2).
2. Väljasta sert Debianile (SAN: www, wp, blogi, perenimi.local, debian) ja Ubuntule (SAN: mail, ubuntu) (8.3).
3. Kopeeri failid `scp`-ga (8.4).
4. Debian: paigalda sert, tee HTTPS vhostid HTTP → HTTPS suunamisega kõigile kolmele saidile (8.5).
5. Muuda WordPressi aadressid `https://`-ks (8.6).
6. Ubuntu: paigalda sert ja CA (8.8).
7. Windowsi klient: impordi `ca.crt` *Trusted Root* hoidlasse (8.7).
8. Ava kõik saidid Windowsis, vaata serti (luku ikoon → *Connection is secure → Certificate is valid*): kes on väljastaja, millised nimed on SAN-is, millal kehtivus lõpeb?
9. **Katse:** ava `https://192.168.XXX.10`. Milline hoiatus ja miks?

**Kontrollpunkt:** `http://wp.perenimi.local` suunab `https://`-le ja leht avaneb lukuga; `openssl s_client … | grep "Verify return code"` → `0 (ok)`.

**Küsimused:**

1. Miks brauser usaldab nüüd serti, mida eile ei usaldanud? Mis muutus?
2. Miks peab `ca.key` olema kõige paremini kaitstud fail?
3. Mis vahe on CN-il ja SAN-il? Kumba brauser kontrollib?
4. Mida teeb `Strict-Transport-Security` päis?
5. Miks tootmises tehakse privaatvõti sihtserveris ja CA-le saadetakse ainult CSR?

---

### Labor 8. Postfix ja Dovecot

**Eesmärk:** Ubuntu on meiliserver: võtab vastu kirju `@perenimi.local` aadressidele, lubab sisseloginud kasutajatel saata TLS-iga ja annab postkastid IMAPS-iga.

**Sammud:**

1. Kontrolli eeldusi: `hostname -f`, `dig MX`, `dig -x 192.168.XXX.20`, serdid olemas.
2. Paigalda Postfix (*Internet Site*, `perenimi.local`) ja Dovecot (10.2).
3. Postfixi põhiseaded, TLS, autentimine ja piirangud `postconf -e` käskudega (10.3–10.5).
4. `login_maps.regexp` (10.5).
5. `master.cf`: submission ja submissions (10.6). `sudo postfix check`.
6. Dovecot `local.conf` (10.7). `sudo doveconf -n`.
7. Kasutajad `mari` ja `jaan`, aliased (10.8). `doveadm auth test`.
8. Tulemüür (10.9).
9. Tee kõik 8 testi peatükist 10.10 ja kopeeri iga testi oluline vastusrida laboripäevikusse.
10. Leia logist ühe kirja kõik read järjekorra-ID järgi (10.12).

**Kontrollpunkt:**

| Test | Oodatav |
| --- | --- |
| port 25 kohalik kiri | `250 2.0.0 Ok: queued` |
| avatud relee | `554 5.7.1 … Relay access denied` |
| 587 + AUTH | `235 2.7.0 Authentication successful` |
| võõras saatja | `553 5.7.1 … not owned by user jaan` |
| AUTH ilma TLS-ita | AUTH-i ei pakuta |
| IMAPS | `* SEARCH 1 2 …` |

**Küsimused:**

1. Mis vahe on portidel 25, 587 ja 465?
2. Miks pordil 25 ei pakuta autentimist?
3. Mis on avatud relee ja miks see on ohtlik? Milline seade selle keelab?
4. Kuidas Postfix kontrollib kasutaja parooli, kui tal endal paroolifaili pole?
5. Mis on LMTP ja milleks seda vaja on?
6. Mis vahe on ümbriku `MAIL FROM`-il ja `From:` päisel? Too näide, kus need erinevad.
7. Miks on Dovecoti soklid kaustas `/var/spool/postfix/private/`?

---

### Labor 9. DKIM, SPF, DMARC ja fail2ban

**Eesmärk:** väljaminevad kirjad on DKIM-iga allkirjastatud, domeenil on SPF, DKIM ja DMARC kirjed ning paroolide äraarvamine on blokeeritud.

**Sammud:**

1. Paigalda OpenDKIM ja genereeri võti selektoriga `s1` (11.2).
2. Tabelid ja `opendkim.conf` – **ära unusta `Nameservers` rida** (11.3–11.4).
3. Ühenda Postfixiga (11.5).
4. Lisa Debian tsooni SPF, DMARC ja DKIM kirjed; suurenda seerianumbrit (11.6).
5. `opendkim-testkey` → `key OK` (11.7).
6. Saada kiri ja kontrolli allkirja `opendkim-testmsg`-ga (11.7).
7. **Katse:** muuda Maildiris salvestatud kirja sisu ühe tähe võrra (`sudo nano`) ja kontrolli allkirja uuesti. Mis juhtus?
8. Paigalda fail2ban (11.8). Kontrolli `fail2ban-regex`-iga.
9. Saada Debian-st 6 korda vale parooliga (`swaks … --auth-password vale`), kontrolli `fail2ban-client status postfix-sasl`, vabasta IP.
10. Täida turvakontrolli tabel 10.10.

**Kontrollpunkt:** `opendkim-testkey` → `key OK`; kirja päises `DKIM-Signature: … d=perenimi.local; s=s1`; `dig +short TXT _dmarc.perenimi.local` vastab; Debian IP oli fail2ban-i nimekirjas.

**Küsimused:**

1. Mida kontrollib SPF, mida DKIM ja mida DMARC? Miks on vaja kõiki kolme?
2. Seleta lahti `v=spf1 mx -all`. Mis vahe on `-all` ja `~all` vahel?
3. Miks DKIM-allkiri läks sammus 7 katki? Mida see tõestab?
4. Mis on DMARC „alignment“? Too näide kirjast, mis läbib SPF-i, kuid ei läbi DMARC-it.
5. Miks oli vaja OpenDKIM-ile eraldi `Nameservers` rida?
6. Miks on `p=none` → `p=quarantine` → `p=reject` järjekord mõistlik uue domeeni puhul?

---

### Labor 10. Veebimeil Roundcube

**Eesmärk:** Windowsi kliendis avaneb `https://mail.perenimi.local`, kasutaja logib sisse, loeb ja saadab kirju.

**Sammud:**

1. Paigalda Apache2 ja Roundcube SQLite andmebaasiga (12.2).
2. Seadista `imap_host`, `smtp_host` ja lisaseaded (12.3).
3. Apache vhost `mail.perenimi.local` HTTP → HTTPS suunamisega (12.4).
4. Manuste suurus (12.5).
5. Test käsurealt (12.6).
6. Windowsis: logi sisse kui `mari`, saada kiri `jaan`-ile, logi sisse kui `jaan`, vasta (12.7).
7. Leia kirja lähtekoodist DKIM-allkiri ja `ESMTPSA`.
8. Lülita sisse fail2ban `roundcube-auth` ja testi (12.9).
9. Valikuline: seadista Thunderbird (12.8).
10. **Katse:** muuda Roundcube'is ajutiselt `imap_host` väärtuseks `localhost:143`. Mis juhtub sisselogimisel? Mis on `errors.log`-is? Taasta.

**Kontrollpunkt:** Windowsis on lukuga `https://mail.perenimi.local`; `mari` ja `jaan` saavad teineteisele kirjutada; kaustas „Saadetud“ on koopia.

**Küsimused:**

1. Milliste protokollidega räägib Roundcube Dovecoti ja Postfixiga? Mis portidel?
2. Miks Postfixi logis on klient Ubuntu ise, mitte Windows?
3. Miks ei tööta paketi vaikeseadistus `localhost:143`?
4. Kuidas Roundcube teab, millise parooliga Postfixi sisse logida?
5. Miks on `config`, `temp` ja `logs` kaustad `Require all denied`?

---

### Labor 11. Väljaminev post relay kaudu

**Eesmärk:** Roundcube'ist saadetud kiri jõuab päris internetis olevasse postkasti.

**Sammud:**

1. Võta õpetajalt relay andmed (server, port, kasutaja, parool) või loo laboriks Gmaili konto ja rakenduse parool (13.3).
2. Paigalda `libsasl2-modules` (13.4).
3. `sasl_passwd` ja `postmap` (13.5).
4. `generic` aadresside ümberkirjutus (13.6).
5. Postfixi relay-seaded (13.7).
6. Saada Roundcube'ist kiri oma isiklikule aadressile; jälgi logi (13.8).
7. Ava saabunud kirja päised: kes on `From:`? Milline DKIM ja SPF tulemus?
8. Saada kiri ka `jaan@perenimi.local`-ile ja kontrolli, et see **ei** läinud relay kaudu.

**Kontrollpunkt:** logis `relay=<relay>:587 … status=sent`; kiri on isiklikus postkastis; kohalik kiri on `relay=…[private/dovecot-lmtp]`.

**Küsimused:**

1. Miks ei saa laborist otse `gmail.com` MX-serverile saata?
2. Miks on `smtp_tls_security_level = encrypt`, aga sissetuleval pordil 25 `may`?
3. Mida teeb `smtp_generic_maps` ja miks see on vajalik?
4. Kuhu jõuab vastus, kui adressaat vajutab „Vasta“? Miks?
5. Mida oleks vaja, et `perenimi`-l oleks päris internetis töötav meiliserver?

---

### Labor 12. Tõrkeotsingu harjutus

**Eesmärk:** leida ja parandada vigu süsteemselt: sümptom → kiht → logi → põhjus → parandus.

Töötage paarides: üks teeb kaaslase süsteemi (või õpetaja teeb) **ühe rikke korraga**, teine leiab ja parandab selle. Iga rikke kohta kirjuta päevikusse: sümptom, millise käsuga/logiga põhjuse leidsid, parandus.

| # | Rike (tegija teeb) | Masin |
| --- | --- | --- |
| 1 | tsoonifailis `mail` kirje IP muudetud, seerianumber suurendatud | Debian |
| 2 | tsoonifailis süntaksiviga, `named` taaskäivitatud | Debian |
| 3 | `wp.perenimi.local.conf` vhostis `AllowOverride None` | Debian |
| 4 | `wp-config.php` `DB_PASSWORD` vale | Debian |
| 5 | Ubuntu tulemüürist eemaldatud port 3306 reegel | Ubuntu |
| 6 | `systemctl stop dovecot` | Ubuntu |
| 7 | `local.conf`-is `ssl_cert` real puudub `<` | Ubuntu |
| 8 | `main.cf`-is `mynetworks = 192.168.XXX.0/24` (avatud relee laborile!) | Ubuntu |
| 9 | `systemctl stop opendkim` | Ubuntu |
| 10 | Roundcube'is `smtp_host = 'tls://localhost:587'` | Ubuntu |
| 11 | Kea `interfaces` real vale liidese nimi | Debian |
| 12 | Windowsist eemaldatud labori CA | Windows |
| 13 | Kea `option-data`-st eemaldatud `domain-name-servers`, Windowsis `ipconfig /release` + `/renew` | Debian |
| 14 | Proxmoxi SDN-i alamvõrgule lisatud DHCP Range (õpetaja teeb) | Proxmox |

Kasuta peatüki 15 kontrollnimekirja ja tabeleid. Rikke 8 puhul: kuidas seda **testiga** avastada, kui teenused justkui töötavad?

**Küsimused:**

1. Millised rikked olid kasutajale nähtavad kohe ja millised alles hiljem või üldse mitte?
2. Milline logifail aitas kõige rohkem?
3. Miks on rike 8 kõige ohtlikum, kuigi kõik „töötab“?
