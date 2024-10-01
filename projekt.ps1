

function urlencode {
    param (
        [string]$arg1,
        [string]$arg2
    )
    $in = "$arg1 $arg2".TrimEnd()
    $out = [uri]::EscapeDataString($in)
    Write-Output $out
}

$OutputEncoding = [System.Text.Encoding]::UTF8
function help {
    Write-Host "Skrypt służy do wyświetlania informacji z najbliższej stacji meteorologicznej podanego miasta, przyjmuje argumenty:" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::Default.GetBytes($_)) }
    Write-Host "--city [nazwa_miasta] : Miasto dla którego chcemy sprawdzić informacje"
    Write-Host "--help, -h : Pomoc"
    Write-Host "--debug : Tryb debugowania"
    Write-Host "W przypadku problemów spróbować usunąć pliki cache"
}


$czy_debug = $false
if ($args.Length -gt 0) {
    switch ($args[0]) {
        "--city" { 
            $MI = "$($args[1]) $($args[2])" 
        }
        {($_ -eq "--debug") -or ($_ -eq "--verbose")} {
            if ($args[1] -eq "--city") {
                $MI = "$($args[2]) $($args[3])"
                $czy_debug = $true
            }
            else {
                Write-Host "Nie podano --city"
                exit 1
            }
        }
        {($_ -eq "--h") -or ($_ -eq "--help")} { 
            help
            exit 1 
        }
        default { 
            Write-Host "Niewlasciwy parametr: $($args[0])"
            exit 1 
        }
    }
}
else {
    Write-Host "Nie podano żadnych argumentów."
    exit 1
}




if ($czy_debug -eq $true) {
    Write-Host "Debugowanie:"
    Write-Host "Szukane miasto: $($MI)"
}

$config = ".projektrc"

if (Test-Path $config) {
    $configContent = Get-Content $config -Raw
    Invoke-Expression $configContent
}
else {
    Write-Host "Plik konfiguracyjny .projektrc nie istnieje. Tworzenie nowego pliku..."
    Add-Content $config '$PI=3.141592653589793'
    Add-Content $config '$PROMIEN_ZIEMI=6371'
    Add-Content $config '$LINK="https://danepubliczne.imgw.pl/api/data/synop"'
    $configContent = Get-Content $config -Raw
    Invoke-Expression $configContent
}

$MIASTO = urlencode $MI
$geocode_result = Invoke-RestMethod -Uri "https://nominatim.openstreetmap.org/search?q=$MIASTO&format=json&limit=1"
Start-Sleep -Seconds 1
$lat1 = $geocode_result[0].lat
$lon1 = $geocode_result[0].lon

$cache_dane = "cache_dane"

if (-not (Test-Path $cache_dane)) {
  New-Item -ItemType File -Path $cache_dane | Out-Null
}

$poprzednia_godzina = Get-Content $cache_dane | Select-Object -Last 1 | Select-String -Pattern '\d+' | ForEach-Object {$_.Matches.Value}

$aktualna_godzina = Get-Date -Format HH

if ($poprzednia_godzina -eq $aktualna_godzina) {
  if ($czy_debug -eq $true) {
    Write-Host "Pobrano dane stacji z pamięci cache"
  }
  $dane = Get-Content $cache_dane
}
else {
  $dane = Invoke-RestMethod -Uri $LINK
  if ($czy_debug -eq $true) {
    Write-Host "Pobrano dane stacji z API"
  }
  Set-Content -Path $cache_dane -Value $dane
  Add-Content -Path $cache_dane -Value "godzinka $aktualna_godzina"
}


function dystans {
    param (
        [double]$lat1,
        [double]$lon1,
        [double]$lat2,
        [double]$lon2
    )
    $r1 = ($lat2 - $lat1) * ($PI / 180)
    $r2 = ($lon2 - $lon1) * ($PI / 180)

    $x = [math]::Sin($r1/2) * [math]::Sin($r1/2) + [math]::Cos($lat1 * ($PI / 180)) * [math]::Cos($lat2 * ($PI / 180)) * [math]::Sin($r2/2) * [math]::Sin($r2/2)
    $y = 2 * [math]::Atan2([math]::Sqrt($x), [math]::Sqrt(1-$x))

    $distance = $PROMIEN_ZIEMI * $y
    $dyst = [math]::Round($distance, 0)
    Write-Output $dyst
}

$mindist = 999999
$nearest = ""

$czy = $false

if (Test-Path "cache_wspolrzedne") {
    $czy = $true
}
if ($czy_debug -eq $true) {
    if ($czy -eq $true) {
        Write-Host "Pobrano współrzędne z pamięci cache"
    }
    else {
        Write-Host "Pobrano współrzędne z API"
    }
}

foreach ($station in $dane) {
    if ($station -eq "godzinka $poprzednia_godzina"){
        continue 
    }
    #----------------------
    $elementy = $station -split '; '
    foreach ($element in $elementy) {
        $klucz, $wartosc = $element -split '='
        if ($klucz -eq "stacja") {
            $NA = $wartosc
            break
        }
    }
    #--------------------
    $NAME = urlencode $NA
        if ($czy -eq $true) {
            $d = Get-Content "cache_wspolrzedne" | Select-String $NA
            $wspolrzedne = $d -replace $NA,''
            $oba = $wspolrzedne -split ' '
            $lat2 = $oba[1]
            $lon2 = $oba[2]
        }
        else {
            $geocode_result2 = Invoke-RestMethod -Uri "https://nominatim.openstreetmap.org/search?q=$NAME+&format=json&limit=1"
            Start-Sleep -Seconds 1
            $lat2 = $geocode_result2[0].lat
            $lon2 = $geocode_result2[0].lon
            "$NA $lat2 $lon2" | Out-File -Append "cache_wspolrzedne"
        }
        if ($czy_debug -eq $true) {
            Write-Host "Sprawdzana stacja: $NA $lat2 $lon2"
        }
        $dist = dystans $lat1 $lon1 $lat2 $lon2

        if ($dist -lt $mindist) {
            $mindist = $dist
            $nearest = $NA
        }
}

$info1 = $dane | Select-String "$nearest"
$elementy = $info1 -split '; '
foreach ($element in $elementy) {
    $klucz, $wartosc = $element -split '='
    $wartosc = $wartosc.TrimEnd('}')
    if ($klucz -eq "@{id_stacji"){
        $id = $wartosc
    }
    if ($klucz -eq "data_pomiaru"){
        $data = $wartosc
    }
    if ($klucz -eq "temperatura"){
        $temperatura = $wartosc
    }
    if ($klucz -eq "predkosc_wiatru"){
        $predkosc_wiatru = $wartosc
    }
    if ($klucz -eq "kierunek_wiatru"){
        $kierunek_wiatru = $wartosc
    }
    if ($klucz -eq "wilgotnosc_wzgledna"){
        $wilgotnosc = $wartosc
    }
    if ($klucz -eq "suma_opadu"){
        $opady = $wartosc
    }
    if ($klucz -eq "cisnienie"){
        $cisnienie = $wartosc
    }
}
$header = "$nearest [$id] / $data $aktualna_godzina" + ":00"
Write-Output $header
Write-Output "Temperatura:        $temperatura °C" 
Write-Output "Prędkość wiatru:     $predkosc_wiatru m/s" 
Write-Output "Kierunek wiatru:     $kierunek_wiatru °" 
Write-Output "Wilgotność wzgl.:   $wilgotnosc %" 
Write-Output "Suma opadu:          $opady mm"
Write-Output "Ciśnienie:           $cisnienie hPa" 
if ($czy_debug -eq $true) {
    Write-Output "Dystans do stacji $nearest : $mindist km"
}
