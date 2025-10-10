Kuna testkeskkonnas puudub DNS-server, on **BIND9** seadistamine parim viis SPF, DKIM ja DMARC kirjeid simuleerida. See võimaldab teil harjutada kogu e-posti ökosüsteemi seadistamist.

Järgnev juhend eeldab, et BIND9 seadistatakse eraldi serveril (või samal VM-il) ning see teenindab domeeni `minumeil.ee`.

-----

## BIND9 DNS-serveri Seadistamine Postfix'i jaoks 🌐

### 1\. BIND9 Paigaldamine

Paigalda BIND9 (nimetatud ka `named`) ja DNS-utiliidid.

```bash
sudo apt update
sudo apt install bind9 dnsutils -y
```

### 2\. DNS-serveri Seadistamine

Me seadistame BIND9 teenindama edasipöördumise tsooni (`minumeil.ee`) ja vastupöördumise tsooni (vajalik meiliserverite kontrollide jaoks).

#### 2.1. Tsoonifailide Deklareerimine

Muuda BIND9 peamist konfiguratsioonifaili `/etc/bind/named.conf.local`.

```bash
sudo nano /etc/bind/named.conf.local
```

Lisa faili lõppu järgmised tsoonide deklaratsioonid. Asenda `192.168.1` oma sisevõrgu esimese kolme oktetiga.

```bind
// minumeil.ee edasipöördumise tsoon (Forward zone)
zone "minumeil.ee" {
    type master;
    file "/etc/bind/db.minumeil.ee";  // Tsoonifaili asukoht
};

// Vastupöördumise tsoon (Reverse zone) - asenda 1.168.192.in-addr.arpa oma võrgu prefiksiga vastupidises järjekorras (nt 192.168.1.x -> 1.168.192)
zone "1.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.192";
};
```

#### 2.2. Edasipöördumise Tsoonifaili Loomine (db.minumeil.ee)

Loo tsoonifail `/etc/bind/db.minumeil.ee`.

```bash
sudo nano /etc/bind/db.minumeil.ee
```

Asenda `$SERVER_IP` oma meiliserveri sisevõrgu IP-aadressiga. Kopeerige siia ka **DKIM-i avalik võti** (mille saite Postfixi seadistamisel OpenDKIM-ist) ja eemaldage sellelt kõik jutumärgid ja reavahetused, jättes selle ühte ritta.

```bind
$TTL 604800
@       IN      SOA     mail.minumeil.ee. postmaster.minumeil.ee. (
                        2024010101      ; Serial (muuda iga kord, kui faili muudad)
                          604800      ; Refresh
                           86400      ; Retry
                         2419200      ; Expire
                          604800 )    ; Negative Cache TTL
@       IN      NS      mail.minumeil.ee.

; A kirjed
mail    IN      A       $SERVER_IP      ; Meiliserveri A-kirje
@       IN      A       $SERVER_IP      ; Põhidomeeni A-kirje (saab olla sama)

; MX kirje
@       IN      MX 10   mail.minumeil.ee. ; Meiliserveri määratlus (Prioriteet 10)

; ------------------------------------------------------------------
; E-POSTI AUTENTIMISE KIRJED
; ------------------------------------------------------------------

; 1. SPF kirje (Sender Policy Framework)
; Lubab meili saatmise sellelt IP-lt ja MX kirjes määratud aadressilt.
@       IN      TXT     "v=spf1 a mx ip4:$SERVER_IP ~all"

; 2. DKIM kirje (DomainKeys Identified Mail)
; DKIM avalik võti. Asenda pikk string oma OpenDKIM-ist saadud väärtusega
; DKIM selektor 'default'
default._domainkey IN TXT ( "v=DKIM1; h=sha256; k=rsa; "
                           "p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyYt24QxH3f9u0g..."
                           "pikk_dkim_voti_ilma_jutumarkideta_uhe_reana_katkesta_vajadusel_sulgudega"
                           "..." )

; 3. DMARC kirje (Domain-based Message Authentication, Reporting, and Conformance)
; Poliitika "none" (jälgimine) ja aruannete saatmine postmaster@minumeil.ee
_dmarc  IN      TXT     "v=DMARC1; p=none; rua=mailto:postmaster@minumeil.ee"
```

#### 2.3. Vastupöördumise Tsoonifaili Loomine (db.192)

Loo vastupöördumise tsoonifail `/etc/bind/db.192` (jällegi, kohanda nime vastavalt oma IP-le).

```bash
sudo nano /etc/bind/db.192
```

Asenda viimane IP-aadressi oktett (`.200` näites) oma serveri IP-aadressi viimase oktetiga ja `1.168.192` oma võrgu prefiksiga (vastupidises järjekorras).

```bind
$TTL 604800
@       IN      SOA     mail.minumeil.ee. postmaster.minumeil.ee. (
                        2024010101      ; Serial
                          604800      ; Refresh
                           86400      ; Retry
                         2419200      ; Expire
                          604800 )    ; Negative Cache TTL
@       IN      NS      mail.minumeil.ee.

; PTR kirje (Pointer)
200     IN      PTR     mail.minumeil.ee. ; Asenda '200' serveri IP viimase oktetiga
```

### 3\. Kontroll ja Teenuse Taaskäivitamine

Enne taaskäivitamist kontrolli tsoonifailide süntaksit:

```bash
# Kontrolli kohalikke tsoonide deklaratsioone
sudo named-checkconf /etc/bind/named.conf.local

# Kontrolli edasipöördumise tsoonifaili
sudo named-checkzone minumeil.ee /etc/bind/db.minumeil.ee

# Kontrolli vastupöördumise tsoonifaili
sudo named-checkzone 1.168.192.in-addr.arpa /etc/bind/db.192
```

Kui vigu pole, taaskäivita BIND9 teenus:

```bash
sudo systemctl restart bind9
```

### 4\. DNS-i Kasutamine

Nüüd peate suunama **oma meiliserveri** ja **testimis-VM-ide** DNS-päringud oma uuele BIND9 serverile.

1.  Muutke kõigi asjakohaste test-VM-ide konfiguratsiooni `/etc/resolv.conf` (või võrguhalduri kaudu) nii, et **nameserver** oleks BIND9 serveri sisevõrgu IP-aadress.

    ```bash
    sudo nano /etc/resolv.conf
    # Eemalda vanad nameserverid ja lisa oma BIND9 IP
    nameserver $BIND9_SERVER_IP
    ```

2.  **Kontrollige DNS kirjeid:**

    ```bash
    # Kontrolli MX kirjet (peaks näitama mail.minumeil.ee)
    dig minumeil.ee MX

    # Kontrolli SPF kirjet
    dig minumeil.ee TXT

    # Kontrolli DKIM kirjet (peaks näitama p= väärtust)
    dig default._domainkey.minumeil.ee TXT

    # Kontrolli DMARC kirjet
    dig _dmarc.minumeil.ee TXT
    ```

Kui kõik kirjed on korrektselt lahendatud, siis teie Postfix/Dovecot seadistused näevad ja kasutavad SPF, DKIM ja DMARC kirjeid, nagu need oleksid avalikus DNS-is\! See võimaldab teil edukalt testida kogu autentimisahelat.
