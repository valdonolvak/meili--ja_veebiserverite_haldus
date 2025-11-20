Jah, loomulikult\! Siin on samm-sammuline juhend BIND9 nimeserveri (DNS) seadistamiseks **Debian** Linuxil, kasutades domeenina **minudomeen.local** ja eeldades, et tegemist on privaatvõrgu/testikeskkonnaga.

Kuna **minudomeen.local** on lokaalne domeen, eeldame siinjuures, et kasutad ka lokaalset IP-aadressi, näiteks **192.168.1.10**.

## 1\. BIND9 installimine ja esialgne seadistamine

### 1.1. Pakettide uuendamine ja BIND9 paigaldamine

Uuenda pakettide loendeid ja paigalda BIND9 ning vajalikud utiliidid testimiseks:

```bash
sudo apt update
sudo apt install bind9 dnsutils
```

  * **Selgitus:** `bind9` on nimeserveri tarkvara ise. `dnsutils` sisaldab tööriistu (nt `nslookup`, `dig`) DNS-i testimiseks.

### 1.2. Põhiseadistus: `named.conf.options`

Muuda põhiseadistusfaili, et lubada rekursiivseid päringuid ja määrata edasisuunajad (forwarders), kui soovid lahendada väliseid domeene (nt Google DNS):

```bash
sudo nano /etc/bind/named.conf.options
```

Lisa `options { ... }` plokki:

```nginx
// ...
options {
    directory "/var/cache/bind";

    // Kui soovid väliseid domeene lahendada, lisa edasisuunajad:
    forwarders {
        8.8.8.8; // Google DNS 1
        8.8.4.4; // Google DNS 2
    };

    auth-nxdomain no;    # Valikuline, et BIND käituks nii nagu peaks (RFC1035)
    listen-on { any; };
};
// ...
```

  * **Selgitus:** **`forwarders`** suunab kõik päringud, millele lokaalne server ei ole autoriteetne, edasi loetletud nimeserveritele. Kui server on ainult lokaalne, võid selle ploki välja jätta või kasutada ainult lokaalset DNS-i.

## 2\. Uue tsooni (Zone) loomine

### 2.1. Tsooni defineerimine: `named.conf.local`

Lisa oma domeeni **minudomeen.local** tsooni definitsioon faili `/etc/bind/named.conf.local`:

```bash
sudo nano /etc/bind/named.conf.local
```

Lisa faili lõppu järgmised read:

```nginx
// Forward Zone - minudomeen.local
zone "minudomeen.local" {
    type master;
    file "/etc/bind/db.minudomeen.local"; // Tsooni andmefaili asukoht
};

// Reverse Zone - asenda '1.168.192' oma võrgu esimese kolme oktetiga pööratud kujul
// Eeldusel, et lokaalne võrk on 192.168.1.0/24
zone "1.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.192"; // Pöördtsooni andmefaili asukoht
};
```

  * **Selgitus:**
      * `zone "minudomeen.local"`: Määratleb edasisuunamise tsooni (Forward Zone) domeeni nimede IP-aadressideks lahendamiseks.
      * `type master`: Määrab serveri primaarseks nimeserveriks selle tsooni jaoks.
      * `file "..."`: Määrab tsooni andmefaili asukoha.
      * `zone "1.168.192.in-addr.arpa"`: Määratleb pöördtsooni (Reverse Zone) IP-aadresside domeeninimedeks lahendamiseks. IP-võrk (`192.168.1`) on tagurpidi ja lisatud on `.in-addr.arpa`.

## 3\. Tsooni andmefailide loomine

### 3.1. Edasisuunamise tsooni fail: `db.minudomeen.local`

Loo tsooni andmefail, kopeerides näidisfaili:

```bash
sudo cp /etc/bind/db.local /etc/bind/db.minudomeen.local
sudo nano /etc/bind/db.minudomeen.local
```

Muuda faili sisu (asenda **192.168.1.10** oma DNS-serveri lokaalse IP-aadressiga ja **minudomeen.local** oma domeeninimega):

```nginx
$TTL 604800
@    IN    SOA    ns1.minudomeen.local.    admin.minudomeen.local. (
              2023110701    ; Serial (YYYYMMDDNN) - muuda seda iga kord
              604800        ; Refresh
               86400        ; Retry
             2419200        ; Expire
              604800 )      ; Negative Cache TTL
;
@            IN    NS    ns1.minudomeen.local.
@            IN    A     192.168.1.10  ; Peamine domeeni IP
ns1          IN    A     192.168.1.10  ; Nimeserveri hosti IP
www          IN    A     192.168.1.10  ; Veebiserveri hosti IP (näiteks)
```

  * **Selgitus:**
      * `SOA`: Start of Authority - defineerib tsooni autoriteedi ja parameetrid. **Serial** peab olema **suurem** iga kord, kui faili muudetakse (nt kuupäev + 2-kohaline number).
      * `NS`: Name Server - määrab selle tsooni nimeserveri.
      * `A`: Address - lahendab domeeninime IPv4 aadressiks.

### 3.2. Pöördtsooni fail: `db.192`

Loo pöördtsooni andmefail, kopeerides näidisfaili:

```bash
sudo cp /etc/bind/db.127 /etc/bind/db.192
sudo nano /etc/bind/db.192
```

Muuda faili sisu (asenda **192.168.1.10** oma DNS-serveri lokaalse IP-aadressiga ja **minudomeen.local** oma domeeninimega):

```nginx
$TTL 604800
@    IN    SOA    ns1.minudomeen.local.    admin.minudomeen.local. (
              2023110701    ; Serial (YYYYMMDDNN) - muuda seda iga kord
              604800        ; Refresh
               86400        ; Retry
             2419200        ; Expire
              604800 )      ; Negative Cache TTL
;
@    IN    NS    ns1.minudomeen.local.
10   IN    PTR   ns1.minudomeen.local.    ; IP 192.168.1.10 - viimane oktett pöördtsoonis
10   IN    PTR   www.minudomeen.local.
```

  * **Selgitus:**
      * `PTR`: Pointer - lahendab IP-aadressi nimeks. Pöördtsoonis kasutatakse ainult IP-aadressi **viimast oktetti** (`10` IP-aadressist `192.168.1.10`).

## 4\. Konfiguratsiooni kontrollimine ja BIND9 taaskäivitamine

### 4.1. Kontrolli süntaksit

Kontrolli konfiguratsiooni ja tsoonifailide süntaksit:

```bash
sudo named-checkconf
sudo named-checkzone minudomeen.local /etc/bind/db.minudomeen.local
sudo named-checkzone 1.168.192.in-addr.arpa /etc/bind/db.192
```

Mõlema `named-checkzone` käsu puhul peaks väljund lõppema reaga **"OK"**.

### 4.2. Taaskäivita teenus

Kui kontrollid olid edukad, taaskäivita BIND9 teenus:

```bash
sudo systemctl restart bind9
sudo systemctl status bind9
```

Veendu, et teenus oleks staatusega **`active (running)`**.

## 5\. DNS-i kasutamine lokaalselt

### 5.1. Muuda lokaalset DNS-i

Muuda serveri enda DNS-i seadistus nii, et see kasutaks lokaalset nimeserverit (`127.0.0.1`):

```bash
sudo nano /etc/resolv.conf
```

Muuda see faili sisu selliseks (või lisa see rida faili algusesse):

```
nameserver 127.0.0.1
```

  * **Märkus:** Tänapäevastes Debiani versioonides haldab `resolv.conf` faili tihti **NetworkManager** või **systemd-resolved**. Kui muudatused kaovad, pead seadistama DNS-i eelistatud meetodi abil (nt NetworkManageri seadete kaudu).

### 5.2. Testimine

Testi DNS-i lahendamist serverist endast:

```bash
dig www.minudomeen.local
dig -x 192.168.1.10
```

Esimene käsk peaks näitama **www.minudomeen.local** A-kirje lahendamist IP-aadressiks **192.168.1.10**. Teine käsk peaks näitama IP **192.168.1.10** lahendamist **www.minudomeen.local** PTR-kirjeks.

-----

See video näitab BIND9 seadistamist Ubuntu/Debianil, mis on sarnane protsess, ja annab visuaalse näite: [Setting Up Your Own DNS Server: Building a BIND9 Server on Ubuntu\!](https://www.youtube.com/watch?v=6mfEYAkDwRs)

Kas sooviksid näiteks seadistada ka teise serveri (Slave DNS) või lisada oma tsooni faili rohkem kirjeid (nt CNAME, MX)?
http://googleusercontent.com/youtube_content/0
