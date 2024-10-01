#!/bin/bash
urlencode() {
  local input="$1 $2"
  local out=$(jq -n --arg input "$input" '$input|@uri')E

  echo "$out"
}

help(){
  echo "Skrypt służy do wyświetlania informacji z najbliższej stacji meteorologicznej podanego miasta, przyjmuje argumenty:"
  echo "--city [nazwa_miasta] : Miasto dla którego chcemy sprawdzić informacje"
  echo "--help, -h : Pomoc"
  echo "--debug : Tryb debugowania"
  echo "W przypadku problemów spróbować usunąć pliki cache" 
}
czy_debug=false

if [[ "$#" -gt 0 ]]; then
    case $1 in
        --city)	MI="$2 $3";;
	--debug|--verbose) 
		if [[ "$2" == "--city" ]]; then
			MI="$3 $4"
			czy_debug=true
		else
			echo "Nie podano --city"
			exit 1
		fi;;
        --help|-h) help; exit 1;;
        *) echo "Niewłaściwy parametr: $1"; exit 1;;
    esac
else
    echo "Nie podano żadnych argumentów."
    exit 1
fi

if [ "$czy_debug" = true ]; then
    echo "Debugowanie:"
    echo "Szukane miasto: $MI"
fi

config=".projektrc"

if [ -e "$config" ]; then
    source "$config"
else
    echo "Plik konfiguracyjny .projektrc nie istnieje. Tworzenie nowego pliku..."
    echo "PI=3.141592653589793" >> "$config"
    echo "PROMIEN_ZIEMI=6371" >> "$config"
    echo "LINK=https://danepubliczne.imgw.pl/api/data/synop" >> "$config"
    source "$config"
fi


MIASTO=$(urlencode $MI)_
geocode_result=$(curl -s "https://nominatim.openstreetmap.org/search?q=$MIASTO&format=json&limit=1")
sleep 1

lat1=$(echo "$geocode_result" | jq -r '.[0].lat')
lon1=$(echo "$geocode_result" | jq -r '.[0].lon')

cache_dane="cache_dane"
touch cache_dane

poprzednia_godzina=$(cat "$cache_dane" | tail -n 1 | grep -oP '\d+')
aktualna_godzina=$(date +%H)

if [ "$poprzednia_godzina" == "$aktualna_godzina" ]; then
    if [ "$czy_debug" == true ]; then
        echo "Pobrano dane stacji z pamięci cache"
    fi
    dane=$(cat "$cache_dane" | head -n 1)
else
    dane=$(curl -s $LINK)
    if [ "$czy_debug" == true ]; then
        echo "Pobrano dane stacji z API"
    fi
    echo "$dane" > "$cache_dane"
    echo "godzinka $aktualna_godzina" >> "$cache_dane"
fi
dystans() {
    local lat1=$1
    local lon1=$2
    local lat2=$3
    local lon2=$4
    local r1=$(echo "($lat2 - $lat1) * ($PI / 180)" | bc -l)
    local r2=$(echo "($lon2 - $lon1) * ($PI / 180)" | bc -l)

    local x=$(echo "s($r1/2) * s($r1/2) + c($lat1 * ($PI / 180)) * c($lat2 * ($PI / 180)) * s($r2/2) * s($r2/2)" | bc -l)
    local y=$(echo "2 * a(sqrt($x) / sqrt(1-$x))" | bc -l)

    local distance=$(echo "$PROMIEN_ZIEMI * $y" | bc -l)
    dyst=$(printf "%.0f" "$distance")
    echo "$dyst"
}


mindist=999999

nearest=""

stac() {
      echo ${station} | base64 --decode | jq -r ${1}
  }

czy=false
if [ -e "cache_wspolrzedne" ]; then
  czy=true
fi

if [ "$czy_debug" = true ]; then
    if [ "$czy" = true ]; then
    	echo "Pobrano współrzędne z pamięci cache"
    else 
        echo "Pobrano współrzędne z API"
    fi
fi


for station in $(echo "$dane" | jq -r '.[] | @base64'); do
  NA=$(stac '.stacja')
  NAME=$(urlencode "$NA")
 

  if [ "$czy" = true ]; then
    d=$(cat cache_wspolrzedne | grep "$NA")
    test=$(echo "$d" | grep -oE '[0-9]+(\.[0-9]+)?' | sort -u)
    wsp=()
    for i in $test; do
        wsp+=("$i")
    done
    lat2=${wsp[1]}
    lon2=${wsp[0]}
  else
    geocode_result2=$(curl -s "https://nominatim.openstreetmap.org/search?q=$NAME+&format=json&limit=1")
    sleep 1
    lat2=$(echo "$geocode_result2" | jq -r '.[0].lat')
    lon2=$(echo "$geocode_result2" | jq -r '.[0].lon')
    echo "$NA $lat2 $lon2" >> cache_wspolrzedne
  fi
  if [ "$czy_debug" = true ]; then
    echo "Sprawdzana stacja: $NA $lat2 $lon2"
  fi
  dist=$(dystans "$lat1" "$lon1" "$lat2" "$lon2")
  if (( $(echo "$dist < $mindist" | bc -l) )); then
    mindist=$dist
    nearest=$NA
  fi
done

info=$(echo "$dane" | jq -r --arg nearest "$nearest" '.[] | select(.stacja == $nearest)')

id=$(echo "$info" | jq -r '.id_stacji')
data=$(echo "$info" | jq -r '.data_pomiaru')
godzina=$(echo "$info" | jq -r '.godzina_pomiaru')
temperatura=$(echo "$info" | jq -r '.temperatura')
predkosc_wiatru=$(echo "$info" | jq -r '.predkosc_wiatru')
kierunek_wiatru=$(echo "$info" | jq -r '.kierunek_wiatru')
wilgotnosc=$(echo "$info" | jq -r '.wilgotnosc_wzgledna')
opady=$(echo "$info" | jq -r '.suma_opadu')
cisnienie=$(echo "$info" | jq -r '.cisnienie')

echo "$nearest [$id] / $data $godzina:00"
echo "Temperatura:        $temperatura °C"
echo "Prędkość wiatru:     $predkosc_wiatru m/s"
echo "Kierunek wiatru:     $kierunek_wiatru °"
echo "Wilgotność wzgl.:   $wilgotnosc %"
echo "Suma opadu:          $opady mm"
echo "Ciśnienie:           $cisnienie hPa"
if [ "$czy_debug" = true ]; then
    echo "Dystans do stacji $nearest: $mindist km"
fi
