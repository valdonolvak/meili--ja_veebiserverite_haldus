urvalisuse mõistmiseks on hädavajalik aru saada, **kuidas** ründed tegelikult toimivad. 
Läbime kolm peamist ründestrateegiat, mis on tihedalt seotud Apache2 ja WordPressi seadistusega, selgitades nende mehhanismi ja tuues näiteid elust.

---

## 1. Rünnaku Tüüp: Paroolide Jõurünnak (Brute Force Attack)

**Põhimehhanism: Proovi-ja-Eksi (Trial-and-Error)**

Paroolide jõurünnak on ründemeetod, mille käigus ründaja proovib süsteemi sisselogimiseks süstemaatiliselt läbi **miljoneid** võimalikke parooli-kasutajanime kombinatsioone, kuni leiab õige.

### Kuidas see rünne toimib?

1.  **Sihtmärgi tuvastamine:** Ründaja teab tavaliselt sihtmärgi kontot (nt **admin**, **administrator**, või sinu veebisaidi URL-ist tuletatud konto).
2.  **Automatiseerimine:** Ründaja kasutab automatiseeritud tarkvara (nagu **Hydra** või spetsialiseeritud WordPressi skriptid) ja laeb üles suured **sõnastikufailid** (dictionary files), mis sisaldavad miljoneid levinud paroole, paroolide kombinatsioone ja lekkinud paroole.
3.  **Rünnak:** Tarkvara saadab iga sekundi tagant kümneid või sadu sisselogimispäringuid lehele `/wp-login.php` (või vanemate WordPressi versioonide puhul `/xmlrpc.php` kaudu).
4.  **Edu:** Kui tarkvara leiab õige kombinatsiooni, pääseb ründaja süsteemi täielikult ligi.

### Seos Sinu Seadistusega:

* **XML-RPC Haavatavus:** Fail **`xmlrpc.php`** (mille keelamist me soovitasime) võimaldas vanematel WordPressi API-del saata **ühes HTTP-päringus sadu** paroolikombinatsioone. See tegi jõurünnaku eriti kiireks ja raskesti tuvastatavaks, kuna server logis ainult ühe päringu.
* **Lahendus:** Keelates **`xmlrpc.php`** ja kasutades mittestandardseid kasutajanimesid (vältides **`admin`**), muudad rünnaku aeglaseks ja kulukaks.

### Päriseluline Turvaintsident:

**Cloudflare'i Tõrked (2014):** Aastal 2014 toimus suur Brute Force rünnak, mis oli suunatud WordPressi saitidele. Ründajad kasutasid pahavara, mis oli installitud koduarvutitesse, luues **botnet'i**. Miljonid koduarvutid saatsid samaaegselt miljoneid sisselogimispäringuid, koormates üle nii ründes olevad veebiserverid kui ka isegi suured sisupakkujaid nagu Cloudflare. Rünnak näitas, kui mastaapseks saab Brute Force minna.

---

## 2. Rünnaku Tüüp: Andmebaasi Süstimine (SQL Injection - SQLi)

**Põhimehhanism: Sisendi Valepuhastamine (Input Sanitation Failure)**

SQL Injection on rünne, mis kasutab ära veebirakenduse viga, kus **kasutaja sisestatud andmeid käsitletakse otse SQL-koodina**, mitte pelgalt andmetena. See võimaldab ründajal sisestada pahatahtlikku SQL-koodi andmebaasi pärimisse.

### Kuidas see rünne toimib?

1.  **Haavatavus:** Kujuta ette, et WordPressi vanas otsingufunktsioonis on kood, mis loob päringu otse kasutaja sisendi põhjal:
    `$query = "SELECT * FROM postitused WHERE kategooria = '" + $_GET['sisend'] + "'";`
2.  **Süstimine:** Ründaja sisestab väljale tavalise nime asemel pahatahtliku SQL-koodi, näiteks:
    `' OR 1=1 --`
3.  **Tulemus:** Serveri käivitatav päring muutub:
    `SELECT * FROM postitused WHERE kategooria = '' OR 1=1 --'`
    * **`' OR 1=1`** – See loogiline tehe on alati tõene, mistõttu andmebaas tagastab kõik postitused.
    * **`--`** – SQL-is tähistab see kommentaari algust, mis ignoreerib ülejäänud pärimusest (nt sulgud ja jutumärgid).
4.  **Katastroof:** Ründaja võib kasutada veel keerukamaid käske (nt **`DROP TABLE users`**), et kustutada andmebaasist tabeleid, või **`UNION SELECT`** käske, et lugeda administraatori kasutajatunnuseid ja paroolihashe.

### Seos Sinu Seadistusega:

* **Tabeli Eesliide:** Sinu seadistuses soovitasime kasutada juhuslikku tabeli eesliidet (nt **`$table_prefix = 'wp_'.rand(10000, 99999).'_';`**).
* **Lahendus:** Enamiku SQL Injection rünnakute puhul eeldab ründaja, et kasutad standardset eesliidet **`wp_`** (nt **`wp_users`**). Kui tabeli nimi on juhuslik (nt **`wp_84321_users`**), muudab see rünnaku oluliselt keerulisemaks, sest ründaja peab enne andmebaasi struktuuri välja nuputama.

### Päriseluline Turvaintsident:

**Hakerite Liidu Rünnak (2012):** Tuntud häkkerite rühmitus kasutas laialdaselt SQL Injection rünnakuid, et varastada andmeid valitsusasutustest ja suurtest ettevõtetest. Nende eesmärk oli sageli avaldada tundlik info ja näidata süsteemide haavatavust. SQLi-st tulenevad andmevargused on üks kallemaid ja levinumaid turvaintsidente.

---

## 3. Rünnaku Tüüp: Kontrollimata Faili Kirjutamine (Unrestricted File Upload)

**Põhimehhanism: Koodi Käivitamine (Remote Code Execution - RCE)**

See rünne leiab aset, kui veebirakendus lubab kasutajal üles laadida faile, kuid **ei kontrolli piisavalt rangelt failitüüpi, sisu või laiendit**.

### Kuidas see rünne toimib?

1.  **Haavatavus:** WordPressi meediakogu lubab tavaliselt üles laadida ainult pilte (.jpg, .png) ja dokumente (.pdf). Kuid vigase plugina või teema puhul võib olla võimalik üles laadida PHP-skript.
2.  **Skripti Laadimine:** Ründaja laeb üles faili, mis näeb välja nagu pilt, kuid sisaldab tegelikult pahatahtlikku PHP-koodi. Näiteks faili **`kest.php`** või **`pilt.jpg.php`**, mis sisaldab koodi:
    `<?php system($_GET['cmd']); ?>`
3.  **Koodi Käivitamine:** Kui ründaja teab faili asukohta (nt `https://minuleht.local/wp-content/uploads/2025/01/kest.php`), avab ta selle brauseris koos täiendava päringuga, näiteks:
    `https://minuleht.local/.../kest.php?cmd=ls%20-la`
4.  **Tagajärg:** **`system()`** funktsioon käivitab serveris kõik, mis on antud `cmd` parameetriga. Ründaja saab nüüd serveris käivitada mis tahes operatsioonisüsteemi käske (**Remote Code Execution**), sealhulgas andmete kopeerimine, kustutamine või pahavara paigaldamine.

### Seos Sinu Seadistusega:

* **`DISALLOW_FILE_EDIT`:** See seade **`wp-config.php`** failis (mida soovitasime) ei aita küll *üleslaadimise* vastu, kuid see aitab kaitsta, kui ründaja on saanud administraatori ligipääsu. Ilma selle seadeta saaks ründaja administraatoripaneelis otse teemade või pluginate koodi muuta ja pahatahtliku koodi lisada.
* **Failiõigused:** Kasutades **`www-data`** omanikku, piirame, milliste õigustega see ründekest saab käivituda.

### Päriseluline Turvaintsident:

**TimThumbi Haavatavus (2011-2014):** TimThumb oli laialdaselt kasutatav WordPressi piltide töötlemise skript. Haavatavus lubas ründajatel laadida üles pahatahtlikke faile (nagu eelmainitud kestad) justkui piltidena, mis tõi kaasa **massilise Remote Code Execution** rünnakulaine tuhandete veebisaitide vastu. See tõi esile, kui ohtlik on *kolmanda osapoole koodi* kontrollimata kasutamine.
