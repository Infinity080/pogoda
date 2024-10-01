Skrypty w tym projekcie odczytują obecną pogodę dla podanego miasta, wyszukując najbliższą stację meteorologiczną w Polsce (za pomocą wzoru haversine) i odczytując dane pogodowe dla miasta, w którym jest stacja. Program pobiera dane pogodowe z publicznego API https://danepubliczne.imgw.pl/api/data/synop oraz współrzędne miast z https://nominatim.openstreetmap.org.
Po informacje dotyczące działania programu odpalić go z flagą --help.

## Versions
- projekt.sh (skrypt w bash)
- projekt.ps1 (skrypt w powershell)

## Requirements

### Bash
- curl

## Installation

### Bash
```bash
sudo apt update
sudo apt install curl
```
## Acknowledgments
-  https://nominatim.openstreetmap.org
-  https://danepubliczne.imgw.pl
