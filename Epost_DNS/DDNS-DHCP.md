# 👉 **perenimi.local**

Bind9 + DHCP DDNS konfiguratsioon seadistamine vastavalt  keskkonnale:

* **Domeen:** perenimi.local
* **DNS server:** 10.0.15.25
* **DHCP server:** 10.0.15.20
* **Võrk:** 10.0.15.0/24
* **Tagurpidi tsoon:** 15.0.10.in-addr.arpa

Ja lõpus on **enim levinud troubleshoot** uuendatud sama domeeni jaoks.

---

# 🟦 **1. TSIG võtme loomine (DNS server 10.0.15.25)**

```bash
sudo tsig-keygen -a HMAC-SHA256 ddnskey > /etc/bind/ddns.key
```

---

# 🟦 **2. Bind9 konfiguratsioon (10.0.15.25)**

## 2.1 Lisa TSIG-võti konfiguratsiooni

Fail: **/etc/bind/named.conf.local**

```conf
include "/etc/bind/ddns.key";

zone "perenimi.local" {
    type master;
    file "/etc/bind/zones/db.perenimi.local";
    allow-update { key ddnskey; };
};

zone "15.0.10.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.10.0.15";
    allow-update { key ddnskey; };
};
```

---

## 2.2 Tsoonifailid (Bind9 peab neid saama kirjutada)

Loo tsoonikataloog:

```bash
sudo mkdir -p /etc/bind/zones
sudo chown bind:bind /etc/bind/zones
```

### Fail: `/etc/bind/zones/db.perenimi.local`

```
$TTL 86400
@   IN SOA ns1.perenimi.local. admin.perenimi.local. (
        2025010101 3600 1800 604800 86400 )
    IN NS ns1.perenimi.local.

ns1 IN A 10.0.15.25
```

### Fail: `/etc/bind/zones/db.10.0.15`

```
$TTL 86400
@   IN SOA ns1.perenimi.local. admin.perenimi.local. (
        2025010101 3600 1800 604800 86400 )
    IN NS ns1.perenimi.local.
```

---

# 🟦 **3. DHCP serveri konfiguratsioon (10.0.15.20)**

Kopeeri võti DNS serverist:

```bash
scp 10.0.15.25:/etc/bind/ddns.key /etc/dhcp/ddns.key
```

## 3.1 DDNS seadistus failis **/etc/dhcp/dhcpd.conf**

```conf
include "/etc/dhcp/ddns.key";

ddns-update-style interim;
ddns-domainname "perenimi.local.";
ddns-rev-domainname "in-addr.arpa.";

update-static-leases on;

zone perenimi.local. {
    primary 10.0.15.25;
    key ddnskey;
}

zone 15.0.10.in-addr.arpa. {
    primary 10.0.15.25;
    key ddnskey;
}

subnet 10.0.15.0 netmask 255.255.255.0 {
    range 10.0.15.100 10.0.15.200;
    option routers 10.0.15.1;
    option domain-name "perenimi.local";
    option domain-name-servers 10.0.15.25;

    ddns-hostname = pick-first-value(option host-name, config-option server-hostname);
}
```

---

# 🟦 **4. Teenuste taaskäivitamine**

DNS:

```bash
sudo systemctl restart bind9
```

DHCP:

```bash
sudo systemctl restart isc-dhcp-server
```

---

# 🟦 **5. Testimine**

### A-kirje:

```bash
dig klient1.perenimi.local @10.0.15.25
```

### PTR-kirje:

```bash
dig -x 10.0.15.150 @10.0.15.25
```

### Logid:

```bash
journalctl -u isc-dhcp-server -f
journalctl -u bind9 -f
```

---

# 🟥 **6. Enim levinud DDNS probleemid (UUENDATUD domeeniga perenimi.local)**

## ❗ **1. Bind9: “update denied”**

**Põhjused:**

* tsoonis pole `allow-update`
* DHCP kasutab vale TSIG-võtit
* vale tsooni nimi (nt perenimi.local → perenimi.local.)
* DHCP üritab uuendada valesse domain’i

**Lahendus:**

* kontrolli, et mõlemal poolel on identne:

```conf
allow-update { key ddnskey; };
```

* kontrolli võtme `secret` väärtust

---

## ❗ **2. DHCP: “TSIG authentication failure”**

**Põhjused:**

* vale võti
* vale algoritm
* võtmefaili õigused valed

**Lahendus:**

```bash
cmp /etc/dhcp/ddns.key /etc/bind/ddns.key
```

Peavad olema *baiti täpselt samad*.

---

## ❗ **3. DNS tsoonid ei uuene (A- ja PTR-kirjed puuduvad)**

**Põhjused:**

* tsoonifailid pole Bind kasutaja omandis
* .jnl fail puudub või pole kirjutatav

**Lahendus:**

```bash
sudo chown bind:bind /etc/bind/zones/*
sudo touch /etc/bind/zones/db.perenimi.local.jnl
sudo touch /etc/bind/zones/db.10.0.15.jnl
sudo chown bind:bind /etc/bind/zones/*.jnl
```

---

## ❗ **4. Tagurpidi (PTR) kirje ei teki**

**Põhjused:**

* vale reverse-tsoon (`15.0.10.in-addr.arpa`)
* DHCP ei saada reverse täiustamiseks infot

**Kontroll:**

```bash
dig -x 10.0.15.101 @10.0.15.25
```

---

## ❗ **5. Kliendi hostname ei lähe DNS-i**

**Põhjused:**

* klient ei saada `host-name` väärtust
* DHCP klient Linuxis vaikimisi ei saada midagi

**Lahendus Linuxi kliendil:**

`/etc/dhcp/dhclient.conf`:

```
send host-name "klient1";
```

---

## ❗ **6. Kontrollida käsitsi (väga kasulik debugimisel)**

DNS serveris:

```bash
nsupdate -k /etc/bind/ddns.key
```

Siis:

```
server 10.0.15.25
zone perenimi.local
update add test.perenimi.local 60 A 10.0.15.222
send
```

Kui see töötab → probleem on DHCP-s, mitte DNS-is.

---


Kas soovid midagi nendest?
