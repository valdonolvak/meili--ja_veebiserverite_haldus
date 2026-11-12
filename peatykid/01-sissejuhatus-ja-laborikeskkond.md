## 1. Sissejuhatus ja laborikeskkond

Selles õppematerjalis ehitad kahest Linuxi serverist väikese, kuid päris ettevõtte moodi teenuste komplekti:

- **DHCP-server** (Kea), mis annab Windowsi kliendile automaatselt IP-aadressi, lüüsi ja nimeserveri;
- **nimeserver** (BIND9), mis teab kõiki sinu domeeni nimesid;
- **veebiserver** (Apache2) mitme saidiga ja WordPress – esmalt andmebaasiga samas masinas, seejärel andmebaasiga teises serveris;
- **meiliserver** (Postfix + Dovecot + OpenDKIM) koos **veebimeiliga** (Roundcube), kuhu saab Windowsi kliendi brauserist sisse logida, kirju saata ja lugeda ning kust kirjad jõuavad ka päris internetti.

Iga teenus on seadistatud nii, nagu seda tehakse tootmises: krüpteeritud ühendused, autentimine, piiratud õigused, logid ja tulemüür.

### 1.1 Laborikeskkond

![Labori võrk: Proxmox SDN vnet, võrk 192.168.XXX.0/24](joonised/01-topoloogia.png)

*Joonis 1.1: Labori võrk ja masinate rollid*

Labor töötab **Proxmox VE** keskkonnas. Igal õppijal on oma **SDN vnet** (*Software-Defined Network, virtual network*) ja oma võrk `192.168.XXX.0/24`, kus **XXX on vneti number**. Kui sinu vnet on number 123, on sinu võrk `192.168.123.0/24`, Debiani aadress `192.168.123.10` ja Ubuntu oma `192.168.123.20`.

| Masin | OS | Hostinimi (FQDN) | IP | Roll |
| --- | --- | --- | --- | --- |
| Debian | Debian 13 (trixie) | `debian.perenimi.local` | 192.168.XXX.10 (staatiline) | Kea DHCP, BIND9, Apache2 + PHP + WordPress (`www`, `wp`, `blogi`), MariaDB (`wp`), labori CA |
| Ubuntu | Ubuntu 24.04 LTS | `mail.perenimi.local` | 192.168.XXX.20 (staatiline) | Postfix, Dovecot, OpenDKIM, Roundcube, MariaDB (`blogi` kaugandmebaas) |
| Windows klient | Windows 11 | – | ajutiselt staatiline **192.168.XXX.30** (laborid 1–2), seejärel **DHCP-st** 192.168.XXX.50–99 | brauser, `nslookup`, Thunderbird (valikuline) |
| Lüüs | – | – | 192.168.XXX.1 | Proxmoxi SDN-i alamvõrgu lüüs, SNAT internetti |

> **NB! Lüüsi aadress** (`192.168.XXX.1`) on Proxmoxi SDN-i alamvõrgu (*subnet*) seadetes määratud *Gateway*. Kontrolli seda õpetajalt. Ülejäänud juhend jääb samaks.

### 1.2 Proxmox SDN – mida õppija peab teadma

| Termin | Selgitus |
| --- | --- |
| Zone (tsoon) | SDN-i võrgutüüp. Laboris tavaliselt **Simple** – iga vnet on Proxmoxi hosti sees eraldi isoleeritud võrk. |
| VNet | Virtuaalne kommutaator (switch), kuhu VM-ide võrgukaardid ühendatakse. VM-i seadetes on võrgukaardi *Bridge* väljal vneti nimi. |
| Subnet | Vnetile määratud IP-võrk (`192.168.XXX.0/24`) ja lüüs (`192.168.XXX.1`). Proxmoxi host ise võtab lüüsi aadressi. |
| SNAT | Proxmox tõlgib vneti aadressid väljuvas liikluses hosti aadressiks – nii pääsevad VM-id internetti. |
| SDN-i DHCP | Simple tsoonis saab Proxmox ise DHCP-d jagada (dnsmasq), kui alamvõrgule on määratud *DHCP Range*. **Meie laboris peab see olema väljas** – DHCP-d jagab Debian (peatükk 4). Kaks DHCP-serverit samas võrgus = kliendid saavad juhuslikult kummastki aadressi. |

### 1.3 Kokkulepped

**Domeeninimi = perekonnanimi.** Kus materjalis on `perenimi`, kirjuta oma perekonnanimi **väiketähtedega ja ilma täpitähtedeta**: Tõnisson → `tonisson.local`, Mägi → `magi.local`. Näidetes ja testväljundites kasutame nime `tamm`.

**XXX = sinu vneti number.** Kõik `192.168.XXX.y` aadressid asenda oma numbriga.

**Käsud.** Käsud on kirjutatud tavakasutajale, kellel on `sudo` õigus. Kui `sudo` puudub (Debiani paigaldusel, kus root-kasutajale anti parool), vaata peatükki 2.2. Faili muutmiseks kasutame `nano`: salvestamine **Ctrl+O**, Enter, väljumine **Ctrl+X**.

**Kus käsk käivitatakse?** Iga koodiploki kohal on märgitud masin: **Debian:**, **Ubuntu:** või **Windowsi klient:**. Vale masina peal käivitatud käsk on laboris kõige sagedasem viga.

**Paroolid.** Näidisparoolid (`Parool.123`, `WpParool.2026!`) on ainult näited – kasuta laboris oma paroole ja kirjuta need laboripäevikusse.

### 1.4 Versioonid

| Komponent | Debian 13 | Ubuntu 24.04 |
| --- | --- | --- |
| Kea DHCPv4 | 2.6 | – |
| BIND9 | 9.20 | – |
| Apache2 | 2.4.x | 2.4.58 |
| PHP | 8.4 | 8.3 |
| MariaDB | 11.8 | 10.11 |
| Postfix | – | 3.8 |
| Dovecot | – | **2.3.21** |
| OpenDKIM | – | 2.11 |
| Roundcube | – | 1.6 |
| fail2ban | – | 1.0.2 |

> **Miks meiliserver on just Ubuntul?** Debian 13 sisaldab Dovecot **2.4**-t, mille seadistuse süntaks on 2.3-st täiesti erinev (nt `mail_location` → `mail_driver` + `mail_path`, `ssl_cert` → `ssl_server_cert_file`). Internetis olevad juhendid on peaaegu kõik 2.3 jaoks. Selle materjali meiliserveri seadistus on testitud Ubuntu 24.04 Dovecot 2.3.21-ga. **Ära kopeeri Dovecoti seadistust Debian 13 masinasse** – see ei käivitu.

### 1.5 Õppematerjali ülesehitus

| Peatükk | Teema | Masin |
| --- | --- | --- |
| 2 | Linuxi serveri alused: võrk, SSH, sudo, teenused, logid, tulemüür | kõik |
| 3 | DNS ja BIND9 | Debian |
| 4 | DHCP ja Kea | Debian → Windowsi klient |
| 5 | Apache2 ja virtuaalhostid | Debian |
| 6 | WordPress samas masinas (LAMP) | Debian |
| 7 | WordPress kaugandmebaasiga | Debian + Ubuntu |
| 8 | Labori CA ja HTTPS | Debian → Ubuntu, Windows |
| 9 | E-posti alused: protokollid, rollid, DNS-kirjed | – |
| 10 | Postfix ja Dovecot | Ubuntu |
| 11 | Meiliserveri turvalisus: DKIM, SPF, DMARC, fail2ban | Ubuntu + Debian |
| 12 | Veebimeil Roundcube | Ubuntu |
| 13 | Väljaminev post internetti relay kaudu | Ubuntu |
| 14 | Laboritööd 1–12 | – |
| 15 | Tõrkeotsing ja käskude spikker | – |
| 16 | Allikad | – |
| **Osa III** | **Andmebaasipõhine meiliserver** | |
| 17 | Põhimõtted: virtuaaldomeenid ja -postkastid | – |
| 18 | PostfixAdmin: andmebaas ja veebiliides | Ubuntu (+ Debian DNS) |
| 19 | Postfix ja Dovecot MariaDB-ga | Ubuntu |
| 20 | Haldus, laborid 13–15, tõrkeotsing | Ubuntu |

Interaktiivsed harjutused (DHCP, DNS, Apache virtuaalhosti valik, e-kirja teekond ja rikked) on kaustas [`interaktiivne/`](https://valdonolvak.github.io/meili--ja_veebiserverite_haldus/interaktiivne/index.html).

### 1.6 Hetktõmmised

Tee Proxmoxis igast Linuxi masinast **hetktõmmis** (*snapshot*) enne iga laborit (nt `enne-labor-8`). Kui seadistus läheb sassi, saad masina mõne sekundiga tagasi keerata. Hetktõmmis ei asenda arusaamist, miks viga tekkis – enne tagasikeeramist vaata alati logi (peatükk 15).
